import Foundation

public enum TerrariumBiome: String, CaseIterable, Identifiable, Codable {
    case meadow = "温润苔原缸"
    case sand = "暖阳沙地缸"
    case rainforest = "热带雨林缸"
    case aquatic = "碧波鱼缸"

    public var id: String { rawValue }

    public var iconEmoji: String {
        switch self {
        case .meadow: return "🌿"
        case .sand: return "🏜️"
        case .rainforest: return "🌴"
        case .aquatic: return "🐟"
        }
    }

    /// 全 4 种生态缸（苔原/沙地/雨林/碧波鱼缸）现已全面开放购置
    public var isPlayableInCurrentWave: Bool {
        true
    }

    private var l10nKey: String {
        switch self {
        case .meadow: return "meadow"
        case .sand: return "sand"
        case .rainforest: return "rainforest"
        case .aquatic: return "aquatic"
        }
    }

    public var localizedName: String {
        TerrariumL10n.t("biome.\(l10nKey).full")
    }

    public var localizedShortName: String {
        TerrariumL10n.t("biome.\(l10nKey).short")
    }
}

public enum ThermalMode: String, Codable, Equatable, CaseIterable {
    case natural = "自然"
    case heating = "加热"
    case cooling = "降温"

    public var localizedName: String {
        switch self {
        case .natural: return TerrariumL10n.t("thermal.natural")
        case .heating: return TerrariumL10n.t("thermal.heating")
        case .cooling: return TerrariumL10n.t("thermal.cooling")
        }
    }
}

public enum SceneAtmosphere: String, CaseIterable, Identifiable, Codable {
    case day = "日间森林"
    case night = "深夜星月"
    case rain = "林间小雨"
    case warm = "暖阳斜照"

    public var id: String { rawValue }

    public var backgroundAssetName: String {
        switch self {
        case .day: return "bg_room_day"
        case .night: return "bg_room_night"
        case .rain: return "bg_room_rain"
        case .warm: return "bg_room_warm"
        }
    }

    private var l10nKey: String {
        switch self {
        case .day: return "day"
        case .night: return "night"
        case .rain: return "rain"
        case .warm: return "warm"
        }
    }

    public var localizedName: String {
        TerrariumL10n.t("atmosphere.\(l10nKey).full")
    }

    public var localizedShortName: String {
        TerrariumL10n.t("atmosphere.\(l10nKey).short")
    }
}

public enum PopoverTab: String, CaseIterable {
    case terrarium = "生态箱"
    case decor = "造景"
    case critters = "生物"
    case codex = "图鉴"

    public var localizedTitle: String {
        switch self {
        case .terrarium: return TerrariumL10n.t("tab.terrarium")
        case .decor: return TerrariumL10n.t("tab.decor")
        case .critters: return TerrariumL10n.t("tab.critters")
        case .codex: return TerrariumL10n.t("tab.codex")
        }
    }
}

public struct GridCoord: Codable, Hashable, Equatable {
    public var col: Int
    public var row: Int

    public init(col: Int, row: Int) {
        self.col = col
        self.row = row
    }
}

public enum PlantStage: String, Codable, Equatable {
    case sprout
    case mature
    case lushDew
    case wilting
    case withered

    public var localizedName: String {
        TerrariumL10n.t("stage.\(rawValue)")
    }
}

public struct PlantInstance: Identifiable, Codable, Equatable {
    public let id: UUID
    public let speciesID: String
    public var coord: GridCoord
    public var stage: PlantStage
    public var dewLevel: Int
    public var growthSeconds: TimeInterval
    public var wiltSeconds: TimeInterval

    public init(
        id: UUID = UUID(),
        speciesID: String,
        coord: GridCoord,
        stage: PlantStage = .sprout,
        dewLevel: Int = 0,
        growthSeconds: TimeInterval = 0,
        wiltSeconds: TimeInterval = 0
    ) {
        self.id = id
        self.speciesID = speciesID
        self.coord = coord
        self.stage = stage
        self.dewLevel = dewLevel
        self.growthSeconds = growthSeconds
        self.wiltSeconds = wiltSeconds
    }
}

