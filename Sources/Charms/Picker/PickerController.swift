import AppKit
import Carbon.HIToolbox
import CharmsCore

/// Runs one picker session at a time.
///
/// Every decision about what may happen next is made by `SessionMachine`.
/// This class gathers facts (where the caret is, whether keys are still
/// held, whether the field is still the same), reports them to the machine
/// as events, and carries out the effects it returns.
@MainActor
final class PickerController: PickerSearchDelegate {
    private let services: AppServices
    private let capture = TargetCaptureService()
    private let insertion: InsertionService
    private let panel = PickerPanel()
    private let model = PickerViewModel()
    private let viewController: PickerViewController
    private var machine = SessionMachine()
    private var session: Session?
    private var observers: [NSObjectProtocol] = []
    private var isShowingMenu = false

    /// Called when a session ends, so the typed trigger can start afresh.
    var onSessionEnded: (() -> Void)?

    private struct Session {
        let id: SessionID
        let invocation: Invocation
        let started = ProcessInfo.processInfo.systemUptime
        var displays: [DisplayGeometry]
        var primaryFrame: CGRect
        var sourceProcess: pid_t?
        var target: CapturedTarget?
        var captureDone = false
        var presented = false
        /// The item the user committed to, frozen when they did.
        var chosen: PickerItem?
        // Typed invocation only.
        var handoff: TriggerHandoff?
        /// UTF-16 units of the query that came from keys the source received.
        var sourceUnitsInQuery = 0
        var lastSourceKey = ProcessInfo.processInfo.systemUptime
        var markerProbe: CaretProbe?
    }

    init(services: AppServices) {
        self.services = services
        insertion = InsertionService(diagnostics: services.diagnostics)
        viewController = PickerViewController(model: model)
        panel.contentViewController = viewController
        panel.setContentSize(PickerPanel.size)
        viewController.searchDelegate = self

        panel.onResignKey = { [weak self] in
            guard let self, self.machine.isPickerVisible, !self.isShowingMenu else { return }
            // The user clicked elsewhere or switched away.
            self.perform(self.machine.handle(.cancel))
        }
        panel.onKeyEquivalent = { [weak self] event in self?.handleKeyEquivalent(event) ?? false }
        model.onActivate = { [weak self] position in
            guard let self else { return }
            self.model.selection = position
            self.activate(.insert)
        }
        model.menuActions = { [weak self] position in self?.menuActions(for: position) ?? [] }
        observeEnvironment()
    }

    // MARK: Entry points

    var sessionActivity: TypedTriggerService.SessionActivity {
        guard !machine.isIdle, let session else { return machine.isIdle ? .none : .other }
        if session.invocation == .typedMarker, let source = session.sourceProcess {
            return .typed(source)
        }
        return .other
    }

    /// The shortcut or the menu-bar item.
    func invoke(_ invocation: Invocation) {
        // Pressing the shortcut while a typed marker is still being
        // confirmed drops that attempt and opens an ordinary session.
        let supersedesTypedCapture = machine.invocation == .typedMarker && machine.state == .capturing
        perform(machine.handle(.invoke(invocation)))
        if supersedesTypedCapture {
            perform(machine.handle(.invoke(invocation)))
        }
    }

    /// `::` was typed into `processID`.
    func invokeTyped(processID: pid_t) {
        guard machine.isIdle else { return }
        let effects = machine.handle(.invoke(.typedMarker))
        guard case .capture(let id, _)? = effects.first else { return }
        beginCapture(id, invocation: .typedMarker, typedSource: processID)
    }

