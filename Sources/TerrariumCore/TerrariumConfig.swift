import CoreGraphics
import Foundation

/// 数据驱动核心配置：集中管理 2:1 等距投影、分缸摆件池、舒缓挂机参数与多物种演化规则
public enum TerrariumConfig {
    // MARK: - 2:1 等距网格投影规格 (224x176 逻辑像素)
    public static let stageLogicalWidth: Double = 224.0
    public static let stageLogicalHeight: Double = 176.0
    public static let gridCols: Int = 11
    public static let gridRows: Int = 11
    public static let isoOriginX: Double = 112.0
    public static let isoOriginY: Double = 62.0
    public static let tileHalfW: Double = 8.0
    public static let tileHalfH: Double = 4.0
    /// 碧波鱼缸水面精确逻辑高度（对应 tank_water_overlay 水面顶点偏移）
    public static let waterSurfaceGZ: Double = 38.0

    public static func isoToScreen(gx: Double, gy: Double, gz: Double = 0.0) -> CGPoint {
        CGPoint(
            x: isoOriginX + (gx - gy) * tileHalfW,
            y: isoOriginY + (gx + gy) * tileHalfH - gz
        )
    }

    public static func screenToIso(x: Double, y: Double, gz: Double = 0.0) -> (gx: Double, gy: Double) {
        let dx = (x - isoOriginX) / tileHalfW
        let dy = ((y + gz) - isoOriginY) / tileHalfH
        return (0.5 * (dx + dy), 0.5 * (dy - dx))
    }

    public static func plantSurfaceGZ(for plant: PlantInstance) -> Double {
        plant.speciesID == "lotus" ? waterSurfaceGZ : 0.0
    }

    // MARK: - 固定食盆与分缸摆件 Footprint
    /// 陆生食盆固定于沙盘最前端视觉中心 (9,9) -> screen (112, 138)；鱼缸悬浮喂食圈固定于后壁水域 (1,2) -> 水面 screen (104, 40)
    public static let foodBowlCoord = GridCoord(col: 9, row: 9)
    public static let aquaticFeedingCoord = GridCoord(col: 1, row: 2)
    public static let maxFoodPortions: Int = 5

    public static func feedingCoord(for biome: TerrariumBiome) -> GridCoord {
        (biome == .aquatic) ? aquaticFeedingCoord : foodBowlCoord
    }

    public static func feedingProtectedCoords(for biome: TerrariumBiome) -> Set<GridCoord> {
        // 鱼缸喂食圈漂浮在后方水面 gz=38，仅保护 (1,2) 不种浮水睡莲，彻底释放前景 (9,9)..(10,10) 6格供造景
        (biome == .aquatic) ? [aquaticFeedingCoord] : foodBowlProtectedCoords
    }

    /// 食盆本体、后方进食槽位及正前方三格净空保护（严禁植物/摆件遮挡）
    public static let foodBowlProtectedCoords: Set<GridCoord> = [
        GridCoord(col: 9, row: 9),
        GridCoord(col: 8, row: 9),
        GridCoord(col: 9, row: 8),
        GridCoord(col: 9, row: 10),
        GridCoord(col: 10, row: 9),
        GridCoord(col: 10, row: 10)
    ]

    /// 食盆正前方三格（动物进食和闲逛停驻时应优先避开，确保食盆始终处于视觉最前沿）
    public static let foodBowlForwardCoords: Set<GridCoord> = [
        GridCoord(col: 9, row: 10),
        GridCoord(col: 10, row: 9),
        GridCoord(col: 10, row: 10)
    ]

    public static func decorDimensions(for decorID: String) -> (cols: Int, rows: Int) {
        switch decorID {
        case "driftwood", "sand_wood", "rainforest_vine", "aquatic_driftwood": return (3, 2)
        case "shallow_pool", "sand_rock", "boulder", "rainforest_waterfall", "rainforest_bark", "aquatic_bubble_rock", "aquatic_castle": return (2, 2)
        case "sand_pebbles", "meadow_stepping_stones", "sand_rib_arch", "rainforest_slate_ledge", "aquatic_seiryu_stone": return (2, 1)
        default: return (1, 1)
        }
    }

    public static func defaultDecorOrigin(for decorID: String) -> GridCoord {
        switch decorID {
        case "shallow_pool", "sand_rock", "rainforest_waterfall", "aquatic_bubble_rock": return GridCoord(col: 8, row: 1)
        case "driftwood", "sand_wood", "rainforest_vine", "aquatic_driftwood": return GridCoord(col: 2, row: 3)
        case "boulder", "rainforest_bark", "aquatic_castle": return GridCoord(col: 1, row: 7)
        case "sand_pebbles": return GridCoord(col: 8, row: 7)
        case "meadow_stepping_stones", "sand_rib_arch", "rainforest_slate_ledge", "aquatic_seiryu_stone": return GridCoord(col: 5, row: 2)
        case "meadow_mushroom_log", "sand_cairn", "rainforest_bromeliad_stump", "aquatic_bamboo_tube": return GridCoord(col: 4, row: 7)
        default: return GridCoord(col: 5, row: 5)
        }
    }

    public static func effectiveDecorOrigin(for decorID: String, decorOrigins: [String: GridCoord] = [:]) -> GridCoord {
        decorOrigins[decorID] ?? defaultDecorOrigin(for: decorID)
    }

    public static func footprint(for decorID: String, decorOrigins: [String: GridCoord] = [:]) -> [GridCoord] {
        let dims = decorDimensions(for: decorID)
        let origin = effectiveDecorOrigin(for: decorID, decorOrigins: decorOrigins)
        var coords: [GridCoord] = []
        for r in origin.row..<(origin.row + dims.rows) {
            for c in origin.col..<(origin.col + dims.cols) {
                coords.append(GridCoord(col: c, row: r))
            }
        }
        return coords
    }

    public static func decorBlocksMovement(_ decorID: String) -> Bool {
        // 浅水洼、卵石滩、汀步石与风蚀拱允许动物涉水/踩踏/穿过，不死堵路径
        decorID != "shallow_pool"
            && decorID != "sand_pebbles"
            && decorID != "meadow_stepping_stones"
            && decorID != "sand_rib_arch"
    }

    public static func anchorGridPos(for decorID: String, decorOrigins: [String: GridCoord] = [:]) -> (gx: Double, gy: Double) {
        let dims = decorDimensions(for: decorID)
        let origin = effectiveDecorOrigin(for: decorID, decorOrigins: decorOrigins)
        return (
            gx: Double(origin.col) + Double(dims.cols) * 0.5,
            gy: Double(origin.row) + Double(dims.rows) * 0.5
        )
    }

    // MARK: - 舒缓挂机参数（告别高频操作）
    public static let tempRange: ClosedRange<Int> = 10...35
    public static let humidityRange: ClosedRange<Int> = 20...98
    public static let humiditySafeFloor: Int = 25

    public static let optimalTempRange: ClosedRange<Int> = 20...26
    public static let optimalHumidityRange: ClosedRange<Int> = 55...75

    public static func optimalTempRange(for biome: TerrariumBiome) -> ClosedRange<Int> {
        switch biome {
        case .meadow: return optimalTempRange
        case .sand: return 24...32
        case .rainforest: return 23...29
        case .aquatic: return 22...28
        }
    }

    public static func optimalHumidityRange(for biome: TerrariumBiome) -> ClosedRange<Int> {
        switch biome {
        case .meadow: return optimalHumidityRange
        case .sand: return 25...50
        case .rainforest: return 65...88
        case .aquatic: return 60...98
        }
    }
    public static let ecoPointMinHumidity: Int = 35
    public static let sandEcoPointMinHumidity: Int = 26

    /// 基础自然蒸发 rate = 5.0%/h（每 12 分钟才降 1%，保湿满时约 2~4 小时无需频繁加水）
    public static let baseEvaporationPerHour: Double = 5.0

    public static let dewLightHumidityThreshold: Int = 72
    public static let dewHeavyHumidityThreshold: Int = 85

    public static let maxPlantsCap: Int = 12
    public static let coldStartPlantPulseSeconds: TimeInterval = 15.0
    public static let plantPulseIntervalSeconds: TimeInterval = 600.0
    public static let plantMatureSeconds: TimeInterval = 300.0
    public static let plantWiltThresholdSeconds: TimeInterval = 7200.0
    public static let plantWitherThresholdSeconds: TimeInterval = 14400.0