/// 地面小动物类型（按食物链群落分区：捕食者与小型虫螺不可同放在同一生态缸内）
public enum CritterKind: String, Codable, CaseIterable {
    // 苔原缸专属
    case snail = "snail"
    case pillBug = "pill_bug"
    case rhinoBeetle = "rhino_beetle"
    case treeFrog = "tree_frog"
    case fireNewt = "fire_newt"
    case ladybug = "ladybug"
    // 沙地缸专属
    case amberBeetle = "amber_beetle"
    case scarab = "scarab"
    case sandGecko = "sand_gecko"
    case sandScorpion = "sand_scorpion"
    case desertMantis = "desert_mantis"
    case hornedToad = "horned_toad"
    // 热带雨林缸专属
    case leafInsect = "leaf_insect"
    case herculesBeetle = "hercules_beetle"
    case chameleon = "chameleon"
    case dartFrog = "dart_frog"
    case blueMorpho = "blue_morpho"
    case redEyedFrog = "red_eyed_frog"
    // 碧波水草鱼缸专属
    case cherryShrimp = "cherry_shrimp"
    case neonTetra = "neon_tetra"
    case bettaFish = "betta_fish"
    case crayfish = "crayfish"
    case corydoras = "corydoras"
    case otoCatfish = "oto_catfish"
    case crystalShrimp = "crystal_shrimp"

    public var localizedName: String {
        TerrariumL10n.t("critter.\(rawValue).name")
    }
}

public enum TankFrameSkin: String, Codable, CaseIterable, Identifiable {
    case classic = "classic"
    case wood = "wood"
    case brass = "brass"
    case frosted = "frosted"
    case obsidian = "obsidian"

    public var id: String { rawValue }
    public var displayName: String {
        TerrariumL10n.t("skin.\(rawValue)")
    }
    public var cost: Int {
        switch self {
        case .classic: return 0
        case .wood: return 25
        case .brass: return 45
        case .frosted: return 45
        case .obsidian: return 80
        }
    }
}

public enum FoodChainGroup: String, Codable, Equatable {
    case meadowInsects = "微虫螺共生群"
    case meadowPredator = "两栖树蛙领地"
    case sandBeetles = "沙漠甲虫共生群"
    case sandPredator = "沙守宫领地"
    case rainforestInsects = "雨林拟态虫群"
    case rainforestPredator = "变色龙树栖领地"
    case aquaticPeaceful = "温顺鱼虾共生群"
    case aquaticBetta = "半月斗鱼领地"
    case aquaticPredator = "螯虾水底领地"

    public var localizedName: String {
        switch self {
        case .meadowInsects: return TerrariumL10n.t("foodchain.meadow_insects")
        case .meadowPredator: return TerrariumL10n.t("foodchain.meadow_predator")
        case .sandBeetles: return TerrariumL10n.t("foodchain.sand_beetles")
        case .sandPredator: return TerrariumL10n.t("foodchain.sand_predator")
        case .rainforestInsects: return TerrariumL10n.t("foodchain.rainforest_insects")
        case .rainforestPredator: return TerrariumL10n.t("foodchain.rainforest_predator")
        case .aquaticPeaceful: return TerrariumL10n.t("foodchain.aquatic_peaceful")
        case .aquaticBetta: return TerrariumL10n.t("foodchain.aquatic_betta")
        case .aquaticPredator: return TerrariumL10n.t("foodchain.aquatic_predator")
        }
    }
}

public struct CritterShopSpec: Identifiable, Equatable {
    public let kind: CritterKind
    public var id: String { kind.rawValue }
    public let name: String
    public let biome: TerrariumBiome
    public let cost: Int
    public let group: FoodChainGroup
    public let assetName: String
    public let frameWidth: Double
    public let frameHeight: Double
    public let unlockConditionText: String
    public let foodChainNote: String

