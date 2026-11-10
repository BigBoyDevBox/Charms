import AppKit
import CharmsCore
import SwiftUI

/// A button that records a keyboard shortcut: click it, then press the keys.
struct ShortcutRecorder: NSViewRepresentable {
    let combo: KeyCombo
    /// Called when recording starts and ends, so the global shortcut can be
    /// released meanwhile and does not open the picker.
    let onRecordingChanged: (Bool) -> Void
    let onRecorded: (KeyCombo) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onRecordingChanged = onRecordingChanged
        button.onRecorded = onRecorded
        button.combo = combo
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.onRecordingChanged = onRecordingChanged
        button.onRecorded = onRecorded
        button.combo = combo
    }
}

final class RecorderButton: NSButton {
    var onRecordingChanged: ((Bool) -> Void)?
    var onRecorded: ((KeyCombo) -> Void)?
    var combo: KeyCombo = .standard { didSet { refreshTitle() } }

    private var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            refreshTitle()
            onRecordingChanged?(isRecording)
        }
    }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        setAccessibilityLabel("Keyboard shortcut")
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RecorderButton is created in code")
    }

    override var acceptsFirstResponder: Bool { true }

    private func refreshTitle() {
        title = isRecording ? "Press a shortcut…" : HotKeyService.displayString(for: combo)
        setAccessibilityValue(isRecording ? "Recording" : title)
    }

    @objc private func toggleRecording() {
        if isRecording {
            isRecording = false
        } else {
            window?.makeFirstResponder(self)
            isRecording = true
        }
    }

    /// Leaving the button, by Tab or by a click elsewhere, ends recording
    /// without changing the shortcut.
    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        record(event)
    }

    /// Combinations with Command arrive here, not in `keyDown`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    private func record(_ event: NSEvent) {
        let modifiers = HotKeyService.modifiers(from: event.modifierFlags)
        // Escape alone leaves the shortcut as it was.
        if event.keyCode == 53, modifiers.isEmpty {
            isRecording = false
            return
        }
        isRecording = false
        onRecorded?(KeyCombo(keyCode: event.keyCode, modifiers: modifiers))
    }
}
