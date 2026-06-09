import Foundation

enum Storage {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static var root: URL {
        if let dir = ProcessInfo.processInfo.environment["DECKS_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".decks", isDirectory: true)
    }

    static func deckDirectory(_ slug: String) -> URL {
        root.appendingPathComponent(slug, isDirectory: true)
    }

    static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func readString(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func writeString(_ value: String, to url: URL) {
        try? Data(value.utf8).write(to: url, options: .atomic)
    }

    static func readJSON<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let value = try? decoder.decode(T.self, from: data) { return value }
        if !data.isEmpty { backupCorrupt(url) }
        return nil
    }

    private static func backupCorrupt(_ url: URL) {
        let backup = url.appendingPathExtension("corrupt")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        try? FileManager.default.copyItem(at: url, to: backup)
    }

    static func writeJSON(_ value: some Encodable, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