    public init(
        kind: CritterKind,
        name: String,
        biome: TerrariumBiome,
        cost: Int,
        group: FoodChainGroup,
        assetName: String,
        frameWidth: Double,
        frameHeight: Double,
        unlockConditionText: String,
        foodChainNote: String
    ) {
        self.kind = kind
        self.name = name
        self.biome = biome
        self.cost = cost
        self.group = group
        self.assetName = assetName
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.unlockConditionText = unlockConditionText
        self.foodChainNote = foodChainNote
    }
}

public enum CritterResidency: String, Codable, Equatable {
    case visitor   // 兼容旧存档过渡态
    case resident  // 当前在生态箱内活跃展示
    case stored    // 已购买但因食物链互斥或手动切换而暂存于生物仓
    case hidden    // 必需生态位摆件被收起时暂隐
}

public struct CritterPersistentState: Codable, Equatable {
    public let kind: CritterKind
    public var residency: CritterResidency
    public var mealsEaten: Int
    public var hunger: Double // 0.0 (饱) ~ 100.0 (极饿)
    public var coord: GridCoord
    public var nickname: String?
    public var affinity: Int
    public var personality: String
    public var lastPettedAt: Date?
    public var dailyPetCount: Int
    public var dailyPetDateKey: String?
    public var lastFedRewardAt: Date?

    private enum CodingKeys: String, CodingKey {
        case kind, residency, mealsEaten, hunger, coord, nickname, affinity, personality
        case lastPettedAt, dailyPetCount, dailyPetDateKey, lastFedRewardAt
    }

    public init(
        kind: CritterKind,
        residency: CritterResidency = .visitor,
        mealsEaten: Int = 0,
        hunger: Double = 40.0,
        coord: GridCoord,
        nickname: String? = nil,
        affinity: Int = 0,
        personality: String? = nil,
        lastPettedAt: Date? = nil,
        dailyPetCount: Int = 0,
        dailyPetDateKey: String? = nil,
        lastFedRewardAt: Date? = nil
    ) {
        self.kind = kind
        self.residency = residency
        self.mealsEaten = mealsEaten
        self.hunger = hunger
        self.coord = coord
        self.nickname = nickname
        self.affinity = min(TerrariumConfig.maxAffinity, max(0, affinity))
        self.personality = personality ?? TerrariumConfig.defaultPersonality(for: kind)
        self.lastPettedAt = lastPettedAt
        self.dailyPetCount = dailyPetCount
        self.dailyPetDateKey = dailyPetDateKey
        self.lastFedRewardAt = lastFedRewardAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(CritterKind.self, forKey: .kind)
        self.kind = kind
        self.residency = try c.decode(CritterResidency.self, forKey: .residency)
        self.mealsEaten = try c.decode(Int.self, forKey: .mealsEaten)
        self.hunger = try c.decode(Double.self, forKey: .hunger)
        self.coord = try c.decode(GridCoord.self, forKey: .coord)
        self.nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
        let rawAffinity = try c.decodeIfPresent(Int.self, forKey: .affinity) ?? 0
        self.affinity = min(TerrariumConfig.maxAffinity, max(0, rawAffinity))
        self.personality = try c.decodeIfPresent(String.self, forKey: .personality) ?? TerrariumConfig.defaultPersonality(for: kind)
        self.lastPettedAt = try c.decodeIfPresent(Date.self, forKey: .lastPettedAt)
        self.dailyPetCount = try c.decodeIfPresent(Int.self, forKey: .dailyPetCount) ?? 0
        self.dailyPetDateKey = try c.decodeIfPresent(String.self, forKey: .dailyPetDateKey)
        self.lastFedRewardAt = try c.decodeIfPresent(Date.self, forKey: .lastFedRewardAt)
    }
}