    public static let backgroundTickSeconds: TimeInterval = 30.0
    public static let ambientTempRelaxIntervalSeconds: TimeInterval = 1800.0
    public static let localTempTrackingIntervalSeconds: TimeInterval = 600.0
    public static let glassFogAccumulationSeconds: TimeInterval = 2700.0
    public static let aquaticAlgaeAccumulationSeconds: TimeInterval = 7200.0
    public static let ecoPointBaseIntervalSeconds: TimeInterval = 1200.0
    public static let ecoPointOptimalIntervalSeconds: TimeInterval = 720.0
    public static let offlineFullRateSeconds: TimeInterval = 4.0 * 3600.0
    public static let maxOfflineSettlementSeconds: TimeInterval = 8.0 * 3600.0
    public static let weatherEventIntervalRange: ClosedRange<TimeInterval> = 1200.0...2400.0
    public static let weatherEventDurationSeconds: TimeInterval = 900.0

    public static let codexUnlockBonusPoints: Int = 3
    public static let maxTankSlots: Int = 9
    public static let sandBiomeUnlockCost: Int = 35
    public static let heatLampCost: Int = 8
    public static let coolingFanCost: Int = 8
    public static let tankRefundRatio: Double = 0.75

    // 五阶好感度羁绊与防刷节流参数（0 轻抚直发点）
    public static let maxAffinity: Int = 100
    public static let petAffinityCooldownSeconds: TimeInterval = 1200.0 // 20 分钟/只
    public static let maxDailyEffectivePets: Int = 6
    public static let startleRecoverySeconds: TimeInterval = 60.0
    public static let mealRewardCooldownSeconds: TimeInterval = 10800.0 // 3 小时/只进食奖励冷却

    public static func baseTankPurchaseCost(for biome: TerrariumBiome) -> Int {
        switch biome {
        case .meadow: return 25
        case .sand: return 35
        case .rainforest: return 45
        case .aquatic: return 55
        }
    }

    /// 槽位阶梯定价：第 2 口缸起原价，之后每新增 1 口 +15 点防晚期通胀
    public static func tankPurchaseCost(for biome: TerrariumBiome, existingTankCount: Int = 1) -> Int {
        let extraIndex = max(0, existingTankCount - 1)
        return baseTankPurchaseCost(for: biome) + extraIndex * 15
    }

    /// 多缸产点递减系数（单缸 100%、2缸 80%、3缸 65%、4缸 55%、5缸起 50%）
    public static func tankEfficiencyMultiplier(slotIndex: Int) -> Double {
        switch slotIndex {
        case 0: return 1.00
        case 1: return 0.80
        case 2: return 0.65
        case 3: return 0.55
        default: return 0.50
        }
    }

    /// 统一分级图鉴奖励：植物 +2、基础动物 +3、稀有/高阶动物 +5
    public static func codexRewardPoints(for entryID: String) -> Int {
        switch entryID {
        case "moss", "clover", "fern", "glow_shroom", "red_shroom", "sundew",
             "succulent", "aloe", "cactus", "lithops", "agave",
             "monstera", "bromeliad", "orchid", "pitcher_plant", "calathea",
             "marimo", "anubias", "lotus", "vallisneria", "red_ludwigia":
            return 2
        case "rhino_beetle", "tree_frog", "fire_newt", "firefly", "moon_moth", "dragonfly", "luna_cicada",
             "sand_gecko", "scarab", "sand_scorpion", "horned_toad", "antlion_lacewing",
             "hercules_beetle", "chameleon", "dart_frog", "blue_morpho", "red_eyed_frog", "orchid_bee",
             "betta_fish", "crayfish", "crystal_shrimp":
            return 5
        default:
            return 3
        }
    }

    public static func hungerRatePerHour(for kind: CritterKind) -> Double {
        switch kind {
        case .snail, .pillBug, .rhinoBeetle, .leafInsect, .cherryShrimp, .corydoras, .ladybug, .otoCatfish: return 5.0
        case .treeFrog, .fireNewt, .dartFrog, .redEyedFrog, .amberBeetle, .herculesBeetle, .neonTetra, .desertMantis, .blueMorpho, .crystalShrimp: return 6.0
        case .sandGecko, .sandScorpion, .hornedToad, .scarab, .chameleon, .bettaFish, .crayfish: return 7.0
        }
    }

    public static func mealsRequiredToSettle(kind: CritterKind, enabledDecorIDs: [String]) -> Int {
        switch kind {
        case .snail: return enabledDecorIDs.contains("driftwood") ? 1 : 2
        case .pillBug, .ladybug, .amberBeetle, .scarab, .rhinoBeetle, .leafInsect, .herculesBeetle, .cherryShrimp, .neonTetra, .corydoras, .otoCatfish, .crystalShrimp: return 1
        case .treeFrog, .fireNewt, .sandGecko, .sandScorpion, .desertMantis, .hornedToad, .chameleon, .dartFrog, .blueMorpho, .redEyedFrog, .bettaFish, .crayfish: return 2
        }
    }

    public static func foodChainGroup(for kind: CritterKind) -> FoodChainGroup {
        switch kind {
        case .snail, .pillBug, .rhinoBeetle, .ladybug: return .meadowInsects
        case .treeFrog, .fireNewt: return .meadowPredator
        case .amberBeetle, .scarab, .desertMantis: return .sandBeetles
        case .sandGecko, .sandScorpion, .hornedToad: return .sandPredator
        case .leafInsect, .herculesBeetle, .blueMorpho: return .rainforestInsects
        case .chameleon, .dartFrog, .redEyedFrog: return .rainforestPredator
        case .cherryShrimp, .neonTetra, .corydoras, .otoCatfish, .crystalShrimp: return .aquaticPeaceful
        case .bettaFish: return .aquaticBetta
        case .crayfish: return .aquaticPredator
        }
    }

    public static func codexMilestoneTitle(unlockedCount: Int) -> String {
        switch unlockedCount {
        case 52...: return "🏆 全生态宗师"
        case 42...: return "🌟 微境守望者"
        case 33...: return "🌿 博物学家"
        case 20...: return "🪴 箱庭园丁"
        case 10...: return "🌱 生态学徒"
        default: return "🔍 探索萌新"
        }
    }

    public enum AffinityStage: Int, Comparable {
        case acquaintance = 1 // 0~9
        case familiar = 2     // 10~29
        case close = 3        // 30~59
        case trusted = 4      // 60~99
        case soulmate = 5     // 100

        public static func < (lhs: AffinityStage, rhs: AffinityStage) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public var title: String {
            switch self {
            case .acquaintance: return "Lv.1 初识"
            case .familiar: return "Lv.2 熟稔"
            case .close: return "Lv.3 亲近"
            case .trusted: return "Lv.4 信赖"
            case .soulmate: return "Lv.5 挚友"
            }
        }
    }

    public enum PersonalityPerkKind {
        case thrifty   // 慢消化：-10% / -20% 饥饿消耗
        case energetic // 共振加速：+5% / +10% 挂机产点速率
        case charming  // 灵动陪伴：-10% 饥饿 + 满级 +5% 产点
    }

    public static func affinityStage(for affinity: Int) -> AffinityStage {
        let clamped = min(maxAffinity, max(0, affinity))
        if clamped >= 100 { return .soulmate }
        if clamped >= 60 { return .trusted }
        if clamped >= 30 { return .close }
        if clamped >= 10 { return .familiar }
        return .acquaintance
    }

    public static func personalityPerk(for personality: String) -> PersonalityPerkKind {
        switch personality {
        case "慢性子", "害羞团", "静如叶", "守沙者":
            return .thrifty
        case "护木侠", "勤劳钳", "角力士", "缸霸", "追光手":
            return .energetic
        default:
            return .charming
        }
    }

    public static func perkDescription(for personality: String, stage: AffinityStage) -> String {
        let kind = personalityPerk(for: personality)
        switch (kind, stage) {
        case (_, .acquaintance): return "亲近中(满10解锁栖息偏好)"
        case (_, .familiar): return "Lv.2 常栖专属摆件旁"
        case (.thrifty, .close), (.thrifty, .trusted): return "Lv.3 细嚼慢咽(饥饿 -10%)"
        case (.thrifty, .soulmate): return "Lv.5 极省食量(饥饿 -20%)"
        case (.energetic, .close), (.energetic, .trusted): return "Lv.3 生态共振(产点 +5%)"
        case (.energetic, .soulmate): return "Lv.5 旺生共鸣(产点 +10%)"
        case (.charming, .close), (.charming, .trusted): return "Lv.3 温顺亲人(饥饿 -10%)"
        case (.charming, .soulmate): return "Lv.5 心灵共鸣(饥饿-10%·产点+5%)"
        }
    }

    public static func petReplyText(nickname: String, stage: AffinityStage) -> String {
        switch stage {
        case .acquaintance: return "💕 轻轻摸了摸「\(nickname)」· 正在慢慢熟悉你"
        case .familiar: return "💕 「\(nickname)」蹭了蹭指尖 · 更喜欢靠在专属摆件旁休息啦"
        case .close: return "💕 「\(nickname)」惬意晃着小身子 · 已激活【性格特技 I】"
        case .trusted: return "💕 「\(nickname)」完全信任你，即使连点也不容易受惊啦"
        case .soulmate: return "💛 挚友「\(nickname)」亮起金色心意！已满级激活【性格特技 II】"
        }
    }

