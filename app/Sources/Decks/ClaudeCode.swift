import Foundation

enum ClaudeCode {
    static func decksRegistered() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        if hasDecksServer(root["mcpServers"]) { return true }
        if let projects = root["projects"] as? [String: Any] {
            for project in projects.values {
                if hasDecksServer((project as? [String: Any])?["mcpServers"]) { return true }
            }
        }
        return false
    }

    private static func hasDecksServer(_ value: Any?) -> Bool {
        guard let servers = value as? [String: Any] else { return false }
        return servers.values.contains { entry in
            ((entry as? [String: Any])?["command"] as? String)?.contains("decks-mcp") ?? false
        }
    }
}
