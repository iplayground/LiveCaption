import Foundation
import Combine
import SwiftUI

enum PubSubCaptionConnectionStatus: Equatable {
    case idle
    case negotiating
    case connected(String)
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            L10n.text("pubSub.caption.idle")
        case .negotiating:
            L10n.text("pubSub.caption.connecting")
        case .connected:
            L10n.text("pubSub.caption.connected")
        case .failed:
            L10n.text("pubSub.caption.failed")
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            .secondary
        case .negotiating:
            .blue
        case .connected:
            .green
        case .failed:
            .red
        }
    }
}

struct PubSubCaptionEvent: Equatable {
    let receivedAt: Date
    let trackNumber: Int?
    let captionMode: CaptionQualityMode
    let captionProvider: String?
    let captions: [String: String]

    var sortedCaptions: [(languageID: String, text: String)] {
        captions
            .filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.key < $1.key }
            .map { (languageID: $0.key, text: $0.value) }
    }
}

@MainActor
final class PubSubCaptionReceiver: ObservableObject {
    @Published private(set) var status = PubSubCaptionConnectionStatus.idle
    @Published private(set) var latestCaptions: [CaptionQualityMode: PubSubCaptionEvent] = [:]

    private var webSocketTasks: [CaptionQualityMode: URLSessionWebSocketTask] = [:]
    private var receiveTask: Task<Void, Never>?
    private var connectionID = UUID()

    func latestCaption(for mode: CaptionQualityMode) -> PubSubCaptionEvent? {
        latestCaptions[mode]
    }

    func connect(settings: RelaySettings, viewerAccessCode: String?) {
        disconnect(keepsLatestCaption: true)
        status = .negotiating

        let currentConnectionID = UUID()
        connectionID = currentConnectionID

        Task {
            do {
                let accesses = try await Self.negotiateAccesses(
                    settings: settings,
                    viewerAccessCode: viewerAccessCode
                )
                await MainActor.run {
                    guard self.connectionID == currentConnectionID else {
                        return
                    }

                    self.openWebSockets(accesses: accesses, connectionID: currentConnectionID)
                }
            } catch {
                await MainActor.run {
                    guard self.connectionID == currentConnectionID else {
                        return
                    }

                    self.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    func disconnect(keepsLatestCaption: Bool = false) {
        connectionID = UUID()
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTasks.values.forEach { $0.cancel(with: .goingAway, reason: nil) }
        webSocketTasks.removeAll()
        status = .idle

        if !keepsLatestCaption {
            latestCaptions.removeAll()
        }
    }

    private func openWebSockets(
        accesses: [(mode: CaptionQualityMode, access: RelayViewerAccess)],
        connectionID: UUID
    ) {
        let groups = accesses.map(\.access.group).joined(separator: ", ")
        status = .connected(groups)

        for item in accesses {
            let task = URLSession.shared.webSocketTask(with: item.access.url)
            webSocketTasks[item.mode] = task
            task.resume()
        }

        receiveTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for item in accesses {
                    guard let task = self?.webSocketTasks[item.mode] else {
                        continue
                    }

                    group.addTask {
                        await self?.receiveMessages(
                            connectionID: connectionID,
                            mode: item.mode,
                            task: task
                        )
                    }
                }
            }
        }
    }

    private func receiveMessages(
        connectionID: UUID,
        mode: CaptionQualityMode,
        task: URLSessionWebSocketTask
    ) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                guard let event = Self.captionEvent(from: message, expectedMode: mode) else {
                    continue
                }

                await MainActor.run {
                    guard self.connectionID == connectionID else {
                        return
                    }

                    self.latestCaptions[event.captionMode] = event
                }
            } catch {
                await MainActor.run {
                    guard self.connectionID == connectionID else {
                        return
                    }

                    self.status = .failed(error.localizedDescription)
                }
                return
            }
        }
    }

    nonisolated private static func negotiateAccesses(
        settings: RelaySettings,
        viewerAccessCode: String?
    ) async throws -> [(mode: CaptionQualityMode, access: RelayViewerAccess)] {
        var accesses: [(mode: CaptionQualityMode, access: RelayViewerAccess)] = []
        for mode in [CaptionQualityMode.fast, .accurate] {
            let access = try await settings.negotiateViewerAccess(
                accessCode: viewerAccessCode,
                captionMode: mode
            )
            accesses.append((mode: mode, access: access))
        }
        return accesses
    }

    nonisolated private static func captionEvent(
        from message: URLSessionWebSocketTask.Message,
        expectedMode: CaptionQualityMode
    ) -> PubSubCaptionEvent? {
        switch message {
        case .string(let text):
            return captionEvent(from: Data(text.utf8), expectedMode: expectedMode)
        case .data(let data):
            return captionEvent(from: data, expectedMode: expectedMode)
        @unknown default:
            return nil
        }
    }

    nonisolated private static func captionEvent(
        from data: Data,
        expectedMode: CaptionQualityMode
    ) -> PubSubCaptionEvent? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        return captionEvent(fromJSONObject: payload, expectedMode: expectedMode)
    }

    nonisolated private static func captionEvent(
        fromJSONObject payload: Any,
        expectedMode: CaptionQualityMode
    ) -> PubSubCaptionEvent? {
        guard let captionPayload = captionPayload(from: payload),
              let captions = captionPayload["captions"] as? [String: String],
              !captions.isEmpty else {
            return nil
        }

        let captionMode = (captionPayload["captionMode"] as? String)
            .flatMap(CaptionQualityMode.init(rawValue:)) ?? .fast

        guard captionMode == expectedMode else {
            return nil
        }

        return PubSubCaptionEvent(
            receivedAt: Date(),
            trackNumber: captionPayload["trackNumber"] as? Int,
            captionMode: captionMode,
            captionProvider: captionPayload["captionProvider"] as? String,
            captions: captions
        )
    }

    nonisolated private static func captionPayload(from payload: Any) -> [String: Any]? {
        guard let dictionary = payload as? [String: Any] else {
            return nil
        }

        if dictionary["captions"] is [String: String] {
            return dictionary
        }

        if let nestedPayload = dictionary["data"] as? [String: Any] {
            return captionPayload(from: nestedPayload)
        }

        if let nestedPayloadString = dictionary["data"] as? String,
           let nestedPayloadData = nestedPayloadString.data(using: .utf8),
           let nestedPayload = try? JSONSerialization.jsonObject(with: nestedPayloadData) {
            return captionPayload(from: nestedPayload)
        }

        return nil
    }
}