    /// During a typed session: a key was delivered to the source, not to
    /// the picker.
    func sourceReceived(_ key: KeyObservation) {
        guard var current = session, current.invocation == .typedMarker, var handoff = current.handoff else { return }
        handoff.sourceReceived(key)
        current.handoff = handoff
        current.lastSourceKey = ProcessInfo.processInfo.systemUptime
        if handoff.problem == nil {
            // The key belongs to the query: it goes in after the other
            // source-side characters and before anything typed in the picker.
            viewController.insertIntoQuery(key.characters, at: current.sourceUnitsInQuery)
            current.sourceUnitsInQuery += key.characters.utf16.count
        }
        session = current
        if handoff.problem != nil {
            // An edit or a space reached the source: the colons were
            // ordinary typing. Leave everything as it is.
            services.diagnostics.record(.trigger, "handoff-abandoned")
            if machine.state != .capturing {
                perform(machine.handle(.cancel))
            }
            return
        }
        refreshContent(keepSelection: false)
        if machine.state == .browsing {
            perform(machine.handle(.sourceReceivedInput(current.id)))
            settleHandoff(current.id)
        }
    }

    /// Favourites, recents or the catalogue changed underneath the picker.
    func contentDidChange() {
        guard machine.isPickerVisible else { return }
        refreshContent(keepSelection: true)
    }

    // MARK: Effects

    private func perform(_ effects: [SessionEffect]) {
        for effect in effects {
            switch effect {
            case .capture(let id, let invocation):
                beginCapture(id, invocation: invocation, typedSource: nil)
            case .present(let id, let canInsert):
                present(id, canInsert: canInsert)
            case .dismiss:
                panel.orderOut(nil)
            case .awaitRelease(let id, _):
                awaitRelease(id)
            case .validate(let id):
                validate(id, attempt: 0)
            case .dispatch(let id):
                dispatch(id)
            case .copy(let id):
                if let chosen = session?.chosen {
                    insertion.copy(chosen.string)
                }
                perform(machine.handle(.copyFinished(id)))
            case .activationExpired:
                showNotice("Keys still held · press ↵ again")
            case .finish(let id, let outcome):
                finish(id, outcome: outcome)
            }
        }
    }

    // MARK: Capture and placement

