import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CharmsCore

/// What Charms knows about the place the user was typing when the picker
/// was invoked. It lives in memory for one session and is then discarded.
/// It holds references and rectangles, never text.
struct CapturedTarget: @unchecked Sendable {
    let processID: pid_t
    let launchDate: Date?
    let bundleIdentifier: String?
    let applicationName: String?
    /// The focused element. Used only on the capture queue.
    let element: AXUIElement?
    let isSecure: Bool
    let selection: CFRange?
    /// Rectangles around the caret, AppKit coordinates.
    let probe: CaretProbe
    let fieldFrame: CGRect?
    let windowFrame: CGRect?
    let milliseconds: Double
    /// The application reported no focused element and says that its
    /// accessibility tree is switched off (see `FieldAccess`).
    var hidesFields = false

    /// True when there is a field Charms may send text to.
    var isInsertable: Bool { element != nil && !isSecure }
}

/// A reading of the text just before the caret, for the typed trigger.
struct MarkerReading: Sendable {
    let caretLocation: Int
    let textBeforeCaret: String
    let precedingCharacter: String?
    /// Geometry at the caret, AppKit coordinates, read in the same pass.
    let probe: CaretProbe
}

/// Reads focus and geometry from other applications on one serial queue.
///
/// Accessibility calls block on the other process. Keeping them on a queue
/// of their own means a slow or hung application delays only its own
/// answer, which the caller then ignores once its deadline has passed.
final class TargetCaptureService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ch.lkmc.Charms.accessibility", qos: .userInteractive)

    init() {
        AX.applyMessagingTimeout()
    }

    /// Captures the frontmost application's focused field.
    func capture(application: NSRunningApplication, primaryFrame: CGRect, completion: @escaping @MainActor (CapturedTarget) -> Void) {
        let processID = application.processIdentifier
        let launchDate = application.launchDate
        let bundleIdentifier = application.bundleIdentifier
        let name = application.localizedName
        queue.async {
            let start = DispatchTime.now()
            let target = Self.read(processID: processID, launchDate: launchDate, bundleIdentifier: bundleIdentifier, name: name, primaryFrame: primaryFrame, start: start)
            Task { @MainActor in completion(target) }
        }
    }

    private static func read(processID: pid_t, launchDate: Date?, bundleIdentifier: String?, name: String?, primaryFrame: CGRect, start: DispatchTime) -> CapturedTarget {
        func elapsed() -> Double { Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000 }
        func convert(_ rect: CGRect?) -> CGRect? {
            rect.map { ScreenSpace.appKitRect(fromAccessibility: $0, primaryFrame: primaryFrame) }
        }

        let application = AX.application(processID)
        let window = AX.element(application, kAXFocusedWindowAttribute)
        guard AXIsProcessTrusted(), let element = AX.element(application, kAXFocusedUIElementAttribute) else {
            return CapturedTarget(
                processID: processID, launchDate: launchDate, bundleIdentifier: bundleIdentifier, applicationName: name,
                element: nil, isSecure: false, selection: nil, probe: CaretProbe(), fieldFrame: nil,
                windowFrame: convert(window.flatMap(AX.frame)), milliseconds: elapsed(),
                hidesFields: AXIsProcessTrusted() && AX.manualAccessibility(application) == false
            )
        }
        AXUIElementSetMessagingTimeout(element, AX.messagingTimeout)

        // A password field is recognised by its role alone; its contents
        // are never looked at.
        let isSecure = AX.string(element, kAXSubroleAttribute) == (kAXSecureTextFieldSubrole as String)
            || AX.string(element, kAXRoleAttribute) == "AXSecureTextField"
        let ownWindow = AX.element(element, kAXWindowAttribute) ?? window
        let selection = isSecure ? nil : AX.range(element, kAXSelectedTextRangeAttribute)
        // The reported selection is kept as it is for the comparison before
        // dispatch; geometry is only asked for a range that can exist.
        let probe = selection.flatMap { SourceTextRange(location: $0.location, length: $0.length) }
            .map { Self.probe(element, selection: $0, primaryFrame: primaryFrame) } ?? CaretProbe()

        return CapturedTarget(
            processID: processID, launchDate: launchDate, bundleIdentifier: bundleIdentifier, applicationName: name,
            element: element, isSecure: isSecure, selection: selection, probe: probe,
            fieldFrame: convert(AX.frame(element)), windowFrame: convert(ownWindow.flatMap(AX.frame)), milliseconds: elapsed()
        )
    }

    /// Rectangles of the caret and of the one character on either side.
    /// Geometry only: the characters themselves are not read.
    private static func probe(_ element: AXUIElement, selection: SourceTextRange, primaryFrame: CGRect) -> CaretProbe {
        func convert(_ rect: CGRect?) -> CGRect? {
            rect.map { ScreenSpace.appKitRect(fromAccessibility: $0, primaryFrame: primaryFrame) }
        }
        let end = selection.end
        return CaretProbe(
            caret: convert(AX.bounds(element, location: end, length: 0)),
            previousCharacter: end > 0 ? convert(AX.bounds(element, location: end - 1, length: 1)) : nil,
            nextCharacter: convert(AX.bounds(element, location: end, length: 1)),
            selection: selection.length > 0 ? convert(AX.bounds(element, location: selection.location, length: selection.length)) : nil
        )
    }

    /// Reads at most `length` UTF-16 units before the caret and the single
    /// character before those: the marker, the query prefix typed after it,
    /// and the boundary. Returns nil when the selection is not a collapsed
    /// caret or the field does not offer ranged text.
    func readMarker(in target: CapturedTarget, length: Int, primaryFrame: CGRect, completion: @escaping @MainActor (MarkerReading?) -> Void) {
        queue.async {
            let reading = Self.readMarker(in: target, length: length, primaryFrame: primaryFrame)
            Task { @MainActor in completion(reading) }
        }
    }

    private static func readMarker(in target: CapturedTarget, length: Int, primaryFrame: CGRect) -> MarkerReading? {
        guard let element = target.element, !target.isSecure, !IsSecureEventInputEnabled(),
              let selection = AX.usableRange(element, kAXSelectedTextRangeAttribute), selection.length == 0 else {
            return nil
        }
        let caret = selection.location
        let available = min(length, caret)
        let start = caret - available
        guard let text = AX.text(element, location: start, length: available) else { return nil }
        let preceding = start > 0 ? AX.text(element, location: start - 1, length: 1) : nil
        if start > 0, preceding == nil { return nil }
        return MarkerReading(
            caretLocation: caret, textBeforeCaret: text, precedingCharacter: preceding,
            probe: probe(element, selection: selection, primaryFrame: primaryFrame)
        )
    }

    /// The facts the final check before dispatch is made from.
    struct Revalidation: Sendable {
        let check: TargetCheck
        /// For a typed session, the marker as it is now.
        let marker: MarkerReading?
    }

    func revalidate(_ target: CapturedTarget, markerLength: Int?, primaryFrame: CGRect, completion: @escaping @MainActor (Revalidation) -> Void) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let running = NSRunningApplication(processIdentifier: target.processID)
        let sameProcess = running != nil && running?.isTerminated == false && running?.launchDate == target.launchDate
        let isFrontmost = frontmost?.processIdentifier == target.processID
        queue.async {
            var sameElement = false
            var isSecure = target.isSecure
            var selectionUnchanged: Bool?
            if sameProcess, let element = target.element {
                let application = AX.application(target.processID)
                if let current = AX.element(application, kAXFocusedUIElementAttribute) {
                    sameElement = CFEqual(current, element)
                    isSecure = AX.string(current, kAXSubroleAttribute) == (kAXSecureTextFieldSubrole as String)
                }
                if sameElement, markerLength == nil, let captured = target.selection {
                    // A shortcut session inserts at the selection it saw.
                    selectionUnchanged = AX.range(element, kAXSelectedTextRangeAttribute).map {
                        $0.location == captured.location && $0.length == captured.length
                    }
                }
            }
            let check = TargetCheck(
                accessibilityTrusted: AXIsProcessTrusted(), secureInputActive: IsSecureEventInputEnabled(),
                sameProcess: sameProcess, processIsFrontmost: isFrontmost, sameElement: sameElement,
                elementIsSecure: isSecure, selectionUnchanged: selectionUnchanged
            )
            let marker = (check.failure == nil ? markerLength : nil).flatMap {
                Self.readMarker(in: target, length: $0, primaryFrame: primaryFrame)
            }
            Task { @MainActor in completion(Revalidation(check: check, marker: marker)) }
        }
    }

    /// How long a field may take to report a selection it was asked to
    /// make. AppKit and WebKit report it at once. Chromium accepts the call
    /// and applies the selection from its renderer afterwards: measured with
    /// Electron 45 on macOS 27, the first reading after the call still shows
    /// the old range and the new one arrives about 3 ms later. The bound is
    /// generous because a busy page takes longer, and because giving up
    /// means the character is not inserted.
    private static let selectionDeadline: TimeInterval = 0.3
    private static let selectionPollInterval: TimeInterval = 0.004

    /// Selects exactly the marker and the prefix typed after it, and
    /// confirms that the selection took. Only a selection the field itself
    /// reports counts: the insertion that follows replaces whatever is
    /// selected.
    func select(in target: CapturedTarget, location: Int, length: Int, completion: @escaping @MainActor (Bool) -> Void) {
        queue.async {
            var succeeded = false
            if let element = target.element, AX.setSelectedRange(element, location: location, length: length) {
                let deadline = ProcessInfo.processInfo.systemUptime + Self.selectionDeadline
                while true {
                    if let now = AX.range(element, kAXSelectedTextRangeAttribute), now.location == location, now.length == length {
                        succeeded = true
                        break
                    }
                    guard ProcessInfo.processInfo.systemUptime < deadline else { break }
                    Thread.sleep(forTimeInterval: Self.selectionPollInterval)
                }
            }
            Task { @MainActor in completion(succeeded) }
        }
    }

    // MARK: Applications that hide their fields

    /// How long an application may take to report a focused element after
    /// it was asked to. Measured with Electron 45: about two seconds.
    private static let fieldsDeadline: TimeInterval = 5
    private static let fieldsPollInterval: TimeInterval = 0.05

    /// Asks an application to switch its accessibility tree on and waits
    /// for it to report a focused element. Reports whether it did.
    ///
    /// The wait runs off the capture queue, which has to stay free for the
    /// next session.
    func requestFields(processID: pid_t, completion: @escaping @MainActor (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let application = AX.application(processID)
            var appeared = false
            if AX.requestManualAccessibility(application) {
                let deadline = ProcessInfo.processInfo.systemUptime + Self.fieldsDeadline
                while ProcessInfo.processInfo.systemUptime < deadline {
                    if AX.element(application, kAXFocusedUIElementAttribute) != nil {
                        appeared = true
                        break
                    }
                    Thread.sleep(forTimeInterval: Self.fieldsPollInterval)
                }
            }
            Task { @MainActor in completion(appeared) }
        }
    }

    /// For an application the user agreed about earlier: asks it again if
    /// its tree is off, as it is after every start. Does not wait.
    func requestFieldsIfHidden(processID: pid_t) {
        queue.async {
            let application = AX.application(processID)
            guard AXIsProcessTrusted(), AX.manualAccessibility(application) == false else { return }
            _ = AX.requestManualAccessibility(application)
        }
    }

    /// Bounds of the frontmost ordinary window of a process from the window
    /// list, for placement when Accessibility offers nothing. Needs no
    /// permission and reads no window titles.
    static func windowListFrame(processID: pid_t, primaryFrame: CGRect) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for window in list {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == processID,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width > 50, bounds.height > 50 else {
                continue
            }
            // Window-list bounds use the same top-left origin as Accessibility.
            return ScreenSpace.appKitRect(fromAccessibility: bounds, primaryFrame: primaryFrame)
        }
        return nil
    }
}
