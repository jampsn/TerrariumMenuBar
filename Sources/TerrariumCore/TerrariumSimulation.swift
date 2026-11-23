import Foundation

public struct InstanceAdvanceSummary: Equatable {
    public let biome: TerrariumBiome
    public let effectiveSeconds: TimeInterval
    public let earnedEcoPoints: Int
    public let newlyUnlockedCodexIDs: [String]
    public let spawnedPlantsCount: Int
    public let arrivedCritters: [CritterKind]
    public let settledCritters: [CritterKind]
}

public struct MultiOfflineSummary: Equatable {
    public let totalEarnedEcoPoints: Int
    public let newlyUnlockedCodexIDs: [String]
    public let spawnedPlantsCount: Int
}

/// 纯逻辑多生态缸仿真引擎（和平共存、零互吃食物链、舒缓挂机、访客-定居双阶段）
public enum TerrariumSimulation {

    public static func clampTemp(_ value: Int) -> Int {
        min(TerrariumConfig.tempRange.upperBound, max(TerrariumConfig.tempRange.lowerBound, value))
    }

    public static func clampHumidity(_ value: Int) -> Int {
        min(TerrariumConfig.humidityRange.upperBound, max(TerrariumConfig.humidityRange.lowerBound, value))
    }

    public static func clampSalinity(_ v: Double) -> Double {
        let clamped = min(TerrariumConfig.salinityRange.upperBound, max(TerrariumConfig.salinityRange.lowerBound, v))
        return (clamped * 10.0).rounded() / 10.0
    }

    public static func isOptimalEnvironment(temperature: Int, humidity: Int, biome: TerrariumBiome, salinity: Double? = nil) -> Bool {
        switch biome {
        case .sand:
            return (24...32).contains(temperature) && (25...50).contains(humidity)
        case .rainforest:
            return (23...29).contains(temperature) && (65...88).contains(humidity)
        case .aquatic:
            return (22...28).contains(temperature) && humidity >= 60
        case .reef:
            let sal = salinity ?? TerrariumConfig.defaultReefSalinity
            return (23...27).contains(temperature) && humidity >= 65 && TerrariumConfig.optimalSalinityRange.contains(sal)
        case .meadow:
            return TerrariumConfig.optimalTempRange.contains(temperature)
                && TerrariumConfig.optimalHumidityRange.contains(humidity)
        }
    }

    public static func nextWeatherEventDelay(
        randomGenerator: (ClosedRange<TimeInterval>) -> TimeInterval = { Double.random(in: $0) }
    ) -> TimeInterval {
        randomGenerator(TerrariumConfig.weatherEventIntervalRange)
    }

    /// 舒缓温湿度耦合蒸发率（叠加温控设备物理效应、植被保水与水景摆件减免）
    public static func evaporationPerHour(for instance: TerrariumInstanceState) -> Double {
        let tempFactorRaw = 1.0 + 0.05 * Double(max(0, instance.temperature - 22)) - 0.03 * Double(max(0, 22 - instance.temperature))
        let tempFactor = min(1.55, max(0.65, tempFactorRaw))
        let biomeFactor = (instance.biome == .sand) ? 1.25 : 1.0
        let thermalEvapFactor: Double = {
            switch instance.thermalMode {
            case .natural: return 1.0
            case .heating: return 1.20
            case .cooling: return 0.85
            }
        }()

        var floraReduction = 0.0
        let lightFlora: Set<String> = ["moss", "red_shroom", "lithops"]
        let lushFlora: Set<String> = [
            "fern", "clover", "sundew",
            "monstera", "bromeliad", "orchid", "pitcher_plant", "calathea",
            "marimo", "anubias", "lotus", "vallisneria", "red_ludwigia",
            "agave",
            "coral_zoanthid", "coral_acropora", "coral_brain", "coral_anemone", "coral_seafan"
        ]
        for p in instance.plants where p.stage != .withered {
            if lightFlora.contains(p.speciesID) { floraReduction += 0.03 }
            else if lushFlora.contains(p.speciesID) {
                floraReduction += 0.05
            }
        }
        floraReduction = min(0.40, floraReduction)

        var decorReduction = 0.0
        if instance.biome == .meadow && instance.enabledDecorIDs.contains("shallow_pool") {
            decorReduction += 0.20
        } else if instance.biome == .rainforest {
            if instance.enabledDecorIDs.contains("rainforest_waterfall") {
                decorReduction += 0.25
            }
            if instance.enabledDecorIDs.contains("rainforest_bromeliad_stump") {
                decorReduction += 0.10
            }
        } else if instance.biome == .aquatic && instance.enabledDecorIDs.contains("aquatic_bubble_rock") {
            decorReduction += 0.30
        } else if instance.biome == .reef && instance.enabledDecorIDs.contains("reef_wavemaker") {
            decorReduction += 0.25
        }
        let retention = max(0.40, 1.0 - floraReduction - decorReduction)
        return TerrariumConfig.baseEvaporationPerHour * tempFactor * biomeFactor * thermalEvapFactor * retention
    }

    public static func computeDewLevel(speciesID: String, humidity: Int, mistDewBoostSeconds: TimeInterval) -> Int {
        if speciesID.hasPrefix("coral_") {
            return humidity >= 72 ? (mistDewBoostSeconds > 0 ? 2 : 1) : 0
        }
        guard speciesID != "succulent", speciesID != "cactus", speciesID != "aloe",
              speciesID != "lithops", speciesID != "agave",
              speciesID != "marimo", speciesID != "anubias", speciesID != "lotus",
              speciesID != "vallisneria", speciesID != "red_ludwigia" else { return 0 }
        if humidity >= TerrariumConfig.dewHeavyHumidityThreshold || mistDewBoostSeconds > 0 {
            return 2
        }
        if humidity >= TerrariumConfig.dewLightHumidityThreshold {
            return 1
        }
        return 0
    }

    /// 同时结算存档内全部已购置生态缸的离线经过时间（互不覆盖、各缸独立演化）
    @discardableResult
    public static func settleOfflineAll(data: inout TerrariumSaveData, now: Date = Date()) -> MultiOfflineSummary {
        let rawElapsed = max(0, now.timeIntervalSince(data.lastSavedAt))
        let cappedElapsed = min(TerrariumConfig.maxOfflineSettlementSeconds, rawElapsed)

        var totalPoints = 0
        var allNewCodex: [String] = []
        var totalPlants = 0

        var pointsBuffer = data.ecoPoints
        var codexBuffer = data.unlockedCodexIDs

        let resonance = TerrariumConfig.ecosystemResonance(containers: data.containers)

        for idx in data.containers.indices {
            var inst = data.containers[idx].instance
            let summary = advanceInstance(
                instance: &inst,
                ecoPoints: &pointsBuffer,
                unlockedCodexIDs: &codexBuffer,
                elapsedSeconds: cappedElapsed,
                now: now,
                localOutdoorTempC: data.lastKnownLocalTempC,
                tankSlotIndex: idx,
                isOfflineSettlement: true,
                resonanceSpawnMult: resonance.plantSpawnMult,
                resonanceEfficiencyBonus: resonance.efficiencyBonus
            )
            data.containers[idx].instance = inst
            totalPoints += summary.earnedEcoPoints
            allNewCodex.append(contentsOf: summary.newlyUnlockedCodexIDs)
            totalPlants += summary.spawnedPlantsCount
        }
        data.ecoPoints = pointsBuffer
        data.unlockedCodexIDs = codexBuffer
        data.lastSavedAt = now
        return MultiOfflineSummary(
            totalEarnedEcoPoints: totalPoints,
            newlyUnlockedCodexIDs: allNewCodex,
            spawnedPlantsCount: totalPlants
        )
    }

