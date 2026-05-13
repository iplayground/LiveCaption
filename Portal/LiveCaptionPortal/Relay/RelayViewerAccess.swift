import Foundation

enum RelayViewerAccessError: LocalizedError {
    case serviceRejected(Int, String?)
    case invalidResponse
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .serviceRejected(let statusCode, let message):
            if let message, !message.isEmpty {
                return L10n.text("relaySettings.error.serviceRejectedWithMessage", statusCode, message)
            }

            return L10n.text("relaySettings.error.serviceRejected", statusCode)
        case .invalidResponse:
            return L10n.text("relaySettings.error.invalidResponse")
        case .connectionFailed(let message):
            return L10n.text("relaySettings.error.connectionFailed", message)
        }
    }
}

struct RelayViewerAccess {
    let url: URL
    let group: String
    let expiresAt: Date
}

extension RelaySettings {
    nonisolated func negotiateViewerAccess(
        accessCode: String?
    ) async throws -> RelayViewerAccess {
        let relayURL = try validatedRelayURL()
        let trackNumber = try validatedTrackNumber()
        let endpointURL = relayURL.appending(path: "api/viewer/negotiate")
        let payload: [String: Any] = ["trackNumber": trackNumber]
        let body = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let accessCode = accessCode?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accessCode.isEmpty {
            request.setValue(accessCode, forHTTPHeaderField: "X-LiveCaption-Viewer-Access-Code")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RelayViewerAccessError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw RelayViewerAccessError.serviceRejected(
                    httpResponse.statusCode,
                    Self.viewerAccessErrorMessage(from: data)
                )
            }

            return try Self.viewerAccess(from: data, trackNumber: trackNumber)
        } catch {
            if let viewerAccessError = error as? RelayViewerAccessError {
                throw viewerAccessError
            }

            throw RelayViewerAccessError.connectionFailed(error.localizedDescription)
        }
    }

    nonisolated private static func viewerAccess(from data: Data, trackNumber: Int) throws -> RelayViewerAccess {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlString = payload["url"] as? String,
              let url = URL(string: urlString),
              let expiresAtString = payload["expiresAt"] as? String,
              let expiresAt = parseViewerAccessTimestamp(expiresAtString) else {
            throw RelayViewerAccessError.invalidResponse
        }

        return RelayViewerAccess(url: url, group: "track \(trackNumber)", expiresAt: expiresAt)
    }

    nonisolated private static func viewerAccessErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = payload["error"] as? [String: Any] else {
            return nil
        }

        return error["message"] as? String
    }

    nonisolated private static func parseViewerAccessTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