public struct DecorItem: Identifiable, Codable, Equatable {
    public let id: String
    public let name: String
    public let assetName: String
    public let biome: TerrariumBiome
    public let cost: Int
    public let nicheDescription: String
    public var unlocked: Bool
    public var enabled: Bool

    public init(
        id: String,
        name: String,
        assetName: String,
        biome: TerrariumBiome,
        cost: Int,
        nicheDescription: String,
        unlocked: Bool,
        enabled: Bool
    ) {
        self.id = id
        self.name = name
        self.assetName = assetName
        self.biome = biome
        self.cost = cost
        self.nicheDescription = nicheDescription
        self.unlocked = unlocked
        self.enabled = enabled
    }
}

public struct CodexEntry: Identifiable, Codable, Equatable {
    public let id: String
    public let name: String
    public let biome: TerrariumBiome
    public let category: String
    public let condition: String
    public let desc: String
    public var unlocked: Bool

    public init(id: String, name: String, biome: TerrariumBiome, category: String, condition: String, desc: String, unlocked: Bool) {
        self.id = id
        self.name = name
        self.biome = biome
        self.category = category
        self.condition = condition
        self.desc = desc
        self.unlocked = unlocked
    }
}

public struct WeatherEventDefinition: Equatable {
    public let id: String
    public let title: String
    public let effectText: String
    public let atmosphere: SceneAtmosphere
    public let tempDelta: Int
    public let humidityDelta: Int
}

/// 单个独立生态缸的完整状态（多缸彻底隔离，各自挂机演化）
public struct TerrariumInstanceState: Codable, Equatable {
    public var biome: TerrariumBiome
    public var atmosphere: SceneAtmosphere
    public var temperature: Int
    public var humidity: Int
    public var isSleeping: Bool
    public var foodBowlPortions: Int
    public var glassFogLevel: Double
    public var mistDewBoostSeconds: TimeInterval
    public var plants: [PlantInstance]
    public var critters: [CritterPersistentState]
    public var unlockedDecorIDs: [String]
    public var enabledDecorIDs: [String]
    public var decorOrigins: [String: GridCoord]
    public var thermalMode: ThermalMode
    public var hasHeatLamp: Bool
    public var hasCoolingFan: Bool
    public var nextWeatherEventAt: Date
    public var weatherCooldownEndAt: Date
    public var accumulatedEcoSeconds: TimeInterval
    public var accumulatedHumidityDecaySeconds: TimeInterval
    public var ambientRelaxSeconds: TimeInterval
    public var plantPulseSeconds: TimeInterval
    public var hasTriggeredColdStart: Bool

    private enum CodingKeys: String, CodingKey {
        case biome, atmosphere, temperature, humidity, isSleeping, foodBowlPortions
        case glassFogLevel, mistDewBoostSeconds, plants, critters
        case unlockedDecorIDs, enabledDecorIDs, decorOrigins, thermalMode, hasHeatLamp, hasCoolingFan
        case nextWeatherEventAt, weatherCooldownEndAt
        case accumulatedEcoSeconds, accumulatedHumidityDecaySeconds
        case ambientRelaxSeconds, plantPulseSeconds, hasTriggeredColdStart
    }

