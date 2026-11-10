import AppKit
import CharmsCore
import Combine
import SwiftUI

/// The first-launch window: what Charms does, and the one choice between
/// inserting characters where the user types and only copying them.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let services: AppServices
    private let onFinished: () -> Void
    private let state = OnboardingState()
    private var window: NSWindow?
    private var timer: Timer?
    private var shortcutObservation: AnyCancellable?

    init(services: AppServices, onFinished: @escaping () -> Void) {
        self.services = services
        self.onFinished = onFinished
        super.init()
        // The window names the shortcut. It follows the setting, so that it
        // never tells the user to press a combination that was just changed.
        shortcutObservation = services.preferences.$value
            .map { HotKeyService.displayString(for: $0.shortcut) }
            .removeDuplicates()
            .sink { [state] in state.shortcut = $0 }
    }

    func show() {
        if window == nil {
            let view = OnboardingView(
                state: state,
                enable: { [weak self] in self?.enableInsertion() },
                finish: { [weak self] in self?.finish() }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Welcome to Charms"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        state.canInsert = Permissions.canInsert
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func enableInsertion() {
        state.isWaiting = true
        Permissions.requestInsertion()
        // The system sends no notice when the permission is granted. While
        // this window is open, and only then, look once a second.
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Permissions.canInsert {
                    self.state.canInsert = true
                    self.state.isWaiting = false
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }
        }
    }

    private func finish() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        services.preferences.update { $0.hasCompletedOnboarding = true }
        services.diagnostics.record(.permission, Permissions.canInsert ? "onboarding-insertion" : "onboarding-copy-only")
        onFinished()
    }
}

@MainActor
final class OnboardingState: ObservableObject {
    @Published var canInsert = false
    @Published var isWaiting = false
    @Published var shortcut = ""
}

private struct OnboardingView: View {
    @ObservedObject var state: OnboardingState
    let enable: () -> Void
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Charms")
                .font(.largeTitle.weight(.semibold))
            Text("Press \(state.shortcut) wherever you are typing. Type a name such as arrow, check or heart, and press Return. The character goes where your cursor was.")
                .fixedSize(horizontal: false, vertical: true)
            Text("To put characters into other applications, Charms needs the Accessibility permission, which macOS 27 calls Device Control and Data Access. It uses it to find the field you are typing in, so the picker can open next to it, and to send the chosen character there. It does not read your documents.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if state.canInsert {
                Label("Insertion is enabled.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if state.isWaiting {
                // The list has different names in different versions of
                // macOS, so it is described rather than named.
                Label("Open System Settings from the message that appeared and switch on Charms in the list. This window notices when you have.", systemImage: "arrow.up.forward.app")
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if state.canInsert {
                    Spacer()
                    Button("Done", action: finish).keyboardShortcut(.defaultAction)
                } else {
                    Button("Browse and Copy", action: finish)
                        .help("Use Charms without the permission. Return copies the character and you paste it yourself.")
                    Spacer()
                    Button("Enable Insertion", action: enable).keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 6)
            Text("You can change this later in Settings. The menu-bar icon opens Charms too.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 460)
    }
}
