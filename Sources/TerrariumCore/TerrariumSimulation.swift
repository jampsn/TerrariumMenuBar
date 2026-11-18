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

    public static func isOptimalEnvironment(temperature: Int, humidity: Int, biome: TerrariumBiome) -> Bool {
        switch biome {
        case .sand:
            return (24...32).contains(temperature) && (25...50).contains(humidity)
        case .rainforest:
            return (23...29).contains(temperature) && (65...88).contains(humidity)
        case .aquatic:
            return (22...28).contains(temperature) && humidity >= 60
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
        for p in instance.plants where p.stage != .withered {
            if p.speciesID == "moss" { floraReduction += 0.03 }
            else if p.speciesID == "fern" || p.speciesID == "clover" || p.speciesID == "monstera" || p.speciesID == "bromeliad" || p.speciesID == "orchid" || p.speciesID == "marimo" || p.speciesID == "anubias" || p.speciesID == "lotus" {
                floraReduction += 0.05
            }
        }
        floraReduction = min(0.40, floraReduction)

        var decorReduction = 0.0
        if instance.biome == .meadow && instance.enabledDecorIDs.contains("shallow_pool") {
            decorReduction = 0.20
        } else if instance.biome == .rainforest && instance.enabledDecorIDs.contains("rainforest_waterfall") {
            decorReduction = 0.25
        } else if instance.biome == .aquatic && instance.enabledDecorIDs.contains("aquatic_bubble_rock") {
            decorReduction = 0.30
        }
        let retention = max(0.40, 1.0 - floraReduction - decorReduction)
        return TerrariumConfig.baseEvaporationPerHour * tempFactor * biomeFactor * thermalEvapFactor * retention
    }

    public static func computeDewLevel(speciesID: String, humidity: Int, mistDewBoostSeconds: TimeInterval) -> Int {
        guard speciesID != "succulent", speciesID != "cactus", speciesID != "aloe",
              speciesID != "marimo", speciesID != "anubias", speciesID != "lotus" else { return 0 }
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

        for idx in data.containers.indices {
            var inst = data.containers[idx].instance
            let summary = advanceInstance(
                instance: &inst,
                ecoPoints: &pointsBuffer,
                unlockedCodexIDs: &codexBuffer,
                elapsedSeconds: cappedElapsed,
                now: now,
                localOutdoorTempC: data.lastKnownLocalTempC,
                tankSlotIndex: idx
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
        tankSlotIndex: Int = 0
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

            // A. 喷水露珠与玻璃水雾 / 鱼缸藻垢按舒缓长周期渐变（彻底避免刚擦完瞬间再起雾/生藻）
            if instance.mistDewBoostSeconds > 0 {
                instance.mistDewBoostSeconds = max(0, instance.mistDewBoostSeconds - dt)
            }
            if instance.biome == .aquatic {
                // 碧波鱼缸：每 ~2 小时才逐渐生满薄藻垢，无需频繁除藻
                instance.glassFogLevel = min(1.0, instance.glassFogLevel + dt / TerrariumConfig.aquaticAlgaeAccumulationSeconds)
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
                let baseInterval = isOptimalEnvironment(temperature: instance.temperature, humidity: instance.humidity, biome: instance.biome)
                    ? TerrariumConfig.ecoPointOptimalIntervalSeconds
                    : TerrariumConfig.ecoPointBaseIntervalSeconds
                let ecoBoost = tankEcoSpeedBoost(for: instance.critters)
                let slotEfficiency = TerrariumConfig.tankEfficiencyMultiplier(slotIndex: tankSlotIndex)
                let interval = baseInterval / max(0.35, slotEfficiency * (1.0 + ecoBoost))
                instance.accumulatedEcoSeconds += dt
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
                    if let spawned = attemptRandomPlantSpawn(instance: &instance) {
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

            // F. 在缸动物饥饿累积与离线代偿进食（严禁生物仓 .stored 偷吃；计入好感度减饥饿特技）
            for idx in instance.critters.indices where (instance.critters[idx].residency == .resident || instance.critters[idx].residency == .visitor) {
                let kind = instance.critters[idx].kind
                let hungerMult = critterHungerMultiplier(for: instance.critters[idx])
                let rate = TerrariumConfig.hungerRatePerHour(for: kind) * hungerMult
                instance.critters[idx].hunger = min(100.0, instance.critters[idx].hunger + rate * (dt / 3600.0))

                if elapsedSeconds > 120.0 && instance.foodBowlPortions > 0 && instance.critters[idx].hunger >= 55.0 {
                    instance.foodBowlPortions -= 1
                    instance.critters[idx].hunger = max(0.0, instance.critters[idx].hunger - 45.0)
                    instance.critters[idx].mealsEaten += 1
                    instance.critters[idx].lastFedRewardAt = now
                    let mealPts = 1
                    earnedPoints += mealPts
                    ecoPoints += mealPts

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

        switch kind {
        case .snail:
            guard instance.biome == .meadow else { return (false, "仅限温润苔原缸") }
            if mossCount < 1 { return (false, "需苔藓≥1") }
            if instance.humidity < 45 { return (false, "需湿度≥45%") }
            return (true, "条件已达标")
        case .pillBug:
            guard instance.biome == .meadow else { return (false, "仅限温润苔原缸") }
            if !instance.enabledDecorIDs.contains("driftwood") { return (false, "需摆放腐殖沉木") }
            if mossCount < 1 { return (false, "需苔藓≥1") }
            return (true, "条件已达标")
        case .rhinoBeetle:
            guard instance.biome == .meadow else { return (false, "仅限温润苔原缸") }
            if !instance.enabledDecorIDs.contains("driftwood") { return (false, "需摆放腐殖沉木") }
            if fernCount < 1 { return (false, "需卷叶蕨≥1") }
            if instance.humidity < 55 { return (false, "需湿度≥55%") }
            return (true, "条件已达标")
        case .treeFrog:
            guard instance.biome == .meadow else { return (false, "仅限温润苔原缸") }
            if !instance.enabledDecorIDs.contains("shallow_pool") { return (false, "需摆放溪石浅水洼") }
            if fernCount < 1 { return (false, "需卷叶蕨≥1") }
            if instance.humidity < 55 { return (false, "需湿度≥55%") }
            return (true, "条件已达标")
        case .amberBeetle:
            guard instance.biome == .sand else { return (false, "仅限暖阳沙地缸") }
            if !instance.enabledDecorIDs.contains("sand_pebbles") { return (false, "需摆放暖阳卵石滩") }
            if succulentCount < 1 { return (false, "需多肉≥1") }
            return (true, "条件已达标")
        case .scarab:
            guard instance.biome == .sand else { return (false, "仅限暖阳沙地缸") }
            if cactusCount < 1 { return (false, "需金琥仙人球≥1") }
            if aloeCount < 1 { return (false, "需星点芦荟≥1") }
            if instance.temperature < 27 { return (false, "需温度≥27°C(可开暖灯)") }
            if instance.humidity > 42 { return (false, "需湿度≤42%") }
            return (true, "条件已达标")
        case .sandGecko:
            guard instance.biome == .sand else { return (false, "仅限暖阳沙地缸") }
            let sandPlants = succulentCount + aloeCount + cactusCount
            if !instance.enabledDecorIDs.contains("sand_rock") { return (false, "需摆放风蚀红砂岩") }
            if sandPlants < 2 { return (false, "需沙地植物≥2") }
            if instance.temperature < 24 { return (false, "需温度≥24°C") }
            return (true, "条件已达标")
        case .leafInsect:
            guard instance.biome == .rainforest else { return (false, "仅限热带雨林缸") }
            if !instance.enabledDecorIDs.contains("rainforest_bark") { return (false, "需摆放朽木树洞") }
            if succinctPlants.monsteraCount < 1 { return (false, "需龟背竹≥1") }
            if instance.humidity < 65 { return (false, "需湿度≥65%") }
            return (true, "条件已达标")
        case .herculesBeetle:
            guard instance.biome == .rainforest else { return (false, "仅限热带雨林缸") }
            if !instance.enabledDecorIDs.contains("rainforest_bark") { return (false, "需摆放朽木树洞") }
            if succinctPlants.orchidCount < 1 { return (false, "需热带兰花≥1") }
            if instance.temperature < 24 { return (false, "需温度≥24°C") }
            return (true, "条件已达标")
        case .chameleon:
            guard instance.biome == .rainforest else { return (false, "仅限热带雨林缸") }
            if !instance.enabledDecorIDs.contains("rainforest_vine") { return (false, "需摆放藤蔓攀爬架") }
            if succinctPlants.monsteraCount + succinctPlants.bromeliadCount < 2 { return (false, "需龟背竹/凤梨≥2") }
            if instance.temperature < 25 { return (false, "需温度≥25°C(可开暖灯)") }
            if instance.humidity < 70 { return (false, "需湿度≥70%") }
            return (true, "条件已达标")
        case .cherryShrimp:
            guard instance.biome == .aquatic else { return (false, "仅限碧波鱼缸") }
            let marimoCount = instance.plants.filter { $0.speciesID == "marimo" && $0.stage != .withered }.count
            if !instance.enabledDecorIDs.contains("aquatic_castle") { return (false, "需摆放陶瓷躲避屋") }
            if marimoCount < 1 { return (false, "需莫斯藻球≥1") }
            return (true, "条件已达标")
        case .neonTetra:
            guard instance.biome == .aquatic else { return (false, "仅限碧波鱼缸") }
            let anubiasCount = instance.plants.filter { $0.speciesID == "anubias" && $0.stage != .withered }.count
            if anubiasCount < 1 { return (false, "需皇冠水草≥1") }
            if instance.humidity < 65 { return (false, "需溶氧≥65%") }
            return (true, "条件已达标")
        case .bettaFish:
            guard instance.biome == .aquatic else { return (false, "仅限碧波鱼缸") }
            let lotusCount = instance.plants.filter { $0.speciesID == "lotus" && $0.stage != .withered }.count
            if lotusCount < 1 { return (false, "需迷你睡莲≥1") }
            if instance.temperature < 24 { return (false, "需水温≥24°C") }
            if instance.humidity < 72 { return (false, "需溶氧≥72%") }
            return (true, "条件已达标")
        case .crayfish:
            guard instance.biome == .aquatic else { return (false, "仅限碧波鱼缸") }
            let aquaticPlants = instance.plants.filter { ($0.speciesID == "marimo" || $0.speciesID == "anubias" || $0.speciesID == "lotus") && $0.stage != .withered }.count
            if !instance.enabledDecorIDs.contains("aquatic_bubble_rock") { return (false, "需摆放冒泡火山石") }
            if !instance.enabledDecorIDs.contains("aquatic_castle") { return (false, "需摆放陶瓷躲避屋") }
            if aquaticPlants < 1 { return (false, "需任意水草≥1") }
            return (true, "条件已达标")
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
            let isDesertPlant = (p.speciesID == "succulent" || p.speciesID == "cactus" || p.speciesID == "aloe")
            let isRainforestPlant = (p.speciesID == "monstera" || p.speciesID == "bromeliad" || p.speciesID == "orchid")
            let isAquaticPlant = (p.speciesID == "marimo" || p.speciesID == "anubias" || p.speciesID == "lotus")
            let isUnhealthy: Bool
            if isDesertPlant {
                isUnhealthy = (instance.humidity >= 80)
            } else if isRainforestPlant {
                isUnhealthy = (instance.humidity < 45)
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

        // 依据生态缸地貌、已有植物梯队与温湿度选取候选植物
        let candidateSpecies: String
        let baseProb: Double
        let hasWoodBoost: Bool

        switch instance.biome {
        case .meadow:
            hasWoodBoost = instance.enabledDecorIDs.contains("driftwood")
            let mossCount = instance.plants.filter { $0.speciesID == "moss" && $0.stage != .withered }.count
            let effectiveTemp = instance.enabledDecorIDs.contains("boulder") ? (instance.temperature - 1) : instance.temperature

            if mossCount == 0 {
                guard instance.humidity >= 45 else { return nil }
                candidateSpecies = "moss"
                baseProb = 1.0 // 冷启动首株破冰必萌发
            } else if effectiveTemp <= 19 && instance.humidity >= 75 {
                candidateSpecies = "glow_shroom"
                baseProb = 0.20
            } else if mossCount >= 2 && instance.humidity >= 62 && (instance.plants.filter { $0.speciesID == "fern" }.count < 3) {
                candidateSpecies = "fern"
                baseProb = 0.24
            } else if instance.humidity >= 68 && (instance.plants.filter { $0.speciesID == "clover" }.count < 3) {
                candidateSpecies = "clover"
                baseProb = 0.24
            } else if instance.humidity >= 45 {
                candidateSpecies = "moss"
                baseProb = 0.20
            } else {
                return nil
            }
        case .sand:
            hasWoodBoost = instance.enabledDecorIDs.contains("sand_wood")
            let succCount = instance.plants.filter { $0.speciesID == "succulent" && $0.stage != .withered }.count
            if succCount == 0 {
                guard instance.humidity <= 55 else { return nil }
                candidateSpecies = "succulent"
                baseProb = 1.0 // 沙地缸冷启动首株必萌发
            } else if instance.temperature >= 25 && instance.humidity <= 50 && (instance.plants.filter { $0.speciesID == "cactus" }.count < 2) {
                candidateSpecies = "cactus"
                baseProb = 0.22
            } else if (28...55).contains(instance.humidity) && (instance.plants.filter { $0.speciesID == "aloe" }.count < 2) {
                candidateSpecies = "aloe"
                baseProb = 0.24
            } else if instance.humidity <= 55 {
                candidateSpecies = "succulent"
                baseProb = 0.18
            } else {
                return nil
            }
        case .rainforest:
            hasWoodBoost = instance.enabledDecorIDs.contains("rainforest_vine")
            let monsteraCount = instance.plants.filter { $0.speciesID == "monstera" && $0.stage != .withered }.count
            if monsteraCount == 0 {
                guard instance.humidity >= 60 else { return nil }
                candidateSpecies = "monstera"
                baseProb = 1.0 // 雨林缸冷启动首株必萌发龟背竹
            } else if instance.temperature >= 24 && instance.humidity >= 75 && (instance.plants.filter { $0.speciesID == "orchid" }.count < 2) {
                candidateSpecies = "orchid"
                baseProb = 0.24
            } else if instance.humidity >= 72 && (instance.plants.filter { $0.speciesID == "bromeliad" }.count < 3) {
                candidateSpecies = "bromeliad"
                baseProb = 0.28
            } else if instance.humidity >= 60 {
                candidateSpecies = "monstera"
                baseProb = 0.20
            } else {
                return nil
            }
        case .aquatic:
            hasWoodBoost = instance.enabledDecorIDs.contains("aquatic_driftwood")
            let marimoCount = instance.plants.filter { $0.speciesID == "marimo" && $0.stage != .withered }.count
            if marimoCount == 0 {
                guard instance.humidity >= 55 else { return nil }
                candidateSpecies = "marimo"
                baseProb = 1.0 // 鱼缸冷启动首株必生莫斯藻球
            } else if instance.temperature >= 23 && instance.humidity >= 72 && (instance.plants.filter { $0.speciesID == "lotus" }.count < 2) {
                candidateSpecies = "lotus"
                baseProb = 0.24
            } else if instance.humidity >= 65 && (instance.plants.filter { $0.speciesID == "anubias" }.count < 3) {
                candidateSpecies = "anubias"
                baseProb = 0.28
            } else if instance.humidity >= 55 {
                candidateSpecies = "marimo"
                baseProb = 0.20
            } else {
                return nil
            }
        }

        let woodMult = hasWoodBoost ? 1.5 : 1.0
        let densityFactor = 1.0 - Double(instance.plants.count) / Double(TerrariumConfig.maxPlantsCap)
        let prob = min(1.0, max(0.0, baseProb * woodMult * (instance.plants.isEmpty ? 1.0 : densityFactor)))

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

        return result
    }
}
