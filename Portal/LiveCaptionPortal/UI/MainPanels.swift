import SwiftUI

struct ControlSidebar: View {
    @ObservedObject var audioInputController: AudioInputController
    let speechAuthorizationStatus: SpeechAuthorizationStatus
    let recognizedCaptionCount: Int

    private var captureBinding: Binding<Bool> {
        Binding(
            get: { audioInputController.isCaptureEnabled },
            set: { audioInputController.setCaptureEnabled($0) }
        )
    }

    private var automaticNoiseCalibrationBinding: Binding<Bool> {
        Binding(
            get: { audioInputController.isAutomaticNoiseCalibrationEnabled },
            set: { audioInputController.setAutomaticNoiseCalibrationEnabled($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Panel(title: "工作階段", systemImage: "dot.radiowaves.left.and.right") {
                VStack(alignment: .leading, spacing: 12) {
                    SessionStatusValue()
                    SessionCaptureValue(isCapturing: audioInputController.isCapturing)
                    SpeechAuthorizationValue(status: speechAuthorizationStatus)
                    SessionMetricValue(label: "字幕事件", value: "\(recognizedCaptionCount)")
                }
            }

            Panel(title: "音訊輸入", systemImage: "mic", minHeight: 168) {
                Toggle("收音", isOn: captureBinding)
                    .font(.caption)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!audioInputController.canToggleCapture)
            } content: {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("來源")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                audioInputController.refreshDevices()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("重新掃描音訊來源")
                        }

                        AudioSourceMenu(
                            devices: audioInputController.devices,
                            selectedDeviceID: audioInputController.selectedDeviceID,
                            selectedDeviceName: audioInputController.selectedDeviceName,
                            isDisabled: audioInputController.devices.isEmpty
                        ) { deviceID in
                            audioInputController.selectDevice(id: deviceID)
                        }
                    }

                    AudioLevelMeter(
                        level: audioInputController.level,
                        peakLevel: audioInputController.peakLevel,
                        decibels: audioInputController.decibels
                    )

                    HStack {
                        Text("自動校準")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Toggle("自動校準", isOn: automaticNoiseCalibrationBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        PermissionRow(
                            title: "麥克風權限",
                            state: audioInputController.microphonePermission.title,
                            tint: audioInputController.microphonePermission.tint
                        )
                    }

                    if let errorMessage = audioInputController.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: WindowLayout.controlSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
        .alert("需要麥克風權限", isPresented: $audioInputController.isMicrophoneSettingsPromptPresented) {
            Button("取消", role: .cancel) {}
            Button("開啟系統設定") {
                audioInputController.openMicrophoneSettingsAfterConfirmation()
            }
        } message: {
            Text("Portal 需要麥克風權限才能收音。是否要前往系統設定調整權限？")
        }
    }
}

struct CaptionWorkspace: View {
    @Binding var inputLanguage: InputLanguage
    let outputLanguages: [SpeechOutputLanguage]
    @ObservedObject var speechRecognitionController: SpeechRecognitionController

    private var previewLanguages: [SpeechOutputLanguage] {
        outputLanguages.filter { language in
            language.id != inputLanguage.matchingOutputLanguageID
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("字幕預覽")
                                .font(.title2.weight(.semibold))

                            StatusPill(
                                title: speechRecognitionController.state.title,
                                systemImage: speechRecognitionController.state.systemImage,
                                tint: speechRecognitionController.state.tint
                            )
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Text("語音語言")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker("語音語言", selection: $inputLanguage) {
                                ForEach(InputLanguage.allCases) { language in
                                    Text(language.nativeName).tag(language)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.trailing, 8)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "即時", systemImage: "waveform")

                        LiveTranscriptCard(
                            languageName: inputLanguage.name,
                            languageNativeName: inputLanguage.transcriptNativeName,
                            text: speechRecognitionController.displayTranscript
                        )

                        if case let .failed(message) = speechRecognitionController.state {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "預覽", systemImage: "captions.bubble")

                        VStack(spacing: 12) {
                            ForEach(previewLanguages) { language in
                                CaptionCard(
                                    languageName: language.name,
                                    languageNativeName: language.nativeName,
                                    text: language.previewText
                                )
                            }
                        }
                    }

                }
                .padding(24)
                .frame(width: geometry.size.width, alignment: .leading)
            }
            .scrollIndicators(.visible)
        }
    }
}

struct StatusSidebar: View {
    let inputLanguage: InputLanguage
    @Binding var speechSettings: SpeechSettings
    @Binding var speechAuthorizationStatus: SpeechAuthorizationStatus
    let onLogEvent: (LogLevel, String, String) -> Void
    @State private var isSpeechSettingsPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Panel(title: "Speech", systemImage: "waveform.badge.magnifyingglass") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledValue(label: "Region", value: speechSettings.regionSummary)
                    LabeledValue(label: "語音語言", value: inputLanguage.nativeName)
                    LabeledValue(label: "字幕輸出", value: speechSettings.outputLanguageSummary)

                    Button {
                        isSpeechSettingsPresented = true
                    } label: {
                        Label("開啟設定", systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .sheet(isPresented: $isSpeechSettingsPresented) {
                SpeechSettingsSheet(
                    settings: $speechSettings,
                    isPresented: $isSpeechSettingsPresented
                ) { result in
                    speechAuthorizationStatus = .authorized
                    speechAuthorizationStatus.save()
                    onLogEvent(.info, "Speech 設定測試成功", "Region \(result.region)")
                } onFailure: { message in
                    speechAuthorizationStatus = .failed
                    speechAuthorizationStatus.save()
                    onLogEvent(.error, "Speech 設定測試失敗", message)
                } onAuthorizationSettingsChanged: {
                    speechAuthorizationStatus = .initial(for: speechSettings)
                    speechAuthorizationStatus.save()
                }
            }

            Panel(title: "Relay", systemImage: "server.rack") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledValue(label: "連線", value: "未設定")
                    LabeledValue(label: "環境", value: "Local")
                    LabeledValue(label: "最後送出", value: "尚無")

                    Button {
                    } label: {
                        Label("開啟設定", systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Panel(title: "最近狀態", systemImage: "clock.badge") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledValue(label: "最後事件", value: "Relay 未連線")
                    LabeledValue(label: "警告", value: "1")
                    LabeledValue(label: "錯誤", value: "0")
                }
            }
        }
        .padding(20)
        .frame(width: WindowLayout.statusSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