    public static func areCompatibleInSameTank(_ lhs: CritterKind, _ rhs: CritterKind) -> Bool {
        foodChainGroup(for: lhs) == foodChainGroup(for: rhs)
    }

    public static func critterShopCatalog(for biome: TerrariumBiome) -> [CritterShopSpec] {
        switch biome {
        case .meadow:
            return [
                CritterShopSpec(
                    kind: .snail,
                    name: "露珠蜗牛",
                    biome: .meadow,
                    cost: 6,
                    group: .meadowInsects,
                    assetName: "char_snail_sheet",
                    frameWidth: 17,
                    frameHeight: 14,
                    unlockConditionText: "苔藓≥1 + 湿度≥45%",
                    foodChainNote: "微虫螺共生群 · 与树蛙互斥"
                ),
                CritterShopSpec(
                    kind: .pillBug,
                    name: "迷你西瓜虫",
                    biome: .meadow,
                    cost: 9,
                    group: .meadowInsects,
                    assetName: "char_pillbug_sheet",
                    frameWidth: 14,
                    frameHeight: 10,
                    unlockConditionText: "腐殖沉木 + 苔藓≥1",
                    foodChainNote: "微虫螺共生群 · 与树蛙互斥"
                ),
                CritterShopSpec(
                    kind: .rhinoBeetle,
                    name: "栗壳独角仙",
                    biome: .meadow,
                    cost: 14,
                    group: .meadowInsects,
                    assetName: "char_rhino_beetle_sheet",
                    frameWidth: 20,
                    frameHeight: 16,
                    unlockConditionText: "腐殖沉木 + 卷叶蕨≥1 + 湿度≥55%",
                    foodChainNote: "微虫螺共生群 · 与树蛙互斥"
                ),
                CritterShopSpec(
                    kind: .treeFrog,
                    name: "绿豆树蛙",
                    biome: .meadow,
                    cost: 18,
                    group: .meadowPredator,
                    assetName: "char_frog_sheet",
                    frameWidth: 24,
                    frameHeight: 22,
                    unlockConditionText: "溪石浅水洼 + 卷叶蕨≥1 + 湿度≥55%",
                    foodChainNote: "两栖捕食者 · 不可与虫螺同缸"
                ),
                CritterShopSpec(
                    kind: .fireNewt,
                    name: "红腹小蝾螈",
                    biome: .meadow,
                    cost: 22,
                    group: .meadowPredator,
                    assetName: "char_fire_newt_sheet",
                    frameWidth: 22,
                    frameHeight: 16,
                    unlockConditionText: "溪涧汀步石 + 浅水洼 + ≤21°C + 湿度≥68%",
                    foodChainNote: "两栖捕食者 · 可与树蛙同栖，互斥虫螺"
                ),
                CritterShopSpec(
                    kind: .ladybug,
                    name: "七星瓢虫",
                    biome: .meadow,
                    cost: 8,
                    group: .meadowInsects,
                    assetName: "char_ladybug_sheet",
                    frameWidth: 14,
                    frameHeight: 11,
                    unlockConditionText: "幸运三叶草≥1 + 湿度≥50%",
                    foodChainNote: "微虫螺共生群 · 与树蛙互斥"
                )
            ]
        case .sand:
            return [
                CritterShopSpec(
                    kind: .amberBeetle,
                    name: "琥珀甲虫",
                    biome: .sand,
                    cost: 10,
                    group: .sandBeetles,
                    assetName: "char_beetle_sheet",
                    frameWidth: 18,
                    frameHeight: 14,
                    unlockConditionText: "暖阳卵石滩 + 多肉≥1",
                    foodChainNote: "沙漠甲虫共生群 · 与守宫互斥"
                ),
                CritterShopSpec(
                    kind: .scarab,
                    name: "琉璃圣甲虫",
                    biome: .sand,
                    cost: 26,
                    group: .sandBeetles,
                    assetName: "char_scarab_sheet",
                    frameWidth: 18,
                    frameHeight: 14,
                    unlockConditionText: "仙人球≥1 + 芦荟≥1 + 暖干(≥27°C, ≤42%)",
                    foodChainNote: "沙漠甲虫共生群 · 与守宫互斥"
                ),
                CritterShopSpec(
                    kind: .sandGecko,
                    name: "豹纹沙守宫",
                    biome: .sand,
                    cost: 18,
                    group: .sandPredator,
                    assetName: "char_gecko_sheet",
                    frameWidth: 28,
                    frameHeight: 18,
                    unlockConditionText: "风蚀红砂岩 + 沙地植物≥2 + ≥24°C",
                    foodChainNote: "沙地捕食者 · 不可与甲虫同缸"
                ),
                CritterShopSpec(
                    kind: .sandScorpion,
                    name: "黄金沙蝎",
                    biome: .sand,
                    cost: 24,
                    group: .sandPredator,
                    assetName: "char_sand_scorpion_sheet",
                    frameWidth: 22,
                    frameHeight: 16,
                    unlockConditionText: "沙漠叠石堆 + 风蚀拱 + 仙人球≥1 + ≥26°C",
                    foodChainNote: "沙地捕食者 · 不可与甲虫同缸"
                ),
                CritterShopSpec(
                    kind: .desertMantis,
                    name: "沙漠枯叶螳",
                    biome: .sand,
                    cost: 16,
                    group: .sandBeetles,
                    assetName: "char_desert_mantis_sheet",
                    frameWidth: 22,
                    frameHeight: 16,
                    unlockConditionText: "白化沙木枝 + 龙舌兰≥1 + ≥24°C",
                    foodChainNote: "沙漠甲虫共生群 · 与守宫/沙蝎互斥"
                ),
                CritterShopSpec(
                    kind: .hornedToad,
                    name: "沙漠角蜥",
                    biome: .sand,
                    cost: 28,
                    group: .sandPredator,
                    assetName: "char_horned_toad_sheet",
                    frameWidth: 28,
                    frameHeight: 18,
                    unlockConditionText: "叠石堆 + 红砂岩 + 仙人球≥1 + ≥27°C",
                    foodChainNote: "沙地大型爬宠 · 不可与甲虫同缸"
                )
            ]
        case .rainforest:
            return [
                CritterShopSpec(
                    kind: .leafInsect,
                    name: "枯叶拟态脩",
                    biome: .rainforest,
                    cost: 12,
                    group: .rainforestInsects,
                    assetName: "char_leaf_insect_sheet",
                    frameWidth: 18,
                    frameHeight: 16,
                    unlockConditionText: "朽木树洞 + 龟背竹≥1 + 湿度≥65%",
                    foodChainNote: "雨林拟态虫群 · 与变色龙互斥"
                ),
                CritterShopSpec(
                    kind: .herculesBeetle,
                    name: "长戟大兜虫",
                    biome: .rainforest,
                    cost: 22,
                    group: .rainforestInsects,
                    assetName: "char_hercules_sheet",
                    frameWidth: 22,
                    frameHeight: 16,
                    unlockConditionText: "朽木树洞 + 热带兰花≥1 + ≥24°C",
                    foodChainNote: "雨林拟态虫群 · 与变色龙互斥"
                ),
                CritterShopSpec(
                    kind: .chameleon,
                    name: "七彩高冠变色龙",
                    biome: .rainforest,
                    cost: 32,
                    group: .rainforestPredator,
                    assetName: "char_chameleon_green",
                    frameWidth: 26,
                    frameHeight: 20,
                    unlockConditionText: "藤蔓攀爬架 + 龟背竹/凤梨≥2 + ≥25°C + 湿度≥70%",
                    foodChainNote: "树栖捕食者（随环境动态变色）· 互斥虫群"
                ),
                CritterShopSpec(
                    kind: .dartFrog,
                    name: "蓝宝石箭毒蛙",
                    biome: .rainforest,
                    cost: 24,
                    group: .rainforestPredator,
                    assetName: "char_dart_frog_sheet",
                    frameWidth: 20,
                    frameHeight: 18,
                    unlockConditionText: "积水凤梨朽桩 + 积水凤梨≥1 + 湿度≥72%",
                    foodChainNote: "林下捕食者 · 可与变色龙共存，互斥虫群"
                ),
                CritterShopSpec(
                    kind: .blueMorpho,
                    name: "蓝闪蝶",
                    biome: .rainforest,
                    cost: 18,
                    group: .rainforestInsects,
                    assetName: "char_blue_morpho_sheet",
                    frameWidth: 22,
                    frameHeight: 18,
                    unlockConditionText: "热带兰花≥1 + 猪笼草≥1 + 湿度≥70%",
                    foodChainNote: "雨林拟态虫群 · 与变色龙/毒蛙互斥"
                ),
                CritterShopSpec(
                    kind: .redEyedFrog,
                    name: "红眼树蛙",
                    biome: .rainforest,
                    cost: 26,
                    group: .rainforestPredator,
                    assetName: "char_red_eyed_frog_sheet",
                    frameWidth: 20,
                    frameHeight: 18,
                    unlockConditionText: "雾化小瀑布石 + 孔雀竹芋≥1 + 湿度≥75%",
                    foodChainNote: "树栖捕食者 · 互斥虫群"
                )
            ]
        case .aquatic:
            return [
                CritterShopSpec(
                    kind: .cherryShrimp,
                    name: "樱花米虾",
                    biome: .aquatic,
                    cost: 10,
                    group: .aquaticPeaceful,
                    assetName: "char_shrimp_sheet",
                    frameWidth: 14,
                    frameHeight: 11,
                    unlockConditionText: "陶瓷躲避屋 + 莫斯藻球≥1",
                    foodChainNote: "温顺鱼虾共生群 · 与斗鱼/蓝螯虾互斥"
                ),
                CritterShopSpec(
                    kind: .neonTetra,
                    name: "红绿灯鱼群",
                    biome: .aquatic,
                    cost: 16,
                    group: .aquaticPeaceful,
                    assetName: "char_tetra_sheet",
                    frameWidth: 14,
                    frameHeight: 10,
                    unlockConditionText: "皇冠水草≥1 + 溶氧≥65%（5尾成群）",
                    foodChainNote: "中层群游观赏鱼 · 与斗鱼/蓝螯虾互斥"
                ),
                CritterShopSpec(
                    kind: .bettaFish,
                    name: "半月斗鱼",
                    biome: .aquatic,
                    cost: 25,
                    group: .aquaticBetta,
                    assetName: "char_betta_sheet",
                    frameWidth: 30,
                    frameHeight: 22,
                    unlockConditionText: "迷你睡莲≥1 + 水温≥24°C + 溶氧≥72%",
                    foodChainNote: "好斗领地观赏鱼 · 需单缸独养（不混养）"
                ),
                CritterShopSpec(
                    kind: .crayfish,
                    name: "天空蓝螯虾",
                    biome: .aquatic,
                    cost: 30,
                    group: .aquaticPredator,
                    assetName: "char_crayfish_sheet",
                    frameWidth: 24,
                    frameHeight: 16,
                    unlockConditionText: "冒泡火山石 + 躲避屋 + 水草≥1",
                    foodChainNote: "水底掠食领地 · 不可与鱼虾/斗鱼同缸"
                ),
                CritterShopSpec(
                    kind: .corydoras,
                    name: "熊猫鼠鱼",
                    biome: .aquatic,
                    cost: 14,
                    group: .aquaticPeaceful,
                    assetName: "char_corydoras_sheet",
                    frameWidth: 16,
                    frameHeight: 12,
                    unlockConditionText: "莫斯竹筒屋 + 沉木水草石 + 溶氧≥60%",
                    foodChainNote: "温顺底栖清道夫 · 可与米虾/灯鱼混养"
                ),
                CritterShopSpec(
                    kind: .otoCatfish,
                    name: "小精灵吸盘鱼",
                    biome: .aquatic,
                    cost: 12,
                    group: .aquaticPeaceful,
                    assetName: "char_oto_catfish_sheet",
                    frameWidth: 16,
                    frameHeight: 12,
                    unlockConditionText: "青龙造景石组 + 螺旋苦草≥1 + 溶氧≥65%",
                    foodChainNote: "温顺除藻鱼 · 可与鱼虾混养"
                ),
                CritterShopSpec(
                    kind: .crystalShrimp,
                    name: "水晶红虾",
                    biome: .aquatic,
                    cost: 20,
                    group: .aquaticPeaceful,
                    assetName: "char_crystal_shrimp_sheet",
                    frameWidth: 14,
                    frameHeight: 11,
                    unlockConditionText: "莫斯竹筒屋 + 红蝴蝶水草≥1 + 溶氧≥72%",
                    foodChainNote: "高阶红白观赏虾 · 与斗鱼/螯虾互斥"
                )
            ]
        }
    }