    public init(
        biome: TerrariumBiome,
        atmosphere: SceneAtmosphere,
        temperature: Int,
        humidity: Int,
        isSleeping: Bool,
        foodBowlPortions: Int,
        glassFogLevel: Double,
        mistDewBoostSeconds: TimeInterval,
        plants: [PlantInstance],
        critters: [CritterPersistentState],
        unlockedDecorIDs: [String],
        enabledDecorIDs: [String],
        decorOrigins: [String: GridCoord] = [:],
        thermalMode: ThermalMode = .natural,
        hasHeatLamp: Bool = false,
        hasCoolingFan: Bool = false,
        nextWeatherEventAt: Date,
        weatherCooldownEndAt: Date,
        accumulatedEcoSeconds: TimeInterval,
        accumulatedHumidityDecaySeconds: TimeInterval,
        ambientRelaxSeconds: TimeInterval,
        plantPulseSeconds: TimeInterval,
        hasTriggeredColdStart: Bool = false
    ) {
        self.biome = biome
        self.atmosphere = atmosphere
        self.temperature = temperature
        self.humidity = humidity
        self.isSleeping = isSleeping
        self.foodBowlPortions = foodBowlPortions
        self.glassFogLevel = glassFogLevel
        self.mistDewBoostSeconds = mistDewBoostSeconds
        self.plants = plants
        self.critters = critters
        self.unlockedDecorIDs = unlockedDecorIDs
        self.enabledDecorIDs = enabledDecorIDs
        self.decorOrigins = decorOrigins
        self.thermalMode = thermalMode
        self.hasHeatLamp = hasHeatLamp
        self.hasCoolingFan = hasCoolingFan
        self.nextWeatherEventAt = nextWeatherEventAt
        self.weatherCooldownEndAt = weatherCooldownEndAt
        self.accumulatedEcoSeconds = accumulatedEcoSeconds
        self.accumulatedHumidityDecaySeconds = accumulatedHumidityDecaySeconds
        self.ambientRelaxSeconds = ambientRelaxSeconds
        self.plantPulseSeconds = plantPulseSeconds
        self.hasTriggeredColdStart = hasTriggeredColdStart
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.biome = try c.decode(TerrariumBiome.self, forKey: .biome)
        self.atmosphere = try c.decode(SceneAtmosphere.self, forKey: .atmosphere)
        self.temperature = try c.decode(Int.self, forKey: .temperature)
        self.humidity = try c.decode(Int.self, forKey: .humidity)
        self.isSleeping = try c.decode(Bool.self, forKey: .isSleeping)
        self.foodBowlPortions = try c.decode(Int.self, forKey: .foodBowlPortions)
        self.glassFogLevel = try c.decode(Double.self, forKey: .glassFogLevel)
        self.mistDewBoostSeconds = try c.decode(TimeInterval.self, forKey: .mistDewBoostSeconds)
        let decodedPlants = try c.decode([PlantInstance].self, forKey: .plants)
        self.plants = decodedPlants
        self.critters = try c.decode([CritterPersistentState].self, forKey: .critters)
        self.unlockedDecorIDs = try c.decode([String].self, forKey: .unlockedDecorIDs)
        self.enabledDecorIDs = try c.decode([String].self, forKey: .enabledDecorIDs)
        self.decorOrigins = try c.decodeIfPresent([String: GridCoord].self, forKey: .decorOrigins) ?? [:]
        self.thermalMode = try c.decodeIfPresent(ThermalMode.self, forKey: .thermalMode) ?? .natural
        self.hasHeatLamp = try c.decodeIfPresent(Bool.self, forKey: .hasHeatLamp) ?? false
        self.hasCoolingFan = try c.decodeIfPresent(Bool.self, forKey: .hasCoolingFan) ?? false
        self.nextWeatherEventAt = try c.decode(Date.self, forKey: .nextWeatherEventAt)
        self.weatherCooldownEndAt = try c.decode(Date.self, forKey: .weatherCooldownEndAt)
        self.accumulatedEcoSeconds = try c.decode(TimeInterval.self, forKey: .accumulatedEcoSeconds)
        self.accumulatedHumidityDecaySeconds = try c.decode(TimeInterval.self, forKey: .accumulatedHumidityDecaySeconds)
        self.ambientRelaxSeconds = try c.decode(TimeInterval.self, forKey: .ambientRelaxSeconds)
        self.plantPulseSeconds = try c.decode(TimeInterval.self, forKey: .plantPulseSeconds)
        self.hasTriggeredColdStart = try c.decodeIfPresent(Bool.self, forKey: .hasTriggeredColdStart) ?? !decodedPlants.isEmpty
    }

