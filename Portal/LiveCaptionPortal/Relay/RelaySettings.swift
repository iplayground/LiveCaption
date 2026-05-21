import Foundation
import CryptoKit

struct RelaySettings: Equatable {
    private static let userDefaults = UserDefaults.standard

    var relayURLString = ""
    var roomName = ""
    var trackNumber = 1

}

extension RelaySettings {
    var relayURLSummary: String {
        normalizedRelayURLString.isEmpty ? L10n.text("common.notConfigured") : normalizedRelayURLString
    }

    var roomNameSummary: String {
        normalizedRoomName.isEmpty ? L10n.text("common.notConfigured") : normalizedRoomName
    }

    var trackNumberSummary: String {
        "\(trackNumber)"
    }

    var isConfigured: Bool {
        (try? validatedRelayURL()) != nil && (try? validatedRoomName()) != nil
            && (try? validatedTrackNumber()) != nil
    }

    nonisolated var normalizedRelayURLString: String {
        var normalizedURLString = relayURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalizedURLString.hasSuffix("/") {
            normalizedURLString.removeLast()
        }
        return normalizedURLString
    }

    nonisolated var normalizedRoomName: String {
        roomName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated func validatedRelayURL() throws -> URL {
        let normalizedURLString = normalizedRelayURLString
        guard !normalizedURLString.isEmpty else {
            throw RelaySettingsValidationError.missingRelayURL
        }

        guard let url = URL(string: normalizedURLString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false
        else {
            throw RelaySettingsValidationError.invalidRelayURL
        }

        return url
    }

    nonisolated func validatedRoomName() throws -> String {
        let normalizedName = normalizedRoomName

        guard normalizedName.count <= 80,
              normalizedName.rangeOfCharacter(from: .newlines) == nil,
              normalizedName.rangeOfCharacter(from: .controlCharacters) == nil,
              normalizedName.rangeOfCharacter(from: CharacterSet(charactersIn: "/?#")) == nil
        else {
            throw RelaySettingsValidationError.invalidRoomName
        }

        return normalizedName
    }

    nonisolated func validatedTrackNumber() throws -> Int {
        guard trackNumber > 0 else {
            throw RelaySettingsValidationError.invalidTrackNumber
        }

        return trackNumber
    }

    nonisolated func testConnection(speechKey: String) async throws -> RelayConnectionTestResult {
        let relayURL = try validatedRelayURL()
        let trackNumber = try validatedTrackNumber()
        let normalizedSpeechKey = speechKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedSpeechKey.isEmpty else {
            throw RelayConnectionTestError.missingSpeechKey
        }

        let endpointURL = relayURL.appending(path: "api/caption-events")
        let createdAtHeader = Self.formatTimestamp(Date())
        let body = Data()
        let signature = Self.signature(speechKey: normalizedSpeechKey, timestamp: createdAtHeader, body: body)

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "HEAD"
        request.setValue(createdAtHeader, forHTTPHeaderField: "X-LiveCaption-Timestamp")
        request.setValue(signature, forHTTPHeaderField: "X-LiveCaption-Signature")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RelayConnectionTestError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw RelayConnectionTestError.serviceRejected(httpResponse.statusCode)
            }

            guard let viewerAccessCode = httpResponse.value(
                forHTTPHeaderField: "X-LiveCaption-Viewer-Access-Code"
            ),
                  let expiresAtString = httpResponse.value(
                    forHTTPHeaderField: "X-LiveCaption-Viewer-Access-Expires-At"
                  ),
                  let viewerAccessExpiresAt = Self.parseTimestamp(expiresAtString)
            else {
                throw RelayConnectionTestError.invalidResponse
            }

            return RelayConnectionTestResult(
                relayURL: relayURL,
                trackNumber: trackNumber,
                viewerAccessCode: viewerAccessCode,
                viewerAccessExpiresAt: viewerAccessExpiresAt
            )
        } catch {
            if let relayError = error as? RelayConnectionTestError {
                throw relayError
            }

            throw RelayConnectionTestError.connectionFailed(error.localizedDescription)
        }
    }

