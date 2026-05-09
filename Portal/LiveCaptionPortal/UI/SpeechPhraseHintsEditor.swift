import SwiftUI

private enum SpeechPhraseHintLayout {
    static let maximumVisibleRows = 10
    static let rowHeight: CGFloat = 40
    static let emptyListHeight: CGFloat = 72
    static let dividerHeight: CGFloat = 1
}

struct SpeechPhraseHintsEditor: View {
    @Binding var selectedScope: SpeechPhraseHintScope
    @Binding var newPhraseText: String
    @Binding var phraseHintsByScope: [SpeechPhraseHintScope: [SpeechPhraseHint]]

    private var canAddPhrase: Bool {
        !newPhraseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && remainingCapacity > 0
    }

    private var remainingCapacity: Int {
        SpeechSettings.remainingPhraseHintCapacity(
            for: selectedScope,
            in: phraseHintsByScope
        )
    }

    private var selectedPhraseHints: Binding<[SpeechPhraseHint]> {
        Binding {
            phraseHintsByScope[selectedScope, default: []]
        } set: { newValue in
            phraseHintsByScope[selectedScope] = newValue
        }
    }

    private var phraseHints: [SpeechPhraseHint] {
        phraseHintsByScope[selectedScope, default: []]
    }

    private var phraseListHeight: CGFloat {
        guard !phraseHints.isEmpty else {
            return SpeechPhraseHintLayout.emptyListHeight
        }

        let visibleRows = min(phraseHints.count, SpeechPhraseHintLayout.maximumVisibleRows)
        let visibleDividers = max(visibleRows - 1, 0)
        return CGFloat(visibleRows) * SpeechPhraseHintLayout.rowHeight
            + CGFloat(visibleDividers) * SpeechPhraseHintLayout.dividerHeight
    }

    private var capacityMessage: String {
        let normalizedPhraseHintsByScope = SpeechSettings.normalizedPhraseHintsByScope(phraseHintsByScope)
        let sharedCount = normalizedPhraseHintsByScope[.shared, default: []].count

        switch selectedScope {
        case .shared:
            let mandarinCount = SpeechSettings.phraseHintRecognitionCount(for: .mandarin, in: phraseHintsByScope)
            let englishCount = SpeechSettings.phraseHintRecognitionCount(for: .english, in: phraseHintsByScope)

            return L10n.text(
                "speechSettings.phraseHints.capacity.shared",
                sharedCount,
                SpeechSettings.maximumPhraseHintsPerRecognition,
                mandarinCount,
                SpeechSettings.maximumPhraseHintsPerRecognition,
                englishCount,
                SpeechSettings.maximumPhraseHintsPerRecognition
            )
        case .mandarin, .english:
            let scopeCount = normalizedPhraseHintsByScope[selectedScope, default: []].count
            let recognitionCount = sharedCount + scopeCount

            return L10n.text(
                "speechSettings.phraseHints.capacity.language",
                sharedCount,
                selectedScope.rawValue,
                scopeCount,
                recognitionCount,
                SpeechSettings.maximumPhraseHintsPerRecognition
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker(L10n.text("speechSettings.phraseHints.scope"), selection: $selectedScope) {
                    ForEach(SpeechPhraseHintScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                Text(capacityMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(remainingCapacity > 0 ? Color.secondary : Color.red)
                    .monospacedDigit()
            }

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    if phraseHints.isEmpty {
                        Text(L10n.text("speechSettings.phraseHints.empty"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: SpeechPhraseHintLayout.emptyListHeight)
                    } else {
                        ForEach(selectedPhraseHints) { phraseHint in
                            SpeechPhraseHintRow(phraseHint: phraseHint) {
                                let id = phraseHint.wrappedValue.id
                                phraseHintsByScope[selectedScope, default: []].removeAll { $0.id == id }
                            }

                            if phraseHint.wrappedValue.id != phraseHints.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .frame(height: phraseListHeight)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            HStack(spacing: 8) {
                TextField(L10n.text("speechSettings.phraseHints.add.placeholder"), text: $newPhraseText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addPhrase)

                Button(action: addPhrase) {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .disabled(!canAddPhrase)
                .help(L10n.text("speechSettings.phraseHints.add"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func addPhrase() {
        let normalizedText = newPhraseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return
        }

        var nextPhraseHints = phraseHints
        nextPhraseHints.append(SpeechPhraseHint(text: normalizedText))
        phraseHintsByScope[selectedScope] = SpeechSettings.normalizedPhraseHintsByScope(
            [selectedScope: nextPhraseHints]
        )[selectedScope, default: []]
        newPhraseText = ""
    }
}

struct SpeechPhraseHintRow: View {
    @Binding var phraseHint: SpeechPhraseHint
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField(L10n.text("speechSettings.phraseHints.item.placeholder"), text: $phraseHint.text)
                .textFieldStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(L10n.text("speechSettings.phraseHints.delete"))
        }
        .padding(.horizontal, 10)
        .frame(height: SpeechPhraseHintLayout.rowHeight)
    }
}