    /// 推进单个生态缸实例的挂机演进
    @discardableResult
    public static func advanceInstance(
        instance: inout TerrariumInstanceState,
        ecoPoints: inout Int,
        unlockedCodexIDs: inout [String],
        elapsedSeconds: TimeInterval,
        now: Date = Date(),
        allowRandomSpawn: Bool = true,
        localOutdoorTempC: Int? = nil,
        tankSlotIndex: Int = 0,
        isOfflineSettlement: Bool = false,
        resonanceSpawnMult: Double = 1.0,
        resonanceEfficiencyBonus: Double = 0.0
    ) -> InstanceAdvanceSummary {
        guard !instance.isSleeping, elapsedSeconds > 0 else {
            return InstanceAdvanceSummary(
                biome: instance.biome,
                effectiveSeconds: 0,
                earnedEcoPoints: 0,
                newlyUnlockedCodexIDs: [],
                spawnedPlantsCount: 0,
                arrivedCritters: [],
                settledCritters: []
            )
        }

        var earnedPoints = 0
        var spawnedCount = 0
        var arrived: [CritterKind] = []
        var settled: [CritterKind] = []
        var remaining = elapsedSeconds
        var progressedSeconds: TimeInterval = 0
        let stepSize: TimeInterval = 60.0
        var unlockedSet = Set(unlockedCodexIDs)
        var newlyUnlockedAll: [String] = []

        if now >= instance.weatherCooldownEndAt {
            let naturalAtm = TerrariumConfig.ambientAtmosphere(for: now, biome: instance.biome)
            if instance.atmosphere == .rain || (instance.biome == .meadow && instance.atmosphere == .warm) {
                instance.atmosphere = naturalAtm
            }
        }

        while remaining > 0 {
            let dt = min(remaining, stepSize)
            remaining -= dt
            progressedSeconds += dt

            // A. 喷水露珠与玻璃水雾 / 鱼缸藻垢按舒缓长周期渐变（彻底避免刚擦完瞬间再起雾/生藻）
            if instance.mistDewBoostSeconds > 0 {
                instance.mistDewBoostSeconds = max(0, instance.mistDewBoostSeconds - dt)
            }
            if instance.biome == .aquatic {
                // 碧波鱼缸：每 ~2 小时才逐渐生满薄藻垢；摆放青龙造景石组可减缓 20% 藻类滋生
                let algaeSlowdown = instance.enabledDecorIDs.contains("aquatic_seiryu_stone") ? 0.80 : 1.0
                instance.glassFogLevel = min(1.0, instance.glassFogLevel + (dt * algaeSlowdown) / TerrariumConfig.aquaticAlgaeAccumulationSeconds)
            } else if instance.biome == .reef {
                // 海缸藻垢：海星贴底爬行可减缓并缓慢清理藻垢
                let hasStarfish = instance.critters.contains { $0.kind == .starfish && ($0.residency == .resident || $0.residency == .visitor) }
                let algaeSlowdown = hasStarfish ? 0.45 : 0.85
                instance.glassFogLevel = min(1.0, instance.glassFogLevel + (dt * algaeSlowdown) / TerrariumConfig.aquaticAlgaeAccumulationSeconds)
                if hasStarfish && instance.glassFogLevel > 0.05 {
                    instance.glassFogLevel = max(0.0, instance.glassFogLevel - dt / 14400.0)
                }
            } else if instance.humidity >= TerrariumConfig.dewLightHumidityThreshold {
                // 陆生缸：高湿状态下按 ~45 分钟缓慢起雾（~30-60 分钟清理一次）
                let targetFog = min(1.0, Double(instance.humidity - 70) / 28.0)
                if instance.glassFogLevel < targetFog {
                    instance.glassFogLevel = min(targetFog, instance.glassFogLevel + dt / TerrariumConfig.glassFogAccumulationSeconds)
                }
            } else {
                instance.glassFogLevel = max(0.0, instance.glassFogLevel - dt / 2400.0)
            }

            // B. 舒缓自然蒸发
            let evapPerHour = evaporationPerHour(for: instance)
            let decayInterval = 3600.0 / evapPerHour
            instance.accumulatedHumidityDecaySeconds += dt
            if instance.accumulatedHumidityDecaySeconds >= decayInterval {
                let decaySteps = Int(instance.accumulatedHumidityDecaySeconds / decayInterval)
                instance.accumulatedHumidityDecaySeconds.formTruncatingRemainder(dividingBy: decayInterval)
                if instance.humidity > TerrariumConfig.humiditySafeFloor {
                    instance.humidity = max(TerrariumConfig.humiditySafeFloor, instance.humidity - decaySteps)
                }
            }
            if instance.biome == .reef {
                // B2. 海缸水分蒸发浓缩：盐度缓慢上升（+0.30‰/h），加热或高温加速；活石拱门减缓 30% 波动
                let baseSal = instance.salinity ?? TerrariumConfig.defaultReefSalinity
                let heatMult = (instance.thermalMode == .heating || instance.temperature >= 28) ? 1.35 : 1.0
                let rockMult = instance.enabledDecorIDs.contains("reef_live_rock") ? 0.70 : 1.0
                let salDelta = 0.30 * heatMult * rockMult * (dt / 3600.0)
                instance.salinity = min(TerrariumConfig.salinityRange.upperBound, baseSal + salDelta)
            }

            // C. 环境基线温度负反馈回归（联动本地实际气温 + 加热灯/降温扇设备恒温目标）
            let baseTemp = TerrariumConfig.baseAmbientTemp(
                for: instance.atmosphere,
                biome: instance.biome,
                thermalMode: instance.thermalMode,
                localOutdoorTempC: localOutdoorTempC
            )
            let relaxInterval = TerrariumConfig.ambientTempRelaxIntervalSeconds(
                for: instance.thermalMode,
                localOutdoorTempC: localOutdoorTempC
            )
            if instance.temperature != baseTemp {
                instance.ambientRelaxSeconds += dt
                if instance.ambientRelaxSeconds >= relaxInterval {
                    instance.ambientRelaxSeconds.formTruncatingRemainder(dividingBy: relaxInterval)
                    let sign = baseTemp > instance.temperature ? 1 : -1
                    instance.temperature = clampTemp(instance.temperature + sign)
                }
            } else {
                instance.ambientRelaxSeconds = 0
            }

            // D. 生态点基础产出（须存在活体植株或在缸生物，按多缸递增递减系数 + 好感度性格共振特技计算）
            let minHum = (instance.biome == .sand) ? TerrariumConfig.sandEcoPointMinHumidity : TerrariumConfig.ecoPointMinHumidity
            let hasLiveFlora = instance.plants.contains(where: { $0.stage != .withered })
            let hasActiveCritters = instance.critters.contains(where: { $0.residency == .resident || $0.residency == .visitor })
            let hasLife = hasLiveFlora || hasActiveCritters
            if hasLife && instance.humidity >= minHum {
                let baseInterval = isOptimalEnvironment(temperature: instance.temperature, humidity: instance.humidity, biome: instance.biome, salinity: instance.salinity)
                    ? TerrariumConfig.ecoPointOptimalIntervalSeconds
                    : TerrariumConfig.ecoPointBaseIntervalSeconds
                let clamBonus = (instance.biome == .reef && instance.enabledDecorIDs.contains("reef_giant_clam")) ? 0.10 : 0.0
                let ecoBoost = tankEcoSpeedBoost(for: instance.critters) + clamBonus
                let baseSlotEff = TerrariumConfig.tankEfficiencyMultiplier(slotIndex: tankSlotIndex)
                let slotEfficiency = min(1.0, baseSlotEff + resonanceEfficiencyBonus)
                let interval = baseInterval / max(0.35, slotEfficiency * (1.0 + ecoBoost))
                let offlineDecayFactor = (isOfflineSettlement && progressedSeconds > TerrariumConfig.offlineFullRateSeconds) ? 0.5 : 1.0
                instance.accumulatedEcoSeconds += dt * offlineDecayFactor
                if instance.accumulatedEcoSeconds >= interval {
                    let gained = Int(instance.accumulatedEcoSeconds / interval)
                    instance.accumulatedEcoSeconds.formTruncatingRemainder(dividingBy: interval)
                    earnedPoints += gained
                    ecoPoints += gained
                }
            }

            // E. 植物更新与冷启动（每缸终身仅限 1 次 15s 破冰）/常规随机萌发脉冲
            updatePlants(instance: &instance, dt: dt)

            if allowRandomSpawn {
                let useColdStart = !instance.hasTriggeredColdStart && instance.plants.isEmpty
                let pulseInterval = useColdStart
                    ? TerrariumConfig.coldStartPlantPulseSeconds
                    : TerrariumConfig.plantPulseIntervalSeconds
                instance.plantPulseSeconds += dt
                if instance.plantPulseSeconds >= pulseInterval {
                    instance.plantPulseSeconds.formTruncatingRemainder(dividingBy: pulseInterval)
                    if let spawned = attemptRandomPlantSpawn(instance: &instance, spawnRateMultiplier: resonanceSpawnMult) {
                        spawnedCount += 1
                        if !unlockedSet.contains(spawned.speciesID) {
                            unlockedSet.insert(spawned.speciesID)
                            unlockedCodexIDs.append(spawned.speciesID)
                            newlyUnlockedAll.append(spawned.speciesID)
                            let bonus = TerrariumConfig.codexRewardPoints(for: spawned.speciesID)
                            earnedPoints += bonus
                            ecoPoints += bonus
                        }
                    }
                }
            }

            // F. 在缸动物饥饿累积与离线代偿进食（严禁生物仓 .stored 偷吃；计入好感度减饥饿特技与清洁虾护理）
            let hasCleanerShrimp = (instance.biome == .reef) && instance.critters.contains {
                $0.kind == .cleanerShrimp && ($0.residency == .resident || $0.residency == .visitor)
            }
            let reefCleanerMult = hasCleanerShrimp ? 0.85 : 1.0
            for idx in instance.critters.indices where (instance.critters[idx].residency == .resident || instance.critters[idx].residency == .visitor) {
                let kind = instance.critters[idx].kind
                let hungerMult = critterHungerMultiplier(for: instance.critters[idx]) * reefCleanerMult
                let rate = TerrariumConfig.hungerRatePerHour(for: kind) * hungerMult
                instance.critters[idx].hunger = min(100.0, instance.critters[idx].hunger + rate * (dt / 3600.0))

                if elapsedSeconds > 120.0 && instance.foodBowlPortions > 0 && instance.critters[idx].hunger >= 55.0 {
                    let rewardReady = instance.critters[idx].lastFedRewardAt.map {
                        now.timeIntervalSince($0) >= TerrariumConfig.mealRewardCooldownSeconds
                    } ?? true
                    instance.foodBowlPortions -= 1
                    instance.critters[idx].hunger = max(0.0, instance.critters[idx].hunger - 45.0)
                    instance.critters[idx].mealsEaten += 1
                    if rewardReady {
                        instance.critters[idx].lastFedRewardAt = now
                        let mealPts = 1
                        earnedPoints += mealPts
                        ecoPoints += mealPts
                    }

                    if instance.critters[idx].residency == .visitor {
                        let req = TerrariumConfig.mealsRequiredToSettle(kind: kind, enabledDecorIDs: instance.enabledDecorIDs)
                        if instance.critters[idx].mealsEaten >= req {
                            instance.critters[idx].residency = .resident
                            settled.append(kind)
                        }
                    }
                }
            }

            // G. 访客引入 & 温和隐匿状态机判定
            let ecoEval = evaluateCritterEcology(instance: &instance)
            arrived.append(contentsOf: ecoEval.arrived)
            settled.append(contentsOf: ecoEval.settled)

            // H. 图鉴条件解锁（含植物、常驻动物与空中高阶专属物种，统一走分级奖励表）
            let unlockedStep = evaluateCodexUnlocks(instance: instance, alreadyUnlocked: unlockedSet)
            if !unlockedStep.isEmpty {
                var bonus = 0
                for id in unlockedStep {
                    unlockedSet.insert(id)
                    newlyUnlockedAll.append(id)
                    bonus += TerrariumConfig.codexRewardPoints(for: id)
                }
                unlockedCodexIDs.append(contentsOf: unlockedStep)
                earnedPoints += bonus
                ecoPoints += bonus
            }
        }

        return InstanceAdvanceSummary(
            biome: instance.biome,
            effectiveSeconds: elapsedSeconds,
            earnedEcoPoints: earnedPoints,
            newlyUnlockedCodexIDs: newlyUnlockedAll,
            spawnedPlantsCount: spawnedCount,
            arrivedCritters: arrived,
            settledCritters: settled
        )
    }

