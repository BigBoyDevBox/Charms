import CharmsCore
import Combine
import Foundation

/// An entry in a cell's menu.
struct PickerMenuAction: Identifiable {
    let id = UUID()
    var title: String
    var isEnabled = true
    var children: [PickerMenuAction] = []
    var perform: (() -> Void)?

    static let separator = PickerMenuAction(title: "-")
    var isSeparator: Bool { title == "-" && perform == nil && children.isEmpty }
}

/// Everything the picker's views draw. The controller writes it; the views
/// only read it and report clicks.
@MainActor
final class PickerViewModel: ObservableObject {
    static let columns = 8
    static let cellSize: CGFloat = 44
    static let cellSpacing: CGFloat = 2
    static let padding: CGFloat = 12

    @Published var sections: [PickerSection] = []
    @Published var selection: GridPosition?
    /// True while the arrow keys move between cells instead of through the
    /// query text.
    @Published var isNavigating = false
    @Published var hover: GridPosition?
    @Published var canInsert = false
    /// A short message that replaces the key hints, for example after the
    /// target changed.
    @Published var notice: String?
    @Published var isLoading = false
    @Published var isQueryEmpty = true
    /// The selected cell's frame in window coordinates, for the keyboard menu.
    var selectedCellFrame: CGRect?

    var onActivate: ((GridPosition) -> Void)?
    var menuActions: ((GridPosition) -> [PickerMenuAction])?

    var navigator: GridNavigator {
        GridNavigator(sections: sections.map(\.items.count), columns: Self.columns)
    }

    func item(at position: GridPosition?) -> PickerItem? {
        guard let position, sections.indices.contains(position.section),
              sections[position.section].items.indices.contains(position.index) else {
            return nil
        }
        return sections[position.section].items[position.index]
    }

    var selectedItem: PickerItem? { item(at: selection) }

    var hasItems: Bool { sections.contains { !$0.items.isEmpty } }

    /// The position of an exact string, to keep the selection on the same
    /// character when the content is rebuilt.
    func position(of string: String, preferringSection section: Int? = nil) -> GridPosition? {
        if let section, sections.indices.contains(section),
           let index = sections[section].items.firstIndex(where: { $0.string.isExactly(string) }) {
            return GridPosition(section: section, index: index)
        }
        for (sectionIndex, candidate) in sections.enumerated() {
            if let index = candidate.items.firstIndex(where: { $0.string.isExactly(string) }) {
                return GridPosition(section: sectionIndex, index: index)
            }
        }
        return nil
    }
}
