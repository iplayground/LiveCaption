import SwiftUI

enum OutputLanguagePortalDisplayMode: String, CaseIterable, Identifiable {
    case disabled
    case analyzedHidden
    case analyzedVisible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled:
            L10n.text("speechSettings.outputLanguage.mode.disabled")
        case .analyzedHidden:
            L10n.text("speechSettings.outputLanguage.mode.analyzedHidden")
        case .analyzedVisible:
            L10n.text("speechSettings.outputLanguage.mode.analyzedVisible")
        }
    }
}

struct OutputLanguageDisplayModeRow: View {
    let language: SpeechOutputLanguage
    let isRequired: Bool
    @Binding var selectedLanguageIDs: Set<String>
    @Binding var portalVisibleLanguageIDs: Set<String>

    private var displayMode: Binding<OutputLanguagePortalDisplayMode> {
        Binding {
            if isRequired {
                return .analyzedVisible
            }

            guard selectedLanguageIDs.contains(language.id) else {
                return .disabled
            }

            return portalVisibleLanguageIDs.contains(language.id) ? .analyzedVisible : .analyzedHidden
        } set: { newValue in
            switch newValue {
            case .disabled:
                guard !isRequired else {
                    selectedLanguageIDs.insert(language.id)
                    portalVisibleLanguageIDs.insert(language.id)
                    return
                }
                selectedLanguageIDs.remove(language.id)
                portalVisibleLanguageIDs.remove(language.id)
            case .analyzedHidden:
                guard !isRequired else {
                    selectedLanguageIDs.insert(language.id)
                    portalVisibleLanguageIDs.insert(language.id)
                    return
                }
                selectedLanguageIDs.insert(language.id)
                portalVisibleLanguageIDs.remove(language.id)
            case .analyzedVisible:
                selectedLanguageIDs.insert(language.id)
                portalVisibleLanguageIDs.insert(language.id)
            }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.nativeName)
                    .font(.subheadline.weight(.medium))
                Text(language.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker(L10n.text("speechSettings.outputLanguage.mode"), selection: displayMode) {
                ForEach(OutputLanguagePortalDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(isRequired)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
