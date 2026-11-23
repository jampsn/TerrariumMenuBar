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
        case 52...: return TerrariumL10n.t("milestone.52")
        case 42...: return TerrariumL10n.t("milestone.42")
        case 33...: return TerrariumL10n.t("milestone.33")
        case 20...: return TerrariumL10n.t("milestone.20")
        case 10...: return TerrariumL10n.t("milestone.10")
        default: return TerrariumL10n.t("milestone.0")
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
            TerrariumL10n.t("affinity.stage.\(rawValue)")
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

    /// 持久化中文性格键 -> 本地化展示名称映射（严禁修改存储原值与 perk 判定）
    public static func localizedPersonality(for rawPersonality: String) -> String {
        let map: [String: String] = [
            "慢性子": "slowpoke",
            "害羞团": "shy_ball",
            "护木侠": "wood_guard",
            "爱戏水": "water_lover",
            "喜阴凉": "shade_lover",
            "晒太阳": "sunbather",
            "好奇眼": "curious_eye",
            "守沙者": "sand_guard",
            "静如叶": "still_leaf",
            "角力士": "horn_wrestler",
            "变色魔术师": "color_mage",
            "爱蹦跳": "hopper",
            "追光手": "light_chaser",
            "勤劳钳": "busy_claw",
            "优雅尾": "graceful_tail",
            "缸霸": "tank_boss",
            "翻沙手": "sand_sifter"
        ]
        guard let key = map[rawPersonality] else { return rawPersonality }
        return TerrariumL10n.t("personality.\(key)")
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
        case (_, .acquaintance): return TerrariumL10n.t("affinity.perk.lv1")
        case (_, .familiar): return TerrariumL10n.t("affinity.perk.lv2")
        case (.thrifty, .close), (.thrifty, .trusted): return TerrariumL10n.t("affinity.perk.thrifty_lv3")
        case (.thrifty, .soulmate): return TerrariumL10n.t("affinity.perk.thrifty_lv5")
        case (.energetic, .close), (.energetic, .trusted): return TerrariumL10n.t("affinity.perk.energetic_lv3")
        case (.energetic, .soulmate): return TerrariumL10n.t("affinity.perk.energetic_lv5")
        case (.charming, .close), (.charming, .trusted): return TerrariumL10n.t("affinity.perk.social_lv3")
        case (.charming, .soulmate): return TerrariumL10n.t("affinity.perk.social_lv5")
        }
    }

    public static func petReplyText(nickname: String, stage: AffinityStage) -> String {
        TerrariumL10n.t("affinity.pet_reply.\(stage.rawValue)", ["name": nickname])
    }

    public static func areCompatibleInSameTank(_ lhs: CritterKind, _ rhs: CritterKind) -> Bool {
        foodChainGroup(for: lhs) == foodChainGroup(for: rhs)
    }

    private static func critterSpec(
        kind: CritterKind,
        biome: TerrariumBiome,
        cost: Int,
        group: FoodChainGroup,
        assetName: String,
        w: Double,
        h: Double
    ) -> CritterShopSpec {
        let id = kind.rawValue
        return CritterShopSpec(
            kind: kind,
            name: TerrariumL10n.t("critter.\(id).name"),
            biome: biome,
            cost: cost,
            group: group,
            assetName: assetName,
            frameWidth: w,
            frameHeight: h,
            unlockConditionText: TerrariumL10n.t("critter.\(id).unlock_cond"),
            foodChainNote: TerrariumL10n.t("critter.\(id).food_chain_note")
        )
    }

    public static func critterShopCatalog(for biome: TerrariumBiome) -> [CritterShopSpec] {
        switch biome {
        case .meadow:
            return [
                critterSpec(kind: .snail, biome: .meadow, cost: 6, group: .meadowInsects, assetName: "char_snail_sheet", w: 17, h: 14),
                critterSpec(kind: .pillBug, biome: .meadow, cost: 9, group: .meadowInsects, assetName: "char_pillbug_sheet", w: 14, h: 10),
                critterSpec(kind: .rhinoBeetle, biome: .meadow, cost: 14, group: .meadowInsects, assetName: "char_rhino_beetle_sheet", w: 20, h: 16),
                critterSpec(kind: .treeFrog, biome: .meadow, cost: 18, group: .meadowPredator, assetName: "char_frog_sheet", w: 24, h: 22),
                critterSpec(kind: .fireNewt, biome: .meadow, cost: 22, group: .meadowPredator, assetName: "char_fire_newt_sheet", w: 22, h: 16),
                critterSpec(kind: .ladybug, biome: .meadow, cost: 8, group: .meadowInsects, assetName: "char_ladybug_sheet", w: 14, h: 11)
            ]
        case .sand:
            return [
                critterSpec(kind: .amberBeetle, biome: .sand, cost: 10, group: .sandBeetles, assetName: "char_beetle_sheet", w: 18, h: 14),
                critterSpec(kind: .scarab, biome: .sand, cost: 26, group: .sandBeetles, assetName: "char_scarab_sheet", w: 18, h: 14),
                critterSpec(kind: .sandGecko, biome: .sand, cost: 18, group: .sandPredator, assetName: "char_gecko_sheet", w: 28, h: 18),
                critterSpec(kind: .sandScorpion, biome: .sand, cost: 24, group: .sandPredator, assetName: "char_sand_scorpion_sheet", w: 22, h: 16),
                critterSpec(kind: .desertMantis, biome: .sand, cost: 16, group: .sandBeetles, assetName: "char_desert_mantis_sheet", w: 22, h: 16),
                critterSpec(kind: .hornedToad, biome: .sand, cost: 28, group: .sandPredator, assetName: "char_horned_toad_sheet", w: 28, h: 18)
            ]
        case .rainforest:
            return [
                critterSpec(kind: .leafInsect, biome: .rainforest, cost: 12, group: .rainforestInsects, assetName: "char_leaf_insect_sheet", w: 18, h: 16),
                critterSpec(kind: .herculesBeetle, biome: .rainforest, cost: 22, group: .rainforestInsects, assetName: "char_hercules_sheet", w: 22, h: 16),
                critterSpec(kind: .chameleon, biome: .rainforest, cost: 32, group: .rainforestPredator, assetName: "char_chameleon_green", w: 26, h: 20),
                critterSpec(kind: .dartFrog, biome: .rainforest, cost: 24, group: .rainforestPredator, assetName: "char_dart_frog_sheet", w: 20, h: 18),
                critterSpec(kind: .blueMorpho, biome: .rainforest, cost: 18, group: .rainforestInsects, assetName: "char_blue_morpho_sheet", w: 22, h: 18),
                critterSpec(kind: .redEyedFrog, biome: .rainforest, cost: 26, group: .rainforestPredator, assetName: "char_red_eyed_frog_sheet", w: 20, h: 18)
            ]
        case .aquatic:
            return [
                critterSpec(kind: .cherryShrimp, biome: .aquatic, cost: 10, group: .aquaticPeaceful, assetName: "char_shrimp_sheet", w: 14, h: 11),
                critterSpec(kind: .neonTetra, biome: .aquatic, cost: 16, group: .aquaticPeaceful, assetName: "char_tetra_sheet", w: 14, h: 10),
                critterSpec(kind: .bettaFish, biome: .aquatic, cost: 25, group: .aquaticBetta, assetName: "char_betta_sheet", w: 30, h: 22),
                critterSpec(kind: .crayfish, biome: .aquatic, cost: 30, group: .aquaticPredator, assetName: "char_crayfish_sheet", w: 24, h: 16),
                critterSpec(kind: .corydoras, biome: .aquatic, cost: 14, group: .aquaticPeaceful, assetName: "char_corydoras_sheet", w: 16, h: 12),
                critterSpec(kind: .otoCatfish, biome: .aquatic, cost: 12, group: .aquaticPeaceful, assetName: "char_oto_catfish_sheet", w: 16, h: 12),
                critterSpec(kind: .crystalShrimp, biome: .aquatic, cost: 20, group: .aquaticPeaceful, assetName: "char_crystal_shrimp_sheet", w: 14, h: 11)
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
    public static var weatherEvents: [WeatherEventDefinition] {
        [
            WeatherEventDefinition(
                id: "cool_rain",
                title: TerrariumL10n.t("weather.cool_rain.title"),
                effectText: TerrariumL10n.t("weather.cool_rain.effect"),
                atmosphere: .rain,
                tempDelta: -4,
                humidityDelta: 18
            ),
            WeatherEventDefinition(
                id: "warm_sun",
                title: TerrariumL10n.t("weather.warm_sun.title"),
                effectText: TerrariumL10n.t("weather.warm_sun.effect"),
                atmosphere: .warm,
                tempDelta: 4,
                humidityDelta: -10
            ),
            WeatherEventDefinition(
                id: "cool_night",
                title: TerrariumL10n.t("weather.cool_night.title"),
                effectText: TerrariumL10n.t("weather.cool_night.effect"),
                atmosphere: .night,
                tempDelta: -3,
                humidityDelta: 6
            ),
            WeatherEventDefinition(
                id: "morning_dew",
                title: TerrariumL10n.t("weather.morning_dew.title"),
                effectText: TerrariumL10n.t("weather.morning_dew.effect"),
                atmosphere: .day,
                tempDelta: -1,
                humidityDelta: 8
            )
        ]
    }

    private static func decorEntry(id: String, assetName: String, biome: TerrariumBiome, cost: Int) -> DecorItem {
        DecorItem(
            id: id,
            name: TerrariumL10n.t("decor.\(id).name"),
            assetName: assetName,
            biome: biome,
            cost: cost,
            nicheDescription: TerrariumL10n.t("decor.\(id).desc"),
            unlocked: false,
            enabled: false
        )
    }

    // MARK: - 分生态缸专属摆件目录
    public static func decorCatalog(for biome: TerrariumBiome) -> [DecorItem] {
        switch biome {
        case .meadow:
            return [
                decorEntry(id: "driftwood", assetName: "env_driftwood", biome: .meadow, cost: 6),
                decorEntry(id: "shallow_pool", assetName: "env_shallow_pool", biome: .meadow, cost: 10),
                decorEntry(id: "boulder", assetName: "env_boulder", biome: .meadow, cost: 12),
                decorEntry(id: "meadow_mushroom_log", assetName: "env_meadow_mushroom_log", biome: .meadow, cost: 8),
                decorEntry(id: "meadow_stepping_stones", assetName: "env_meadow_stepping_stones", biome: .meadow, cost: 7)
            ]
        case .sand:
            return [
                decorEntry(id: "sand_pebbles", assetName: "env_pebbles", biome: .sand, cost: 6),
                decorEntry(id: "sand_rock", assetName: "env_sand_rock", biome: .sand, cost: 10),
                decorEntry(id: "sand_wood", assetName: "env_sand_wood", biome: .sand, cost: 12),
                decorEntry(id: "sand_cairn", assetName: "env_sand_cairn", biome: .sand, cost: 8),
                decorEntry(id: "sand_rib_arch", assetName: "env_sand_rib_arch", biome: .sand, cost: 11)
            ]
        case .rainforest:
            return [
                decorEntry(id: "rainforest_vine", assetName: "env_rainforest_vine", biome: .rainforest, cost: 10),
                decorEntry(id: "rainforest_waterfall", assetName: "env_rainforest_waterfall", biome: .rainforest, cost: 14),
                decorEntry(id: "rainforest_bark", assetName: "env_rainforest_bark", biome: .rainforest, cost: 9),
                decorEntry(id: "rainforest_bromeliad_stump", assetName: "env_rainforest_bromeliad_stump", biome: .rainforest, cost: 9),
                decorEntry(id: "rainforest_slate_ledge", assetName: "env_rainforest_slate_ledge", biome: .rainforest, cost: 11)
            ]
        case .aquatic:
            return [
                decorEntry(id: "aquatic_bubble_rock", assetName: "env_aquatic_bubble_rock", biome: .aquatic, cost: 14),
                decorEntry(id: "aquatic_driftwood", assetName: "env_aquatic_driftwood", biome: .aquatic, cost: 10),
                decorEntry(id: "aquatic_castle", assetName: "env_aquatic_castle", biome: .aquatic, cost: 9),
                decorEntry(id: "aquatic_seiryu_stone", assetName: "env_aquatic_seiryu_stone", biome: .aquatic, cost: 10),
                decorEntry(id: "aquatic_bamboo_tube", assetName: "env_aquatic_bamboo_tube", biome: .aquatic, cost: 8)
            ]
        }
    }

    private static func codexItem(id: String, biome: TerrariumBiome, categoryKey: String, isCritter: Bool = false) -> CodexEntry {
        let name = isCritter ? TerrariumL10n.t("critter.\(id).name") : TerrariumL10n.t("codex.\(id).name")
        return CodexEntry(
            id: id,
            name: name,
            biome: biome,
            category: TerrariumL10n.t("codex.cat.\(categoryKey)"),
            condition: TerrariumL10n.t("codex.\(id).cond"),
            desc: TerrariumL10n.t("codex.\(id).desc"),
            unlocked: false
        )
    }

    // MARK: - 全局生态图鉴（共 52 项）
    public static func defaultCodexEntries() -> [CodexEntry] {
        [
            // 苔原缸植物 (6) & 动物 (9)
            codexItem(id: "moss", biome: .meadow, categoryKey: "plant"),
            codexItem(id: "clover", biome: .meadow, categoryKey: "plant"),
            codexItem(id: "fern", biome: .meadow, categoryKey: "plant"),
            codexItem(id: "glow_shroom", biome: .meadow, categoryKey: "rare_plant"),
            codexItem(id: "red_shroom", biome: .meadow, categoryKey: "plant"),
            codexItem(id: "sundew", biome: .meadow, categoryKey: "rare_plant"),
            codexItem(id: "snail", biome: .meadow, categoryKey: "animal", isCritter: true),
            codexItem(id: "pill_bug", biome: .meadow, categoryKey: "animal", isCritter: true),
            codexItem(id: "ladybug", biome: .meadow, categoryKey: "animal", isCritter: true),
            codexItem(id: "rhino_beetle", biome: .meadow, categoryKey: "animal", isCritter: true),
            codexItem(id: "tree_frog", biome: .meadow, categoryKey: "animal", isCritter: true),
            codexItem(id: "fire_newt", biome: .meadow, categoryKey: "rare_animal", isCritter: true),
            codexItem(id: "firefly", biome: .meadow, categoryKey: "rare_animal"),
            codexItem(id: "moon_moth", biome: .meadow, categoryKey: "exclusive"),
            codexItem(id: "dragonfly", biome: .meadow, categoryKey: "exclusive"),
            // 沙地缸植物 (5) & 动物 (7)
            codexItem(id: "succulent", biome: .sand, categoryKey: "sand_plant"),
            codexItem(id: "aloe", biome: .sand, categoryKey: "sand_plant"),
            codexItem(id: "cactus", biome: .sand, categoryKey: "rare_plant"),
            codexItem(id: "lithops", biome: .sand, categoryKey: "sand_plant"),
            codexItem(id: "agave", biome: .sand, categoryKey: "rare_plant"),
            codexItem(id: "amber_beetle", biome: .sand, categoryKey: "sand_animal", isCritter: true),
            codexItem(id: "desert_mantis", biome: .sand, categoryKey: "sand_animal", isCritter: true),
            codexItem(id: "sand_gecko", biome: .sand, categoryKey: "sand_animal", isCritter: true),
            codexItem(id: "scarab", biome: .sand, categoryKey: "exclusive", isCritter: true),
            codexItem(id: "sand_scorpion", biome: .sand, categoryKey: "exclusive", isCritter: true),
            codexItem(id: "horned_toad", biome: .sand, categoryKey: "exclusive", isCritter: true),
            codexItem(id: "antlion_lacewing", biome: .sand, categoryKey: "exclusive"),
            // 雨林缸植物 (5) & 动物 (8)
            codexItem(id: "monstera", biome: .rainforest, categoryKey: "rainforest_plant"),
            codexItem(id: "bromeliad", biome: .rainforest, categoryKey: "rainforest_plant"),
            codexItem(id: "orchid", biome: .rainforest, categoryKey: "rare_plant"),
            codexItem(id: "pitcher_plant", biome: .rainforest, categoryKey: "rare_plant"),
            codexItem(id: "calathea", biome: .rainforest, categoryKey: "rainforest_plant"),
            codexItem(id: "leaf_insect", biome: .rainforest, categoryKey: "rainforest_animal", isCritter: true),
            codexItem(id: "hercules_beetle", biome: .rainforest, categoryKey: "rainforest_animal", isCritter: true),
            codexItem(id: "blue_morpho", biome: .rainforest, categoryKey: "rare_animal", isCritter: true),
            codexItem(id: "chameleon", biome: .rainforest, categoryKey: "exclusive", isCritter: true),
            codexItem(id: "dart_frog", biome: .rainforest, categoryKey: "exclusive", isCritter: true),
            codexItem(id: "red_eyed_frog", biome: .rainforest, categoryKey: "exclusive", isCritter: true),
            codexItem(id: "luna_cicada", biome: .rainforest, categoryKey: "exclusive"),
            codexItem(id: "orchid_bee", biome: .rainforest, categoryKey: "exclusive"),
            // 碧波鱼缸植物 (5) & 动物 (7)
            codexItem(id: "marimo", biome: .aquatic, categoryKey: "aquatic_plant"),
            codexItem(id: "anubias", biome: .aquatic, categoryKey: "aquatic_plant"),
            codexItem(id: "lotus", biome: .aquatic, categoryKey: "rare_aquatic_plant"),
            codexItem(id: "vallisneria", biome: .aquatic, categoryKey: "aquatic_plant"),
            codexItem(id: "red_ludwigia", biome: .aquatic, categoryKey: "rare_aquatic_plant"),
            codexItem(id: "cherry_shrimp", biome: .aquatic, categoryKey: "aquatic_animal", isCritter: true),
            codexItem(id: "oto_catfish", biome: .aquatic, categoryKey: "aquatic_animal", isCritter: true),
            codexItem(id: "crystal_shrimp", biome: .aquatic, categoryKey: "exclusive", isCritter: true),
            codexItem(id: "neon_tetra", biome: .aquatic, categoryKey: "aquatic_animal", isCritter: true),
            codexItem(id: "betta_fish", biome: .aquatic, categoryKey: "exclusive", isCritter: true),
            codexItem(id: "crayfish", biome: .aquatic, categoryKey: "aquatic_boss", isCritter: true),
            codexItem(id: "corydoras", biome: .aquatic, categoryKey: "aquatic_animal", isCritter: true)
        ]
    }

    // MARK: - 生物个性、昵称与生态位停驻坐标
    public static func defaultNickname(for kind: CritterKind) -> String {
        TerrariumL10n.t("critter.\(kind.rawValue).default_nick")
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
            return TerrariumL10n.t("narrative.rain", ["name": nickname])
        }
        if atmosphere == .night {
            return TerrariumL10n.t("narrative.night", ["name": nickname])
        }
        if let temp = localTempC {
            if temp <= 15 {
                return TerrariumL10n.t("narrative.cold", ["name": nickname, "temp": "\(temp)"])
            } else if temp >= 28 {
                return TerrariumL10n.t("narrative.hot", ["name": nickname, "temp": "\(temp)"])
            } else {
                return TerrariumL10n.t("narrative.mild", ["name": nickname, "temp": "\(temp)"])
            }
        }
        return TerrariumL10n.t("narrative.default", ["name": nickname])
    }

    // MARK: - 组合式成就称号系统（14 项，首次达成一次性奖励 +1~+3 生态点）

    private static func achievementDef(_ id: String, _ catKey: String, _ pts: Int) -> AchievementDefinition {
        AchievementDefinition(
            id: id,
            title: TerrariumL10n.t("ach.\(id).title"),
            category: TerrariumL10n.t("ach.cat.\(catKey)"),
            conditionDesc: TerrariumL10n.t("ach.\(id).cond"),
            rewardPoints: pts
        )
    }

    public static var defaultAchievements: [AchievementDefinition] {
        [
            achievementDef("ach_codex_10", "milestone", 1),
            achievementDef("ach_codex_20", "milestone", 2),
            achievementDef("ach_codex_33", "milestone", 2),
            achievementDef("ach_codex_42", "milestone", 3),
            achievementDef("ach_codex_52", "milestone", 3),
            achievementDef("ach_four_biomes", "cross_biome", 3),
            achievementDef("ach_aerial_collector", "theme", 3),
            achievementDef("ach_frog_chorus", "theme", 2),
            achievementDef("ach_desert_lords", "theme", 2),
            achievementDef("ach_carnivore_flora", "theme", 2),
            achievementDef("ach_aquatic_jewels", "theme", 2),
            achievementDef("ach_first_soulmate", "bond", 2),
            achievementDef("ach_three_soulmates", "bond", 3),
            achievementDef("ach_skin_collector", "aesthetic", 1)
        ]
    }

    public static func displayTitle(for saveData: TerrariumSaveData) -> String {
        let unlocked = Set(saveData.unlockedAchievementIDs)
        if let eqID = saveData.equippedTitleID,
           unlocked.contains(eqID),
           let def = defaultAchievements.first(where: { $0.id == eqID }) {
            return def.title
        }
        if let latest = defaultAchievements.last(where: { unlocked.contains($0.id) }) {
            return latest.title
        }
        return codexMilestoneTitle(unlockedCount: saveData.unlockedCodexIDs.count)
    }

    /// 计算从起始日期到当前日期的挂机自然天数（Day 0, 1, 2...）
    public static func elapsedDays(from startDate: Date, to now: Date = Date(), calendar: Calendar = .current) -> Int {
        let startDay = calendar.startOfDay(for: startDate)
        let currentDay = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: startDay, to: currentDay).day ?? 0
        return max(0, days)
    }
}
