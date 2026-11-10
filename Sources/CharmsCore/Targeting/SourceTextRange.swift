/// A text range reported by another application, in UTF-16 units.
///
/// Another application is not obliged to report sensible numbers, and a
/// broken one must not be able to stop Charms. A range exists only when both
/// values are non-negative and its end can be computed, so arithmetic on an
/// accepted range cannot overflow.
public struct SourceTextRange: Equatable, Sendable {
    public let location: Int
    public let length: Int

    public init?(location: Int, length: Int) {
        guard location >= 0, length >= 0, !location.addingReportingOverflow(length).overflow else { return nil }
        self.location = location
        self.length = length
    }

    /// The position just after the range.
    public var end: Int { location + length }
}
