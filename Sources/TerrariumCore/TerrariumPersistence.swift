import Foundation
import os

/// 本地 JSON 持久化管理（默认存放于 ~/Library/Application Support/TerrariumMenuBar/save.json）
public final class TerrariumPersistence {
    public let fileURL: URL
    public var backupURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("json.bak")
    }
    private let logger = Logger(subsystem: "com.ccgs.TerrariumMenuBar", category: "Persistence")

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
        let fm = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if fm.fileExists(atPath: fileURL.path) {
            if let data = try? Data(contentsOf: fileURL),
               let decoded = try? decoder.decode(TerrariumSaveData.self, from: data) {
                return decoded
            }
            // 主档存在但损坏/解码失败：隔离坏档并尝试从 .bak 恢复，绝不静默覆写丢档
            let stamp = Int(Date().timeIntervalSince1970)
            let corruptedURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("save.corrupted.\(stamp).json")
            try? fm.moveItem(at: fileURL, to: corruptedURL)
            logger.error("Primary save corrupted, isolated to \(corruptedURL.lastPathComponent, privacy: .public)")
        }

        if fm.fileExists(atPath: backupURL.path),
           let bakData = try? Data(contentsOf: backupURL),
           let bakDecoded = try? decoder.decode(TerrariumSaveData.self, from: bakData) {
            logger.notice("Recovered save data from backup \(self.backupURL.lastPathComponent, privacy: .public)")
            return bakDecoded
        }
        return nil
    }

    @discardableResult
    public func save(_ saveData: TerrariumSaveData) -> Bool {
        let dir = fileURL.deletingLastPathComponent()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(saveData)

            // 仅当现存主档可正常解码时才轮转覆盖 .bak，防止坏档污染备份
            if fm.fileExists(atPath: fileURL.path),
               let existing = try? Data(contentsOf: fileURL) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if (try? decoder.decode(TerrariumSaveData.self, from: existing)) != nil {
                    try? fm.removeItem(at: backupURL)
                    try? fm.copyItem(at: fileURL, to: backupURL)
                }
            }

            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            logger.error("Failed to save data: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    public func reset() {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: backupURL)
    }
}