    public static func empty(biome: TerrariumBiome, now: Date = Date(), nextEventDelay: TimeInterval = 1500) -> TerrariumInstanceState {
        let initialTemp: Int
        let initialHumidity: Int
        let initialAtm: SceneAtmosphere
        switch biome {
        case .meadow:
            initialTemp = 22; initialHumidity = 35; initialAtm = .day
        case .sand:
            initialTemp = 27; initialHumidity = 28; initialAtm = .warm
        case .rainforest:
            initialTemp = 25; initialHumidity = 65; initialAtm = .day
        case .aquatic:
            initialTemp = 24; initialHumidity = 60; initialAtm = .day
        }
        return TerrariumInstanceState(
            biome: biome,
            atmosphere: initialAtm,
            temperature: initialTemp,
            humidity: initialHumidity,
            isSleeping: false,
            foodBowlPortions: 0,
            glassFogLevel: 0.0,
            mistDewBoostSeconds: 0,
            plants: [],
            critters: [],
            unlockedDecorIDs: [],
            enabledDecorIDs: [],
            decorOrigins: [:],
            thermalMode: .natural,
            hasHeatLamp: false,
            hasCoolingFan: false,
            nextWeatherEventAt: now.addingTimeInterval(nextEventDelay),
            weatherCooldownEndAt: .distantPast,
            accumulatedEcoSeconds: 0,
            accumulatedHumidityDecaySeconds: 0,
            ambientRelaxSeconds: 0,
            plantPulseSeconds: 0
        )
    }
}

/// 独立可购置生态缸容器（支持同种生态多缸共存、独立命名与购入价值记录用于退点拆缸）
public struct TerrariumContainer: Identifiable, Codable, Equatable {
    public let id: UUID
    public var customName: String
    public var purchasedCost: Int
    public var createdAt: Date
    public var instance: TerrariumInstanceState

    private enum CodingKeys: String, CodingKey {
        case id, customName, purchasedCost, createdAt, instance
    }

    public init(id: UUID = UUID(), customName: String, purchasedCost: Int = 0, createdAt: Date = Date(), instance: TerrariumInstanceState) {
        self.id = id
        self.customName = customName
        self.purchasedCost = purchasedCost
        self.createdAt = createdAt
        self.instance = instance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.customName = try c.decode(String.self, forKey: .customName)
        self.purchasedCost = try c.decodeIfPresent(Int.self, forKey: .purchasedCost) ?? 0
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.instance = try c.decode(TerrariumInstanceState.self, forKey: .instance)
    }
}

/// 组合式成就与收集称号定义
public struct AchievementDefinition: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let category: String
    public let conditionDesc: String
    public let rewardPoints: Int

    public init(id: String, title: String, category: String, conditionDesc: String, rewardPoints: Int) {
        self.id = id
        self.title = title
        self.category = category
        self.conditionDesc = conditionDesc
        self.rewardPoints = rewardPoints
    }
}

