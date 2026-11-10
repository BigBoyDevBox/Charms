import ApplicationServices
import CharmsCore
import Foundation

/// Thin typed wrappers around the Accessibility calls Charms makes into
/// other applications. Every call here is a round trip to another process
/// and may block up to the messaging timeout, so they run only on the
/// capture queue, never on the main thread.
enum AX {
    /// Upper bound for one call. A hung application then costs a bounded
    /// delay, not a frozen picker.
    static let messagingTimeout: Float = 0.1

    /// Applies the timeout to every Accessibility call this process makes.
    ///
    /// A timeout set on one element holds for that object only, not for
    /// the elements read from it (`AXUIElement.h`), and those would wait
    /// the system's default of several seconds for a hung application.
    /// Setting it on the system-wide element makes it the process default.
    static func applyMessagingTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
    }

    static func application(_ processID: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let result = value(element, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        // The type was checked on the line above.
        return (result as! AXUIElement)
    }

    static func range(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        guard let result = value(element, attribute), CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(result as! AXValue, .cfRange, &range) else { return nil }
        // The numbers come from another application. One that reports a
        // negative value, or a range whose end overflows, has no range.
        guard SourceTextRange(location: range.location, length: range.length) != nil else { return nil }
        return range
    }

    /// Position and size of an element, in Accessibility coordinates.
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = value(element, kAXPositionAttribute), CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue = value(element, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    /// Screen rectangle of a text range, in Accessibility coordinates. This
    /// reads geometry only; no text is returned.
    static func bounds(_ element: AXUIElement, location: Int, length: Int) -> CGRect? {
        guard location >= 0, length >= 0 else { return nil }
        var range = CFRange(location: location, length: length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &result)
        guard status == .success, let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(result as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    /// The text of a range. Used only for the typed trigger, and only for
    /// the few characters around the marker.
    static func text(_ element: AXUIElement, location: Int, length: Int) -> String? {
        guard location >= 0, length >= 0 else { return nil }
        if length == 0 { return "" }
        var range = CFRange(location: location, length: length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &result)
        guard status == .success else { return nil }
        return result as? String
    }

    static func setSelectedRange(_ element: AXUIElement, location: Int, length: Int) -> Bool {
        var range = CFRange(location: location, length: length)
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    static func processID(of element: AXUIElement) -> pid_t? {
        var processID: pid_t = 0
        return AXUIElementGetPid(element, &processID) == .success ? processID : nil
    }
}
