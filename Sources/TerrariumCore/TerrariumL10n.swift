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

/// 温度显示单位偏好（底层仿真与存档始终保持摄氏度 °C，仅在展示层与文案层自动换算）
public enum TemperatureUnit: String, CaseIterable, Identifiable, Codable {
    case celsius = "C"
    case fahrenheit = "F"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    public var localizedButtonLabel: String {
        switch self {
        case .celsius: return TerrariumL10n.t("settings.temp_celsius")
        case .fahrenheit: return TerrariumL10n.t("settings.temp_fahrenheit")
        }
    }

    /// 绝对温度换算：°F = round(°C * 9 / 5 + 32)
    public func convert(celsius: Int) -> Int {
        switch self {
        case .celsius:
            return celsius
        case .fahrenheit:
            return Int((Double(celsius) * 9.0 / 5.0 + 32.0).rounded())
        }
    }

    /// 温差换算：Δ°F = round(Δ°C * 9 / 5)
    public func convertDelta(celsiusDelta: Int) -> Int {
        switch self {
        case .celsius:
            return celsiusDelta
        case .fahrenheit:
            return Int((Double(celsiusDelta) * 9.0 / 5.0).rounded())
        }
    }

    /// 格式化温度读数（includeUnitLetter=true 输出如 "22°C"/"72°F"，false 输出如 "22°"/"72°"）
    public func format(celsius: Int, includeUnitLetter: Bool = true) -> String {
        let val = convert(celsius: celsius)
        return includeUnitLetter ? "\(val)\(symbol)" : "\(val)°"
    }
}

/// 日常生态小贴士轮播频率设定（默认每 60 秒轮播一条）
public enum DailyTipsFrequency: String, CaseIterable, Identifiable, Codable {
    case fast30s = "30s"
    case standard1m = "60s"
    case relaxed5m = "300s"
    case off = "off"

    public var id: String { rawValue }

    /// 自动轮播间隔秒数（`nil` 表示关闭日常小贴士）
    public var intervalSeconds: TimeInterval? {
        switch self {
        case .fast30s: return 30.0
        case .standard1m: return 60.0
        case .relaxed5m: return 300.0
        case .off: return nil
        }
    }

    public var localizedButtonLabel: String {
        switch self {
        case .fast30s: return TerrariumL10n.t("settings.tips_freq_30s")
        case .standard1m: return TerrariumL10n.t("settings.tips_freq_60s")
        case .relaxed5m: return TerrariumL10n.t("settings.tips_freq_300s")
        case .off: return TerrariumL10n.t("settings.tips_freq_off")
        }
    }
}

/// 纯 Foundation 跨模块本地化引擎（不引入 SwiftUI/AppKit，保障无头核心层与单测纯净运行）
public final class TerrariumL10n {
    public static let shared = TerrariumL10n()

    private static let preferenceKey = "terrarium.languagePreference"
    private static let temperatureUnitKey = "terrarium.temperatureUnit"
    private static let tipsFrequencyKey = "terrarium.dailyTipsFrequency"
    private static let celsiusPattern: NSRegularExpression? = try? NSRegularExpression(pattern: "([+-]?\\d+)°C")
    private let lock = NSLock()
    private var tables: [SupportedLanguage: [String: String]] = [:]
    private var overrideLanguageStorage: SupportedLanguage?
    private var overrideTemperatureUnitStorage: TemperatureUnit?
    private var overrideTipsFrequencyStorage: DailyTipsFrequency?

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

