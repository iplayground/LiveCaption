import SwiftUI

struct LogDrawer: View {
    @Binding var isExpanded: Bool
    @Binding var selectedLevel: LogLevel
    let entries: [LogEntry]

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            LogDrawerHeader(
                isExpanded: $isExpanded,
                selectedLevel: $selectedLevel,
                entryCount: entries.count
            )

            if isExpanded {
                LogDrawerContent(entries: entries)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .shadow(color: .black.opacity(isExpanded ? 0.12 : 0), radius: 16, y: -4)
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

                    Text("事件紀錄")
                }
                .font(.headline)

                Text("最近 \(entryCount) 筆")
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
        let picker = Picker("Log Level", selection: $selectedLevel) {
            ForEach(LogLevel.allCases) { level in
                Text(level.rawValue).tag(level)
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

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            ScrollView {
                if entries.isEmpty {
                    ContentUnavailableView("尚無事件紀錄", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 56)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            LogEntryRow(entry: entry)

                            if entry.id != entries.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
    }
}

struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            Text(entry.level.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.level.tint)
                .frame(width: 64, alignment: .leading)

            Text(entry.title)
                .font(.subheadline.weight(.medium))
                .frame(width: 160, alignment: .leading)
                .lineLimit(1)

            Text(entry.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }
}
