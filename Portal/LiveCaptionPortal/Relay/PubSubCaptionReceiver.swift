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

    private var webSocketTask: URLSessionWebSocketTask?
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
                let access = try await settings.negotiateViewerAccess(accessCode: viewerAccessCode)
                await MainActor.run {
                    guard self.connectionID == currentConnectionID else {
                        return
                    }

                    self.openWebSocket(access: access, connectionID: currentConnectionID)
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
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        status = .idle

        if !keepsLatestCaption {
            latestCaptions.removeAll()
        }
    }

    private func openWebSocket(
        access: RelayViewerAccess,
        connectionID: UUID
    ) {
        status = .connected(access.group)

        let task = URLSession.shared.webSocketTask(with: access.url)
        webSocketTask = task
        task.resume()
        receiveTask = Task { [weak self] in
            await self?.receiveMessages(
                connectionID: connectionID,
                task: task
            )
        }
    }

    private func receiveMessages(
        connectionID: UUID,
        task: URLSessionWebSocketTask
    ) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                guard let event = Self.captionEvent(from: message) else {
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

    nonisolated private static func captionEvent(
        from message: URLSessionWebSocketTask.Message
    ) -> PubSubCaptionEvent? {
        switch message {
        case .string(let text):
            return captionEvent(from: Data(text.utf8))
        case .data(let data):
            return captionEvent(from: data)
        @unknown default:
            return nil
        }
    }

    nonisolated private static func captionEvent(
        from data: Data
    ) -> PubSubCaptionEvent? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        return captionEvent(fromJSONObject: payload)
    }

    nonisolated private static func captionEvent(
        fromJSONObject payload: Any
    ) -> PubSubCaptionEvent? {
        guard let captionPayload = captionPayload(from: payload),
              let captions = captionPayload["captions"] as? [String: String],
              !captions.isEmpty else {
            return nil
        }

        let captionMode = (captionPayload["captionMode"] as? String)
            .flatMap(CaptionQualityMode.init(rawValue:)) ?? .fast

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