    private func beginCapture(_ id: SessionID, invocation: Invocation, typedSource: pid_t?) {
        let screens = NSScreen.screens
        let displays = screens.enumerated().map { index, screen in
            // The first screen is the one with the menu bar; its frame
            // anchors both coordinate systems.
            DisplayGeometry(frame: screen.frame, visibleFrame: screen.visibleFrame, isPrimary: index == 0)
        }
        let primaryFrame = ScreenSpace.primaryFrame(in: displays) ?? .zero
        var current = Session(id: id, invocation: invocation, displays: displays, primaryFrame: primaryFrame)
        if invocation == .typedMarker {
            current.handoff = TriggerHandoff()
        }

        // A new session starts with an empty query.
        viewController.setQuery("")
        model.isNavigating = false
        model.selection = nil
        model.hover = nil
        model.notice = nil
        services.diagnostics.record(.invocation, "invoked-\(invocation.rawValue.lowercased())")

        let frontmost = NSWorkspace.shared.frontmostApplication
        let isExternal = frontmost.map { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier } ?? false
        current.sourceProcess = isExternal ? frontmost?.processIdentifier : nil
        session = current

        if let typedSource, frontmost?.processIdentifier != typedSource {
            // The user has already moved on to another application.
            perform(machine.handle(.markerUnconfirmed(id)))
            return
        }
        guard let frontmost, isExternal, Permissions.canInsert else {
            // Nothing can be read: Charms itself is in front, or
            // Accessibility has not been granted. Browse and copy.
            captureFinished(id, target: nil)
            return
        }
        capture.capture(application: frontmost, primaryFrame: primaryFrame) { [weak self] target in
            self?.captureFinished(id, target: target)
        }
        // A slow or hung application must not hold the picker back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.session?.id == id, self.session?.captureDone == false else { return }
                self.services.diagnostics.record(.capture, "capture-timeout", application: frontmost.bundleIdentifier)
                self.captureFinished(id, target: nil)
            }
        }
    }

    private func captureFinished(_ id: SessionID, target: CapturedTarget?) {
        guard var current = session, current.id == id, !current.captureDone, machine.state == .capturing else { return }
        current.captureDone = true
        current.target = target
        session = current
        if let target {
            services.diagnostics.record(.capture, target.isInsertable ? "capture-field" : "capture-no-field", application: target.bundleIdentifier, milliseconds: target.milliseconds)
        }
        let insertable = target?.isInsertable == true && Permissions.canInsert && !IsSecureEventInputEnabled()
        if current.invocation == .typedMarker {
            guard insertable else {
                perform(machine.handle(.markerUnconfirmed(id)))
                return
            }
            confirmMarker(id)
            return
        }
        perform(machine.handle(.captured(id, insertable ? .insertable : .copyOnly)))
    }

    private func placement(for current: Session) -> CGRect {
        let target = current.target
        var window = target?.windowFrame
        if window == nil, let source = current.sourceProcess {
            window = TargetCaptureService.windowListFrame(processID: source, primaryFrame: current.primaryFrame)
        }
        if window == nil, current.sourceProcess == nil {
            // Charms' own settings window is in front.
            window = NSApp.keyWindow?.frame
        }
        let container = window ?? target?.fieldFrame
        let probe = current.markerProbe ?? target?.probe ?? CaretProbe()
        let request = PlacementRequest(
            caret: CaretGeometry.estimate(probe, container: container),
            field: target?.fieldFrame,
            window: window,
            mouse: NSEvent.mouseLocation,
            displays: current.displays,
            panelSize: PickerPanel.size
        )
        guard let placement = PlacementEngine.place(request) else {
            return CGRect(origin: CGPoint(x: 100, y: 100), size: PickerPanel.size)
        }
        services.diagnostics.record(.placement, "placed-\(placement.source.rawValue.lowercased())-\(placement.side.rawValue.lowercased())", application: target?.bundleIdentifier)
        if let evidence = request.caret?.evidence, placement.source == .caret {
            services.diagnostics.record(.placement, "caret-\(evidence.rawValue.lowercased())")
        }
        return placement.frame
    }

    private func present(_ id: SessionID, canInsert: Bool) {
        guard var current = session, current.id == id else { return }
        model.canInsert = canInsert
        if !current.presented {
            panel.setFrame(placement(for: current), display: false)
            current.presented = true
            session = current
            refreshContent(keepSelection: false)
            let elapsed = (ProcessInfo.processInfo.systemUptime - current.started) * 1000
            services.diagnostics.record(.session, canInsert ? "presented-insert" : "presented-copy", milliseconds: elapsed)
        } else if !canInsert {
            showNotice("Target changed · ↵ copies", duration: 4)
        }
        panel.makeKeyAndOrderFront(nil)
        viewController.focusSearch()
        if current.invocation == .typedMarker, machine.state == .handoff {
            settleHandoff(id)
        }
    }

    // MARK: Typed marker

    /// How long the source may take to show the marker before the attempt
    /// is given up.
    private static let markerDeadline: TimeInterval = 0.35
    /// How long the source must have been quiet before its text is taken as
    /// settled.
    private static let quietInterval: TimeInterval = 0.06

    /// Waits until the source's own text shows `::`, plus whatever was typed
    /// after it, at an allowed boundary. The observer fires before the
    /// source has applied a key, so the first readings are often short.
    private func confirmMarker(_ id: SessionID) {
        guard let current = session, current.id == id, machine.state == .capturing,
              let target = current.target, let handoff = current.handoff else {
            return
        }
        guard handoff.problem == nil, ProcessInfo.processInfo.systemUptime - current.started < Self.markerDeadline else {
            services.diagnostics.record(.trigger, "marker-unconfirmed", application: target.bundleIdentifier)
            perform(machine.handle(.markerUnconfirmed(id)))
            return
        }
        let requested = handoff.expectedUTF16Length
        capture.readMarker(in: target, length: requested, primaryFrame: current.primaryFrame) { [weak self] reading in
            guard let self, var current = self.session, current.id == id, self.machine.state == .capturing,
                  let handoff = current.handoff else {
                return
            }
            guard let reading else {
                // The field offers no ranged text, or has a selection.
                self.services.diagnostics.record(.trigger, "marker-unreadable", application: target.bundleIdentifier)
                self.perform(self.machine.handle(.markerUnconfirmed(id)))
                return
            }
            let verdict = handoff.expectedUTF16Length == requested
                ? handoff.verify(caretLocation: reading.caretLocation, textBeforeCaret: reading.textBeforeCaret, precedingCharacter: reading.precedingCharacter)
                : .incomplete
            switch verdict {
            case .verified:
                current.markerProbe = reading.probe
                self.session = current
                self.services.diagnostics.record(.trigger, "marker-confirmed", application: target.bundleIdentifier)
                self.perform(self.machine.handle(.captured(id, .insertable)))
            case .notAtBoundary:
                self.services.diagnostics.record(.trigger, "marker-not-at-boundary")
                self.perform(self.machine.handle(.markerUnconfirmed(id)))
            case .incomplete, .mismatch:
                // A mismatch can be the source running ahead of the keys
                // observed so far; only the deadline makes it final.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) { [weak self] in
                    MainActor.assumeIsolated { self?.confirmMarker(id) }
                }
            }
        }
    }

    /// After the picker has the keyboard: waits for the source to go quiet
    /// and checks once more that it holds exactly the marker and prefix.
    private func settleHandoff(_ id: SessionID) {
        guard let current = session, current.id == id, machine.state == .handoff,
              let target = current.target, let handoff = current.handoff else {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - current.lastSourceKey > 1.0, !panel.isKeyWindow {
            perform(machine.handle(.handoffSettled(id, verified: false)))
            return
        }
        guard panel.isKeyWindow, now - current.lastSourceKey >= Self.quietInterval else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
                MainActor.assumeIsolated { self?.settleHandoff(id) }
            }
            return
        }
        let requested = handoff.expectedUTF16Length
        capture.readMarker(in: target, length: requested, primaryFrame: current.primaryFrame) { [weak self] reading in
            guard let self, let current = self.session, current.id == id, self.machine.state == .handoff,
                  let handoff = current.handoff else {
                return
            }
            var verified = false
            if let reading, handoff.expectedUTF16Length == requested,
               case .verified = handoff.verify(caretLocation: reading.caretLocation, textBeforeCaret: reading.textBeforeCaret, precedingCharacter: reading.precedingCharacter) {
                verified = true
            }
            let waited = ProcessInfo.processInfo.systemUptime - current.lastSourceKey
            if !verified, waited < Self.markerDeadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
                    MainActor.assumeIsolated { self?.settleHandoff(id) }
                }
                return
            }
            if !verified {
                self.services.diagnostics.record(.trigger, "handoff-unverified", application: target.bundleIdentifier)
            }
            self.perform(self.machine.handle(.handoffSettled(id, verified: verified)))
        }
    }

    // MARK: Commit

    private func activate(_ action: SessionAction, choosing item: PickerItem? = nil) {
        guard let chosen = item ?? model.selectedItem else { return }
        guard machine.state == .browsing || machine.state == .handoff else { return }
        // During handoff only the first choice counts. A second Return on
        // another cell must not replace what the first one froze.
        if machine.state == .handoff, machine.pendingActivation != nil { return }
        session?.chosen = chosen
        perform(machine.handle(.activate(action)))
    }

    /// Waits until Return, the mouse button and the modifiers are up, so
    /// that none of them reaches the source when focus goes back.
    private func awaitRelease(_ id: SessionID) {
        let gate = ReleaseGate(start: ProcessInfo.processInfo.systemUptime)
        func poll() {
            guard session?.id == id, machine.isWaitingForRelease else { return }
            switch gate.evaluate(KeyState.current(), now: ProcessInfo.processInfo.systemUptime) {
            case .released:
                perform(machine.handle(.keysReleased(id)))
            case .expired:
                perform(machine.handle(.releaseDeadlinePassed(id)))
            case .wait:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) {
                    MainActor.assumeIsolated { poll() }
                }
            }
        }
        poll()
    }

    /// Hands the keyboard back and makes sure the field that will receive
    /// the text is the one the session was opened for.
    private func validate(_ id: SessionID, attempt: Int) {
        guard let current = session, current.id == id, machine.state == .validating else { return }
        panel.orderOut(nil)
        guard let target = current.target else {
            perform(machine.handle(.validated(id, .copyOnly)))
            return
        }
        capture.revalidate(target, markerLength: current.handoff?.expectedUTF16Length, primaryFrame: current.primaryFrame) { [weak self] result in
            guard let self, let current = self.session, current.id == id, self.machine.state == .validating else { return }
            if let failure = result.check.failure {
                // Focus needs a moment to return after the panel goes away.
                if failure == .focusMoved, attempt < 4 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
                        MainActor.assumeIsolated { self?.validate(id, attempt: attempt + 1) }
                    }
                    return
                }
                self.services.diagnostics.record(.insertion, "blocked-\(Self.code(failure.rawValue))", application: target.bundleIdentifier)
                self.perform(self.machine.handle(.validated(id, result.check.validation)))
                return
            }
            guard let handoff = current.handoff else {
                self.perform(self.machine.handle(.validated(id, .valid)))
                return
            }
            // Typed session: the marker and prefix must still be exactly
            // what was typed. They are selected, never deleted blindly, and
            // the insertion then replaces that selection.
            guard let marker = result.marker,
                  case .verified(let location, let length) = handoff.verify(caretLocation: marker.caretLocation, textBeforeCaret: marker.textBeforeCaret, precedingCharacter: marker.precedingCharacter) else {
                self.services.diagnostics.record(.insertion, "blocked-marker-changed", application: target.bundleIdentifier)
                self.perform(self.machine.handle(.validated(id, .copyOnly)))
                return
            }
            self.capture.select(in: target, location: location, length: length) { [weak self] selected in
                guard let self, self.session?.id == id, self.machine.state == .validating else { return }
                if !selected {
                    self.services.diagnostics.record(.insertion, "blocked-selection-refused", application: target.bundleIdentifier)
                }
                self.perform(self.machine.handle(.validated(id, selected ? .valid : .copyOnly)))
            }
        }
    }

    private func dispatch(_ id: SessionID) {
        guard let current = session, current.id == id, let chosen = current.chosen, let target = current.target else {
            perform(machine.handle(.dispatchNotStarted(id)))
            return
        }
        let backend = InsertionPolicy.backend(forBundleIdentifier: target.bundleIdentifier, pasteApplications: services.preferences.value.pasteApplications)
        let result = insertion.insert(chosen.string, processID: target.processID, backend: backend, session: id)
        services.diagnostics.record(.insertion, "sent-\(backend == .paste ? "paste" : "unicode")", application: target.bundleIdentifier)
        switch result {
        case .dispatched: perform(machine.handle(.dispatchFinished(id)))
        case .notStarted: perform(machine.handle(.dispatchNotStarted(id)))
        }
    }

    private func finish(_ id: SessionID, outcome: SessionOutcome) {
        guard let current = session, current.id == id else { return }
        if outcome == .dispatched || outcome == .copied, let chosen = current.chosen {
            services.library.change { $0.recordUse(LibraryItem(string: chosen.string, name: chosen.name)) }
        }
        if outcome == .failedBeforeDispatch {
            NSSound.beep()
        }
        services.diagnostics.record(.session, "outcome-\(Self.code(outcome.rawValue))", application: current.target?.bundleIdentifier)
        session = nil
        onSessionEnded?()
    }

    // MARK: Content

    private func refreshContent(keepSelection: Bool) {
        let query = viewController.searchField.stringValue
        model.isQueryEmpty = query.allSatisfy(\.isWhitespace)
        guard let content = services.content else {
            model.sections = []
            model.isLoading = true
            return
        }
        model.isLoading = false
        let previous = model.selection
        let previousItem = model.selectedItem
        let glyphs = services.glyphs
        model.sections = content.sections(
            query: query,
            library: services.library.library,
            skinTone: services.preferences.value.skinTone,
            columns: PickerViewModel.columns,
            isSupported: { glyphs.isSupported($0) }
        )
        if keepSelection, let previousItem {
            model.selection = model.position(of: previousItem.string, preferringSection: previous?.section)
                ?? previous.flatMap { model.navigator.contains($0) ? $0 : nil }
                ?? model.navigator.first
        } else {
            // The first item is selected from the start, with or without a
            // query: the first favourite when the picker opens, the best
            // match while searching. Return always acts on a visible choice.
            model.selection = model.navigator.first
        }
        if model.selection == nil {
            model.isNavigating = false
        }
    }

    // MARK: PickerSearchDelegate

    func searchTextChanged(_ text: String) {
        // Typing always goes back to editing the query.
        model.isNavigating = false
        refreshContent(keepSelection: false)
    }

    func searchCommand(_ command: PickerCommand, caretAtEnd: Bool) -> Bool {
        switch command {
        case .cancel:
            perform(machine.handle(.cancel))
            return true
        case .activate:
            activate(.insert)
            return true
        case .contextMenu:
            showMenuForSelection()
            return true
        case .down:
            guard model.hasItems else { return true }
            if model.isNavigating || model.selection != nil {
                model.isNavigating = true
                move(.down)
            } else {
                enterGrid()
            }
            return true
        case .up:
            // From the search field there is nothing above.
            guard model.isNavigating else { return true }
            move(.up)
            return true
        case .right:
            if model.isNavigating {
                move(.right)
                return true
            }
            // At the end of the query Right has nothing to do in the text,
            // so it steps into the results instead.
            guard caretAtEnd, model.hasItems else { return false }
            if model.selection == nil {
                enterGrid()
            } else {
                model.isNavigating = true
                move(.right)
            }
            return true
        case .left:
            guard model.isNavigating else { return false }
            move(.left)
            return true
        case .tab, .backTab:
            if model.isNavigating {
                model.isNavigating = false
            } else if model.hasItems {
                enterGrid()
            }
            return true
        }
    }

    private func enterGrid() {
        model.isNavigating = true
        if model.selection == nil {
            model.selection = model.navigator.first
        }
        announceSelection()
    }

    private func move(_ direction: GridDirection) {
        switch model.navigator.move(from: model.selection, direction) {
        case .position(let position)?:
            model.selection = position
            announceSelection()
        case .searchField?:
            model.isNavigating = false
        case nil:
            break
        }
    }

    /// The search field keeps the keyboard, so VoiceOver would not notice
    /// the selection moving through the grid by itself.
    private func announceSelection() {
        guard NSWorkspace.shared.isVoiceOverEnabled, let item = model.selectedItem else { return }
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
            .announcement: item.name,
            .priority: NSAccessibilityPriorityLevel.high.rawValue
        ])
    }

    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard machine.isPickerVisible else { return false }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard flags == .command else { return false }
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            activate(.copy)
            return true
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "d":
            if let item = model.selectedItem { toggleFavourite(item) }
            return true
        case "c":
            // In the query, Command-C keeps copying selected query text.
            guard model.isNavigating, model.selectedItem != nil else { return false }
            activate(.copy)
            return true
        default:
            return false
        }
    }

    // MARK: Cell menu

    private func menuActions(for position: GridPosition) -> [PickerMenuAction] {
        guard let item = model.item(at: position), let content = services.content else { return [] }
        var actions: [PickerMenuAction] = []
        actions.append(PickerMenuAction(title: model.canInsert ? "Insert" : "Copy") { [weak self] in
            self?.model.selection = position
            self?.activate(.insert)
        })
        if model.canInsert {
            actions.append(PickerMenuAction(title: "Copy") { [weak self] in
                self?.model.selection = position
                self?.activate(.copy)
            })
        }
        actions.append(.separator)
        actions.append(PickerMenuAction(title: item.isFavourite ? "Remove from Favourites" : "Add to Favourites") { [weak self] in
            self?.toggleFavourite(item)
        })
        if item.isFavourite, model.sections.indices.contains(position.section), model.sections[position.section].kind == .favourites {
            let count = services.library.library.favourites.count
            let index = services.library.library.favourites.firstIndex { $0.string.isExactly(item.string) } ?? 0
            actions.append(PickerMenuAction(title: "Move Left", isEnabled: index > 0) { [weak self] in
                self?.moveFavourite(item, by: -1)
            })
            actions.append(PickerMenuAction(title: "Move Right", isEnabled: index < count - 1) { [weak self] in
                self?.moveFavourite(item, by: 1)
            })
        }
        if let base = item.variantBaseIndex {
            let glyphs = services.glyphs
            let variants = content.variants(ofBaseAt: base, library: services.library.library, isSupported: { glyphs.isSupported($0) })
            if variants.count > 1 {
                let children = variants.map { variant in
                    PickerMenuAction(title: "\(variant.string)  \(variant.name)") { [weak self] in
                        self?.activate(.insert, choosing: variant)
                    }
                }
                actions.append(.separator)
                actions.append(PickerMenuAction(title: "Skin Tone", children: children))
            }
        }
        return actions
    }

    private func toggleFavourite(_ item: PickerItem) {
        services.library.change { $0.toggleFavourite(LibraryItem(string: item.string, name: item.name)) }
        refreshContent(keepSelection: true)
    }

    private func moveFavourite(_ item: PickerItem, by offset: Int) {
        services.library.change { $0.moveFavourite(item.string, by: offset) }
        refreshContent(keepSelection: true)
    }

    /// Control-Return: the selected cell's menu, for use without a mouse.
    private func showMenuForSelection() {
        guard let position = model.selection else { return }
        let actions = menuActions(for: position)
        guard !actions.isEmpty, let view = panel.contentView else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for action in actions {
            menu.addItem(ClosureMenuItem.make(action))
        }
        var point = CGPoint(x: PickerViewModel.padding, y: 34)
        if let frame = model.selectedCellFrame {
            // SwiftUI reports the frame from the window's top-left corner.
            point = CGPoint(x: frame.minX, y: view.bounds.height - frame.maxY - 2)
        }
        isShowingMenu = true
        menu.popUp(positioning: nil, at: point, in: view)
        isShowingMenu = false
    }

    // MARK: Notices and cancellation

    private func showNotice(_ text: String, duration: TimeInterval = 2.5) {
        model.notice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.notice == text else { return }
                self.model.notice = nil
            }
        }
    }

    /// Anything that changes where the user is ends the session. A session
    /// never follows the user to another application, display or Space.
    private func observeEnvironment() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let activated = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let current = self.session else { return }
                if activated != current.sourceProcess, activated != ProcessInfo.processInfo.processIdentifier {
                    self.cancel(reason: "cancelled-application-changed")
                }
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let terminated = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let current = self.session, terminated == current.sourceProcess else { return }
                self.cancel(reason: "cancelled-application-quit")
            }
        })
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel(reason: "cancelled-context-changed") }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel(reason: "cancelled-displays-changed") }
        })
    }

    private func cancel(reason: String) {
        guard !machine.isIdle else { return }
        services.diagnostics.record(.session, reason)
        perform(machine.handle(.cancel))
    }

    /// Turns a camel-case identifier into a diagnostics code.
    private static func code(_ identifier: String) -> String {
        var code = ""
        for character in identifier {
            if character.isUppercase {
                code += "-" + character.lowercased()
            } else {
                code.append(character)
            }
        }
        return code
    }
}

/// A menu item that runs a closure.
private final class ClosureMenuItem: NSMenuItem {
    private var handler: (() -> Void)?

    static func make(_ action: PickerMenuAction) -> NSMenuItem {
        if action.isSeparator { return .separator() }
        let item = ClosureMenuItem(title: action.title, action: nil, keyEquivalent: "")
        item.isEnabled = action.isEnabled
        if !action.children.isEmpty {
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for child in action.children {
                submenu.addItem(make(child))
            }
            item.submenu = submenu
        } else if let perform = action.perform {
            item.handler = perform
            item.target = item
            item.action = #selector(run)
        }
        return item
    }

    @objc private func run() {
        handler?()
    }
}
