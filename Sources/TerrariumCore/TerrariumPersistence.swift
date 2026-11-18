import Foundation

/// 本地 JSON 持久化管理（默认存放于 ~/Library/Application Support/TerrariumMenuBar/save.json）
public final class TerrariumPersistence {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let customURL = fileURL {
            self.fileURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let dir = appSupport.appendingPathComponent("TerrariumMenuBar", isDirectory: true)
            self.fileURL = dir.appendingPathComponent("save.json")
        }
    }

    public func load() -> TerrariumSaveData? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TerrariumSaveData.self, from: data)
    }

    @discardableResult
    public func save(_ saveData: TerrariumSaveData) -> Bool {
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(saveData)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