/// 全局持久化存档容器（schemaVersion = 5：多实例自由购置容器 + 共享点数与图鉴 + 边框皮肤 + 成就称号，无损兼容 v1~v4）
public struct TerrariumSaveData: Codable, Equatable {
    public var schemaVersion: Int
    public var containers: [TerrariumContainer]
    public var activeContainerID: UUID
    public var ecoPoints: Int
    public var unlockedCodexIDs: [String]
    public var lastSavedAt: Date
    public var lastKnownLocalTempC: Int?
    public var lastKnownLocalCity: String?
    public var unlockedFrameSkinIDs: [String]
    public var activeFrameSkinID: String
    public var unlockedAchievementIDs: [String]
    public var equippedTitleID: String?
    public var firstStartedAt: Date

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, containers, activeContainerID, ecoPoints, unlockedCodexIDs, lastSavedAt
        case lastKnownLocalTempC, lastKnownLocalCity
        case unlockedFrameSkinIDs, activeFrameSkinID
        case unlockedAchievementIDs, equippedTitleID, firstStartedAt
        // v3 兼容迁移键
        case currentBiome, unlockedBiomes, terrariums
    }

    public init(
        schemaVersion: Int = 5,
        containers: [TerrariumContainer]? = nil,
        activeContainerID: UUID? = nil,
        ecoPoints: Int = 5,
        unlockedCodexIDs: [String] = [],
        lastSavedAt: Date = Date(),
        lastKnownLocalTempC: Int? = nil,
        lastKnownLocalCity: String? = nil,
        unlockedFrameSkinIDs: [String] = [TankFrameSkin.classic.rawValue],
        activeFrameSkinID: String = TankFrameSkin.classic.rawValue,
        unlockedAchievementIDs: [String] = [],
        equippedTitleID: String? = nil,
        firstStartedAt: Date? = nil
    ) {
        let start = firstStartedAt ?? lastSavedAt
        let defaultMeadowName = TerrariumL10n.t("tank.default_name", ["biome": TerrariumBiome.meadow.localizedShortName, "index": "1"])
        let initialContainers = containers ?? [
            TerrariumContainer(
                customName: defaultMeadowName,
                createdAt: start,
                instance: TerrariumInstanceState.empty(biome: .meadow, now: lastSavedAt)
            )
        ]
        self.schemaVersion = schemaVersion
        self.containers = initialContainers
        self.activeContainerID = activeContainerID ?? initialContainers[0].id
        self.ecoPoints = ecoPoints
        self.unlockedCodexIDs = unlockedCodexIDs
        self.lastSavedAt = lastSavedAt
        self.lastKnownLocalTempC = lastKnownLocalTempC
        self.lastKnownLocalCity = lastKnownLocalCity
        self.unlockedFrameSkinIDs = unlockedFrameSkinIDs
        self.activeFrameSkinID = activeFrameSkinID
        self.unlockedAchievementIDs = unlockedAchievementIDs
        self.equippedTitleID = equippedTitleID
        self.firstStartedAt = start
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(containers, forKey: .containers)
        try c.encode(activeContainerID, forKey: .activeContainerID)
        try c.encode(ecoPoints, forKey: .ecoPoints)
        try c.encode(unlockedCodexIDs, forKey: .unlockedCodexIDs)
        try c.encode(lastSavedAt, forKey: .lastSavedAt)
        try c.encodeIfPresent(lastKnownLocalTempC, forKey: .lastKnownLocalTempC)
        try c.encodeIfPresent(lastKnownLocalCity, forKey: .lastKnownLocalCity)
        try c.encode(unlockedFrameSkinIDs, forKey: .unlockedFrameSkinIDs)
        try c.encode(activeFrameSkinID, forKey: .activeFrameSkinID)
        try c.encode(unlockedAchievementIDs, forKey: .unlockedAchievementIDs)
        try c.encodeIfPresent(equippedTitleID, forKey: .equippedTitleID)
        try c.encode(firstStartedAt, forKey: .firstStartedAt)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date()
        let decodedVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1

        if decodedVersion >= 4,
           let list = try c.decodeIfPresent([TerrariumContainer].self, forKey: .containers),
           !list.isEmpty {
            self.schemaVersion = 5
            self.containers = list
            let activeID = try c.decodeIfPresent(UUID.self, forKey: .activeContainerID)
            self.activeContainerID = list.contains(where: { $0.id == activeID }) ? activeID! : list[0].id
            self.ecoPoints = try c.decodeIfPresent(Int.self, forKey: .ecoPoints) ?? 2
            self.unlockedCodexIDs = try c.decodeIfPresent([String].self, forKey: .unlockedCodexIDs) ?? []
            let savedAt = try c.decodeIfPresent(Date.self, forKey: .lastSavedAt) ?? now
            self.lastSavedAt = savedAt
            self.lastKnownLocalTempC = try c.decodeIfPresent(Int.self, forKey: .lastKnownLocalTempC)
            self.lastKnownLocalCity = try c.decodeIfPresent(String.self, forKey: .lastKnownLocalCity)
            self.unlockedFrameSkinIDs = try c.decodeIfPresent([String].self, forKey: .unlockedFrameSkinIDs) ?? [TankFrameSkin.classic.rawValue]
            self.activeFrameSkinID = try c.decodeIfPresent(String.self, forKey: .activeFrameSkinID) ?? TankFrameSkin.classic.rawValue
            self.unlockedAchievementIDs = try c.decodeIfPresent([String].self, forKey: .unlockedAchievementIDs) ?? []
            self.equippedTitleID = try c.decodeIfPresent(String.self, forKey: .equippedTitleID)
            self.firstStartedAt = try c.decodeIfPresent(Date.self, forKey: .firstStartedAt) ?? savedAt
        } else if decodedVersion == 3,
                  let map = try c.decodeIfPresent([String: TerrariumInstanceState].self, forKey: .terrariums) {
            let curBiome = try c.decodeIfPresent(TerrariumBiome.self, forKey: .currentBiome) ?? .meadow
            let unlocked = try c.decodeIfPresent([TerrariumBiome].self, forKey: .unlockedBiomes) ?? [.meadow]
            var migrated: [TerrariumContainer] = []
            var pickedActive: UUID?
            for b in unlocked {
                if let inst = map[b.rawValue] {
                    let item = TerrariumContainer(customName: TerrariumL10n.t("tank.default_name", ["biome": b.localizedShortName, "index": "1"]), createdAt: now, instance: inst)
                    if b == curBiome { pickedActive = item.id }
                    migrated.append(item)
                }
            }
            if migrated.isEmpty {
                let first = TerrariumContainer(customName: TerrariumL10n.t("tank.default_name", ["biome": TerrariumBiome.meadow.localizedShortName, "index": "1"]), createdAt: now, instance: TerrariumInstanceState.empty(biome: .meadow, now: now))
                migrated = [first]
                pickedActive = first.id
            }
            self.schemaVersion = 5
            self.containers = migrated
            self.activeContainerID = pickedActive ?? migrated[0].id
            self.ecoPoints = try c.decodeIfPresent(Int.self, forKey: .ecoPoints) ?? 2
            self.unlockedCodexIDs = try c.decodeIfPresent([String].self, forKey: .unlockedCodexIDs) ?? []
            let savedAt = try c.decodeIfPresent(Date.self, forKey: .lastSavedAt) ?? now
            self.lastSavedAt = savedAt
            self.unlockedFrameSkinIDs = [TankFrameSkin.classic.rawValue]
            self.activeFrameSkinID = TankFrameSkin.classic.rawValue
            self.unlockedAchievementIDs = []
            self.equippedTitleID = nil
            self.firstStartedAt = savedAt
        } else {
            let legacyPoints = try c.decodeIfPresent(Int.self, forKey: .ecoPoints) ?? 2
            let first = TerrariumContainer(customName: TerrariumL10n.t("tank.default_name", ["biome": TerrariumBiome.meadow.localizedShortName, "index": "1"]), createdAt: now, instance: TerrariumInstanceState.empty(biome: .meadow, now: now))
            self.schemaVersion = 5
            self.containers = [first]
            self.activeContainerID = first.id
            self.ecoPoints = max(2, legacyPoints)
            self.unlockedCodexIDs = []
            self.lastSavedAt = now
            self.unlockedFrameSkinIDs = [TankFrameSkin.classic.rawValue]
            self.activeFrameSkinID = TankFrameSkin.classic.rawValue
            self.unlockedAchievementIDs = []
            self.equippedTitleID = nil
            self.firstStartedAt = now
        }
    }
}