    /// 检查某个物种当前生态门槛是否已达标（达标后方可消耗生态点购买入缸）
    public static func critterUnlockEligibility(kind: CritterKind, instance: TerrariumInstanceState) -> (eligible: Bool, missingReason: String) {
        let mossCount = instance.plants.filter { $0.speciesID == "moss" && $0.stage != .withered }.count
        let fernCount = instance.plants.filter { $0.speciesID == "fern" && $0.stage != .withered }.count
        let succulentCount = instance.plants.filter { $0.speciesID == "succulent" && $0.stage != .withered }.count
        let aloeCount = instance.plants.filter { $0.speciesID == "aloe" && $0.stage != .withered }.count
        let cactusCount = instance.plants.filter { $0.speciesID == "cactus" && $0.stage != .withered }.count

        let succinctPlants = (
            monsteraCount: instance.plants.filter { $0.speciesID == "monstera" && $0.stage != .withered }.count,
            bromeliadCount: instance.plants.filter { $0.speciesID == "bromeliad" && $0.stage != .withered }.count,
            orchidCount: instance.plants.filter { $0.speciesID == "orchid" && $0.stage != .withered }.count
        )

        func onlyBiome(_ biome: TerrariumBiome) -> (Bool, String) {
            (false, TerrariumL10n.t("elig.only_biome", ["biome": biome.localizedName]))
        }
        func needDecor(_ id: String) -> (Bool, String) {
            (false, TerrariumL10n.t("elig.need_decor", ["decor": TerrariumL10n.t("decor.\(id).name")]))
        }
        func needPlant(_ id: String, _ count: Int = 1) -> (Bool, String) {
            (false, TerrariumL10n.t("elig.need_plant", ["plant": TerrariumL10n.t("codex.\(id).name"), "count": "\(count)"]))
        }
        func eligOK() -> (Bool, String) {
            (true, TerrariumL10n.t("elig.ok"))
        }

        switch kind {
        case .snail:
            guard instance.biome == .meadow else { return onlyBiome(.meadow) }
            if mossCount < 1 { return needPlant("moss") }
            if instance.humidity < 45 { return (false, TerrariumL10n.t("elig.need_humidity_min", ["val": "45"])) }
            return eligOK()
        case .pillBug:
            guard instance.biome == .meadow else { return onlyBiome(.meadow) }
            if !instance.enabledDecorIDs.contains("driftwood") { return needDecor("driftwood") }
            if mossCount < 1 { return needPlant("moss") }
            return eligOK()
        case .rhinoBeetle:
            guard instance.biome == .meadow else { return onlyBiome(.meadow) }
            if !instance.enabledDecorIDs.contains("driftwood") { return needDecor("driftwood") }
            if fernCount < 1 { return needPlant("fern") }
            if instance.humidity < 55 { return (false, TerrariumL10n.t("elig.need_humidity_min", ["val": "55"])) }
            return eligOK()
        case .treeFrog:
            guard instance.biome == .meadow else { return onlyBiome(.meadow) }
            if !instance.enabledDecorIDs.contains("shallow_pool") { return needDecor("shallow_pool") }
            if fernCount < 1 { return needPlant("fern") }
            if instance.humidity < 55 { return (false, TerrariumL10n.t("elig.need_humidity_min", ["val": "55"])) }
            return eligOK()
        case .fireNewt:
            guard instance.biome == .meadow else { return onlyBiome(.meadow) }
            if !instance.enabledDecorIDs.contains("meadow_stepping_stones") { return needDecor("meadow_stepping_stones") }
            if !instance.enabledDecorIDs.contains("shallow_pool") { return needDecor("shallow_pool") }
            if instance.temperature > 21 { return (false, TerrariumL10n.t("elig.need_temp_max", ["val": "21"])) }
            if instance.humidity < 68 { return (false, TerrariumL10n.t("elig.need_humidity_min", ["val": "68"])) }
            return eligOK()
        case .ladybug:
            guard instance.biome == .meadow else { return onlyBiome(.meadow) }
            let cloverCount = instance.plants.filter { $0.speciesID == "clover" && $0.stage != .withered }.count
            if cloverCount < 1 { return needPlant("clover") }
            if instance.humidity < 50 { return (false, TerrariumL10n.t("elig.need_humidity_min", ["val": "50"])) }
            return eligOK()
        case .amberBeetle:
            guard instance.biome == .sand else { return onlyBiome(.sand) }
            if !instance.enabledDecorIDs.contains("sand_pebbles") { return needDecor("sand_pebbles") }
            if succulentCount < 1 { return needPlant("succulent") }
            return eligOK()
        case .scarab:
            guard instance.biome == .sand else { return onlyBiome(.sand) }
            if cactusCount < 1 { return needPlant("cactus") }
            if aloeCount < 1 { return needPlant("aloe") }
            if instance.temperature < 27 { return (false, TerrariumL10n.t("elig.need_temp_min_lamp", ["val": "27"])) }
            if instance.humidity > 42 { return (false, TerrariumL10n.t("elig.need_humidity_max", ["val": "42"])) }
            return eligOK()
        case .sandGecko:
            guard instance.biome == .sand else { return onlyBiome(.sand) }
            let sandPlants = succulentCount + aloeCount + cactusCount
            if !instance.enabledDecorIDs.contains("sand_rock") { return needDecor("sand_rock") }
            if sandPlants < 2 { return (false, TerrariumL10n.t("elig.need_sand_plants", ["count": "2"])) }
            if instance.temperature < 24 { return (false, TerrariumL10n.t("elig.need_temp_min", ["val": "24"])) }
            return eligOK()
        case .sandScorpion:
            guard instance.biome == .sand else { return onlyBiome(.sand) }
            if !instance.enabledDecorIDs.contains("sand_cairn") { return needDecor("sand_cairn") }
            if !instance.enabledDecorIDs.contains("sand_rib_arch") { return needDecor("sand_rib_arch") }
            if cactusCount < 1 { return needPlant("cactus") }
            if instance.temperature < 26 { return (false, TerrariumL10n.t("elig.need_temp_min", ["val": "26"])) }
            return eligOK()
        case .desertMantis:
            guard instance.biome == .sand else { return onlyBiome(.sand) }
            let agaveCount = instance.plants.filter { $0.speciesID == "agave" && $0.stage != .withered }.count
            if !instance.enabledDecorIDs.contains("sand_wood") { return needDecor("sand_wood") }
            if agaveCount < 1 { return needPlant("agave") }
            if instance.temperature < 24 { return (false, TerrariumL10n.t("elig.need_temp_min", ["val": "24"])) }
            return eligOK()
        case .hornedToad:
            guard instance.biome == .sand else { return onlyBiome(.sand) }
            if !instance.enabledDecorIDs.contains("sand_cairn") { return needDecor("sand_cairn") }
            if !instance.enabledDecorIDs.contains("sand_rock") { return needDecor("sand_rock") }
            if cactusCount < 1 { return needPlant("cactus") }
            if instance.temperature < 27 { return (false, TerrariumL10n.t("elig.need_temp_min", ["val": "27"])) }
            return eligOK()
        case .leafInsect:
            guard instance.biome == .rainforest else { return onlyBiome(.rainforest) }
            if !instance.enabledDecorIDs.contains("rainforest_bark") { return needDecor("rainforest_bark") }
            if succinctPlants.monsteraCount < 1 { return needPlant("monstera") }
            if instance.humidity < 65 { return (false, TerrariumL10n.t("elig.need_humidity_min", ["val": "65"])) }
            return eligOK()
        case .herculesBeetle:
            guard instance.biome == .rainforest else { return onlyBiome(.rainforest) }
            if !instance.enabledDecorIDs.contains("rainforest_bark") { return needDecor("rainforest_bark") }
            if succinctPlants.orchidCount < 1 { return needPlant("orchid") }
            if instance.temperature < 24 { return (false, TerrariumL10n.t("elig.need_temp_min", ["val": "24"])) }
            return eligOK()
        case .chameleon:
            guard instance.biome == .rainforest else { return onlyBiome(.rainforest) }
            if !instance.enabledDecorIDs.contains("rainforest_vine") { return needDecor("rainforest_vine") }
            if succinctPlants.monsteraCount + succinctPlants.bromeliadCount < 2 { return (false, TerrariumL10n.t("elig.need_rainforest_core", ["count": "2"])) }
            if instance.temperature < 25 { return (false, TerrariumL10n.t("elig.need_temp_min_lamp", ["val": "25"])) }
            if instance.humidity < 70 { return (false, TerrariumL10n.t("elig.need_humidity_min", ["val": "70"])) }
            return eligOK()
        case .dartFrog:
            guard instance.biome == .rainforest else { return onlyBiome(.rainforest) }
            if !instance.enabledDecorIDs.contains("rainforest_bromeliad_stump") { return needDecor("rainforest_bromeliad_stump") }
            if succinctPlants.bromeliadCount < 1 { return needPlant("bromeliad") }
            if instance.humidity < 72 { return (false, TerrariumL10n.t("elig.need_humidity_min", ["val": "72"])) }
            return eligOK()
        case .blueMorpho:
            guard instance.biome == .rainforest else { return onlyBiome(.rainforest) }
            let pitcherCount = instance.plants.filter { $0.speciesID == "pitcher_plant" && $0.stage != .withered }.count
            if succinctPlants.orchidCount < 1 { return needPlant("orchid") }
            if pitcherCount < 1 { return needPlant("pitcher_plant") }
            if instance.humidity < 70 { return (false, TerrariumL10n.t("elig.need_humidity_min", ["val": "70"])) }
            return eligOK()
        case .redEyedFrog:
            guard instance.biome == .rainforest else { return onlyBiome(.rainforest) }
            let calatheaCount = instance.plants.filter { $0.speciesID == "calathea" && $0.stage != .withered }.count
            if !instance.enabledDecorIDs.contains("rainforest_waterfall") { return needDecor("rainforest_waterfall") }
            if calatheaCount < 1 { return needPlant("calathea") }
            if instance.humidity < 75 { return (false, TerrariumL10n.t("elig.need_humidity_min", ["val": "75"])) }
            return eligOK()
        case .cherryShrimp:
            guard instance.biome == .aquatic else { return onlyBiome(.aquatic) }
            let marimoCount = instance.plants.filter { $0.speciesID == "marimo" && $0.stage != .withered }.count
            if !instance.enabledDecorIDs.contains("aquatic_castle") { return needDecor("aquatic_castle") }
            if marimoCount < 1 { return needPlant("marimo") }
            return eligOK()
        case .neonTetra:
            guard instance.biome == .aquatic else { return onlyBiome(.aquatic) }
            let anubiasCount = instance.plants.filter { $0.speciesID == "anubias" && $0.stage != .withered }.count
            if anubiasCount < 1 { return needPlant("anubias") }
            if instance.humidity < 65 { return (false, TerrariumL10n.t("elig.need_oxygen_min", ["val": "65"])) }
            return eligOK()
        case .bettaFish:
            guard instance.biome == .aquatic else { return onlyBiome(.aquatic) }
            let lotusCount = instance.plants.filter { $0.speciesID == "lotus" && $0.stage != .withered }.count
            if lotusCount < 1 { return needPlant("lotus") }
            if instance.temperature < 24 { return (false, TerrariumL10n.t("elig.need_water_temp_min", ["val": "24"])) }
            if instance.humidity < 72 { return (false, TerrariumL10n.t("elig.need_oxygen_min", ["val": "72"])) }
            return eligOK()
        case .crayfish:
            guard instance.biome == .aquatic else { return onlyBiome(.aquatic) }
            let aquaticPlants = instance.plants.filter { ($0.speciesID == "marimo" || $0.speciesID == "anubias" || $0.speciesID == "lotus") && $0.stage != .withered }.count
            if !instance.enabledDecorIDs.contains("aquatic_bubble_rock") { return needDecor("aquatic_bubble_rock") }
            if !instance.enabledDecorIDs.contains("aquatic_castle") { return needDecor("aquatic_castle") }
            if aquaticPlants < 1 { return (false, TerrariumL10n.t("elig.need_any_aquatic_plant", ["count": "1"])) }
            return eligOK()
        case .corydoras:
            guard instance.biome == .aquatic else { return onlyBiome(.aquatic) }
            if !instance.enabledDecorIDs.contains("aquatic_bamboo_tube") { return needDecor("aquatic_bamboo_tube") }
            if !instance.enabledDecorIDs.contains("aquatic_driftwood") { return needDecor("aquatic_driftwood") }
            if instance.humidity < 60 { return (false, TerrariumL10n.t("elig.need_oxygen_min", ["val": "60"])) }
            return eligOK()
        case .otoCatfish:
            guard instance.biome == .aquatic else { return onlyBiome(.aquatic) }
            let valCount = instance.plants.filter { $0.speciesID == "vallisneria" && $0.stage != .withered }.count
            if !instance.enabledDecorIDs.contains("aquatic_seiryu_stone") { return needDecor("aquatic_seiryu_stone") }
            if valCount < 1 { return needPlant("vallisneria") }
            if instance.humidity < 65 { return (false, TerrariumL10n.t("elig.need_oxygen_min", ["val": "65"])) }
            return eligOK()
        case .crystalShrimp:
            guard instance.biome == .aquatic else { return onlyBiome(.aquatic) }
            let ludCount = instance.plants.filter { $0.speciesID == "red_ludwigia" && $0.stage != .withered }.count
            if !instance.enabledDecorIDs.contains("aquatic_bamboo_tube") { return needDecor("aquatic_bamboo_tube") }
            if ludCount < 1 { return needPlant("red_ludwigia") }
            if instance.humidity < 72 { return (false, TerrariumL10n.t("elig.need_oxygen_min", ["val": "72"])) }
            return eligOK()
        case .clownfish:
            guard instance.biome == .reef else { return onlyBiome(.reef) }
            let hasAnemone = instance.plants.contains { $0.speciesID == "coral_anemone" && $0.stage != .withered }
            if !hasAnemone && !instance.enabledDecorIDs.contains("reef_live_rock") {
                return needDecor("reef_live_rock")
            }
            return eligOK()
        case .starfish:
            guard instance.biome == .reef else { return onlyBiome(.reef) }
            if !instance.enabledDecorIDs.contains("reef_sand_shells") && !instance.enabledDecorIDs.contains("reef_live_rock") {
                return needDecor("reef_sand_shells")
            }
            if instance.humidity < 60 { return (false, TerrariumL10n.t("elig.need_oxygen_min", ["val": "60"])) }
            return eligOK()
        case .cleanerShrimp:
            guard instance.biome == .reef else { return onlyBiome(.reef) }
            if !instance.enabledDecorIDs.contains("reef_live_rock") { return needDecor("reef_live_rock") }
            return eligOK()
        case .blueTang:
            guard instance.biome == .reef else { return onlyBiome(.reef) }
            if !instance.enabledDecorIDs.contains("reef_wavemaker") { return needDecor("reef_wavemaker") }
            if !instance.enabledDecorIDs.contains("reef_live_rock") { return needDecor("reef_live_rock") }
            if instance.humidity < 75 { return (false, TerrariumL10n.t("elig.need_oxygen_min", ["val": "75"])) }
            return eligOK()
        case .seahorse:
            guard instance.biome == .reef else { return onlyBiome(.reef) }
            let seafanCount = instance.plants.filter { $0.speciesID == "coral_seafan" && $0.stage != .withered }.count
            if seafanCount < 1 { return needPlant("coral_seafan") }
            return eligOK()
        case .hermitCrab:
            guard instance.biome == .reef else { return onlyBiome(.reef) }
            if !instance.enabledDecorIDs.contains("reef_sand_shells") && !instance.enabledDecorIDs.contains("reef_coral_cave") {
                return needDecor("reef_sand_shells")
            }
            return eligOK()
        }
    }

