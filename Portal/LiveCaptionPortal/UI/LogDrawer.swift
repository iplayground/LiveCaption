import SwiftUI
import AppKit

struct LogDrawer: View {
    @Binding var isExpanded: Bool
    @Binding var selectedLevel: LogLevel
    @Binding var contentHeight: CGFloat
    let maximumContentHeight: CGFloat
    let entries: [LogEntry]

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            LogDrawerHeader(
                isExpanded: $isExpanded,
                selectedLevel: $selectedLevel,
                entryCount: entries.count
            )
            .overlay(alignment: .top) {
                if isExpanded {
                    LogDrawerResizeHandle(
                        contentHeight: $contentHeight,
                        maximumContentHeight: maximumContentHeight
                    )
                }
            }

            if isExpanded {
                LogDrawerContent(entries: entries, height: contentHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .shadow(color: .black.opacity(isExpanded ? 0.12 : 0), radius: 16, y: -4)
        .onChange(of: maximumContentHeight) { _, newValue in
            contentHeight = min(contentHeight, newValue)
        }
    }
}

struct LogDrawerResizeHandle: View {
    @Binding var contentHeight: CGFloat
    let maximumContentHeight: CGFloat
    @State private var dragStartHeight: CGFloat?
    @State private var dragStartLocationY: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let startHeight = dragStartHeight ?? contentHeight
                        let startLocationY = dragStartLocationY ?? value.startLocation.y
                        dragStartHeight = startHeight
                        dragStartLocationY = startLocationY
                        contentHeight = clampedHeight(startHeight + startLocationY - value.location.y)
                    }
                    .onEnded { _ in
                        dragStartHeight = nil
                        dragStartLocationY = nil
                    }
            )
            .resizeUpDownCursor()
    }

    private func clampedHeight(_ height: CGFloat) -> CGFloat {
        min(
            max(height, WindowLayout.defaultLogDrawerContentHeight),
            maximumContentHeight
        )
    }
}

private struct ResizeUpDownCursorModifier: ViewModifier {
    @State private var isCursorPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                if isHovering {
                    guard !isCursorPushed else {
                        return
                    }

                    NSCursor.resizeUpDown.push()
                    isCursorPushed = true
                    return
                }

                popCursorIfNeeded()
            }
            .onDisappear {
                popCursorIfNeeded()
            }
    }

    private func popCursorIfNeeded() {
        guard isCursorPushed else {
            return
        }

        NSCursor.pop()
        isCursorPushed = false
    }
}

private extension View {
    func resizeUpDownCursor() -> some View {
        modifier(ResizeUpDownCursorModifier())
    }
}

struct LogDrawerHeader: View {
    @Binding var isExpanded: Bool
    @Binding var selectedLevel: LogLevel
    let entryCount: Int
    @State private var isLevelPickerHidden = true

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.up")
                        .font(.subheadline.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.18), value: isExpanded)
                        .frame(width: 14, height: 14)

                    Text(L10n.text("log.events"))
                }
                .font(.headline)

                Text(L10n.text("log.recentCount", entryCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            levelPicker
                .opacity(isExpanded ? 1 : 0)
                .animation(.easeInOut(duration: 0.18), value: isExpanded)
                .disabled(!isExpanded)
                .accessibilityHidden(!isExpanded)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleLogDrawer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            toggleLogDrawer()
        }
        .onAppear {
            isLevelPickerHidden = !isExpanded
        }
        .onChange(of: isExpanded) { _, newValue in
            if newValue {
                return
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                guard !isExpanded else {
                    return
                }

                isLevelPickerHidden = true
            }
        }
    }

    private func toggleLogDrawer() {
        if isExpanded {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded = false
            }
            return
        }

        isLevelPickerHidden = false

        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded = true
            }
        }
    }

    @ViewBuilder
    private var levelPicker: some View {
        let picker = Picker(L10n.text("log.level"), selection: $selectedLevel) {
            ForEach(LogLevel.allCases) { level in
                Text(level.title).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 320)

        if isLevelPickerHidden {
            picker.hidden()
        } else {
            picker
        }
    }
}

struct LogDrawerContent: View {
    let entries: [LogEntry]
    let height: CGFloat
    @State private var selectedEntryIDs: Set<LogEntry.ID> = []
    @State private var anchorEntryID: LogEntry.ID?
    @FocusState private var isLogSelectionFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            ScrollView {
                if entries.isEmpty {
                    ContentUnavailableView(L10n.text("log.noEvents"), systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 56)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            LogEntryRow(
                                entry: entry,
                                isSelected: selectedEntryIDs.contains(entry.id)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                select(entry, using: NSApp.currentEvent?.modifierFlags ?? [])
                            }
                            .contextMenu {
                                Button(L10n.text("log.copySelected")) {
                                    copySelectedEntries()
                                }
                                .disabled(selectedEntries.isEmpty)
                            }

                            if entry.id != entries.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                clearSelection()
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .focusable()
        .focused($isLogSelectionFocused)
        .focusEffectDisabled()
        .onCopyCommand {
            guard !selectedEntries.isEmpty else {
                return []
            }

            return [NSItemProvider(object: selectedEntriesText as NSString)]
        }
        .onChange(of: entries.map(\.id)) { _, visibleEntryIDs in
            selectedEntryIDs.formIntersection(Set(visibleEntryIDs))

            if let anchorEntryID, !visibleEntryIDs.contains(anchorEntryID) {
                self.anchorEntryID = selectedEntryIDs.first
            }
        }
    }

    private var selectedEntries: [LogEntry] {
        entries.filter { selectedEntryIDs.contains($0.id) }
    }

    private var selectedEntriesText: String {
        selectedEntries
            .map { entry in
                "[\(entry.time)] \(entry.level.title) \(entry.title)\n\(entry.detail)"
            }
            .joined(separator: "\n\n")
    }

    private func select(_ entry: LogEntry, using modifiers: NSEvent.ModifierFlags) {
        isLogSelectionFocused = true

        if modifiers.contains(.shift), let anchorEntryID {
            selectRange(from: anchorEntryID, to: entry.id)
            return
        }

        if modifiers.contains(.command) {
            if selectedEntryIDs.contains(entry.id) {
                selectedEntryIDs.remove(entry.id)
            } else {
                selectedEntryIDs.insert(entry.id)
            }
            anchorEntryID = entry.id
            return
        }

        selectedEntryIDs = [entry.id]
        anchorEntryID = entry.id
    }

    private func clearSelection() {
        selectedEntryIDs.removeAll()
        anchorEntryID = nil
    }

    private func selectRange(from anchorID: LogEntry.ID, to targetID: LogEntry.ID) {
        guard
            let anchorIndex = entries.firstIndex(where: { $0.id == anchorID }),
            let targetIndex = entries.firstIndex(where: { $0.id == targetID })
        else {
            selectedEntryIDs = [targetID]
            anchorEntryID = targetID
            return
        }

        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedEntryIDs = Set(entries[range].map(\.id))
    }

    private func copySelectedEntries() {
        guard !selectedEntries.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedEntriesText, forType: .string)
    }
}

struct LogEntryRow: View {
    let entry: LogEntry
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
                .padding(.top, 1)

            Text(entry.level.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.level.tint)
                .frame(width: 64, alignment: .leading)
                .padding(.top, 1)

            Text(entry.title)
                .font(.subheadline.weight(.medium))
                .frame(width: 160, alignment: .leading)
                .lineLimit(1)

            Text(entry.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
    }
}