    // MARK: - 空中专属物种条件（不参与地面寻路与食物链）
    public static func isFireflyCondition(biome: TerrariumBiome, atmosphere: SceneAtmosphere, humidity: Int, plants: [PlantInstance], enabledDecorIDs: [String]) -> Bool {
        guard biome == .meadow else { return false }
        let hasFlora = plants.contains { $0.speciesID == "clover" || $0.speciesID == "fern" }
        return (atmosphere == .night || atmosphere == .rain)
            && humidity >= 65
            && hasFlora
            && enabledDecorIDs.contains("driftwood")
    }

    public static func isMoonMothCondition(biome: TerrariumBiome, atmosphere: SceneAtmosphere, humidity: Int, plants: [PlantInstance]) -> Bool {
        guard biome == .meadow else { return false }
        // 高阶专属动物：必须拥有特殊植物「微光菇」+ 夜晚 + 高湿
        let hasGlowShroom = plants.contains { $0.speciesID == "glow_shroom" && $0.stage != .withered }
        return hasGlowShroom && atmosphere == .night && humidity >= 72
    }

    public static func isDragonflyCondition(biome: TerrariumBiome, atmosphere: SceneAtmosphere, humidity: Int, plants: [PlantInstance], enabledDecorIDs: [String]) -> Bool {
        guard biome == .meadow || biome == .aquatic else { return false }
        let hasWaterAnchor = enabledDecorIDs.contains("shallow_pool") || plants.contains { $0.speciesID == "lotus" && $0.stage != .withered }
        return (atmosphere == .day || atmosphere == .warm) && humidity >= 68 && hasWaterAnchor
    }

    public static func isLunaCicadaCondition(biome: TerrariumBiome, atmosphere: SceneAtmosphere, temperature: Int, plants: [PlantInstance], enabledDecorIDs: [String]) -> Bool {
        guard biome == .rainforest else { return false }
        let hasMonstera = plants.contains { $0.speciesID == "monstera" && $0.stage != .withered }
        return atmosphere == .night && temperature >= 26 && enabledDecorIDs.contains("rainforest_vine") && hasMonstera
    }

    public static func isAntlionLacewingCondition(biome: TerrariumBiome, atmosphere: SceneAtmosphere, temperature: Int, humidity: Int, plants: [PlantInstance], enabledDecorIDs: [String]) -> Bool {
        guard biome == .sand else { return false }
        let hasSandRock = enabledDecorIDs.contains("sand_cairn") || enabledDecorIDs.contains("sand_rib_arch")
        let hasMatureFlora = plants.contains { $0.stage == .mature || $0.stage == .lushDew }
        return (atmosphere == .day || atmosphere == .warm) && temperature >= 26 && humidity <= 48 && hasSandRock && hasMatureFlora
    }

    public static func isOrchidBeeCondition(biome: TerrariumBiome, atmosphere: SceneAtmosphere, humidity: Int, plants: [PlantInstance]) -> Bool {
        guard biome == .rainforest else { return false }
        let hasFlowerAnchor = plants.contains {
            ($0.speciesID == "orchid" || $0.speciesID == "pitcher_plant") && $0.stage != .withered
        }
        return (atmosphere == .day || atmosphere == .warm) && humidity >= 72 && hasFlowerAnchor
    }

    public static func isGlowShroomCondition(temperature: Int, humidity: Int, enabledDecorIDs: [String]) -> Bool {
        let effectiveTemp = enabledDecorIDs.contains("boulder") ? (temperature - 1) : temperature
        return effectiveTemp <= 19 && humidity >= 75
    }

    public static func thermalTempOffset(for mode: ThermalMode) -> Int {
        switch mode {
        case .natural: return 0
        case .heating: return 6
        case .cooling: return -4
        }
    }

    public static func ambientTempRelaxIntervalSeconds(for mode: ThermalMode, localOutdoorTempC: Int? = nil) -> TimeInterval {
        if mode != .natural { return 180.0 }
        return (localOutdoorTempC != nil) ? localTempTrackingIntervalSeconds : ambientTempRelaxIntervalSeconds
    }

