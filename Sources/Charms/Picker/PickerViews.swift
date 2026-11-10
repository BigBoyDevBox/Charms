import CharmsCore
import SwiftUI

/// Reports the selected cell's frame so a menu opened from the keyboard can
/// appear next to it.
private struct SelectedCellFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// The grid: favourites and recents before a query, results after.
struct PickerGridView: View {
    @ObservedObject var model: PickerViewModel

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(PickerViewModel.cellSize), spacing: PickerViewModel.cellSpacing), count: PickerViewModel.columns)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.sections.enumerated()), id: \.element.id) { sectionIndex, section in
                        sectionView(section, index: sectionIndex)
                    }
                    if model.isLoading {
                        message("Loading characters…")
                    } else if !model.isQueryEmpty, !model.hasItems {
                        message("No matching characters")
                    }
                }
                .padding(PickerViewModel.padding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .onChange(of: model.selection) { _, position in
                guard let position else { return }
                proxy.scrollTo(position, anchor: nil)
            }
            .onPreferenceChange(SelectedCellFrameKey.self) { frame in
                model.selectedCellFrame = frame
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: PickerSection, index sectionIndex: Int) -> some View {
        if let title = title(for: section.kind) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .padding(.top, sectionIndex == 0 ? 0 : 6)
                .accessibilityAddTraits(.isHeader)
        }
        if section.items.isEmpty, let hint = emptyHint(for: section.kind) {
            Text(hint)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
                .frame(height: PickerViewModel.cellSize, alignment: .leading)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: PickerViewModel.cellSpacing) {
                // Cells are identified by where they are, not by what they
                // show. Identifying them by character while also giving each
                // an explicit position id left cells of the previous query in
                // the grid when a character changed place (seen with "a"
                // followed by "arrow").
                ForEach(Array(section.items.enumerated()), id: \.offset) { itemIndex, item in
                    cell(item, at: GridPosition(section: sectionIndex, index: itemIndex))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title(for: section.kind) ?? "Results")
        }
    }

    private func cell(_ item: PickerItem, at position: GridPosition) -> some View {
        let isSelected = model.selection == position
        return PickerCell(item: item, isSelected: isSelected, isNavigating: model.isNavigating, isHovered: model.hover == position)
            .id(position)
            .background {
                if isSelected {
                    GeometryReader { geometry in
                        Color.clear.preference(key: SelectedCellFrameKey.self, value: geometry.frame(in: .global))
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.onActivate?(position) }
            // Hover is only a highlight. It never moves the selection, so a
            // mouse resting over the grid cannot change what Return inserts.
            .onHover { inside in
                if inside {
                    model.hover = position
                } else if model.hover == position {
                    model.hover = nil
                }
            }
            .contextMenu { menu(model.menuActions?(position) ?? []) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.name)
            .accessibilityValue(item.codePoints)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.onActivate?(position) }
            .help("\(item.name)\n\(item.codePoints)")
    }

    private func menu(_ actions: [PickerMenuAction]) -> some View {
        ForEach(actions) { action in
            if action.isSeparator {
                Divider()
            } else if !action.children.isEmpty {
                Menu(action.title) {
                    ForEach(action.children) { child in
                        Button(child.title) { child.perform?() }.disabled(!child.isEnabled)
                    }
                }
            } else {
                Button(action.title) { action.perform?() }.disabled(!action.isEnabled)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
    }

    private func title(for kind: PickerSection.Kind) -> String? {
        switch kind {
        case .favourites: return "Favourites"
        case .recents: return "Recent"
        case .results: return nil
        }
    }

    private func emptyHint(for kind: PickerSection.Kind) -> String? {
        switch kind {
        case .favourites: return "Press ⌘D on a character to keep it here."
        case .recents: return "Characters you use will appear here."
        case .results: return nil
        }
    }
}

private struct PickerCell: View {
    let item: PickerItem
    let isSelected: Bool
    let isNavigating: Bool
    let isHovered: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(item.preview)
            .font(.system(size: item.isEmoji ? 26 : 24))
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .foregroundStyle(isSelected && isNavigating ? Color.white : Color.primary)
            .opacity(item.preview == item.string ? 1 : 0.55)
            .frame(width: PickerViewModel.cellSize, height: PickerViewModel.cellSize)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: contrast == .increased ? 2.5 : 1.5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if item.isFavourite {
                    Circle()
                        .fill(isSelected && isNavigating ? Color.white : Color.accentColor)
                        .frame(width: 5, height: 5)
                        .padding(5)
                        .accessibilityHidden(true)
                }
            }
    }

    /// The selection is filled while the arrow keys act on the grid and
    /// only tinted while they act on the query, so it is visible which of
    /// the two the keyboard is driving.
    private var background: Color {
        if isSelected { return isNavigating ? Color.accentColor : Color.accentColor.opacity(0.18) }
        if isHovered { return Color.primary.opacity(0.08) }
        return Color.clear
    }
}

/// The line under the grid: what is selected, and what Return will do.
struct PickerFooterView: View {
    @ObservedObject var model: PickerViewModel

    var body: some View {
        HStack(spacing: 8) {
            if let item = model.selectedItem {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Text(item.codePoints)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(model.notice ?? hints)
                .foregroundStyle(model.notice == nil ? .secondary : .primary)
                .lineLimit(1)
                .fixedSize()
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var hints: String {
        model.canInsert ? "↵ Insert · ⌘↵ Copy" : "↵ Copy"
    }
}
