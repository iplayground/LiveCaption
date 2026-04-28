//
//  ContentView.swift
//  LiveCaptionPortal
//
//  Created by Hao Lee on 2026/4/26.
//

import SwiftUI
import AppKit
import MicrosoftCognitiveServicesSpeech

struct ContentView: View {
    @State private var inputLanguage = InputLanguage.mandarin
    @State private var speechSettings: SpeechSettings
    @State private var speechAuthorizationStatus: SpeechAuthorizationStatus
    @State private var shouldVerifySpeechAuthorizationOnLaunch: Bool
    @State private var isLogDrawerExpanded = false
    @State private var selectedLogLevel = LogLevel.all
    @State private var logEntries = sampleLogEntries
    private let windowMinimumSize = WindowLayout.minimumSize

    init() {
        let speechSettings = SpeechSettings.load()
        let authorizationStatus = SpeechAuthorizationStatus.load(for: speechSettings)
        let shouldVerifySpeechAuthorizationOnLaunch = authorizationStatus == .authorized

        _speechSettings = State(initialValue: speechSettings)
        _speechAuthorizationStatus = State(
            initialValue: shouldVerifySpeechAuthorizationOnLaunch ? .verifying : authorizationStatus
        )
        _shouldVerifySpeechAuthorizationOnLaunch = State(initialValue: shouldVerifySpeechAuthorizationOnLaunch)
    }

    private var filteredLogEntries: [LogEntry] {
        guard selectedLogLevel != .all else {
            return logEntries
        }

        return logEntries.filter { $0.level == selectedLogLevel }
    }

    private func appendLog(level: LogLevel, title: String, detail: String) {
        logEntries.insert(
            LogEntry(time: LogClock.currentTimeString(), level: level, title: title, detail: detail),
            at: 0
        )
    }

    @MainActor
    private func verifySpeechAuthorizationOnLaunchIfNeeded() async {
        guard shouldVerifySpeechAuthorizationOnLaunch else {
            return
        }

        shouldVerifySpeechAuthorizationOnLaunch = false
        let settingsToTest = speechSettings

        do {
            let result = try await settingsToTest.testConnection()
            speechAuthorizationStatus = .authorized
            speechAuthorizationStatus.save()
            appendLog(level: .info, title: "Speech 授權重新驗證成功", detail: "Region \(result.region)")
        } catch {
            let message = error.localizedDescription
            speechAuthorizationStatus = .failed
            speechAuthorizationStatus.save()
            appendLog(level: .error, title: "Speech 授權重新驗證失敗", detail: message)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HeaderView()

                Divider()

                HStack(alignment: .top, spacing: 0) {
                    ControlSidebar()

                    Divider()

                    CaptionWorkspace(
                        inputLanguage: $inputLanguage,
                        outputLanguages: speechSettings.selectedOutputLanguages
                    )

                    Divider()

                    StatusSidebar(
                        inputLanguage: inputLanguage,
                        speechSettings: $speechSettings,
                        speechAuthorizationStatus: $speechAuthorizationStatus
                    ) { level, title, detail in
                        appendLog(level: level, title: title, detail: detail)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.bottom, WindowLayout.logDrawerHeaderHeight)

            LogDrawer(
                isExpanded: $isLogDrawerExpanded,
                selectedLevel: $selectedLogLevel,
                entries: filteredLogEntries
            )
            .zIndex(100)
        }
        .frame(minWidth: windowMinimumSize.width, minHeight: windowMinimumSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await verifySpeechAuthorizationOnLaunchIfNeeded()
        }
    }
}

private enum WindowLayout {
    private static let preferredMinimumSize = CGSize(width: 1280, height: 820)
    static let logDrawerHeaderHeight: CGFloat = 50