    nonisolated func publishCaptionEvent(
        _ input: RelayCaptionPublishInput,
        speechKey: String
    ) async throws -> RelayPublishResult {
        let relayURL = try validatedRelayURL()
        let roomName = try validatedRoomName()
        let trackNumber = try validatedTrackNumber()
        let publishedAt = Date()
        let payload: [String: Any] = [
            "roomName": roomName,
            "trackNumber": trackNumber,
            "sessionId": input.sessionID,
            "createdAt": Self.formatTimestamp(publishedAt),
            "source": Self.sourcePayload(),
            "speech": [
                "inputLanguage": input.inputLanguageSpeechLocale,
                "offsetTicks": input.offsetTicks,
                "durationTicks": input.durationTicks,
                "text": input.speechText,
            ],
            "captions": Self.captions(from: input),
            "captionMode": input.captionMode.rawValue,
            "captionProvider": input.captionProvider,
        ]

        try await send(payload: payload, speechKey: speechKey, createdAt: publishedAt)
        return RelayPublishResult(relayURL: relayURL, publishedAt: publishedAt)
    }

    nonisolated func publishPortalStatus(
        _ status: String,
        speechKey: String
    ) async throws -> RelayPublishResult {
        try await publishControlEvent(
            [
                "event": "portalStatus",
                "status": status,
            ],
            speechKey: speechKey
        )
    }

    nonisolated func markPortalActivity(speechKey: String) async throws -> RelayPublishResult {
        let relayURL = try validatedRelayURL()
        let trackNumber = try validatedTrackNumber()
        let publishedAt = Date()
        let payload: [String: Any] = [
            "trackNumber": trackNumber,
        ]

        try await send(
            payload: payload,
            speechKey: speechKey,
            createdAt: publishedAt,
            path: "api/portal/activity"
        )
        return RelayPublishResult(relayURL: relayURL, publishedAt: publishedAt)
    }

    nonisolated func publishSessionStatus(
        _ status: String,
        sessionID: String,
        speechKey: String
    ) async throws -> RelayPublishResult {
        try await publishControlEvent(
            [
                "event": "sessionStatus",
                "status": status,
                "sessionId": sessionID,
            ],
            speechKey: speechKey
        )
    }

    nonisolated func publishCaptionAvailability(
        sessionID: String?,
        captionModes: [CaptionQualityMode],
        languages: [SpeechOutputLanguage],
        speechKey: String
    ) async throws -> RelayPublishResult {
        var payload: [String: Any] = [
            "event": "captionAvailability",
            "availableCaptionModes": captionModes.map(\.rawValue),
            "availableLanguages": languages.map(\.id),
        ]
        if let sessionID {
            payload["sessionId"] = sessionID
        }

        return try await publishControlEvent(payload, speechKey: speechKey)
    }

    nonisolated private func publishControlEvent(
        _ input: [String: Any],
        speechKey: String
    ) async throws -> RelayPublishResult {
        let relayURL = try validatedRelayURL()
        let trackNumber = try validatedTrackNumber()
        let publishedAt = Date()
        var payload = input
        payload["type"] = "control"
        payload["trackNumber"] = trackNumber
        payload["updatedAt"] = Self.formatTimestamp(publishedAt)

        try await send(payload: payload, speechKey: speechKey, createdAt: publishedAt)
        return RelayPublishResult(relayURL: relayURL, publishedAt: publishedAt)
    }