    /// 持久化于 UserDefaults 的温度显示单位（默认摄氏度 °C）
    public var temperatureUnit: TemperatureUnit {
        get {
            lock.lock()
            defer { lock.unlock() }
            if let raw = UserDefaults.standard.string(forKey: Self.temperatureUnitKey),
               let parsed = TemperatureUnit(rawValue: raw) {
                return parsed
            }
            return .celsius
        }
        set {
            lock.lock()
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.temperatureUnitKey)
            lock.unlock()
        }
    }

    /// 无头单测专用的临时温度单位覆写（不修改 UserDefaults）
    public static func setOverrideTemperatureUnit(_ unit: TemperatureUnit?) {
        shared.lock.lock()
        shared.overrideTemperatureUnitStorage = unit
        shared.lock.unlock()
    }

    /// 当前实际生效温度单位（测试覆写 > UserDefaults 持久化设定）
    public var currentTemperatureUnit: TemperatureUnit {
        lock.lock()
        let overrideUnit = overrideTemperatureUnitStorage
        lock.unlock()
        if let overrideUnit {
            return overrideUnit
        }
        return temperatureUnit
    }

    /// 持久化于 UserDefaults 的日常小贴士轮播频率（默认 1 分钟 `.standard1m`）
    public var tipsFrequency: DailyTipsFrequency {
        get {
            lock.lock()
            defer { lock.unlock() }
            if let raw = UserDefaults.standard.string(forKey: Self.tipsFrequencyKey),
               let parsed = DailyTipsFrequency(rawValue: raw) {
                return parsed
            }
            return .standard1m
        }
        set {
            lock.lock()
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.tipsFrequencyKey)
            lock.unlock()
        }
    }

    /// 无头单测专用的临时小贴士频率覆写（不修改 UserDefaults）
    public static func setOverrideTipsFrequency(_ freq: DailyTipsFrequency?) {
        shared.lock.lock()
        shared.overrideTipsFrequencyStorage = freq
        shared.lock.unlock()
    }

    /// 当前实际生效日常小贴士频率（测试覆写 > UserDefaults 持久化设定）
    public var currentTipsFrequency: DailyTipsFrequency {
        lock.lock()
        let overrideFreq = overrideTipsFrequencyStorage
        lock.unlock()
        if let overrideFreq {
            return overrideFreq
        }
        return tipsFrequency
    }

    /// 当前生态缸可用的日常小贴士 Key 池（12 条通用 + 1 条当前生态缸专属，共 13 条）
    public static func dailyTipKeys(for biome: TerrariumBiome) -> [String] {
        var keys = (1...12).map { "tips.general.\($0)" }
        switch biome {
        case .meadow:
            keys.append("tips.biome.meadow")
        case .sand:
            keys.append("tips.biome.sand")
        case .rainforest:
            keys.append("tips.biome.rainforest")
        case .aquatic:
            keys.append("tips.biome.aquatic")
        case .reef:
            keys.append("tips.biome.reef")
        }
        return keys
    }

    /// 按轮播序号获取当前生态缸的本地化日常小贴士
    public static func dailyTip(for biome: TerrariumBiome, index: Int) -> String {
        let keys = dailyTipKeys(for: biome)
        let safeIdx = ((index % keys.count) + keys.count) % keys.count
        return t(keys[safeIdx])
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
        let unit = shared.currentTemperatureUnit
        if unit == .fahrenheit, result.contains("°C") {
            result = convertCelsiusInText(result, key: key, unit: unit)
        }
        return result
    }

    /// 将本地化文本中的 `([+-]?\d+)°C` 自动换算为 `°F`（兼容绝对温度与温差 Δ°C）
    private static func convertCelsiusInText(_ text: String, key: String, unit: TemperatureUnit) -> String {
        guard unit == .fahrenheit, let regex = celsiusPattern else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            let fullToken = nsText.substring(with: match.range)
            let numStr = nsText.substring(with: match.range(at: 1))
            guard let cVal = Int(numStr) else { continue }

            let isDelta = (key == "decor.boulder.desc")
                || numStr.hasPrefix("+")
                || (key == "sensor.fan_help_on" && fullToken == "-4°C")
            let replacement: String
            if isDelta {
                let dVal = unit.convertDelta(celsiusDelta: cVal)
                let prefix = (numStr.hasPrefix("+") && dVal > 0) ? "+" : ""
                replacement = "\(prefix)\(dVal)°F"
            } else {
                let fVal = unit.convert(celsius: cVal)
                replacement = "\(fVal)°F"
            }
            mutable.replaceCharacters(in: match.range, with: replacement)
        }
        return mutable as String
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