    /// 性格好感度被动特技：单只饥饿折减倍率
    public static func critterHungerMultiplier(for critter: CritterPersistentState) -> Double {
        let stage = TerrariumConfig.affinityStage(for: critter.affinity)
        guard stage >= .close else { return 1.0 }
        let perk = TerrariumConfig.personalityPerk(for: critter.personality)
        switch (perk, stage) {
        case (.thrifty, .soulmate): return 0.80
        case (.thrifty, _): return 0.90
        case (.charming, _): return 0.90
        case (.energetic, _): return 1.00
        }
    }

    /// 性格好感度被动特技：全缸在缸生物生态产点加速总和（上限 +25%）
    public static func tankEcoSpeedBoost(for critters: [CritterPersistentState]) -> Double {
        var total = 0.0
        for c in critters where (c.residency == .resident || c.residency == .visitor) {
            let stage = TerrariumConfig.affinityStage(for: c.affinity)
            guard stage >= .close else { continue }
            let perk = TerrariumConfig.personalityPerk(for: c.personality)
            switch (perk, stage) {
            case (.energetic, .soulmate): total += 0.10
            case (.energetic, _): total += 0.05
            case (.charming, .soulmate): total += 0.05
            default: break
            }
        }
        return min(0.25, total)
    }

    /// 拆缸退点核算：按 75% 造景折旧退还本缸购置原价 + 缸内已解锁摆件/温控器材/已领养生物的花费（初始免费缸购置价为 0）
    public static func refundEcoPoints(for container: TerrariumContainer) -> Int {
        let inst = container.instance
        var rawTotal = container.purchasedCost

        let decorCatalog = TerrariumConfig.decorCatalog(for: inst.biome)
        for decorID in inst.unlockedDecorIDs {
            rawTotal += decorCatalog.first(where: { $0.id == decorID })?.cost ?? 0
        }

        let critterCatalog = TerrariumConfig.critterShopCatalog(for: inst.biome)
        for c in inst.critters {
            rawTotal += critterCatalog.first(where: { $0.kind == c.kind })?.cost ?? 0
        }

        if inst.hasHeatLamp {
            rawTotal += TerrariumConfig.heatLampCost
        }
        if inst.hasCoolingFan {
            rawTotal += TerrariumConfig.coolingFanCost
        }
        return max(0, Int((Double(rawTotal) * TerrariumConfig.tankRefundRatio).rounded(.down)))
    }