    /// 本地实际气温 + 室内微缓冲映射，并保障夹缸加热/降温设备在极端季节仍可触及物种解锁温度门槛
    public static func baseAmbientTemp(
        for atmosphere: SceneAtmosphere,
        biome: TerrariumBiome,
        thermalMode: ThermalMode = .natural,
        localOutdoorTempC: Int? = nil
    ) -> Int {
        let natural: Int
        if let outdoor = localOutdoorTempC {
            let roomTemp: Int
            if outdoor < 16 {
                roomTemp = max(12, outdoor + min(6, (18 - outdoor) / 2))
            } else if outdoor > 29 {
                roomTemp = min(33, outdoor - min(4, (outdoor - 28) / 2))
            } else {
                roomTemp = outdoor
            }
            switch biome {
            case .sand:
                natural = roomTemp + ((atmosphere == .night) ? 0 : 2)
            case .rainforest:
                natural = roomTemp + 1
            case .aquatic, .meadow:
                natural = roomTemp
            }
        } else {
            switch biome {
            case .sand:
                natural = (atmosphere == .night) ? 21 : 28
            case .rainforest:
                natural = (atmosphere == .night) ? 22 : 26
            case .aquatic:
                natural = 24
            case .meadow:
                switch atmosphere {
                case .night: natural = 19
                case .warm: natural = 27
                case .day, .rain: natural = 22
                }
            }
        }

        let target: Int
        switch thermalMode {
        case .natural:
            target = natural
        case .heating:
            let heatingFloor: Int = {
                switch biome {
                case .sand: return 28
                case .rainforest: return 26
                case .aquatic, .meadow: return 25
                }
            }()
            target = max(natural + thermalTempOffset(for: .heating), heatingFloor)
        case .cooling:
            let coolingCeiling: Int = {
                switch biome {
                case .meadow: return 18
                case .aquatic: return 22
                case .rainforest: return 23
                case .sand: return 24
                }
            }()
            target = min(natural + thermalTempOffset(for: .cooling), coolingCeiling)
        }
        return min(tempRange.upperBound, max(tempRange.lowerBound, target))
    }

    public static func ambientAtmosphere(for date: Date, biome: TerrariumBiome) -> SceneAtmosphere {
        let hour = Calendar.current.component(.hour, from: date)
        if hour >= 18 || hour < 6 {
            return .night
        }
        return (biome == .sand) ? .warm : .day
    }

    // MARK: - 随机小气候事件池
    public static let weatherEvents: [WeatherEventDefinition] = [
        WeatherEventDefinition(
            id: "cool_rain",
            title: "林间小雨",
            effectText: "湿度上升、降温，叶片更容易凝结露珠！",
            atmosphere: .rain,
            tempDelta: -4,
            humidityDelta: 18
        ),
        WeatherEventDefinition(
            id: "warm_sun",
            title: "暖阳斜照",
            effectText: "阳光温暖微燥，喜阳植物活力提升！",
            atmosphere: .warm,
            tempDelta: 4,
            humidityDelta: -10
        ),
        WeatherEventDefinition(
            id: "cool_night",
            title: "深夜微凉",
            effectText: "夜色降临，微凉空气适合夜间昆虫出没！",
            atmosphere: .night,
            tempDelta: -3,
            humidityDelta: 6
        ),
        WeatherEventDefinition(
            id: "morning_dew",
            title: "晨露微风",
            effectText: "空气清新温润，生态箱进入舒适挂机态。",
            atmosphere: .day,
            tempDelta: -1,
            humidityDelta: 8
        )
    ]

    // MARK: - 分生态缸专属摆件目录
    public static func decorCatalog(for biome: TerrariumBiome) -> [DecorItem] {
        switch biome {
        case .meadow:
            return [
                DecorItem(
                    id: "driftwood",
                    name: "腐殖沉木桩",
                    assetName: "env_driftwood",
                    biome: .meadow,
                    cost: 6,
                    nicheDescription: "苔藓/蕨类萌发+50% · 吸引西瓜虫 · 萤火虫信标",
                    unlocked: false,
                    enabled: false
                ),
                DecorItem(
                    id: "shallow_pool",
                    name: "溪石浅水洼",
                    assetName: "env_shallow_pool",
                    biome: .meadow,
                    cost: 10,
                    nicheDescription: "被动保湿 -20% 蒸发 · 绿豆树蛙定居必需",
                    unlocked: false,
                    enabled: false
                ),
                DecorItem(
                    id: "boulder",
                    name: "覆苔阴凉青石",
                    assetName: "env_boulder",
                    biome: .meadow,
                    cost: 12,
                    nicheDescription: "局部降温 -1°C · 助推微光菇与月光飞蛾",
                    unlocked: false,
                    enabled: false
                ),
                DecorItem(
                    id: "meadow_mushroom_log",
                    name: "菌丝小木墩",
                    assetName: "env_meadow_mushroom_log",
                    biome: .meadow,
                    cost: 8,
                    nicheDescription: "微光菇萌发+40% · 丰富森林底层生态",
                    unlocked: false,
                    enabled: false
                ),
                DecorItem(
                    id: "meadow_stepping_stones",
                    name: "溪涧汀步石",
                    assetName: "env_meadow_stepping_stones",
                    biome: .meadow,
                    cost: 7,
                    nicheDescription: "可行走装饰不堵路 · 提升小动物巡逻质感",
                    unlocked: false,
                    enabled: false
                )
            ]
        case .sand:
            return [
                DecorItem(
                    id: "sand_pebbles",
                    name: "暖阳卵石滩",
                    assetName: "env_pebbles",
                    biome: .sand,
                    cost: 6,
                    nicheDescription: "可行走晒背点 · 琥珀甲虫定居必需",
                    unlocked: false,
                    enabled: false
                ),
                DecorItem(
                    id: "sand_rock",
                    name: "风蚀红砂岩",
                    assetName: "env_sand_rock",
                    biome: .sand,
                    cost: 10,
                    nicheDescription: "昼夜庇护所 · 豹纹沙守宫定居必需",
                    unlocked: false,
                    enabled: false
                ),
                DecorItem(
                    id: "sand_wood",
                    name: "白化沙木枝",
                    assetName: "env_sand_wood",
                    biome: .sand,
                    cost: 12,
                    nicheDescription: "荒漠植物萌发+50% · 助推芦荟与仙人球",
                    unlocked: false,
                    enabled: false
                ),
                DecorItem(
                    id: "sand_cairn",
                    name: "沙漠叠石堆",
                    assetName: "env_sand_cairn",
                    biome: .sand,
                    cost: 8,
                    nicheDescription: "荒漠路标石堆 · 营造沙丘高低落差",
                    unlocked: false,
                    enabled: false
                ),
                DecorItem(
                    id: "sand_rib_arch",
                    name: "枯木风蚀拱",
                    assetName: "env_sand_rib_arch",
                    biome: .sand,
                    cost: 11,
                    nicheDescription: "可穿过遮阴拱门 · 沙地植物萌发+25%",
                    unlocked: false,
                    enabled: false
                )
            ]
        case .rainforest:
            return [
                DecorItem(
                    id: "rainforest_vine",
                    name: "热带藤蔓攀爬架",
                    assetName: "env_rainforest_vine",
                    biome: .rainforest,
                    cost: 10,
                    nicheDescription: "变色龙必配栖架 · 雨林植物萌发+50%",
                    unlocked: false,
                    enabled: false
                ),
                DecorItem(
                    id: "rainforest_waterfall",
                    name: "雾化小瀑布石",
                    assetName: "env_rainforest_waterfall",
                    biome: .rainforest,
                    cost: 14,
                    nicheDescription: "流动瀑布 · 被动保湿 -25% 蒸发",
                    unlocked: false,
                    enabled: false
                ),
                DecorItem(
                    id: "rainforest_bark",
                    name: "雨林朽木树洞",
                    assetName: "env_rainforest_bark",
                    biome: .rainforest,
                    cost: 9,
                    nicheDescription: "枯叶脩与长戟大兜虫必配隐蔽所",
                    unlocked: false,
                    enabled: false
                ),
                DecorItem(
                    id: "rainforest_bromeliad_stump",
                    name: "积水凤梨朽桩",
                    assetName: "env_rainforest_bromeliad_stump",
                    biome: .rainforest,
                    cost: 9,
                    nicheDescription: "树洞蓄水 · 被动保湿 -10% 蒸发",
                    unlocked: false,
                    enabled: false
                ),
                DecorItem(
                    id: "rainforest_slate_ledge",
                    name: "苔藓阶梯岩",
                    assetName: "env_rainforest_slate_ledge",
                    biome: .rainforest,
                    cost: 11,
                    nicheDescription: "阶梯层岩 · 雨林植物萌发+30%",
                    unlocked: false,
                    enabled: false
                )
            ]
        case .aquatic:
            return [
                DecorItem(
                    id: "aquatic_bubble_rock",
                    name: "冒泡火山石",
                    assetName: "env_aquatic_bubble_rock",
                    biome: .aquatic,
                    cost: 14,
                    nicheDescription: "持续冒泡充氧 · 被动稳住溶氧 -30% 衰减",
                    unlocked: false,
                    enabled: false
                ),
                DecorItem(
                    id: "aquatic_driftwood",
                    name: "沉木水草石",
                    assetName: "env_aquatic_driftwood",
                    biome: .aquatic,
                    cost: 10,
                    nicheDescription: "附着小水榕 · 水草萌发速度 +50%",
                    unlocked: false,
                    enabled: false
                ),
                DecorItem(
                    id: "aquatic_castle",
                    name: "陶瓷躲避屋",
                    assetName: "env_aquatic_castle",
                    biome: .aquatic,
                    cost: 9,
                    nicheDescription: "虾蟹脱壳藏身洞 · 米虾与蓝螯虾必需",
                    unlocked: false,
                    enabled: false
                ),
                DecorItem(
                    id: "aquatic_seiryu_stone",
                    name: "青龙造景石组",
                    assetName: "env_aquatic_seiryu_stone",
                    biome: .aquatic,
                    cost: 10,
                    nicheDescription: "稳住水体清澈 · 减缓缸壁藻垢滋生 -20%",
                    unlocked: false,
                    enabled: false
                ),
                DecorItem(
                    id: "aquatic_bamboo_tube",
                    name: "莫斯竹筒屋",
                    assetName: "env_aquatic_bamboo_tube",
                    biome: .aquatic,
                    cost: 8,
                    nicheDescription: "水草萌发+20% · 虾鱼穿梭微缩隧道",
                    unlocked: false,
                    enabled: false
                )
            ]
        }
    }

