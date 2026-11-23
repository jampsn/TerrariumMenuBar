import Foundation

/// 用户在设置中可选的语言偏好（支持跟随系统与 8 种显式语种）
public enum AppLanguagePreference: String, CaseIterable, Identifiable, Codable {
    case system
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en
    case ja
    case ko
    case es
    case de
    case fr

    public var id: String { rawValue }
}

/// 实际生效的 8 种本地化语言
public enum SupportedLanguage: String, CaseIterable, Identifiable {
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en
    case ja
    case ko
    case es
    case de
    case fr

    public var id: String { rawValue }

    /// 供语言选择器展示的母语名称
    public var nativeDisplayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .es: return "Español"
        case .de: return "Deutsch"
        case .fr: return "Français"
        }
    }

    /// 列表拼接分隔符
    public var listSeparator: String {
        switch self {
        case .zhHans, .zhHant, .ja:
            return "、"
        case .en, .ko, .es, .de, .fr:
            return ", "
        }
    }
}

/// 纯 Foundation 跨模块本地化引擎（不引入 SwiftUI/AppKit，保障无头核心层与单测纯净运行）
public final class TerrariumL10n {
    public static let shared = TerrariumL10n()

    private static let preferenceKey = "terrarium.languagePreference"
    private let lock = NSLock()
    private var tables: [SupportedLanguage: [String: String]] = [:]
    private var overrideLanguageStorage: SupportedLanguage?

    private static let resourceBundle: Bundle = {
        if let resURL = Bundle.main.url(forResource: "TerrariumMenuBar_TerrariumCore", withExtension: "bundle"),
           let bundle = Bundle(url: resURL) {
            return bundle
        }
        return Bundle.module
    }()

    private init() {}

    /// 持久化于 UserDefaults 的语言偏好（默认跟随系统）
    public var preference: AppLanguagePreference {
        get {
            lock.lock()
            defer { lock.unlock() }
            if let raw = UserDefaults.standard.string(forKey: Self.preferenceKey),
               let parsed = AppLanguagePreference(rawValue: raw) {
                return parsed
            }
            return .system
        }
        set {
            lock.lock()
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.preferenceKey)
            lock.unlock()
        }
    }

    /// 无头单测专用的临时语言覆写（不修改 UserDefaults）
    public static func setOverrideLanguage(_ language: SupportedLanguage?) {
        shared.lock.lock()
        shared.overrideLanguageStorage = language
        shared.lock.unlock()
    }

    /// 按系统 Locale 偏好列表解析支持的语言（未命中统一回退英语）
    public static func resolveSystemLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> SupportedLanguage {
        for raw in preferredLanguages {
            let tag = raw.lowercased().replacingOccurrences(of: "_", with: "-")
            if tag.hasPrefix("zh") {
                if tag.contains("hant") || tag.contains("tw") || tag.contains("hk") || tag.contains("mo") {
                    return .zhHant
                }
                return .zhHans
            }
            if tag.hasPrefix("ja") { return .ja }
            if tag.hasPrefix("ko") { return .ko }
            if tag.hasPrefix("es") { return .es }
            if tag.hasPrefix("de") { return .de }
            if tag.hasPrefix("fr") { return .fr }
            if tag.hasPrefix("en") { return .en }
        }
        return .en
    }

    /// 当前实际生效语言（测试覆写 > 手动选择 > 系统语言）
    public var currentLanguage: SupportedLanguage {
        lock.lock()
        let overrideLang = overrideLanguageStorage
        lock.unlock()
        if let overrideLang {
            return overrideLang
        }

        switch preference {
        case .system:
            return Self.resolveSystemLanguage()
        case .zhHans: return .zhHans
        case .zhHant: return .zhHant
        case .en: return .en
        case .ja: return .ja
        case .ko: return .ko
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        }
    }

    /// 核心翻译入口：支持 `{name}` 命名占位符；按 当前语种 -> en -> zh-Hans -> key 安全回退
    public static func t(_ key: String, _ params: [String: String] = [:]) -> String {
        let lang = shared.currentLanguage
        var template: String?

        if let currentTable = shared.loadTable(for: lang) {
            template = currentTable[key]
        }
        if template == nil, lang != .en, let enTable = shared.loadTable(for: .en) {
            template = enTable[key]
        }
        if template == nil, lang != .zhHans, let zhTable = shared.loadTable(for: .zhHans) {
            template = zhTable[key]
        }

        var result = template ?? key
        if !params.isEmpty {
            for (paramKey, paramValue) in params {
                result = result.replacingOccurrences(of: "{\(paramKey)}", with: paramValue)
            }
        }
        return result
    }

    /// 读取指定语言的原始词典（供单测与 `--self-test` 做完整度断言）
    public static func rawTable(for language: SupportedLanguage) -> [String: String]? {
        shared.loadTable(for: language)
    }

    private func loadTable(for language: SupportedLanguage) -> [String: String]? {
        lock.lock()
        if let cached = tables[language] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let url = Self.resourceBundle.url(forResource: language.rawValue, withExtension: "json", subdirectory: "Locales"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }

        lock.lock()
        tables[language] = decoded
        lock.unlock()
        return decoded
    }
}