    nonisolated private func send(
        payload: [String: Any],
        speechKey: String,
        createdAt: Date,
        path: String = "api/caption-events"
    ) async throws {
        let relayURL = try validatedRelayURL()
        let normalizedSpeechKey = speechKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedSpeechKey.isEmpty else {
            throw RelayConnectionTestError.missingSpeechKey
        }

        let endpointURL = relayURL.appending(path: path)
        let createdAtHeader = Self.formatTimestamp(createdAt)
        let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
        let signature = Self.signature(speechKey: normalizedSpeechKey, timestamp: createdAtHeader, body: body)

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(createdAtHeader, forHTTPHeaderField: "X-LiveCaption-Timestamp")
        request.setValue(signature, forHTTPHeaderField: "X-LiveCaption-Signature")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RelayConnectionTestError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw RelayConnectionTestError.serviceRejected(httpResponse.statusCode)
            }
        } catch {
            if let relayError = error as? RelayConnectionTestError {
                throw relayError
            }

            throw RelayConnectionTestError.connectionFailed(error.localizedDescription)
        }
    }

    mutating func normalize() {
        relayURLString = normalizedRelayURLString
        roomName = normalizedRoomName
    }

    func validationMessage() -> String {
        do {
            _ = try validatedRelayURL()
            _ = try validatedRoomName()
            _ = try validatedTrackNumber()
            return L10n.text("relaySettings.requirements.ready")
        } catch {
            return error.localizedDescription
        }
    }

    static func load() -> RelaySettings {
        RelaySettings(
            relayURLString: userDefaults.string(forKey: UserDefaultsKey.relayURL.rawValue) ?? "",
            roomName: userDefaults.string(forKey: UserDefaultsKey.roomName.rawValue) ?? "",
            trackNumber: max(1, userDefaults.integer(forKey: UserDefaultsKey.trackNumber.rawValue))
        )
    }

    func save() {
        let normalizedURLString = normalizedRelayURLString
        if normalizedURLString.isEmpty {
            Self.userDefaults.removeObject(forKey: UserDefaultsKey.relayURL.rawValue)
        } else {
            Self.userDefaults.set(normalizedURLString, forKey: UserDefaultsKey.relayURL.rawValue)
        }

        let normalizedRoomName = normalizedRoomName
        if normalizedRoomName.isEmpty {
            Self.userDefaults.removeObject(forKey: UserDefaultsKey.roomName.rawValue)
        } else {
            Self.userDefaults.set(normalizedRoomName, forKey: UserDefaultsKey.roomName.rawValue)
        }

        Self.userDefaults.set(max(1, trackNumber), forKey: UserDefaultsKey.trackNumber.rawValue)
    }

    private enum UserDefaultsKey: String {
        case relayURL = "relay.url"
        case roomName = "relay.roomName"
        case trackNumber = "relay.trackNumber"
    }

    nonisolated private static func signature(speechKey: String, timestamp: String, body: Data) -> String {
        var message = Data(timestamp.utf8)
        message.append(Data(".".utf8))
        message.append(body)

        let key = SymmetricKey(data: Data(speechKey.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return "sha256=\(signature.map { String(format: "%02x", $0) }.joined())"
    }

    nonisolated private static func formatTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    nonisolated private static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    nonisolated private static func sourcePayload() -> [String: Any] {
        var payload: [String: Any] = [
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "io.iplayground.LiveCaptionPortal"
        ]

        if let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            payload["appVersion"] = appVersion
        }

        return payload
    }

    nonisolated private static func captions(from input: RelayCaptionPublishInput) -> [String: String] {
        captions(
            text: input.text,
            translations: input.translations,
            inputLanguageOutputID: input.inputLanguageOutputID,
            outputLanguageIDs: input.outputLanguageIDs
        )
    }

    nonisolated private static func captions(
        text: String,
        translations: [String: String],
        inputLanguageOutputID: String,
        outputLanguageIDs: [String]
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: outputLanguageIDs.compactMap { languageID in
            let captionText = languageID == inputLanguageOutputID
                ? text
                : translations[languageID]

            guard let normalizedText = captionText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !normalizedText.isEmpty else {
                return nil
            }

            return (languageID, normalizedText)
        })
    }
}
