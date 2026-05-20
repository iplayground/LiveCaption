import Foundation

struct SpeechCredentials: Codable, Equatable {
    var speechKey = ""
    var azureOpenAIAPIKey = ""

    var isEmpty: Bool {
        speechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && azureOpenAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum SpeechCredentialStore {
    static func load() -> SpeechCredentials {
        loadFromFile()
    }

    @discardableResult
    static func save(_ credentials: SpeechCredentials) -> Bool {
        guard let fileURL else {
            return false
        }

        do {
            let fileManager = FileManager.default
            let directoryURL = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directoryURL.path
            )

            if credentials.isEmpty {
                if fileManager.fileExists(atPath: fileURL.path) {
                    try fileManager.removeItem(at: fileURL)
                }
                return true
            }

            let data = try JSONEncoder().encode(credentials)
            try data.write(to: fileURL, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            return true
        } catch {
            return false
        }
    }

    private static func loadFromFile() -> SpeechCredentials {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let credentials = try? JSONDecoder().decode(SpeechCredentials.self, from: data)
        else {
            return SpeechCredentials()
        }

        return credentials
    }

    private static var fileURL: URL? {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        return applicationSupportURL
            .appendingPathComponent("LiveCaptionPortal", isDirectory: true)
            .appendingPathComponent("speech-secrets.json", isDirectory: false)
    }
}
