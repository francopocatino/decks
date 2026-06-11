import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class UpdateChecker {
    struct Update: Equatable {
        var version: String
        var url: URL
        var download: URL?
    }

    private(set) var update: Update?
    private(set) var installing = false
    var installError: String?

    private let repo = "francopocatino/decks"

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    func install() async {
        guard let update, let zip = update.download, !installing else { return }
        installing = true
        installError = nil
        do {
            let downloaded = try await URLSession.shared.download(from: zip).0
            let target = Bundle.main.bundlePath
            let script = try await Task.detached { try Self.stage(zip: downloaded, target: target) }.value
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path]
            try process.run()
            NSApp.terminate(nil)
        } catch {
            installError = error.localizedDescription
            installing = false
        }
    }

    private nonisolated static func stage(zip: URL, target: String) throws -> URL {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("DecksUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let extract = Process()
        extract.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        extract.arguments = ["-x", "-k", zip.path, work.path]
        try extract.run()
        extract.waitUntilExit()

        let newApp = work.appendingPathComponent("Decks.app")
        guard extract.terminationStatus == 0, FileManager.default.fileExists(atPath: newApp.path) else {
            throw UpdateError.badArchive
        }

        let script = """
        #!/bin/bash
        while /usr/bin/pgrep -x Decks >/dev/null 2>&1; do sleep 0.3; done
        /bin/rm -rf "\(target)"
        /usr/bin/ditto "\(newApp.path)" "\(target)"
        /usr/bin/xattr -dr com.apple.quarantine "\(target)" 2>/dev/null
        /usr/bin/open "\(target)"
        /bin/rm -rf "\(work.path)"
        """
        let scriptURL = work.appendingPathComponent("swap.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        return scriptURL
    }

    enum UpdateError: LocalizedError {
        case badArchive

        var errorDescription: String? {
            switch self {
            case .badArchive: "The downloaded update was not a valid Decks.app."
            }
        }
    }

    func check() async {
        guard
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            let endpoint = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")
        else { return }

        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200,
            let release = try? JSONDecoder().decode(Release.self, from: data),
            let page = URL(string: release.htmlURL)
        else { return }

        let latest = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        let download = release.assets
            .first { $0.name.hasSuffix(".zip") }
            .flatMap { URL(string: $0.browserDownloadURL) }
        update = isNewer(latest, than: current) ? Update(version: latest, url: page, download: download) : nil
    }

    private func isNewer(_ latest: String, than current: String) -> Bool {
        let left = latest.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0 ..< max(left.count, right.count) {
            let lhs = index < left.count ? left[index] : 0
            let rhs = index < right.count ? right[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}