    static var minimumSize: CGSize {
        guard let visibleSize = NSScreen.main?.visibleFrame.size else {
            return preferredMinimumSize
        }

        return CGSize(
            width: min(preferredMinimumSize.width, visibleSize.width),
            height: min(preferredMinimumSize.height, visibleSize.height)
        )
    }
}

private enum InputLanguage: String, CaseIterable, Identifiable {
    case mandarin = "zh-TW"
    case english = "en-US"

    var id: String { rawValue }

    var speechLocale: String {
        rawValue
    }

    var name: String {
        switch self {
        case .mandarin:
            "Chinese Traditional"
        case .english:
            "English"
        }
    }

    var nativeName: String {
        switch self {
        case .mandarin:
            "繁體中文"
        case .english:
            "English"
        }
    }

    var transcriptNativeName: String {
        switch self {
        case .mandarin:
            "繁體中文"
        case .english:
            "English"
        }
    }
}

private struct SpeechOutputLanguage: Identifiable {
    let code: String
    let name: String
    let nativeName: String
    let previewText: String

    var id: String { code }
}

private struct SpeechConnectionTestResult {
    let region: String
}

private enum SpeechSettingsValidationError: LocalizedError {
    case missingRegion
    case missingSpeechKey
    case serviceRejected(Int)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRegion:
            "尚未設定 Region"
        case .missingSpeechKey:
            "尚未設定 Speech Key"
        case .serviceRejected(let statusCode):
            "Azure Speech 拒絕連線，HTTP \(statusCode)"
        case .connectionFailed(let message):
            "Azure Speech 連線失敗：\(message)"
        }
    }
}

private struct SpeechSettings {
    static let requiredOutputLanguageIDs: Set<String> = ["zh-Hant", "en"]
    static let defaultOutputLanguageIDs: Set<String> = ["zh-Hant", "en", "ja"]
    private static let userDefaults = UserDefaults.standard

    var region = ""
    var speechKey = ""
    var selectedOutputLanguageIDs = defaultOutputLanguageIDs {
        didSet {
            selectedOutputLanguageIDs.formUnion(Self.requiredOutputLanguageIDs)
        }
    }

    var hasAuthorizationMaterial: Bool {
        !speechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var regionSummary: String {
        region.isEmpty ? "尚未設定" : region
    }

    var outputLanguageSummary: String {
        "\(selectedOutputLanguageIDs.count) 種"
    }

    var selectedOutputLanguages: [SpeechOutputLanguage] {
        availableSpeechOutputLanguages.filter {
            selectedOutputLanguageIDs.contains($0.id)
        }
    }

    func testConnection() async throws -> SpeechConnectionTestResult {
        let normalizedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSpeechKey = speechKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedRegion.isEmpty else {
            throw SpeechSettingsValidationError.missingRegion
        }

        guard !normalizedSpeechKey.isEmpty else {
            throw SpeechSettingsValidationError.missingSpeechKey
        }

        let endpointURLString = "https://\(normalizedRegion).api.cognitive.microsoft.com/sts/v1.0/issueToken"

        guard let endpointURL = URL(string: endpointURLString) else {
            throw SpeechSettingsValidationError.connectionFailed("Region 格式無效")
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue(normalizedSpeechKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("0", forHTTPHeaderField: "Content-Length")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SpeechSettingsValidationError.connectionFailed("未收到 HTTP 回應")
            }

            guard (200..<300).contains(httpResponse.statusCode), !data.isEmpty else {
                throw SpeechSettingsValidationError.serviceRejected(httpResponse.statusCode)
            }
        } catch {
            if let validationError = error as? SpeechSettingsValidationError {
                throw validationError
            }

            throw SpeechSettingsValidationError.connectionFailed(error.localizedDescription)
        }

        return SpeechConnectionTestResult(region: normalizedRegion)
    }

    static func load() -> SpeechSettings {
        var settings = SpeechSettings()

        settings.region = userDefaults.string(forKey: UserDefaultsKey.region.rawValue) ?? ""
        settings.speechKey = userDefaults.string(forKey: UserDefaultsKey.speechKey.rawValue) ?? ""

        if let outputLanguageIDs = userDefaults.object(forKey: UserDefaultsKey.outputLanguageIDs.rawValue) as? [String] {
            settings.selectedOutputLanguageIDs = Set(outputLanguageIDs).union(requiredOutputLanguageIDs)
        }

        return settings
    }

    mutating func save() {
        Self.userDefaults.set(region, forKey: UserDefaultsKey.region.rawValue)
        Self.userDefaults.set(
            Array(selectedOutputLanguageIDs.union(Self.requiredOutputLanguageIDs)).sorted(),
            forKey: UserDefaultsKey.outputLanguageIDs.rawValue
        )
        if speechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Self.userDefaults.removeObject(forKey: UserDefaultsKey.speechKey.rawValue)
        } else {
            Self.userDefaults.set(speechKey, forKey: UserDefaultsKey.speechKey.rawValue)
        }
    }

