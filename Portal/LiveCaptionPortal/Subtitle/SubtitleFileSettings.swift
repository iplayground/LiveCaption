import Foundation

struct SubtitleFileSettings: Equatable {
    private static let userDefaults = UserDefaults.standard

    var storageDirectoryURL: URL?

    var storageDirectorySummary: String {
        storageDirectoryURL?.path(percentEncoded: false) ?? L10n.text("common.notConfigured")
    }

    static func load() -> SubtitleFileSettings {
        guard let bookmarkData = userDefaults.data(forKey: UserDefaultsKey.storageDirectoryBookmark.rawValue) else {
            return SubtitleFileSettings()
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            return SubtitleFileSettings(storageDirectoryURL: isStale ? nil : url)
        } catch {
            return SubtitleFileSettings()
        }
    }

    mutating func setStorageDirectory(_ url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        storageDirectoryURL = url
        Self.userDefaults.set(bookmarkData, forKey: UserDefaultsKey.storageDirectoryBookmark.rawValue)
    }

    mutating func clearStorageDirectory() {
        storageDirectoryURL = nil
        Self.userDefaults.removeObject(forKey: UserDefaultsKey.storageDirectoryBookmark.rawValue)
    }

    private enum UserDefaultsKey: String {
        case storageDirectoryBookmark = "subtitleFileSettings.storageDirectoryBookmark"
    }
}