    public static func activeFoodChainGroup(in instance: TerrariumInstanceState) -> FoodChainGroup? {
        guard let first = instance.critters.first(where: { $0.residency == .resident || $0.residency == .visitor }) else {
            return nil
        }
        return TerrariumConfig.foodChainGroup(for: first.kind)
    }

    /// 规范化历史存档中可能存在的食物链混养冲突（如旧档中半月斗鱼与鱼虾同缸）：保留斗鱼（高阶专属），将其余冲突物种温和转入生物仓 .stored
    @discardableResult
    public static func normalizeFoodChainCompatibility(instance: inout TerrariumInstanceState) -> [CritterKind] {
        let active = instance.critters.filter { $0.residency == .resident || $0.residency == .visitor }
        guard active.count > 1 else { return [] }

        let targetGroup: FoodChainGroup
        if active.contains(where: { $0.kind == .bettaFish }) {
            targetGroup = .aquaticBetta
        } else {
            targetGroup = TerrariumConfig.foodChainGroup(for: active[0].kind)
        }

        var movedOut: [CritterKind] = []
        for idx in instance.critters.indices {
            let item = instance.critters[idx]
            guard item.residency == .resident || item.residency == .visitor else { continue }
            if TerrariumConfig.foodChainGroup(for: item.kind) != targetGroup {
                instance.critters[idx].residency = .stored
                movedOut.append(item.kind)
            }
        }
        return movedOut
    }