    // MARK: - 全局生态图鉴（共 50 项）
    public static func defaultCodexEntries() -> [CodexEntry] {
        [
            // 苔原缸植物 (6)
            CodexEntry(id: "moss", name: "绒球苔藓", biome: .meadow, category: "植物", condition: "苔原湿润(≥45%)", desc: "第一抹绿色生机，高湿时叶尖凝结露珠。", unlocked: false),
            CodexEntry(id: "clover", name: "幸运三叶草", biome: .meadow, category: "植物", condition: "苔藓≥1 + 湿度≥68%", desc: "圆润翠绿的贴地草丛，常吸引夜虫停栖。", unlocked: false),
            CodexEntry(id: "fern", name: "卷叶蕨", biome: .meadow, category: "植物", condition: "苔藓≥2 + 湿度≥62%", desc: "优雅的羽状林冠植物，为树蛙提供阴凉。", unlocked: false),
            CodexEntry(id: "glow_shroom", name: "微光菇", biome: .meadow, category: "稀有植物", condition: "阴凉(≤19°C) + 高湿(≥75%)", desc: "散发冷青柔光的珍稀菌类，是月光飞蛾的最爱。", unlocked: false),
            CodexEntry(id: "red_shroom", name: "绯红伞菌", biome: .meadow, category: "植物", condition: "苔藓≥1 + 湿度≥60%", desc: "点缀着白色斑点的森林小红伞菌。", unlocked: false),
            CodexEntry(id: "sundew", name: "茅膏菜", biome: .meadow, category: "稀有植物", condition: "卷叶蕨≥1 + 浅水洼 + 湿度≥72%", desc: "叶缘晶莹红尖腺毛常挂满露珠的迷你食虫草。", unlocked: false),
            // 苔原缸动物 (8)
            CodexEntry(id: "snail", name: "露珠蜗牛", biome: .meadow, category: "动物", condition: "苔藓≥1 + 湿润(≥45%)", desc: "温和的慢行小软体动物，不可与树蛙同缸。", unlocked: false),
            CodexEntry(id: "pill_bug", name: "迷你西瓜虫", biome: .meadow, category: "动物", condition: "腐殖沉木 + 苔藓≥1", desc: "圆滚滚的小小分解者，轻触连点会缩成小球。", unlocked: false),
            CodexEntry(id: "ladybug", name: "七星瓢虫", biome: .meadow, category: "动物", condition: "三叶草≥1 + 湿度≥50%", desc: "鲜红背甲点缀七颗黑星的小小护叶使者。", unlocked: false),
            CodexEntry(id: "rhino_beetle", name: "栗壳独角仙", biome: .meadow, category: "动物", condition: "腐殖沉木 + 卷叶蕨≥1 + 湿度≥55%", desc: "顶着优雅 Y 型大角的温顺大型甲虫，喜栖沉木旁。", unlocked: false),
            CodexEntry(id: "tree_frog", name: "绿豆树蛙", biome: .meadow, category: "动物", condition: "溪石浅水洼 + 卷叶蕨≥1 + 湿度≥55%", desc: "鼓着高凸大眼的林间捕食者，需独立单养不可混放虫螺。", unlocked: false),
            CodexEntry(id: "fire_newt", name: "红腹小蝾螈", biome: .meadow, category: "稀有动物", condition: "汀步石 + 浅水洼 + ≤21°C + 湿度≥68%", desc: "黑背朱腹的冷溪两栖小精灵，偏爱清凉湿润的苔原石滩。", unlocked: false),
            CodexEntry(id: "firefly", name: "微光萤火虫", biome: .meadow, category: "稀有动物", condition: "腐殖沉木 + 幸运草/蕨 + 夜/雨高湿", desc: "伴随夜风在草叶上空翩翩起舞的微光。", unlocked: false),
            CodexEntry(id: "moon_moth", name: "月光小飞蛾", biome: .meadow, category: "专属高阶", condition: "微光菇≥1 + 夜晚 + 高湿(≥72%)", desc: "仅被发光蘑菇吸引入驻的梦幻夜行精灵。", unlocked: false),
            CodexEntry(id: "dragonfly", name: "碧蓝蜻蜓", biome: .meadow, category: "专属高阶", condition: "日/暖阳 + 浅水洼/睡莲 + 湿度≥68%", desc: "薄翼透亮的晴空巡游精灵，点水而过。", unlocked: false),
            // 沙地缸植物 & 动物 (10)
            CodexEntry(id: "succulent", name: "莲座多肉", biome: .sand, category: "沙地植物", condition: "沙地缸(湿度≤55%)", desc: "饱满耐旱的沙漠莲座，在暖阳下独自绽放。", unlocked: false),
            CodexEntry(id: "aloe", name: "星点芦荟", biome: .sand, category: "沙地植物", condition: "多肉≥1 + 湿度28~55%", desc: "厚实多汁的荒漠植物，叶缘带着淡淡星斑。", unlocked: false),
            CodexEntry(id: "cactus", name: "金琥仙人球", biome: .sand, category: "稀有植物", condition: "多肉≥1 + 温暖(≥25°C) + 干燥(≤50%)", desc: "圆润金刺仙人球，高成熟度会开出明黄小花。", unlocked: false),
            CodexEntry(id: "lithops", name: "生石花", biome: .sand, category: "沙地植物", condition: "多肉≥1 + 干燥(≤45%)", desc: "伪装成圆润鹅卵石的拟态多肉，花期会绽放黄白小花。", unlocked: false),
            CodexEntry(id: "agave", name: "蓝叶龙舌兰", biome: .sand, category: "稀有植物", condition: "芦荟≥1 + 温暖(≥25°C)", desc: "剑状放射的蓝绿厚叶荒漠霸主。", unlocked: false),
            CodexEntry(id: "amber_beetle", name: "琥珀甲虫", biome: .sand, category: "沙地动物", condition: "暖阳卵石滩 + 多肉≥1", desc: "喜欢在暖阳卵石旁活动、爬去食盆的小甲虫。", unlocked: false),
            CodexEntry(id: "desert_mantis", name: "沙漠枯叶螳", biome: .sand, category: "沙地动物", condition: "白化沙木枝 + 龙舌兰≥1 + ≥24°C", desc: "高举双镰刀随风轻晃的沙漠伪装高手。", unlocked: false),
            CodexEntry(id: "sand_gecko", name: "豹纹沙守宫", biome: .sand, category: "沙地动物", condition: "风蚀红砂岩 + 沙地植物≥2 + ≥24°C", desc: "拖着斑点小尾巴在沙地上慢跑的萌宠守宫。", unlocked: false),
            CodexEntry(id: "scarab", name: "琉璃圣甲虫", biome: .sand, category: "专属高阶", condition: "仙人球≥1 + 芦荟≥1 + 暖干(≥27°C, ≤42%)", desc: "只在仙人球与芦荟共存的暖阳荒漠中现身的宝石甲虫。", unlocked: false),
            CodexEntry(id: "sand_scorpion", name: "黄金沙蝎", biome: .sand, category: "专属高阶", condition: "叠石堆 + 风蚀拱 + 仙人球≥1 + ≥26°C", desc: "高举双钳与金黄尾刺在红砂间巡逻的沙漠守卫。", unlocked: false),
            CodexEntry(id: "horned_toad", name: "沙漠角蜥", biome: .sand, category: "专属高阶", condition: "叠石堆 + 红砂岩 + 仙人球≥1 + ≥27°C", desc: "头顶双角、身披棘甲的霸气荒漠大爬宠。", unlocked: false),
            CodexEntry(id: "antlion_lacewing", name: "砂金蚁狮蛉", biome: .sand, category: "专属高阶", condition: "日/暖阳 + 叠石/风蚀拱 + 成熟植物 + ≥26°C且干燥", desc: "闪烁琥珀金光、拖着细长棒状触角的沙漠飞蛉。", unlocked: false),
            // 雨林缸植物 & 动物 (12)
            CodexEntry(id: "monstera", name: "龟背竹", biome: .rainforest, category: "雨林植物", condition: "热带雨林缸 + 湿度≥60%", desc: "标志性裂孔阔叶植物，是变色龙最喜欢的翠绿伪装屏障。", unlocked: false),
            CodexEntry(id: "bromeliad", name: "积水凤梨", biome: .rainforest, category: "雨林植物", condition: "龟背竹≥1 + 湿度≥72%", desc: "中心叶杯常蓄积甘露的艳红热带凤梨。", unlocked: false),
            CodexEntry(id: "orchid", name: "热带兰花", biome: .rainforest, category: "稀有植物", condition: "龟背竹≥1 + 温暖(≥24°C) + 湿度≥75%", desc: "幽香娇艳的紫金树冠兰花，吸引大兜虫栖息。", unlocked: false),
            CodexEntry(id: "pitcher_plant", name: "猪笼草", biome: .rainforest, category: "稀有植物", condition: "龟背竹≥1 + 湿度≥74%", desc: "垂挂着红润捕虫笼的热带奇特藤本。", unlocked: false),
            CodexEntry(id: "calathea", name: "孔雀竹芋", biome: .rainforest, category: "雨林植物", condition: "积水凤梨≥1 + 湿度≥68%", desc: "叶片带有银绿羽状纹路的阴生雨林植物。", unlocked: false),
            CodexEntry(id: "leaf_insect", name: "枯叶拟态脩", biome: .rainforest, category: "雨林动物", condition: "朽木树洞 + 龟背竹≥1 + 湿度≥65%", desc: "脉络如真实叶片般精致，轻碰会随风轻晃。", unlocked: false),
            CodexEntry(id: "hercules_beetle", name: "长戟大兜虫", biome: .rainforest, category: "雨林动物", condition: "朽木树洞 + 热带兰花≥1 + ≥24°C", desc: "身披金甲、拥有标志性前后长戟大角的力量之王。", unlocked: false),
            CodexEntry(id: "blue_morpho", name: "蓝闪蝶", biome: .rainforest, category: "稀有动物", condition: "兰花≥1 + 猪笼草≥1 + 湿度≥70%", desc: "双翼折射出金属电光蓝的雨林飞仙。", unlocked: false),
            CodexEntry(id: "chameleon", name: "七彩高冠变色龙", biome: .rainforest, category: "专属高阶", condition: "藤蔓架 + 雨林植被≥2 + ≥25°C + 湿度≥70%", desc: "会根据所处植物与藤蔓色彩实时拟态变色的雨林明星！", unlocked: false),
            CodexEntry(id: "dart_frog", name: "蓝宝石箭毒蛙", biome: .rainforest, category: "专属高阶", condition: "积水凤梨朽桩 + 积水凤梨≥1 + 湿度≥72%", desc: "闪烁宝石蓝警戒斑的雨林迷你精灵，最爱在凤梨叶下轻跃。", unlocked: false),
            CodexEntry(id: "red_eyed_frog", name: "红眼树蛙", biome: .rainforest, category: "专属高阶", condition: "小瀑布石 + 孔雀竹芋≥1 + 湿度≥75%", desc: "睁着宝石红大眼、橙色脚趾的经典雨林明星。", unlocked: false),
            CodexEntry(id: "luna_cicada", name: "翠光夏蝉", biome: .rainforest, category: "专属高阶", condition: "夜晚 + ≥26°C + 藤蔓架 + 龟背竹≥1", desc: "仅在盛夏闷热雨林夜晚轻鸣滑翔的翡翠灵虫。", unlocked: false),
            CodexEntry(id: "orchid_bee", name: "翡翠兰花蜂", biome: .rainforest, category: "专属高阶", condition: "日/暖阳 + 湿度≥72% + 热带兰花/猪笼草≥1", desc: "泛着金属翡翠光泽、专程飞来兰花丛采蜜的小精灵。", unlocked: false),
            // 碧波鱼缸植物 & 动物 (12)
            CodexEntry(id: "marimo", name: "莫斯藻球", biome: .aquatic, category: "水草", condition: "碧波鱼缸 + 溶氧≥55%", desc: "毛茸茸的圆球水藻，水底米虾的最爱。", unlocked: false),
            CodexEntry(id: "anubias", name: "皇冠水草", biome: .aquatic, category: "水草", condition: "莫斯藻球≥1 + 溶氧≥65%", desc: "苍翠阔叶水草，为红绿灯鱼提供穿行林影。", unlocked: false),
            CodexEntry(id: "lotus", name: "迷你水睡莲", biome: .aquatic, category: "稀有水草", condition: "莫斯藻球≥1 + ≥23°C + 溶氧≥72%", desc: "在水面绽放粉嫩小花的精致浮水植物。", unlocked: false),
            CodexEntry(id: "vallisneria", name: "螺旋苦草", biome: .aquatic, category: "水草", condition: "莫斯藻球≥1 + 溶氧≥60%", desc: "随水流轻柔摇曳的翠绿丝带后景草。", unlocked: false),
            CodexEntry(id: "red_ludwigia", name: "红蝴蝶水草", biome: .aquatic, category: "稀有水草", condition: "皇冠水草≥1 + ≥23°C + 溶氧≥70%", desc: "酒红色对生叶片在清澈水体中格外醒目。", unlocked: false),
            CodexEntry(id: "cherry_shrimp", name: "樱花米虾", biome: .aquatic, category: "水生生物", condition: "陶瓷躲避屋 + 莫斯藻球≥1", desc: "在河沙与藻球间忙碌拾藻、偶尔轻盈游水换草的通红小精灵。", unlocked: false),
            CodexEntry(id: "oto_catfish", name: "小精灵吸盘鱼", biome: .aquatic, category: "水生生物", condition: "青龙石组 + 螺旋苦草≥1 + 溶氧≥65%", desc: "带有贯穿黑侧带的勤劳除藻小鱼。", unlocked: false),
            CodexEntry(id: "crystal_shrimp", name: "水晶红虾", biome: .aquatic, category: "专属高阶", condition: "莫斯竹筒屋 + 红蝴蝶≥1 + 溶氧≥72%", desc: "红白节段分明、姿态优雅的高阶观赏虾。", unlocked: false),
            CodexEntry(id: "neon_tetra", name: "红绿灯鱼群", biome: .aquatic, category: "水生生物", condition: "皇冠水草≥1 + 溶氧≥65%", desc: "体侧闪烁着电光蓝与霓虹红、成群结队在中层游曳的观赏鱼。", unlocked: false),
            CodexEntry(id: "betta_fish", name: "半月斗鱼", biome: .aquatic, category: "专属高阶", condition: "水睡莲≥1 + 水温≥24°C + 溶氧≥72%", desc: "性格好斗需单独分缸，拖曳蓝红半月大尾鳍在睡莲下优雅巡游。", unlocked: false),
            CodexEntry(id: "crayfish", name: "天空蓝螯虾", biome: .aquatic, category: "水底霸主", condition: "冒泡火山石 + 躲避屋 + 水草≥1", desc: "威风凛凛的蓝甲螯虾，不可与小鱼、米虾或斗鱼混养。", unlocked: false),
            CodexEntry(id: "corydoras", name: "熊猫鼠鱼", biome: .aquatic, category: "水生生物", condition: "莫斯竹筒屋 + 沉木水草石 + 溶氧≥60%", desc: "戴着黑眼罩的可爱底栖鼠鱼，总爱用小胡须在河沙间翻找碎屑。", unlocked: false)
        ]
    }

