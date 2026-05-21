import SwiftUI

struct CaptionWorkspace: View {
    @Binding var sessionTitle: String
    @Binding var inputLanguage: InputLanguage
    @Binding var speakerIdentity: SpeakerIdentity
    let processingInputLanguage: InputLanguage
    let areConfigurationControlsLocked: Bool
    let outputLanguages: [SpeechOutputLanguage]
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    @ObservedObject var pubSubCaptionReceiver: PubSubCaptionReceiver
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case sessionTitle
    }

    private var previewLanguages: [SpeechOutputLanguage] {
        outputLanguages.filter { language in
            inputLanguage != processingInputLanguage
                || language.id != processingInputLanguage.matchingOutputLanguageID
        }
    }

    private func dismissSessionTitleFocus() {
        if focusedField == .sessionTitle {
            focusedField = nil
        }
    }

    private func clearInitialFocus() {
        focusedField = nil

        DispatchQueue.main.async {
            if focusedField == nil {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                workspaceHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 18)
                    .frame(width: geometry.size.width, alignment: .leading)

                ScrollView {
                    scrollingCaptionContent
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissSessionTitleFocus()
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .frame(width: geometry.size.width, alignment: .leading)
                }
                .scrollIndicators(.visible)
            }
        }
        .onAppear {
            clearInitialFocus()
        }
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(L10n.text("caption.previewTitle"))
                        .font(.title2.weight(.semibold))

                    StatusPill(
                        title: captionPreviewState.state.title,
                        systemImage: captionPreviewState.state.systemImage,
                        tint: captionPreviewState.state.tint
                    )
                }

                Spacer()

                speechControlCluster
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("session.title"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ClickFocusedTextField(
                    placeholder: L10n.text("session.title.placeholder"),
                    text: $sessionTitle
                ) {
                    focusedField = nil
                }
                .focused($focusedField, equals: .sessionTitle)
                .frame(height: 28)
                .disabled(areConfigurationControlsLocked)
            }

            liveTranscriptSection
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissSessionTitleFocus()
        }
    }

    private var speechControlCluster: some View {
        HStack(spacing: 12) {
            if inputLanguage == .english {
                HStack(spacing: 4) {
                    Text(L10n.text("speakerIdentity"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker(L10n.text("speakerIdentity"), selection: $speakerIdentity) {
                        ForEach(SpeakerIdentity.allCases) { identity in
                            Text(identity.title).tag(identity)
                        }
                    }
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(areConfigurationControlsLocked)
                }
            }

            HStack(spacing: 4) {
                Text(L10n.text("speech.inputLanguage"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(L10n.text("speech.inputLanguage"), selection: $inputLanguage) {
                    ForEach(InputLanguage.allCases) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(areConfigurationControlsLocked)
            }
        }
        .padding(.trailing, 8)
    }

    private var scrollingCaptionContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: L10n.text("caption.preview"), systemImage: "captions.bubble")

                VStack(spacing: 12) {
                    ForEach(previewLanguages) { language in
                        CaptionCard(
                            languageName: language.name,
                            languageNativeName: language.nativeName,
                            text: captionPreviewState.finalCaptionText(
                                for: language,
                                inputLanguage: processingInputLanguage
                            )
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: L10n.text("pubSub.caption"), systemImage: "dot.radiowaves.left.and.right")

                PubSubCaptionCard(receiver: pubSubCaptionReceiver)
            }
        }
    }

    private var liveTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: L10n.text("caption.live"), systemImage: "waveform")

            LiveTranscriptCard(
                languageName: processingInputLanguage.name,
                languageNativeName: processingInputLanguage.transcriptNativeName,
                text: captionPreviewState.liveTranscript(for: processingInputLanguage)
            )

            if case let .failed(message) = captionPreviewState.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
