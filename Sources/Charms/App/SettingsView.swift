import AppKit
import CharmsCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let model: SettingsModel
    private var window: NSWindow?

    init(model: SettingsModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model, preferences: model.services.preferences))
            // Only the minimum comes from the content. With the default
            // options the window would also be pinned to the content's
            // ideal size and could not be resized.
            hosting.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "Charms Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentMinSize = SettingsView.minimumSize
            window.setContentSize(Self.initialSize(for: window))
            window.center()
            self.window = window
        }
        // An accessory app is not activated by showing a window.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// The default size, shortened on a display too small to show it whole.
    private static func initialSize(for window: NSWindow) -> NSSize {
        var size = SettingsView.defaultSize
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            let titleBar = window.frame.height - window.contentLayoutRect.height
            size.height = max(SettingsView.minimumSize.height, min(size.height, visible.height - titleBar))
        }
        return size
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var preferences: PreferencesStore

    /// Tall enough to show each tab whole, so that nothing has to be
    /// scrolled to be found. The longest are General and Applications.
    static let defaultSize = NSSize(width: 600, height: 680)
    static let minimumSize = NSSize(width: 520, height: 400)

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            typing.tabItem { Label("Typing ::", systemImage: "keyboard") }
            applications.tabItem { Label("Applications", systemImage: "app.badge") }
            data.tabItem { Label("Data", systemImage: "tray.full") }
        }
        .padding(16)
        .frame(minWidth: Self.minimumSize.width, maxWidth: .infinity, minHeight: Self.minimumSize.height, maxHeight: .infinity)
    }

    // MARK: General

    private var general: some View {
        Form {
            Section {
                LabeledContent("Open Charms") {
                    HStack {
                        ShortcutRecorder(
                            combo: preferences.value.shortcut,
                            onRecordingChanged: { model.recordingChanged($0) },
                            onRecorded: { model.recorded($0) }
                        )
                        .frame(width: 150, height: 24)
                        Button("Reset") { model.resetShortcut() }
                            .disabled(preferences.value.shortcut == .standard)
                    }
                }
                if let message = model.shortcutMessage {
                    Text(message).font(.callout).foregroundStyle(.orange)
                }
                Text("The shortcut works in every application and overrides what the same keys do there. To turn it off for an application that needs those keys, add the application under Applications. If another utility uses the same shortcut, the one started first gets it: quit that one or record a different shortcut.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Insertion") {
                    if model.canInsert {
                        Label("Enabled", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Enable Insertion…") { model.enableInsertion() }
                    }
                }
                Text(model.canInsert
                     ? "Charms can find the field you are typing in and put the chosen character there."
                     : "Charms can browse and copy. To insert characters where you type, press Enable Insertion and switch on Charms in the System Settings list it leads to. If Charms is already switched on there, switch it off and on again.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Open Charms at login", isOn: Binding(
                    get: { model.launchState == .on || model.launchState == .needsApproval },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .disabled(model.launchState == .unavailable)
                if model.launchState == .needsApproval {
                    HStack {
                        Text("Allow Charms under Login Items to finish.").font(.callout).foregroundStyle(.orange)
                        Button("Open Login Items…") { LaunchAtLogin.openLoginItemsSettings() }
                    }
                } else if model.launchState == .unavailable {
                    Text("Move Charms to the Applications folder to use this.").font(.callout).foregroundStyle(.secondary)
                }
                if let message = model.launchMessage {
                    Text(message).font(.callout).foregroundStyle(.orange)
                }
                Picker("Emoji skin tone", selection: Binding(
                    get: { preferences.value.skinTone },
                    set: { tone in preferences.update { $0.skinTone = tone } }
                )) {
                    ForEach(SkinTone.allCases, id: \.self) { tone in
                        Text(Self.label(for: tone)).tag(tone)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private static func label(for tone: SkinTone) -> String {
        switch tone {
        case .none: return "👋  Default"
        case .light: return "👋🏻  Light"
        case .mediumLight: return "👋🏼  Medium-light"
        case .medium: return "👋🏽  Medium"
        case .mediumDark: return "👋🏾  Medium-dark"
        case .dark: return "👋🏿  Dark"
        }
    }

    // MARK: Typing ::

    private var typing: some View {
        Form {
            Section {
                Toggle("Open Charms by typing ::", isOn: Binding(
                    get: { preferences.value.typedTriggerEnabled && model.canInsert },
                    set: { model.setTypedTrigger($0) }
                ))
                .disabled(!model.canInsert)
                if !model.canInsert {
                    HStack {
                        Text("Enable Insertion to use the typed trigger.").font(.callout).foregroundStyle(.orange)
                        Button("Enable Insertion…") { model.enableInsertion() }
                    }
                }
                Text("Type two colons at the start of a field or after a space, keep typing a name such as ::arrow, and press Return. The colons and the name are replaced by the character. Escape closes the picker and leaves the colons in your text.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("While this is on, Charms watches the keys typed in other applications for the two colons. It keeps nothing but a colon it is waiting to see repeated, sends nothing anywhere, and stops watching when you turn this off.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Never in these applications") {
                ApplicationList(
                    identifiers: Binding(
                        get: { preferences.value.triggerExclusions },
                        set: { list in preferences.update { $0.triggerExclusions = list } }
                    ),
                    model: model
                )
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Applications

    private var applications: some View {
        Form {
            Section("Turn off the shortcut in these applications") {
                ApplicationList(
                    identifiers: Binding(
                        get: { preferences.value.shortcutPassThrough },
                        set: { list in preferences.update { $0.shortcutPassThrough = list } }
                    ),
                    model: model
                )
                Text("While one of these applications is in front, the shortcut does not open Charms and its keys reach the application instead. Add applications that need those keys themselves, such as a terminal, where ⌃P brings back the previous command.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Insert by pasting in these applications") {
                ApplicationList(
                    identifiers: Binding(
                        get: { preferences.value.pasteApplications },
                        set: { list in preferences.update { $0.pasteApplications = list } }
                    ),
                    model: model
                )
                Text("For applications where a chosen character does not arrive. Charms then puts it on the clipboard, sends Paste, and puts back what was there, unless you copied something else meanwhile or the system would have to ask before the clipboard can be read.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Data

    private var data: some View {
        Form {
            Section {
                LabeledContent("Recents") {
                    Button("Clear Recents") { model.clearRecents() }
                }
                LabeledContent("Favourites") {
                    Button("Restore Default Favourites") { model.restoreDefaultFavourites() }
                }
                Text("Restoring replaces your favourites with the set Charms started with. To remove a single favourite, select it in the picker and press ⌘D.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Diagnostics") {
                    Button("Export Diagnostics…") { model.exportDiagnostics() }
                }
                Text("Saves a text file with timings and outcome categories from this run of Charms, for a bug report. It contains no typed text, searches or clipboard contents, and it is only ever written where you choose.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Show Welcome Again") { model.onShowOnboarding?() }
            }
            if let message = model.dataMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// An editable list of applications, stored as bundle identifiers.
private struct ApplicationList: View {
    @Binding var identifiers: Set<String>
    let model: SettingsModel
    @State private var selection: String?
    @State private var typed = ""

    private static let rowHeight: CGFloat = 24
    private static let visibleRows: CGFloat = 5

    private var sorted: [String] {
        identifiers.sorted { Self.title($0).localizedCaseInsensitiveCompare(Self.title($1)) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            List(sorted, id: \.self, selection: $selection) { identifier in
                HStack {
                    // One line, so that every row has the height the list
                    // was sized for.
                    Text(Self.title(identifier)).lineLimit(1).truncationMode(.tail)
                    Spacer()
                    // An application that is not installed has no name to
                    // show; its identifier is already the title.
                    if Self.title(identifier) != identifier {
                        Text(identifier).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            // A box of its own with striped rows: inside a grouped form a
            // plain list has no edge, and a row cut off by the bottom of
            // the list looks like a drawing fault instead of more to scroll.
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .environment(\.defaultMinListRowHeight, Self.rowHeight)
            .frame(height: Self.rowHeight * Self.visibleRows)
            .overlay {
                if identifiers.isEmpty {
                    Text("None").foregroundStyle(.tertiary)
                }
            }
            HStack {
                Button("Add Application…") {
                    if let identifier = model.chooseApplication() {
                        identifiers.insert(identifier)
                    }
                }
                Button("Remove") {
                    if let selection {
                        identifiers.remove(selection)
                    }
                    selection = nil
                }
                .disabled(selection == nil)
                Spacer()
                // Inside a form a text field's title becomes a label beside
                // it; the hint belongs in the field.
                TextField("", text: $typed, prompt: Text("com.example.app"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                    .onSubmit(addTyped)
                    .accessibilityLabel("Bundle identifier to add")
                    .help("Type a bundle identifier and press Return. End it with .* to cover a family, for example com.jetbrains.*")
            }
        }
    }

    private func addTyped() {
        let identifier = typed.trimmingCharacters(in: .whitespaces)
        guard !identifier.isEmpty, !identifier.contains(" ") else { return }
        identifiers.insert(identifier)
        typed = ""
    }

    private static func title(_ identifier: String) -> String {
        SettingsModel.displayName(forBundleIdentifier: identifier) ?? identifier
    }
}
