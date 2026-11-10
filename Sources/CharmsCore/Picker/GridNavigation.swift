import Foundation

/// A cell in the picker: a section (favourites, recents, or the one result
/// grid) and an index within it.
public struct GridPosition: Hashable, Sendable {
    public var section: Int
    public var index: Int

    public init(section: Int, index: Int) {
        self.section = section
        self.index = index
    }
}

public enum GridDirection: Sendable {
    case left, right, up, down
}

public enum GridMove: Equatable, Sendable {
    case position(GridPosition)
    /// Up from the first row: keyboard navigation goes back to the query.
    case searchField
}

/// Arrow-key movement over sections of cells laid out in rows.
///
/// A short last row is the normal case, not an edge case, so the rules are
/// spelled out: Left and Right walk the cells in reading order and stop at
/// the two ends; Down keeps the column and clamps to the last cell of a
/// shorter row; Up keeps the column and, from the first row, returns to the
/// search field. Nothing wraps around.
public struct GridNavigator: Equatable, Sendable {
    /// Number of cells in each section. Empty sections are skipped.
    public let sections: [Int]
    public let columns: Int

    public init(sections: [Int], columns: Int) {
        self.sections = sections
        self.columns = max(1, columns)
    }

    public var isEmpty: Bool { sections.allSatisfy { $0 <= 0 } }

    public var first: GridPosition? {
        sections.firstIndex(where: { $0 > 0 }).map { GridPosition(section: $0, index: 0) }
    }

    public var last: GridPosition? {
        sections.lastIndex(where: { $0 > 0 }).map { GridPosition(section: $0, index: sections[$0] - 1) }
    }

    public func contains(_ position: GridPosition) -> Bool {
        sections.indices.contains(position.section) && position.index >= 0 && position.index < sections[position.section]
    }

    /// Moves from `position`. With no current position every direction lands
    /// on the first cell.
    public func move(from position: GridPosition?, _ direction: GridDirection) -> GridMove? {
        guard let first else { return nil }
        guard let position, contains(position) else { return .position(first) }
        switch direction {
        case .right:
            return .position(next(after: position) ?? position)
        case .left:
            return .position(previous(before: position) ?? position)
        case .down:
            return .position(below(position) ?? position)
        case .up:
            return above(position).map(GridMove.position) ?? .searchField
        }
    }

    private func next(after position: GridPosition) -> GridPosition? {
        if position.index + 1 < sections[position.section] {
            return GridPosition(section: position.section, index: position.index + 1)
        }
        return nextSection(after: position.section).map { GridPosition(section: $0, index: 0) }
    }

    private func previous(before position: GridPosition) -> GridPosition? {
        if position.index > 0 {
            return GridPosition(section: position.section, index: position.index - 1)
        }
        return previousSection(before: position.section).map { GridPosition(section: $0, index: sections[$0] - 1) }
    }

    private func below(_ position: GridPosition) -> GridPosition? {
        let count = sections[position.section]
        let column = position.index % columns
        let rowStart = position.index - column
        if rowStart + columns < count {
            return GridPosition(section: position.section, index: min(position.index + columns, count - 1))
        }
        guard let section = nextSection(after: position.section) else { return nil }
        return GridPosition(section: section, index: min(column, sections[section] - 1))
    }

    private func above(_ position: GridPosition) -> GridPosition? {
        let column = position.index % columns
        if position.index >= columns {
            return GridPosition(section: position.section, index: position.index - columns)
        }
        guard let section = previousSection(before: position.section) else { return nil }
        let count = sections[section]
        let lastRowStart = ((count - 1) / columns) * columns
        return GridPosition(section: section, index: min(lastRowStart + column, count - 1))
    }

    private func nextSection(after section: Int) -> Int? {
        sections.indices.first(where: { $0 > section && sections[$0] > 0 })
    }

    private func previousSection(before section: Int) -> Int? {
        sections.indices.last(where: { $0 < section && sections[$0] > 0 })
    }
}
