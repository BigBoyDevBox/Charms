import AppKit
import ApplicationServices

/// Read-only views of the system for assertions.
enum Inspect {
    static func frontmost() -> [String: Any] {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            Output.fail("no frontmost application")
        }
        return [
            "pid": Int(application.processIdentifier),
            "bundleID": application.bundleIdentifier ?? NSNull(),
            "name": application.localizedName ?? NSNull()
        ]
    }

    static func pasteboard(setting text: String?) -> [String: Any] {
        let pasteboard = NSPasteboard.general
        if let text {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        return ["changeCount": pasteboard.changeCount, "string": pasteboard.string(forType: .string) ?? NSNull()]
    }

    static func displays() -> [String: Any] {
        let main = NSScreen.screens.first
        let screens: [[String: Any]] = NSScreen.screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let identifier = CGDirectDisplayID(number?.uint32Value ?? 0)
            return [
                "id": Int(identifier),
                "frame": rectangle(screen.frame),
                "visibleFrame": rectangle(screen.visibleFrame),
                "cgBounds": rectangle(CGDisplayBounds(identifier)),
                "scale": screen.backingScaleFactor,
                "isMain": screen == main
            ]
        }
        let mouse = NSEvent.mouseLocation
        return ["displays": screens, "mouse": [mouse.x, mouse.y], "separateSpaces": NSScreen.screensHaveSeparateSpaces]
    }

    static func windows(ownedBy processID: Int) -> [String: Any] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let owned: [[String: Any]] = list.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? Int) == processID else { return nil }
            var bounds = CGRect.zero
            if let dictionary = window[kCGWindowBounds as String] as? NSDictionary {
                bounds = CGRect(dictionaryRepresentation: dictionary) ?? .zero
            }
            return [
                "id": window[kCGWindowNumber as String] as? Int ?? 0,
                "layer": window[kCGWindowLayer as String] as? Int ?? 0,
                "alpha": window[kCGWindowAlpha as String] as? Double ?? 0,
                "bounds": rectangle(bounds)
            ]
        }
        return ["windows": owned]
    }

    /// The focused element of the frontmost application, as another
    /// application sees it through Accessibility.
    static func focused() -> [String: Any] {
        var result: [String: Any] = ["trusted": AXIsProcessTrusted()]
        guard let application = NSWorkspace.shared.frontmostApplication else { return result }
        result["pid"] = Int(application.processIdentifier)
        result["bundleID"] = application.bundleIdentifier ?? NSNull()

        let root = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        guard let focused = copy(root, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return result
        }
        // Core Foundation types cannot be cast conditionally; the type id
        // was checked above.
        let element = focused as! AXUIElement
        let role = copy(element, kAXRoleAttribute) as? String
        let subrole = copy(element, kAXSubroleAttribute) as? String
        result["role"] = role ?? NSNull()
        result["subrole"] = subrole ?? NSNull()

        // A password field's contents are never read.
        let isSecure = role == "AXSecureTextField" || subrole == (kAXSecureTextFieldSubrole as String)
        if !isSecure, let value = copy(element, kAXValueAttribute) as? String, value.utf16.count <= 4000 {
            result["value"] = value
        }
        guard let rangeValue = copy(element, kAXSelectedTextRangeAttribute), CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return result
        }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return result }
        result["selection"] = [range.location, range.length]

        var caret = CFRange(location: range.location + range.length, length: 0)
        if let parameter = AXValueCreate(.cfRange, &caret) {
            var bounds: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &bounds) == .success,
               let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() {
                var rect = CGRect.zero
                if AXValueGetValue(bounds as! AXValue, .cgRect, &rect) {
                    result["caretBounds"] = rectangle(rect)
                }
            }
        }
        return result
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func rectangle(_ rect: CGRect) -> [Double] {
        [Double(rect.origin.x), Double(rect.origin.y), Double(rect.width), Double(rect.height)]
    }
}