    /// 将已购买物种（或新购物种）放入生态箱，并自动将食物链冲突物种温柔移入生物仓 (.stored)
    @discardableResult
    public static func placeOrSwapCritter(
        kind: CritterKind,
        instance: inout TerrariumInstanceState,
        spawnCoord: GridCoord = GridCoord(col: 1, row: 5)
    ) -> [CritterKind] {
        var swappedOut: [CritterKind] = []
        for idx in instance.critters.indices {
            let existing = instance.critters[idx]
            if existing.kind != kind,
               (existing.residency == .resident || existing.residency == .visitor),
               !TerrariumConfig.areCompatibleInSameTank(existing.kind, kind) {
                instance.critters[idx].residency = .stored
                swappedOut.append(existing.kind)
            }
        }

        if let existingIdx = instance.critters.firstIndex(where: { $0.kind == kind }) {
            let nicheOK = critterUnlockEligibility(kind: kind, instance: instance).eligible
            instance.critters[existingIdx].residency = nicheOK ? .resident : .hidden
        } else {
            instance.critters.append(
                CritterPersistentState(
                    kind: kind,
                    residency: .resident,
                    mealsEaten: 1,
                    hunger: 35.0,
                    coord: spawnCoord
                )
            )
        }
        return swappedOut
    }

    /// 评估生态位：维护已拥有物种的隐匿与复出（购买由生态点商店触发，不再免费自动刷出未购买动物）
    @discardableResult
    public static func evaluateCritterEcology(instance: inout TerrariumInstanceState) -> (arrived: [CritterKind], settled: [CritterKind]) {
        normalizeFoodChainCompatibility(instance: &instance)

        // 更新已放养动物的隐匿与复出（手动收起至生物仓 .stored 的保持不动）
        for idx in instance.critters.indices {
            let kind = instance.critters[idx].kind
            let nicheOK = critterUnlockEligibility(kind: kind, instance: instance).eligible
            if (instance.critters[idx].residency == .resident || instance.critters[idx].residency == .visitor) && !nicheOK {
                instance.critters[idx].residency = .hidden
            } else if instance.critters[idx].residency == .hidden && nicheOK {
                // 复出前若与当前在缸物种食物链冲突，则先转入生物仓待命
                if let activeGroup = activeFoodChainGroup(in: instance),
                   TerrariumConfig.foodChainGroup(for: kind) != activeGroup {
                    instance.critters[idx].residency = .stored
                } else {
                    instance.critters[idx].residency = .resident
                }
            }
        }

        return ([], [])
    }

    public static func applyWeatherEvent(
        _ event: WeatherEventDefinition,
        to instance: inout TerrariumInstanceState,
        now: Date = Date(),
        nextDelay: TimeInterval? = nil
    ) {
        instance.atmosphere = event.atmosphere
        instance.weatherCooldownEndAt = now.addingTimeInterval(TerrariumConfig.weatherEventDurationSeconds)
        if !instance.isSleeping {
            instance.temperature = clampTemp(instance.temperature + event.tempDelta)
            instance.humidity = clampHumidity(instance.humidity + event.humidityDelta)
            if event.humidityDelta > 0 {
                instance.mistDewBoostSeconds = max(instance.mistDewBoostSeconds, 180.0)
            }
        }
        instance.nextWeatherEventAt = now.addingTimeInterval(nextDelay ?? nextWeatherEventDelay())
    }

    public static func updatePlants(instance: inout TerrariumInstanceState, dt: TimeInterval) {
        for idx in instance.plants.indices {
            var p = instance.plants[idx]
            if p.stage == .withered { continue }
            let isDesertPlant = (instance.biome == .sand
                || p.speciesID == "succulent" || p.speciesID == "cactus" || p.speciesID == "aloe"
                || p.speciesID == "lithops" || p.speciesID == "agave")
            let isRainforestPlant = (!isDesertPlant && (instance.biome == .rainforest
                || p.speciesID == "monstera" || p.speciesID == "bromeliad" || p.speciesID == "orchid"
                || p.speciesID == "pitcher_plant" || p.speciesID == "calathea"))
            let isAquaticPlant = (!isDesertPlant && !isRainforestPlant && (instance.biome == .aquatic
                || p.speciesID == "marimo" || p.speciesID == "anubias" || p.speciesID == "lotus"
                || p.speciesID == "vallisneria" || p.speciesID == "red_ludwigia"))
            let isReefCoral = (!isDesertPlant && !isRainforestPlant && !isAquaticPlant && (instance.biome == .reef
                || p.speciesID.hasPrefix("coral_")))
            let isUnhealthy: Bool
            if isDesertPlant {
                isUnhealthy = (instance.humidity >= 80)
            } else if isRainforestPlant {
                isUnhealthy = (instance.humidity < 45)
            } else if isReefCoral {
                let sal = instance.salinity ?? TerrariumConfig.defaultReefSalinity
                isUnhealthy = (instance.humidity < 45 || !TerrariumConfig.optimalSalinityRange.contains(sal))
            } else if isAquaticPlant {
                isUnhealthy = (instance.humidity < 40)
            } else {
                isUnhealthy = (instance.humidity < 35)
            }

            if isUnhealthy {
                p.wiltSeconds += dt
                p.dewLevel = 0
                if p.wiltSeconds >= TerrariumConfig.plantWitherThresholdSeconds {
                    p.stage = .withered
                } else if p.wiltSeconds >= TerrariumConfig.plantWiltThresholdSeconds {
                    p.stage = .wilting
                }
            } else {
                p.wiltSeconds = max(0, p.wiltSeconds - dt * 2.0)
                p.growthSeconds += dt
                p.dewLevel = computeDewLevel(
                    speciesID: p.speciesID,
                    humidity: instance.humidity,
                    mistDewBoostSeconds: instance.mistDewBoostSeconds
                )
                if p.growthSeconds >= TerrariumConfig.plantMatureSeconds {
                    p.stage = (p.dewLevel > 0) ? .lushDew : .mature
                } else {
                    p.stage = .sprout
                }
            }
            instance.plants[idx] = p
        }
    }

