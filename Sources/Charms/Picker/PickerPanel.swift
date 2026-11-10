import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The picker's window: a borderless panel that can take the keyboard
/// without activating Charms.
///
/// Measured on macOS 27: with the non-activating style this panel becomes
/// key about 10 ms after it is ordered front while the application being
/// typed in stays frontmost, and when the panel is ordered out the same
/// field has keyboard focus again within a few milliseconds. That is what
/// lets a character go back to where the user was typing.
final class PickerPanel: NSPanel {
    static let size = CGSize(width: 392, height: 320)

    /// Keys the search field never sees as commands: Command-Return,
    /// Command-D and Command-C. Returns true when the key was used.
    var onKeyEquivalent: ((NSEvent) -> Bool)?
    var onResignKey: (() -> Void)?

    init() {
        super.init(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: true
        )
        level = .floating
        // Join whichever Space is current, including another application's
        // full-screen Space, instead of pulling the user to a different one.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // Charms is never the active application while the picker is open,
        // so hiding on deactivation would hide it at once.
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        setAccessibilityLabel("Charms")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyEquivalent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// What the search field asks of its owner.
@MainActor
protocol PickerSearchDelegate: AnyObject {
    func searchTextChanged(_ text: String)
    /// A command key such as an arrow or Return. Returns true when handled.
    func searchCommand(_ command: PickerCommand, caretAtEnd: Bool) -> Bool
}

enum PickerCommand {
    case up, down, left, right
    case activate
    case contextMenu
    case cancel
    case tab, backTab
}

/// Lays out the search field, the grid and the footer.
@MainActor
final class PickerViewController: NSViewController, NSTextFieldDelegate {
    let searchField = NSTextField()
    weak var searchDelegate: PickerSearchDelegate?
    private let model: PickerViewModel

    init(model: PickerViewModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PickerViewController is created in code")
    }

    override func loadView() {
        let effect = NSVisualEffectView(frame: CGRect(origin: .zero, size: PickerPanel.size))
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.cgColor

        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 17)
        searchField.placeholderString = "Search arrows, symbols, emoji…"
        searchField.delegate = self
        searchField.usesSingleLineMode = true
        searchField.lineBreakMode = .byTruncatingHead
        searchField.cell?.isScrollable = true
        searchField.setAccessibilityLabel("Search characters")
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let escapeHint = NSTextField(labelWithString: "esc")
        escapeHint.font = .systemFont(ofSize: 11)
        escapeHint.textColor = .tertiaryLabelColor
        escapeHint.setAccessibilityElement(false)
        escapeHint.translatesAutoresizingMaskIntoConstraints = false

        // The hosting views take their size from the constraints below and
        // must not push their own ideal size back onto the borderless
        // window, which would make the panel jump while typing.
        let grid = NSHostingView(rootView: PickerGridView(model: model))
        grid.sizingOptions = []
        grid.translatesAutoresizingMaskIntoConstraints = false
        let footer = NSHostingView(rootView: PickerFooterView(model: model))
        footer.sizingOptions = []
        footer.translatesAutoresizingMaskIntoConstraints = false
        let upperRule = Self.rule()
        let lowerRule = Self.rule()

        for view in [searchField, escapeHint, upperRule, grid, lowerRule, footer] {
            effect.addSubview(view)
        }
        NSLayoutConstraint.activate([
            effect.widthAnchor.constraint(equalToConstant: PickerPanel.size.width),
            effect.heightAnchor.constraint(equalToConstant: PickerPanel.size.height),

            searchField.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: escapeHint.leadingAnchor, constant: -8),
            searchField.centerYAnchor.constraint(equalTo: effect.topAnchor, constant: 23),
            escapeHint.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -14),
            escapeHint.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),

            upperRule.topAnchor.constraint(equalTo: effect.topAnchor, constant: 46),
            upperRule.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            upperRule.trailingAnchor.constraint(equalTo: effect.trailingAnchor),

            grid.topAnchor.constraint(equalTo: upperRule.bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: lowerRule.topAnchor),

            lowerRule.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            lowerRule.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            lowerRule.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 30)
        ])
        view = effect
    }

    private static func rule() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    /// Puts the keyboard into the search field with the caret at the end.
    func focusSearch() {
        view.window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectedRange = NSRange(location: (searchField.stringValue as NSString).length, length: 0)
    }

    func setQuery(_ text: String) {
        searchField.stringValue = text
        searchField.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }

    /// Inserts text at a UTF-16 offset of the query, keeping the caret after
    /// what the user has typed in the picker.
    func insertIntoQuery(_ text: String, at offset: Int) {
        let current = searchField.stringValue as NSString
        let location = max(0, min(offset, current.length))
        let editor = searchField.currentEditor()
        let caret = editor?.selectedRange
        searchField.stringValue = current.replacingCharacters(in: NSRange(location: location, length: 0), with: text)
        if let editor, let caret {
            let added = (text as NSString).length
            let moved = caret.location >= location ? caret.location + added : caret.location
            editor.selectedRange = NSRange(location: moved, length: caret.length)
        }
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        searchDelegate?.searchTextChanged(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // While an input method is composing, Return, the arrows and Escape
        // belong to its candidate window, not to the picker.
        if textView.hasMarkedText() { return false }
        let caretAtEnd = textView.selectedRange.length == 0 && textView.selectedRange.location == (textView.string as NSString).length
        let command: PickerCommand
        switch selector {
        case #selector(NSResponder.moveUp(_:)): command = .up
        case #selector(NSResponder.moveDown(_:)): command = .down
        case #selector(NSResponder.moveLeft(_:)): command = .left
        case #selector(NSResponder.moveRight(_:)): command = .right
        case #selector(NSResponder.insertNewline(_:)): command = .activate
        case #selector(NSResponder.insertLineBreak(_:)): command = .contextMenu
        case #selector(NSResponder.cancelOperation(_:)): command = .cancel
        case #selector(NSResponder.insertTab(_:)): command = .tab
        case #selector(NSResponder.insertBacktab(_:)): command = .backTab
        default: return false
        }
        return searchDelegate?.searchCommand(command, caretAtEnd: caretAtEnd) ?? false
    }
}