    private enum UserDefaultsKey: String {
        case region = "speech.region"
        case speechKey = "speech.key"
        case outputLanguageIDs = "speech.outputLanguageIDs"
    }
}

private enum SpeechAuthorizationStatus: String {
    case unauthorized
    case unverified
    case verifying
    case authorized
    case failed

    private static let userDefaults = UserDefaults.standard
    private static let userDefaultsKey = "speech.authorizationStatus"

    static func load(for settings: SpeechSettings) -> SpeechAuthorizationStatus {
        guard settings.hasAuthorizationMaterial else {
            return .unauthorized
        }

        guard let rawValue = userDefaults.string(forKey: userDefaultsKey),
              let status = SpeechAuthorizationStatus(rawValue: rawValue),
              status != .unauthorized,
              status != .verifying else {
            return .unverified
        }

        return status
    }

    static func initial(for settings: SpeechSettings) -> SpeechAuthorizationStatus {
        settings.hasAuthorizationMaterial ? .unverified : .unauthorized
    }

    func save() {
        Self.userDefaults.set(rawValue, forKey: Self.userDefaultsKey)
    }

    var title: String {
        switch self {
        case .unauthorized:
            "未授權"
        case .unverified:
            "未驗證"
        case .verifying:
            "驗證中"
        case .authorized:
            "已授權"
        case .failed:
            "授權失敗"
        }
    }

    var tint: Color {
        switch self {
        case .unauthorized:
            .secondary
        case .unverified:
            .orange
        case .verifying:
            .blue
        case .authorized:
            .green
        case .failed:
            .red
        }
    }
}

private let availableSpeechOutputLanguages = [
    SpeechOutputLanguage(
        code: "zh-Hant",
        name: "Chinese Traditional",
        nativeName: "繁體中文",
        previewText: "歡迎來到今天的活動，字幕系統準備就緒。"
    ),
    SpeechOutputLanguage(
        code: "en",
        name: "English",
        nativeName: "English",
        previewText: "Welcome to today's event. The caption system is ready."
    ),
    SpeechOutputLanguage(
        code: "ja",
        name: "Japanese",
        nativeName: "日本語",
        previewText: "本日のイベントへようこそ。字幕システムの準備ができました。"
    ),
    SpeechOutputLanguage(
        code: "ko",
        name: "Korean",
        nativeName: "한국어",
        previewText: "오늘 행사에 오신 것을 환영합니다. 자막 시스템이 준비되었습니다."
    )
]

private enum LogLevel: String, CaseIterable, Identifiable {
    case all = "全部"
    case info = "Info"
    case warning = "Warning"
    case error = "Error"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .all:
            .secondary
        case .info:
            .blue
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}

private struct LogEntry: Identifiable {
    let id = UUID()
    let time: String
    let level: LogLevel
    let title: String
    let detail: String
}

private enum LogClock {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func currentTimeString() -> String {
        formatter.string(from: Date())
    }
}

