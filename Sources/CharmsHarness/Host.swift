import AppKit

/// A window with known text controls, standing in for "the application the
/// user is typing in". It answers questions about its own contents, so a
/// check can compare what Charms inserted with what arrived, scalar for
/// scalar, without going through Accessibility.
@MainActor
final class Host: NSObject, NSApplicationDelegate, NSWindowDelegate {
    nonisolated static let commandNotification = Notification.Name("ch.lkmc.CharmsHarness.command")

    nonisolated static func replyURL(for identifier: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("charms-harness-reply-\(identifier).json")
    }

    private let arguments: Arguments
    private var window: NSWindow!
    private let editor = HostTextView()
    private let field = NSTextField()
    private let secret = NSSecureTextField()

    init(arguments: Arguments) {
        self.arguments = arguments
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
        makeWindow()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(command(_:)), name: Self.commandNotification, object: nil,
            suspensionBehavior: .deliverImmediately
        )
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        print(Output.encode(["pid": Int(ProcessInfo.processInfo.processIdentifier), "ready": true]))
        fflush(stdout)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Window

    private func makeWindow() {
        let width = arguments.number("width") ?? 560
        let height = arguments.number("height") ?? 420
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.title = "Charms Harness"
        window.isReleasedWhenClosed = false
        window.delegate = self

        editor.isRichText = false
        editor.allowsUndo = true
        editor.font = .systemFont(ofSize: 14)
        // Nothing may rewrite what a check types or what Charms inserts.
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true
        editor.setAccessibilityIdentifier("editor")
        editor.string = arguments.string("text") ?? ""

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = editor
        scroll.borderType = .bezelBorder
        field.setAccessibilityIdentifier("field")
        field.placeholderString = "field"
        secret.setAccessibilityIdentifier("secret")
        secret.placeholderString = "secret"

        let stack = NSStackView(views: [scroll, field, secret])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        window.contentView = stack
        editor.frame = CGRect(x: 0, y: 0, width: width - 40, height: 10)

        if let x = arguments.number("x"), let y = arguments.number("y") {
            window.setFrameTopLeftPoint(CGPoint(x: x, y: y))
        } else {
            window.center()
        }
    }

    private func makeMenu() -> NSMenu {
        let main = NSMenu()
        let application = NSMenu()
        application.addItem(withTitle: "Quit Charms Harness", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = application

        // The standard Edit commands, so Undo, Paste and Select All behave
        // as they do in a real application.
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        return main
    }

    // MARK: Commands

    @objc private func command(_ notification: Notification) {
        guard let text = notification.object as? String,
              let request = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let identifier = request["id"] as? String, let operation = request["op"] as? String else {
            return
        }
        var reply: [String: Any]
        if let problem = perform(operation, request) {
            reply = ["error": problem]
        } else {
            reply = state()
            reply["ok"] = true
        }
        try? Data(Output.encode(reply).utf8).write(to: Self.replyURL(for: identifier), options: .atomic)
    }

    /// Returns a description of what was wrong with the request, or nil.
    private func perform(_ operation: String, _ request: [String: Any]) -> String? {
        switch operation {
        case "state":
            return nil
        case "setText":
            guard let text = request["text"] as? String else { return "setText needs text" }
            editor.string = text
            editor.undoManager?.removeAllActions()
            editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        case "select":
            guard let location = request["location"] as? Int, let length = request["length"] as? Int,
                  location >= 0, length >= 0, location + length <= (editor.string as NSString).length else {
                return "select needs a location and length inside the text"
            }
            editor.setSelectedRange(NSRange(location: location, length: length))
        case "focus":
            let targets: [String: NSView] = ["editor": editor, "field": field, "secret": secret]
            guard let name = request["target"] as? String, let view = targets[name] else {
                return "focus needs a target of editor, field or secret"
            }
            window.makeFirstResponder(view)
        case "undo":
            editor.undoManager?.undo()
        case "selectionDelay":
            guard let milliseconds = request["ms"] as? Double else { return "selectionDelay needs ms" }
            editor.accessibilitySelectionDelay = milliseconds < 0 ? nil : milliseconds / 1000
        case "activate":
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        case "move":
            guard let x = request["x"] as? Double, let y = request["y"] as? Double else { return "move needs x and y" }
            window.setFrameTopLeftPoint(CGPoint(x: x, y: y))
        default:
            return "unknown op \(operation)"
        }
        return nil
    }

    private func state() -> [String: Any] {
        let selection = editor.selectedRange()
        return [
            "editor": editor.string,
            "editorSelection": [selection.location, selection.length],
            "field": field.stringValue,
            // The length only: enough to see that nothing was typed into
            // the password field.
            "secretLength": secret.stringValue.utf16.count,
            "firstResponder": firstResponderName,
            "isActive": NSApp.isActive,
            "isKeyWindow": window.isKeyWindow,
            "windowFrame": Inspect.rectangle(window.frame)
        ]
    }

    private var firstResponderName: String {
        guard let responder = window.firstResponder else { return "other" }
        if responder === editor { return "editor" }
        // A text field being edited hands first responder to its field
        // editor, whose delegate is the field.
        if let fieldEditor = responder as? NSTextView, let owner = fieldEditor.delegate as? NSTextField {
            if owner === secret { return "secret" }
            if owner === field { return "field" }
        }
        return "other"
    }

    // MARK: Client

    /// Asks the running host to perform `request` and returns its reply.
    nonisolated static func send(_ request: [String: Any], timeout: TimeInterval) -> [String: Any] {
        let identifier = UUID().uuidString
        var request = request
        request["id"] = identifier
        let url = replyURL(for: identifier)
        DistributedNotificationCenter.default().postNotificationName(
            commandNotification, object: Output.encode(request), userInfo: nil, deliverImmediately: true
        )
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                try? FileManager.default.removeItem(at: url)
                return reply
            }
            usleep(10_000)
        }
        Output.fail("the host did not answer; is `CharmsHarness host` running?")
    }
}

/// The editor. It can imitate applications that do not apply a selection
/// made through Accessibility at once.
final class HostTextView: NSTextView {
    /// How long a selection set through Accessibility takes to arrive. Zero
    /// is what AppKit does. Chromium answers the call at once and applies the
    /// selection from its renderer afterwards: measured with Electron 45,
    /// about 3 ms later. Nil drops the request, for a field that accepts the
    /// call and never honours it.
    var accessibilitySelectionDelay: TimeInterval? = 0

    override func setAccessibilitySelectedTextRange(_ range: NSRange) {
        guard let delay = accessibilitySelectionDelay else { return }
        guard delay > 0 else {
            super.setAccessibilitySelectedTextRange(range)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, NSMaxRange(range) <= (self.string as NSString).length else { return }
            self.setSelectedRange(range)
        }
    }
}