    @discardableResult
    public static func attemptRandomPlantSpawn(
        instance: inout TerrariumInstanceState,
        spawnRateMultiplier: Double = 1.0,
        randomUnit: () -> Double = { Double.random(in: 0.0...1.0) },
        pickCoord: ([GridCoord]) -> GridCoord? = { $0.randomElement() }
    ) -> PlantInstance? {
        guard instance.plants.count < TerrariumConfig.maxPlantsCap else { return nil }

        let occupied = GridPathfinder.buildNonPlantableSet(
            enabledDecorIDs: instance.enabledDecorIDs,
            plants: instance.plants,
            decorOrigins: instance.decorOrigins,
            biome: instance.biome
        )
        var freeCoords: [GridCoord] = []
        for col in 0..<TerrariumConfig.gridCols {
            for row in 0..<TerrariumConfig.gridRows {
                let c = GridCoord(col: col, row: row)
                if !occupied.contains(c) {
                    freeCoords.append(c)
                }
            }
        }
        guard !freeCoords.isEmpty else { return nil }

        // 依据生态缸地貌、已有植物梯队与温湿度构建候选池：
        // 1) 特定前置/组合植物在缸内数量为 0 时，只要达标即 100% 首株必出（消除看脸阻塞）
        // 2) 首株齐备后，从所有满足条件且未满额的物种中按动态权重池随机萌发
        struct PlantCandidate {
            let speciesID: String
            let count: Int
            let cap: Int
            let weight: Double
            let baseProb: Double
        }

        func countOf(_ id: String) -> Int {
            instance.plants.filter { $0.speciesID == id && $0.stage != .withered }.count
        }

        let hasWoodBoost: Bool
        var candidates: [PlantCandidate] = []

        switch instance.biome {
        case .meadow:
            hasWoodBoost = instance.enabledDecorIDs.contains("driftwood")
            let mossCount = countOf("moss")
            let fernCount = countOf("fern")
            let effectiveTemp = instance.enabledDecorIDs.contains("boulder") ? (instance.temperature - 1) : instance.temperature

            if instance.humidity >= 45 {
                candidates.append(PlantCandidate(speciesID: "moss", count: mossCount, cap: TerrariumConfig.maxPlantsCap, weight: 1.4, baseProb: 0.24))
            }
            if mossCount >= 1 && instance.humidity >= 58 {
                candidates.append(PlantCandidate(speciesID: "fern", count: fernCount, cap: 3, weight: 1.1, baseProb: 0.26))
            }
            if mossCount >= 1 && instance.humidity >= 62 {
                candidates.append(PlantCandidate(speciesID: "clover", count: countOf("clover"), cap: 3, weight: 1.1, baseProb: 0.26))
            }
            if mossCount >= 1 && instance.enabledDecorIDs.contains("driftwood") && instance.humidity >= 60 {
                candidates.append(PlantCandidate(speciesID: "red_shroom", count: countOf("red_shroom"), cap: 2, weight: 0.8, baseProb: 0.22))
            }
            if fernCount >= 1 && instance.enabledDecorIDs.contains("shallow_pool") && instance.humidity >= 72 {
                candidates.append(PlantCandidate(speciesID: "sundew", count: countOf("sundew"), cap: 2, weight: 0.8, baseProb: 0.22))
            }
            if effectiveTemp <= 19 && instance.humidity >= 75 {
                candidates.append(PlantCandidate(speciesID: "glow_shroom", count: countOf("glow_shroom"), cap: 2, weight: 0.75, baseProb: 0.22))
            }

        case .sand:
            hasWoodBoost = instance.enabledDecorIDs.contains("sand_wood")
            let succCount = countOf("succulent")
            let aloeCount = countOf("aloe")

            if instance.humidity <= 55 {
                candidates.append(PlantCandidate(speciesID: "succulent", count: succCount, cap: TerrariumConfig.maxPlantsCap, weight: 1.4, baseProb: 0.22))
            }
            if succCount >= 1 && (28...55).contains(instance.humidity) {
                candidates.append(PlantCandidate(speciesID: "aloe", count: aloeCount, cap: 2, weight: 1.0, baseProb: 0.25))
            }
            if succCount >= 1 && instance.temperature >= 25 && instance.humidity <= 50 {
                candidates.append(PlantCandidate(speciesID: "cactus", count: countOf("cactus"), cap: 2, weight: 0.9, baseProb: 0.24))
            }
            if succCount >= 1 && instance.humidity <= 45 {
                candidates.append(PlantCandidate(speciesID: "lithops", count: countOf("lithops"), cap: 2, weight: 0.85, baseProb: 0.22))
            }
            if aloeCount >= 1 && instance.temperature >= 25 {
                candidates.append(PlantCandidate(speciesID: "agave", count: countOf("agave"), cap: 2, weight: 0.8, baseProb: 0.22))
            }

        case .rainforest:
            hasWoodBoost = instance.enabledDecorIDs.contains("rainforest_vine")
            let monsteraCount = countOf("monstera")
            let bromeliadCount = countOf("bromeliad")

            if instance.humidity >= 60 {
                candidates.append(PlantCandidate(speciesID: "monstera", count: monsteraCount, cap: TerrariumConfig.maxPlantsCap, weight: 1.4, baseProb: 0.24))
            }
            if monsteraCount >= 1 && instance.humidity >= 70 {
                candidates.append(PlantCandidate(speciesID: "bromeliad", count: bromeliadCount, cap: 3, weight: 1.1, baseProb: 0.28))
            }
            if monsteraCount >= 1 && instance.temperature >= 24 && instance.humidity >= 74 {
                candidates.append(PlantCandidate(speciesID: "orchid", count: countOf("orchid"), cap: 2, weight: 0.85, baseProb: 0.24))
            }
            if monsteraCount >= 1 && instance.humidity >= 74 {
                candidates.append(PlantCandidate(speciesID: "pitcher_plant", count: countOf("pitcher_plant"), cap: 2, weight: 0.8, baseProb: 0.22))
            }
            if bromeliadCount >= 1 && instance.humidity >= 68 {
                candidates.append(PlantCandidate(speciesID: "calathea", count: countOf("calathea"), cap: 2, weight: 0.9, baseProb: 0.24))
            }

        case .aquatic:
            hasWoodBoost = instance.enabledDecorIDs.contains("aquatic_driftwood")
            let marimoCount = countOf("marimo")
            let anubiasCount = countOf("anubias")

            if instance.humidity >= 55 {
                candidates.append(PlantCandidate(speciesID: "marimo", count: marimoCount, cap: TerrariumConfig.maxPlantsCap, weight: 1.4, baseProb: 0.24))
            }
            if marimoCount >= 1 && instance.humidity >= 65 {
                candidates.append(PlantCandidate(speciesID: "anubias", count: anubiasCount, cap: 3, weight: 1.1, baseProb: 0.28))
            }
            if marimoCount >= 1 && instance.humidity >= 60 {
                candidates.append(PlantCandidate(speciesID: "vallisneria", count: countOf("vallisneria"), cap: 3, weight: 1.0, baseProb: 0.24))
            }
            if marimoCount >= 1 && instance.temperature >= 23 && instance.humidity >= 72 {
                candidates.append(PlantCandidate(speciesID: "lotus", count: countOf("lotus"), cap: 2, weight: 0.85, baseProb: 0.24))
            }
            if anubiasCount >= 1 && instance.temperature >= 23 && instance.humidity >= 70 {
                candidates.append(PlantCandidate(speciesID: "red_ludwigia", count: countOf("red_ludwigia"), cap: 2, weight: 0.8, baseProb: 0.22))
            }

        case .reef:
            hasWoodBoost = instance.enabledDecorIDs.contains("reef_live_rock")
            let zoaCount = countOf("coral_zoanthid")
            let sal = instance.salinity ?? TerrariumConfig.defaultReefSalinity
            let isSalIdeal = (32.5...36.0).contains(sal)

            if instance.humidity >= 55 && (31.0...38.0).contains(sal) {
                candidates.append(PlantCandidate(speciesID: "coral_zoanthid", count: zoaCount, cap: TerrariumConfig.maxPlantsCap, weight: 1.4, baseProb: 0.24))
            }
            if instance.enabledDecorIDs.contains("reef_live_rock") && isSalIdeal && instance.humidity >= 75 {
                candidates.append(PlantCandidate(speciesID: "coral_acropora", count: countOf("coral_acropora"), cap: 3, weight: 1.0, baseProb: 0.26))
            }
            if zoaCount >= 1 && (24...27).contains(instance.temperature) {
                candidates.append(PlantCandidate(speciesID: "coral_brain", count: countOf("coral_brain"), cap: 2, weight: 0.9, baseProb: 0.24))
            }
            if zoaCount >= 1 && instance.humidity >= 70 {
                candidates.append(PlantCandidate(speciesID: "coral_anemone", count: countOf("coral_anemone"), cap: 2, weight: 0.95, baseProb: 0.26))
            }
            if instance.enabledDecorIDs.contains("reef_wavemaker") && isSalIdeal {
                candidates.append(PlantCandidate(speciesID: "coral_seafan", count: countOf("coral_seafan"), cap: 2, weight: 0.85, baseProb: 0.24))
            }
        }

        guard !candidates.isEmpty else { return nil }

        let chosen: PlantCandidate
        let isGuaranteedFirstSpawn: Bool
        if let firstMissing = candidates.first(where: { $0.count == 0 }) {
            chosen = firstMissing
            isGuaranteedFirstSpawn = true
        } else {
            let pool = candidates.filter { $0.count < $0.cap }
            guard !pool.isEmpty else { return nil }
            let totalWeight = pool.reduce(0.0) { $0 + $1.weight }
            var roll = randomUnit() * totalWeight
            var picked = pool[0]
            for item in pool {
                roll -= item.weight
                if roll <= 0 {
                    picked = item
                    break
                }
            }
            chosen = picked
            isGuaranteedFirstSpawn = false
        }

        let candidateSpecies = chosen.speciesID
        let baseProb = chosen.baseProb

        let woodMult = hasWoodBoost ? 1.5 : 1.0
        var extraSpawnMult = 1.0
        switch instance.biome {
        case .meadow:
            if (candidateSpecies == "glow_shroom" || candidateSpecies == "red_shroom") && instance.enabledDecorIDs.contains("meadow_mushroom_log") {
                extraSpawnMult = 1.40
            }
        case .sand:
            if instance.enabledDecorIDs.contains("sand_rib_arch") {
                extraSpawnMult = 1.25
            }
        case .rainforest:
            if instance.enabledDecorIDs.contains("rainforest_slate_ledge") {
                extraSpawnMult = 1.30
            }
        case .aquatic:
            if instance.enabledDecorIDs.contains("aquatic_bamboo_tube") {
                extraSpawnMult = 1.20
            }
        case .reef:
            if instance.enabledDecorIDs.contains("reef_giant_clam") {
                extraSpawnMult = 1.20
            }
        }
        let densityFactor = 1.0 - Double(instance.plants.count) / Double(TerrariumConfig.maxPlantsCap)
        let prob = isGuaranteedFirstSpawn
            ? 1.0
            : min(1.0, max(0.0, baseProb * woodMult * extraSpawnMult * spawnRateMultiplier * (instance.plants.isEmpty ? 1.0 : densityFactor)))

        guard randomUnit() <= prob, let chosenCoord = pickCoord(freeCoords) else {
            return nil
        }

        let newPlant = PlantInstance(
            speciesID: candidateSpecies,
            coord: chosenCoord,
            stage: .sprout,
            dewLevel: computeDewLevel(speciesID: candidateSpecies, humidity: instance.humidity, mistDewBoostSeconds: instance.mistDewBoostSeconds)
        )
        instance.plants.append(newPlant)
        instance.hasTriggeredColdStart = true
        return newPlant
    }