private let sampleLogEntries = [
    LogEntry(time: "00:00", level: .info, title: "Portal 已啟動", detail: "等待音訊來源與 Relay 設定"),
    LogEntry(time: "00:00", level: .info, title: "字幕輸出已載入", detail: "預設繁體中文、English、日本語"),
    LogEntry(time: "00:00", level: .warning, title: "Relay 未連線", detail: "字幕事件尚未送出"),
    LogEntry(time: "00:00", level: .info, title: "工作階段待機", detail: "尚未開始收音")
]

private struct HeaderView: View {
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LiveCaption Portal")
                    .font(.system(size: 22, weight: .semibold))
                Text("現場字幕操作台")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusPill(title: "待機", systemImage: "circle.fill", tint: .secondary)
            StatusPill(title: "Relay 未連線", systemImage: "antenna.radiowaves.left.and.right.slash", tint: .orange)

            Button {
            } label: {
                Label("開始字幕", systemImage: "play.fill")
                    .frame(minWidth: 104)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

private struct ControlSidebar: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Panel(title: "工作階段", systemImage: "dot.radiowaves.left.and.right") {
                VStack(alignment: .leading, spacing: 14) {
                    LabeledValue(label: "狀態", value: "尚未開始")
                    LabeledValue(label: "收音", value: "未啟用")
                    LabeledValue(label: "字幕事件", value: "0")
                }
            }

            Panel(title: "音訊輸入", systemImage: "mic", minHeight: 168) {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("來源", selection: .constant("MacBook Pro Microphone")) {
                        Text("MacBook Pro Microphone").tag("MacBook Pro Microphone")
                    }

                    AudioLevelMeter()

                    VStack(alignment: .leading, spacing: 8) {
                        PermissionRow(title: "麥克風權限", state: "待確認", tint: .orange)
                        PermissionRow(title: "系統音訊權限", state: "未啟用", tint: .secondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct CaptionWorkspace: View {
    @Binding var inputLanguage: InputLanguage
    let outputLanguages: [SpeechOutputLanguage]

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("字幕預覽")
                                .font(.title2.weight(.semibold))

                            StatusPill(title: "等待語音", systemImage: "pause.circle", tint: .secondary)
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
                            text: "歡迎來到今天的活動，字幕系統準備就緒。"
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "預覽", systemImage: "captions.bubble")

                        VStack(spacing: 12) {
                            ForEach(outputLanguages) { language in
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

private struct StatusSidebar: View {
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
                    SpeechAuthorizationValue(status: speechAuthorizationStatus)
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
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct SpeechSettingsSheet: View {
    @Binding var settings: SpeechSettings
    @Binding var isPresented: Bool
    let onConnectionTested: (SpeechConnectionTestResult) -> Void
    let onFailure: (String) -> Void
    let onAuthorizationSettingsChanged: () -> Void
    @State private var connectionTestStatus = SpeechConnectionTestStatus.idle
    @State private var activeConnectionTestID: UUID?

    private var canTestConnection: Bool {
        settings.hasAuthorizationMaterial && !settings.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var buildRequirementMessage: String {
        var missingItems: [String] = []

        if settings.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missingItems.append("Region")
        }

        if !settings.hasAuthorizationMaterial {
            missingItems.append("Speech Key")
        }

        guard !missingItems.isEmpty else {
            return "設定完整，可測試 Azure Speech 連線。"
        }

        return "補齊 \(missingItems.joined(separator: "、")) 後可測試。"
    }

    private var connectionHintMessage: String {
        connectionTestStatus.message.isEmpty ? buildRequirementMessage : connectionTestStatus.message
    }

    private var connectionHintTint: Color {
        connectionTestStatus.message.isEmpty
            ? (canTestConnection ? .green : .orange)
            : connectionTestStatus.tint
    }

    private func saveSettings() {
        settings.save()
    }

    private func testConnection() {
        settings.save()
        let testID = UUID()
        activeConnectionTestID = testID
        connectionTestStatus = .testing
        let settingsToTest = settings

        Task {
            do {
                let result = try await settingsToTest.testConnection()

                await MainActor.run {
                    guard activeConnectionTestID == testID else {
                        return
                    }

                    connectionTestStatus = .success
                    onConnectionTested(result)
                }
            } catch {
                let message = error.localizedDescription

                await MainActor.run {
                    guard activeConnectionTestID == testID else {
                        return
                    }

                    connectionTestStatus = .failure(message)
                    onFailure(message)
                }
            }
        }
    }

    private func markConnectionTestChanged() {
        activeConnectionTestID = nil
        connectionTestStatus = .idle
        onAuthorizationSettingsChanged()
    }

    var body: some View {
        VStack(spacing: 0) {
            SpeechSettingsHeader()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SpeechSettingsSection(title: "認證", systemImage: "key.horizontal") {
                        VStack(alignment: .leading, spacing: 14) {
                            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                                SpeechSettingsFieldRow(label: "Region") {
                                    TextField("例如：japaneast", text: $settings.region)
                                        .textFieldStyle(.roundedBorder)
                                }

                                SpeechSettingsFieldRow(label: "Speech Key") {
                                    SecureField("只保存在本機設定中", text: $settings.speechKey)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    }

                    SpeechSettingsSection(title: "字幕輸出", systemImage: "captions.bubble") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(availableSpeechOutputLanguages) { language in
                                OutputLanguageToggleRow(
                                    language: language,
                                    isRequired: SpeechSettings.requiredOutputLanguageIDs.contains(language.id),
                                    selectedLanguageIDs: $settings.selectedOutputLanguageIDs
                                )
                            }
                        }
                    }

                    SpeechSettingsSection(title: "檢查", systemImage: "checkmark.seal") {
                        VStack(alignment: .leading, spacing: 12) {
                            SpeechSettingsStatusRow(
                                title: "連線測試",
                                state: connectionTestStatus.title,
                                tint: connectionTestStatus.tint
                            )

                            HStack {
                                SpeechConnectionTestButton(
                                    isEnabled: canTestConnection && !connectionTestStatus.isTesting,
                                    action: testConnection
                                )

                                Spacer()
                            }
                            .controlSize(.large)

                            Text(connectionHintMessage)
                                .font(.caption)
                                .foregroundStyle(connectionHintTint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Spacer()

                Button("完成") {
                    saveSettings()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(width: 640, height: 660)
        .onDisappear {
            saveSettings()
        }
        .onChange(of: settings.region) {
            markConnectionTestChanged()
        }
        .onChange(of: settings.speechKey) {
            markConnectionTestChanged()
        }
    }
}

private enum SpeechConnectionTestStatus {
    case idle
    case testing
    case success
    case failure(String)

    var title: String {
        switch self {
        case .idle:
            "尚未測試"
        case .testing:
            "測試中"
        case .success:
            "可連線"
        case .failure:
            "測試失敗"
        }
    }

    var message: String {
        switch self {
        case .idle:
            ""
        case .testing:
            "正在測試 Azure Speech 認證與區域設定。"
        case .success:
            "Azure Speech 測試成功。"
        case .failure(let message):
            message
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            .secondary
        case .testing:
            .blue
        case .success:
            .green
        case .failure:
            .red
        }
    }

    var isTesting: Bool {
        if case .testing = self {
            return true
        }

        return false
    }
}

private struct SpeechSettingsHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("Speech 設定")
                    .font(.title3.weight(.semibold))
                Text("Azure Speech SDK 連線與認證設定")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusPill(title: "SDK 1.43.0", systemImage: "shippingbox", tint: .blue)
        }
        .padding(24)
    }
}

private struct SpeechSettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: title, systemImage: systemImage)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SpeechSettingsFieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        GridRow {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            content
        }
    }
}

private struct SpeechConnectionTestButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            guard isEnabled else {
                return
            }

            action()
        } label: {
            Label("測試連線", systemImage: "network")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isEnabled ? Color.white : Color.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isEnabled ? Color.accentColor : Color(nsColor: .disabledControlTextColor).opacity(0.12))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isEnabled ? Color.accentColor.opacity(0.35) : Color(nsColor: .separatorColor),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.62)
        .accessibilityHint(isEnabled ? "測試 Azure Speech 設定" : "需要補齊 Region 與 Speech Key")
    }
}

private struct OutputLanguageToggleRow: View {
    let language: SpeechOutputLanguage
    let isRequired: Bool
    @Binding var selectedLanguageIDs: Set<String>

    private var isSelected: Binding<Bool> {
        Binding {
            isRequired || selectedLanguageIDs.contains(language.id)
        } set: { newValue in
            if isRequired {
                selectedLanguageIDs.insert(language.id)
            } else if newValue {
                selectedLanguageIDs.insert(language.id)
            } else {
                selectedLanguageIDs.remove(language.id)
            }
        }
    }

    var body: some View {
        Toggle(isOn: isSelected) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.nativeName)
                        .font(.subheadline.weight(.medium))
                    Text(language.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isRequired {
                    Text("必選")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(isRequired)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct SpeechSettingsStatusRow: View {
    let title: String
    let state: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)

            Text(title)
                .font(.subheadline)

            Spacer()

            Text(state)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
        }
    }
}

private struct LogDrawer: View {
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

private struct LogDrawerHeader: View {
    @Binding var isExpanded: Bool
    @Binding var selectedLevel: LogLevel
    let entryCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                Label("事件紀錄", systemImage: isExpanded ? "chevron.down" : "chevron.up")
            }
            .buttonStyle(.plain)
            .font(.headline)

            Text("最近 \(entryCount) 筆")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Picker("Log Level", selection: $selectedLevel) {
                ForEach(LogLevel.allCases) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct LogDrawerContent: View {
    let entries: [LogEntry]

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            ScrollView {
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
        .frame(height: 220)
        .frame(maxWidth: .infinity)
    }
}

private struct LogEntryRow: View {
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

private struct Panel<Content: View>: View {
    let title: String
    let systemImage: String
    var minHeight: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .labelStyle(.titleAndIcon)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }
}

private struct CaptionCard: View {
    let languageName: String
    let languageNativeName: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(languageNativeName)
                        .font(.headline)
                    Text(languageName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(text)
                .font(.system(size: 24, weight: .regular))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.blue)
                .frame(width: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }
}

private struct LiveTranscriptCard: View {
    let languageName: String
    let languageNativeName: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(languageNativeName)
                        .font(.headline)
                    Text(languageName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(text)
                .font(.system(size: 28, weight: .medium))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.green)
                .frame(width: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }
}

private struct SectionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct AudioLevelMeter: View {
    private let currentLevel = 0.64
    private let peakLevel = 0.78

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.green, .yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * currentLevel)

                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 2)
                        .offset(x: max(0, proxy.size.width * peakLevel - 1))
                }
            }
            .frame(height: 12)
            .accessibilityLabel("音訊輸入音量")
            .accessibilityValue("-36 dB")

            Text("-36 dB")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct StatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct LabeledValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .font(.subheadline)
    }
}

private struct SpeechAuthorizationValue: View {
    let status: SpeechAuthorizationStatus

    var body: some View {
        HStack {
            Text("授權")
                .foregroundStyle(.secondary)

            Spacer()

            Text(status.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(status.tint)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(status.tint.opacity(0.14), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(status.tint.opacity(0.34), lineWidth: 1)
                }
        }
        .font(.subheadline)
    }
}

private struct PermissionRow: View {
    let title: String
    let state: String
    let tint: Color

    var body: some View {
        HStack {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text(state)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
