import AppKit

// Charms is a menu-bar accessory: no Dock icon and no main window.
// A program's entry point runs on the main thread, which is the main actor.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    // NSApplication keeps only a weak reference to its delegate.
    withExtendedLifetime(delegate) {
        application.run()
    }
}
