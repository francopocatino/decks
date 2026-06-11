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

    private let repo = "francopocatino/decks"

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
