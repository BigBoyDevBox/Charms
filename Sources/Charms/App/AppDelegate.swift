import AppKit
import CharmsCore
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let instance = SingleInstance()
    private var services: AppServices?
    private var picker: PickerController?
    private var hotKeys: HotKeyService?
    private var trigger: TypedTriggerService?
    private var statusItem: StatusItemController?
    private var settings: SettingsWindowController?
    private var onboarding: OnboardingWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let paths = AppPaths.resolve()
        guard instance.acquire(at: paths.lockFile) else {
            // Another Charms already owns the shortcut and the menu-bar
            // item. Ask it to show its settings and step aside.
            DistributedNotificationCenter.default().postNotificationName(SingleInstance.showSettingsNotification, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }

        let services = AppServices(paths: paths)
        self.services = services
        MainMenu.install()

        let picker = PickerController(services: services)
        self.picker = picker

        let hotKeys = HotKeyService(combo: services.preferences.value.shortcut, diagnostics: services.diagnostics)
        self.hotKeys = hotKeys
        let trigger = TypedTriggerService(diagnostics: services.diagnostics)
        self.trigger = trigger

        hotKeys.onPressed = { [weak self] in
            // The shortcut supersedes a half-typed marker.
            self?.trigger?.reset()
            self?.refreshCapabilities()
            self?.picker?.invoke(.shortcut)
        }
        trigger.sessionState = { [weak picker] in picker?.sessionActivity ?? .none }
        trigger.onTriggered = { [weak picker] processID in picker?.invokeTyped(processID: processID) }
        trigger.onSourceKey = { [weak picker] key in picker?.sourceReceived(key) }
        picker.onSessionEnded = { [weak trigger] in trigger?.reset() }

        let statusItem = StatusItemController(services: services)
        statusItem.onOpenPicker = { [weak self] in
            self?.refreshCapabilities()
            self?.picker?.invoke(.menuBar)
        }
        statusItem.onShowSettings = { [weak self] in self?.showSettings(nil) }
        statusItem.onShowAbout = { [weak self] in self?.showAbout(nil) }
        self.statusItem = statusItem

        // Settings take effect as they change; nothing needs a relaunch.
        services.preferences.$value
            .sink { [weak self] preferences in self?.apply(preferences) }
            .store(in: &cancellables)
        services.library.$library
            .dropFirst()
            .sink { [weak picker] _ in
                // The published value is set after the sink returns.
                DispatchQueue.main.async { picker?.contentDidChange() }
            }
            .store(in: &cancellables)
        services.onCatalogLoaded = { [weak picker] in picker?.contentDidChange() }
        Task { await services.loadCatalog() }

        // There is no notification for a permission being granted or taken
        // away. Coming back from System Settings is the moment to look.
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCapabilities() }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: SingleInstance.showSettingsNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showSettings(nil) }
        })

        services.diagnostics.record(.launch, "launched")
        services.diagnostics.record(.permission, Permissions.canInsert ? "insertion-enabled" : "insertion-not-enabled")
        if !hotKeys.isAvailable {
            services.diagnostics.record(.hotKey, "unavailable-at-launch")
        }

        let skipOnboarding = ProcessInfo.processInfo.environment["CHARMS_SKIP_ONBOARDING"] != nil
        if !services.preferences.value.hasCompletedOnboarding, !skipOnboarding {
            showOnboarding()
        }
    }

    /// Opening the app again while it runs has one sensible meaning for an
    /// app without a window: show its settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings(nil)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func apply(_ preferences: Preferences) {
        guard let hotKeys, let trigger else { return }
        if hotKeys.combo != preferences.shortcut {
            hotKeys.apply(preferences.shortcut)
        }
        hotKeys.setPassThrough(preferences.shortcutPassThrough)
        trigger.update(enabled: preferences.typedTriggerEnabled, exclusions: preferences.triggerExclusions)
        DispatchQueue.main.async { [weak self] in self?.picker?.contentDidChange() }
    }

    /// Re-reads the permission state and installs or removes the typed
    /// trigger's observer to match.
    func refreshCapabilities() {
        guard let services, let trigger else { return }
        let preferences = services.preferences.value
        trigger.update(enabled: preferences.typedTriggerEnabled, exclusions: preferences.triggerExclusions)
        settings?.model.refresh()
    }

    @objc func showSettings(_ sender: Any?) {
        guard let services, let hotKeys else { return }
        if settings == nil {
            let model = SettingsModel(services: services, hotKeys: hotKeys)
            model.onCapabilitiesChanged = { [weak self] in self?.refreshCapabilities() }
            model.onShowOnboarding = { [weak self] in self?.showOnboarding() }
            model.onForgetFieldAccessAnswers = { [weak self] in self?.picker?.forgetFieldAccessAnswers() }
            settings = SettingsWindowController(model: model)
        }
        settings?.model.refresh()
        settings?.show()
    }

    @objc func showAbout(_ sender: Any?) {
        guard let services else { return }
        var credits = "Characters, names and keywords come from the Unicode Character Database, Unicode Emoji data and CLDR annotations, used under the Unicode License. See THIRD_PARTY_NOTICES.md inside the app."
        if let header = services.content?.catalog.header {
            credits = "Unicode \(header.unicodeVersion) · Emoji \(header.emojiVersion) · CLDR \(header.cldrVersion)\n\n" + credits
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: credits, attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
        ])
    }

    private func showOnboarding() {
        guard let services else { return }
        if onboarding == nil {
            onboarding = OnboardingWindowController(services: services) { [weak self] in
                self?.refreshCapabilities()
                self?.onboarding = nil
            }
        }
        onboarding?.show()
    }
}