    // MARK: - 生物个性、昵称与生态位停驻坐标
    public static func defaultNickname(for kind: CritterKind) -> String {
        switch kind {
        case .snail: return "蜗宝"
        case .pillBug: return "小团子"
        case .rhinoBeetle: return "独角侠"
        case .treeFrog: return "青瓜"
        case .fireNewt: return "小赤腹"
        case .ladybug: return "七星仔"
        case .amberBeetle: return "小琥珀"
        case .sandGecko: return "小橘"
        case .sandScorpion: return "金钳子"
        case .desertMantis: return "小镰刀"
        case .hornedToad: return "刺角王"
        case .scarab: return "琉璃星"
        case .leafInsect: return "青叶"
        case .herculesBeetle: return "大力神"
        case .chameleon: return "小七彩"
        case .dartFrog: return "小蓝莓"
        case .blueMorpho: return "蓝精灵"
        case .redEyedFrog: return "红眼仔"
        case .cherryShrimp: return "小红虾"
        case .neonTetra: return "霓虹豆"
        case .bettaFish: return "蓝绸"
        case .crayfish: return "蓝钳将"
        case .corydoras: return "小熊猫"
        case .otoCatfish: return "小吸盘"
        case .crystalShrimp: return "红水晶"
        }
    }

    public static func defaultPersonality(for kind: CritterKind) -> String {
        switch kind {
        case .snail: return "慢性子"
        case .pillBug: return "害羞团"
        case .rhinoBeetle: return "护木侠"
        case .treeFrog: return "爱戏水"
        case .fireNewt: return "喜阴凉"
        case .ladybug: return "慢性子"
        case .amberBeetle: return "晒太阳"
        case .sandGecko: return "好奇眼"
        case .sandScorpion: return "守沙者"
        case .desertMantis: return "静如叶"
        case .hornedToad: return "守沙者"
        case .scarab: return "守沙者"
        case .leafInsect: return "静如叶"
        case .herculesBeetle: return "角力士"
        case .chameleon: return "变色魔术师"
        case .dartFrog: return "爱蹦跳"
        case .blueMorpho: return "追光手"
        case .redEyedFrog: return "爱蹦跳"
        case .cherryShrimp: return "勤劳钳"
        case .neonTetra: return "追光手"
        case .bettaFish: return "优雅尾"
        case .crayfish: return "缸霸"
        case .corydoras: return "翻沙手"
        case .otoCatfish: return "勤劳钳"
        case .crystalShrimp: return "优雅尾"
        }
    }

