//
//  ContentView.swift
//  LiveCaptionPortal
//
//  Created by Hao Lee on 2026/4/26.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var inputLanguage = InputLanguage.mandarin
    @State private var isLogDrawerExpanded = false
    @State private var selectedLogLevel = LogLevel.all
    private let windowMinimumSize = WindowLayout.minimumSize

    private var filteredLogEntries: [LogEntry] {
        guard selectedLogLevel != .all else {
            return sampleLogEntries
        }

        return sampleLogEntries.filter { $0.level == selectedLogLevel }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HeaderView()

                Divider()

                HStack(alignment: .top, spacing: 0) {
                    ControlSidebar()

                    Divider()

                    CaptionWorkspace(inputLanguage: $inputLanguage)

                    Divider()

                    StatusSidebar()
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
    case mandarin = "國語"
    case english = "English"

    var id: String { rawValue }
}

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

private let sampleLogEntries = [
    LogEntry(time: "00:00", level: .info, title: "Portal 已啟動", detail: "等待音訊來源與 Relay 設定"),
    LogEntry(time: "00:00", level: .info, title: "語言輸出已固定", detail: "zh-TW、ja-JP、en-US"),
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
                                    Text(language.rawValue).tag(language)
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
                            inputLanguage: inputLanguage.rawValue,
                            text: "歡迎來到今天的活動，字幕系統準備就緒。"
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "預覽", systemImage: "captions.bubble")

                        VStack(spacing: 12) {
                            CaptionCard(
                                language: "台灣繁體中文",
                                code: "zh-TW",
                                text: "歡迎來到今天的活動，字幕系統準備就緒。"
                            )
                            CaptionCard(
                                language: "日本語",
                                code: "ja-JP",
                                text: "本日のイベントへようこそ。字幕システムの準備ができました。"
                            )
                            CaptionCard(
                                language: "English",
                                code: "en-US",
                                text: "Welcome to today's event. The caption system is ready."
                            )
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
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Panel(title: "Speech", systemImage: "waveform.badge.magnifyingglass") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledValue(label: "授權", value: "未設定")
                    LabeledValue(label: "Region", value: "尚未設定")
                    LabeledValue(label: "Token", value: "尚未取得")
                    LabeledValue(label: "最後刷新", value: "尚無")
                    LabeledValue(label: "下次刷新", value: "尚無")

                    Button {
                    } label: {
                        Label("開啟設定", systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
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

private struct LogDrawer: View {
    @Binding var isExpanded: Bool
    @Binding var selectedLevel: LogLevel
    let entries: [LogEntry]

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            LogDrawerHeader(
                isExpanded: $isExpanded,
                selectedLevel: $selectedLevel
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

            Text("最近 \(sampleLogEntries.count) 筆")
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
    let language: String
    let code: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language)
                        .font(.headline)
                    Text(code)
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
    let inputLanguage: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("語音輸入即時字幕")
                        .font(.headline)
                    Text(inputLanguage)
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
