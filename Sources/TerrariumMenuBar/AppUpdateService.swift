import AppKit
import Foundation

struct GitHubReleaseInfo: Equatable {
    let tagName: String
    let version: String
    let htmlURL: URL
    let dmgURL: URL?
    let dmgFileName: String?
}

enum AppUpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(current: String)
    case available(GitHubReleaseInfo)
    case downloading(version: String)
    case downloaded(fileURL: URL)
    case failed
}

/// 基于 GitHub Releases API 的轻量原生更新检查与 .dmg 下载服务（零第三方依赖）
enum AppUpdateService {
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/jampsn/TerrariumMenuBar/releases/latest")!
    static let releasesPageURL = URL(string: "https://github.com/jampsn/TerrariumMenuBar/releases")!

    private struct ReleaseAssetDTO: Decodable {
        let name: String
        let browser_download_url: String
    }

    private struct ReleaseDTO: Decodable {
        let tag_name: String
        let html_url: String
        let draft: Bool?
        let prerelease: Bool?
        let assets: [ReleaseAssetDTO]?
    }

    static func currentShortVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.1"
    }

    static func normalizeVersion(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[vV]+", with: "", options: .regularExpression)
    }

    static func isNewerVersion(_ remoteRaw: String, than localRaw: String) -> Bool {
        let remoteParts = normalizeVersion(remoteRaw).split(separator: ".").map { Int($0) ?? 0 }
        let localParts = normalizeVersion(localRaw).split(separator: ".").map { Int($0) ?? 0 }
        let count = max(remoteParts.count, localParts.count)
        guard count > 0 else { return false }

        for i in 0..<count {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r != l {
                return r > l
            }
        }
        return false
    }

    static func fetchLatestRelease() async -> GitHubReleaseInfo? {
        var request = URLRequest(url: latestReleaseAPI)
        request.timeoutInterval = 6.0
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PixelTerrarium/\(currentShortVersion())", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let dto = try JSONDecoder().decode(ReleaseDTO.self, from: data)
            guard dto.draft != true, dto.prerelease != true,
                  let htmlURL = URL(string: dto.html_url) else {
                return nil
            }
            let dmgAsset = dto.assets?.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
            let dmgURL = dmgAsset.flatMap { URL(string: $0.browser_download_url) }
            return GitHubReleaseInfo(
                tagName: dto.tag_name,
                version: normalizeVersion(dto.tag_name),
                htmlURL: htmlURL,
                dmgURL: dmgURL,
                dmgFileName: dmgAsset?.name
            )
        } catch {
            return nil
        }
    }

    static func downloadDMG(from remoteURL: URL, fileName: String) async -> URL? {
        guard let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return nil
        }
        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 60.0
        request.setValue("PixelTerrarium/\(currentShortVersion())", forHTTPHeaderField: "User-Agent")

        do {
            let (tempURL, response) = try await URLSession.shared.download(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let destURL = uniqueDestinationURL(in: downloadsDir, fileName: fileName)
            try FileManager.default.moveItem(at: tempURL, to: destURL)
            return destURL
        } catch {
            return nil
        }
    }

    private static func uniqueDestinationURL(in directory: URL, fileName: String) -> URL {
        let baseURL = directory.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: baseURL.path) {
            return baseURL
        }
        let stem = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        for index in 2...50 {
            let candidateName = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }
        return baseURL
    }
}