    /// 优先停驻的专属生态位摆件近旁坐标（随摆件实际摆放原点动态跟随）
    public static func nicheSpot(for kind: CritterKind, enabledDecorIDs: [String], decorOrigins: [String: GridCoord] = [:]) -> GridCoord? {
        switch kind {
        case .treeFrog:
            guard enabledDecorIDs.contains("shallow_pool") else { return nil }
            return effectiveDecorOrigin(for: "shallow_pool", decorOrigins: decorOrigins)
        case .fireNewt:
            guard enabledDecorIDs.contains("meadow_stepping_stones") else { return nil }
            return effectiveDecorOrigin(for: "meadow_stepping_stones", decorOrigins: decorOrigins)
        case .snail, .pillBug, .rhinoBeetle, .ladybug:
            guard enabledDecorIDs.contains("driftwood") else { return nil }
            let o = effectiveDecorOrigin(for: "driftwood", decorOrigins: decorOrigins)
            return GridCoord(col: o.col + 1, row: max(0, o.row - 1))
        case .amberBeetle:
            guard enabledDecorIDs.contains("sand_pebbles") else { return nil }
            return effectiveDecorOrigin(for: "sand_pebbles", decorOrigins: decorOrigins)
        case .sandGecko, .hornedToad:
            guard enabledDecorIDs.contains("sand_rock") else { return nil }
            let o = effectiveDecorOrigin(for: "sand_rock", decorOrigins: decorOrigins)
            return GridCoord(col: o.col, row: min(gridRows - 1, o.row + 2))
        case .sandScorpion:
            guard enabledDecorIDs.contains("sand_cairn") else { return nil }
            let o = effectiveDecorOrigin(for: "sand_cairn", decorOrigins: decorOrigins)
            return GridCoord(col: o.col, row: max(0, o.row - 1))
        case .scarab, .desertMantis:
            guard enabledDecorIDs.contains("sand_wood") else { return nil }
            let o = effectiveDecorOrigin(for: "sand_wood", decorOrigins: decorOrigins)
            return GridCoord(col: o.col + 1, row: min(gridRows - 1, o.row + 2))
        case .leafInsect, .herculesBeetle:
            guard enabledDecorIDs.contains("rainforest_bark") else { return nil }
            let o = effectiveDecorOrigin(for: "rainforest_bark", decorOrigins: decorOrigins)
            return GridCoord(col: o.col + 1, row: max(0, o.row - 1))
        case .chameleon, .blueMorpho:
            guard enabledDecorIDs.contains("rainforest_vine") else { return nil }
            let o = effectiveDecorOrigin(for: "rainforest_vine", decorOrigins: decorOrigins)
            return GridCoord(col: o.col + 1, row: min(gridRows - 1, o.row + 2))
        case .dartFrog:
            guard enabledDecorIDs.contains("rainforest_bromeliad_stump") else { return nil }
            let o = effectiveDecorOrigin(for: "rainforest_bromeliad_stump", decorOrigins: decorOrigins)
            return GridCoord(col: o.col, row: max(0, o.row - 1))
        case .redEyedFrog:
            guard enabledDecorIDs.contains("rainforest_waterfall") else { return nil }
            let o = effectiveDecorOrigin(for: "rainforest_waterfall", decorOrigins: decorOrigins)
            return GridCoord(col: o.col, row: min(gridRows - 1, o.row + 2))
        case .cherryShrimp, .crayfish:
            guard enabledDecorIDs.contains("aquatic_castle") else { return nil }
            let o = effectiveDecorOrigin(for: "aquatic_castle", decorOrigins: decorOrigins)
            return GridCoord(col: o.col + 1, row: max(0, o.row - 1))
        case .corydoras, .crystalShrimp:
            guard enabledDecorIDs.contains("aquatic_bamboo_tube") else { return nil }
            let o = effectiveDecorOrigin(for: "aquatic_bamboo_tube", decorOrigins: decorOrigins)
            return GridCoord(col: o.col, row: max(0, o.row - 1))
        case .otoCatfish:
            guard enabledDecorIDs.contains("aquatic_seiryu_stone") else { return nil }
            let o = effectiveDecorOrigin(for: "aquatic_seiryu_stone", decorOrigins: decorOrigins)
            return GridCoord(col: o.col, row: min(gridRows - 1, o.row + 1))
        case .neonTetra, .bettaFish:
            guard enabledDecorIDs.contains("aquatic_bubble_rock") else { return nil }
            let o = effectiveDecorOrigin(for: "aquatic_bubble_rock", decorOrigins: decorOrigins)
            return GridCoord(col: max(0, o.col - 1), row: o.row + 1)
        }
    }

    // MARK: - v0.3.0 第二阶段：多缸轻度生态共鸣、晨昏光影与挚友微叙事

    public struct EcosystemResonance: Equatable {
        public let isActive: Bool
        public let distinctBiomeCount: Int
        public let plantSpawnMult: Double
        public let efficiencyBonus: Double
    }

    /// 当存档内同时存在 ≥2 种不同生态的活跃未休眠缸时，激活跨缸微气候共鸣
    public static func ecosystemResonance(containers: [TerrariumContainer]) -> EcosystemResonance {
        let activeBiomes = Set(containers.filter { !$0.instance.isSleeping }.map { $0.instance.biome })
        let distinctCount = activeBiomes.count
        if distinctCount >= 2 {
            return EcosystemResonance(isActive: true, distinctBiomeCount: distinctCount, plantSpawnMult: 1.10, efficiencyBonus: 0.05)
        }
        return EcosystemResonance(isActive: false, distinctBiomeCount: distinctCount, plantSpawnMult: 1.0, efficiencyBonus: 0.0)
    }

    /// 日出（06:00~07:30）与日落（17:30~19:00）的柔和暖金光晕强度（0.0~1.0）
    public static func twilightTintIntensity(for date: Date = Date(), calendar: Calendar = .current) -> Double {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let totalMins = Double(hour * 60 + minute)

        // 日出 360~450，峰值 405
        if totalMins >= 360.0 && totalMins <= 450.0 {
            let dist = abs(totalMins - 405.0) / 45.0
            return max(0.0, 1.0 - dist)
        }
        // 日落 1050~1140，峰值 1095
        if totalMins >= 1050.0 && totalMins <= 1140.0 {
            let dist = abs(totalMins - 1095.0) / 45.0
            return max(0.0, 1.0 - dist)
        }
        return 0.0
    }

    /// Lv.5 挚友微叙事短句（结合昵称、当地室外气温与氛围）
    public static func soulmateMicroNarrative(nickname: String, kind: CritterKind, localTempC: Int?, atmosphere: SceneAtmosphere) -> String {
        if atmosphere == .rain {
            return "「\(nickname)」静静望着窗外雨丝，安心地打了个盹"
        }
        if atmosphere == .night {
            return "「\(nickname)」在微光下陪你加班，状态很惬意呢"
        }
        if let temp = localTempC {
            if temp <= 15 {
                return "「\(nickname)」贴在玻璃边打招呼：外面只有 \(temp)°C 呢"
            } else if temp >= 28 {
                return "「\(nickname)」躲在叶荫乘凉：外面 \(temp)°C 好热呀"
            } else {
                return "「\(nickname)」精神满满，外面 \(temp)°C 正舒适"
            }
        }
        return "「\(nickname)」对你亲昵地蹭了蹭玻璃壁 ♥"
    }
}