    public static func evaluateCodexUnlocks(instance: TerrariumInstanceState, alreadyUnlocked: Set<String>) -> [String] {
        var result: [String] = []

        for plant in instance.plants where plant.stage != .withered {
            if !alreadyUnlocked.contains(plant.speciesID) && !result.contains(plant.speciesID) {
                result.append(plant.speciesID)
            }
        }

        for c in instance.critters where c.residency == .resident {
            if !alreadyUnlocked.contains(c.kind.rawValue) && !result.contains(c.kind.rawValue) {
                result.append(c.kind.rawValue)
            }
        }

        if !alreadyUnlocked.contains("firefly") && TerrariumConfig.isFireflyCondition(
            biome: instance.biome,
            atmosphere: instance.atmosphere,
            humidity: instance.humidity,
            plants: instance.plants,
            enabledDecorIDs: instance.enabledDecorIDs
        ) {
            result.append("firefly")
        }

        if !alreadyUnlocked.contains("moon_moth") && TerrariumConfig.isMoonMothCondition(
            biome: instance.biome,
            atmosphere: instance.atmosphere,
            humidity: instance.humidity,
            plants: instance.plants
        ) {
            result.append("moon_moth")
        }

        if !alreadyUnlocked.contains("dragonfly") && TerrariumConfig.isDragonflyCondition(
            biome: instance.biome,
            atmosphere: instance.atmosphere,
            humidity: instance.humidity,
            plants: instance.plants,
            enabledDecorIDs: instance.enabledDecorIDs
        ) {
            result.append("dragonfly")
        }

        if !alreadyUnlocked.contains("luna_cicada") && TerrariumConfig.isLunaCicadaCondition(
            biome: instance.biome,
            atmosphere: instance.atmosphere,
            temperature: instance.temperature,
            plants: instance.plants,
            enabledDecorIDs: instance.enabledDecorIDs
        ) {
            result.append("luna_cicada")
        }

        if !alreadyUnlocked.contains("antlion_lacewing") && TerrariumConfig.isAntlionLacewingCondition(
            biome: instance.biome,
            atmosphere: instance.atmosphere,
            temperature: instance.temperature,
            humidity: instance.humidity,
            plants: instance.plants,
            enabledDecorIDs: instance.enabledDecorIDs
        ) {
            result.append("antlion_lacewing")
        }

        if !alreadyUnlocked.contains("orchid_bee") && TerrariumConfig.isOrchidBeeCondition(
            biome: instance.biome,
            atmosphere: instance.atmosphere,
            humidity: instance.humidity,
            plants: instance.plants
        ) {
            result.append("orchid_bee")
        }

        return result
    }

    /// 评估组合式成就与称号解锁，首次达成时一次性发放 +1~+3 生态点（绝不重复发点）
    @discardableResult
    public static func evaluateAchievements(data: inout TerrariumSaveData) -> [AchievementDefinition] {
        let codex = Set(data.unlockedCodexIDs)
        let biomes = Set(data.containers.map { $0.instance.biome })
        let allCritters = data.containers.flatMap { $0.instance.critters }
        let soulmateCount = allCritters.filter { TerrariumConfig.affinityStage(for: $0.affinity) == .soulmate }.count
        var already = Set(data.unlockedAchievementIDs)
        var newlyUnlocked: [AchievementDefinition] = []

        func check(_ id: String, _ condition: Bool) {
            guard condition, !already.contains(id),
                  let def = TerrariumConfig.defaultAchievements.first(where: { $0.id == id }) else { return }
            already.insert(id)
            data.unlockedAchievementIDs.append(id)
            data.ecoPoints += def.rewardPoints
            newlyUnlocked.append(def)
        }

        let baseCodexIDs = Set(TerrariumConfig.defaultCodexEntries().filter { !$0.isHiddenReef }.map { $0.id })
        let baseCodexCount = codex.intersection(baseCodexIDs).count
        let hiddenReefIDs = Set(TerrariumConfig.defaultCodexEntries().filter { $0.isHiddenReef }.map { $0.id })

        check("ach_codex_10", baseCodexCount >= 10)
        check("ach_codex_20", baseCodexCount >= 20)
        check("ach_codex_33", baseCodexCount >= 33)
        check("ach_codex_42", baseCodexCount >= 42)
        check("ach_codex_52", baseCodexCount >= 52)
        check("ach_four_biomes", Set([TerrariumBiome.meadow, .sand, .rainforest, .aquatic]).isSubset(of: biomes))
        check("ach_aerial_collector", Set(["firefly", "moon_moth", "dragonfly", "luna_cicada", "antlion_lacewing", "orchid_bee"]).isSubset(of: codex))
        check("ach_frog_chorus", Set(["tree_frog", "dart_frog", "red_eyed_frog"]).isSubset(of: codex))
        check("ach_desert_lords", Set(["sand_gecko", "sand_scorpion", "horned_toad"]).isSubset(of: codex))
        check("ach_carnivore_flora", Set(["sundew", "pitcher_plant"]).isSubset(of: codex))
        check("ach_aquatic_jewels", Set(["cherry_shrimp", "crystal_shrimp", "lotus"]).isSubset(of: codex))
        check("ach_first_soulmate", soulmateCount >= 1)
        check("ach_three_soulmates", soulmateCount >= 3)
        check("ach_skin_collector", data.unlockedFrameSkinIDs.count >= 3)
        check("ach_reef_unlock", biomes.contains(.reef))
        check("ach_reef_master", !hiddenReefIDs.isEmpty && hiddenReefIDs.isSubset(of: codex))

        return newlyUnlocked
    }
}
