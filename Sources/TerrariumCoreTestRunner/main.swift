import Foundation
import TerrariumCore

private var passedCount = 0
private var failedCount = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    if !condition() {
        fputs("  [FAIL] \(message) (\(file):\(line))\n", stderr)
        failedCount += 1
    }
}

private func runTest(_ name: String, _ block: () -> Void) {
    let beforeFail = failedCount
    block()
    if failedCount == beforeFail {
        passedCount += 1
        print("[PASS] \(name)")
    } else {
        print("[FAIL] \(name)")
    }
}

// MARK: - 独立多生态缸、零起点成长与食盆槽位寻路测试

TerrariumL10n.setOverrideLanguage(.zhHans)
TerrariumL10n.setOverrideTemperatureUnit(.celsius)

runTest("test_day0EmptyStart_startsWithNoPlantsCrittersOrCodex") {
    let save = TerrariumSaveData()
    let meadow = save.containers.first?.instance
    check(save.containers.count == 1, "开局应初始化 1 口温润苔原缸")
    check(meadow?.plants.isEmpty == true, "Day 0 开局植物应为空")
    check(meadow?.critters.isEmpty == true, "Day 0 开局动物应为空")
    check(meadow?.enabledDecorIDs.isEmpty == true, "Day 0 开局摆件应为空")
    check(save.unlockedCodexIDs.isEmpty, "Day 0 开局图鉴应为 0 解锁")
}

runTest("test_slowIdleEvaporation_lastsHoursWithoutFrequentMisting") {
    var inst = TerrariumInstanceState.empty(biome: .meadow)
    inst.humidity = 75
    inst.enabledDecorIDs = ["shallow_pool"]
    inst.plants = [PlantInstance(speciesID: "moss", coord: GridCoord(col: 4, row: 4), stage: .mature)]

    var pts = 0
    var codex: [String] = []
    // 挂机 1 小时，含浅水洼(-20%) + 苔藓(-3%)，蒸发应 <= 4%/h（不用频繁加水）
    TerrariumSimulation.advanceInstance(instance: &inst, ecoPoints: &pts, unlockedCodexIDs: &codex, elapsedSeconds: 3600, allowRandomSpawn: false)
    check(inst.humidity >= 70, "1 小时内有浅水洼保湿湿度降幅应 <= 5%，实际 \(inst.humidity)%")
}

runTest("test_coldStartAndVisitorSettlement_progressesFromBareSoil") {
    var save = TerrariumSaveData()
    var meadow = save.containers[0].instance
    meadow.humidity = 50 // 玩家喷水润土

    // 15 秒冷启动加速应萌发第 1 株苔藓
    let s1 = TerrariumSimulation.advanceInstance(
        instance: &meadow,
        ecoPoints: &save.ecoPoints,
        unlockedCodexIDs: &save.unlockedCodexIDs,
        elapsedSeconds: 20
    )
    check(meadow.plants.count == 1 && meadow.plants.first?.speciesID == "moss", "冷启动后应先萌发绒球苔藓")
    check(s1.newlyUnlockedCodexIDs.contains("moss"), "应解锁苔藓图鉴")

    // 达成苔藓 + 湿润门槛后，蜗牛购买条件达标（不再免费刷出未购买访客）
    meadow.foodBowlPortions = 2
    TerrariumSimulation.evaluateCritterEcology(instance: &meadow)
    check(meadow.critters.isEmpty, "改用生态点购买后，投喂不应免费白嫖生成未购买动物")
    let elig = TerrariumSimulation.critterUnlockEligibility(kind: .snail, instance: meadow)
    check(elig.eligible, "有苔藓与湿度≥45%后，蜗牛应满足购买解锁资格")
}

runTest("test_multiTerrariumIsolation_meadowAndSandAreCompletelyIndependent") {
    var save = TerrariumSaveData()
    var meadow = save.containers[0].instance
    meadow.plants = [PlantInstance(speciesID: "fern", coord: GridCoord(col: 2, row: 2), stage: .mature)]
    meadow.enabledDecorIDs = ["shallow_pool"]
    meadow.critters = [CritterPersistentState(kind: .treeFrog, residency: .resident, mealsEaten: 2, coord: GridCoord(col: 5, row: 5))]
    save.containers[0].instance = meadow

    // 再购置两口独立缸体：第二口苔原缸（证明同类型可多缸）与沙地缸
    let secondMeadow = TerrariumContainer(customName: "苔原缸 #2", instance: TerrariumInstanceState.empty(biome: .meadow))
    let sandTank = TerrariumContainer(customName: "暖阳沙地 #1", instance: TerrariumInstanceState.empty(biome: .sand))
    save.containers.append(secondMeadow)
    save.containers.append(sandTank)

    check(save.containers[1].instance.plants.isEmpty && save.containers[2].instance.plants.isEmpty, "新增第二口苔原缸与沙地缸必须完全空白独立")
    let preservedMeadow = save.containers[0].instance
    check(preservedMeadow.plants.count == 1 && preservedMeadow.critters.count == 1 && preservedMeadow.enabledDecorIDs == ["shallow_pool"], "切换后第一口苔原缸的植物、动物与摆件必须原封不动")
}

runTest("test_specialExclusiveCritters_requireSpecialPlantsAndEnvironment") {
    // 1. 月光小飞蛾必须有特殊植物 微光菇(glow_shroom) + 夜晚 + 高湿
    var meadow = TerrariumInstanceState.empty(biome: .meadow)
    meadow.atmosphere = .night
    meadow.humidity = 78
    meadow.plants = [PlantInstance(speciesID: "fern", coord: GridCoord(col: 2, row: 2), stage: .mature)]
    var unlocks = TerrariumSimulation.evaluateCodexUnlocks(instance: meadow, alreadyUnlocked: [])
    check(!unlocks.contains("moon_moth"), "没有微光菇时不应解锁月光小飞蛾")

    meadow.plants.append(PlantInstance(speciesID: "glow_shroom", coord: GridCoord(col: 3, row: 3), stage: .mature))
    unlocks = TerrariumSimulation.evaluateCodexUnlocks(instance: meadow, alreadyUnlocked: [])
    check(unlocks.contains("moon_moth"), "拥有微光菇 + 夜晚 + 高湿应解锁月光小飞蛾")

    // 2. 琉璃圣甲虫购买门槛必须拥有特殊植物 金琥仙人球(cactus) + 星点芦荟(aloe) + 暖干
    var sand = TerrariumInstanceState.empty(biome: .sand)
    sand.temperature = 28
    sand.humidity = 38
    sand.plants = [PlantInstance(speciesID: "succulent", coord: GridCoord(col: 3, row: 3), stage: .mature)]
    check(!TerrariumSimulation.critterUnlockEligibility(kind: .scarab, instance: sand).eligible, "缺少仙人球和芦荟时不应达标琉璃圣甲虫")

    sand.plants.append(PlantInstance(speciesID: "cactus", coord: GridCoord(col: 4, row: 4), stage: .mature))
    sand.plants.append(PlantInstance(speciesID: "aloe", coord: GridCoord(col: 6, row: 4), stage: .mature))
    check(TerrariumSimulation.critterUnlockEligibility(kind: .scarab, instance: sand).eligible, "仙人球 + 芦荟 + 暖干应达标琉璃圣甲虫领养条件")
}

runTest("test_mildHidingAndReturn_whenNicheDecorRemovedAndRestored") {
    var meadow = TerrariumInstanceState.empty(biome: .meadow)
    meadow.humidity = 65
    meadow.enabledDecorIDs = ["shallow_pool"]
    meadow.plants = [PlantInstance(speciesID: "fern", coord: GridCoord(col: 2, row: 2), stage: .mature)]
    meadow.critters = [CritterPersistentState(kind: .treeFrog, residency: .resident, mealsEaten: 2, coord: GridCoord(col: 5, row: 5))]

    // 收起浅水洼，树蛙应温和隐匿而不删除记录
    meadow.enabledDecorIDs = []
    TerrariumSimulation.evaluateCritterEcology(instance: &meadow)
    check(meadow.critters.first?.residency == .hidden, "移除浅水洼后树蛙应温和隐匿")

    // 放回浅水洼，树蛙立刻复出
    meadow.enabledDecorIDs = ["shallow_pool"]
    TerrariumSimulation.evaluateCritterEcology(instance: &meadow)
    check(meadow.critters.first?.residency == .resident, "放回浅水洼后树蛙应立刻复出")
}

runTest("test_foodBowlReservation_assignsDistinctAdjacentSlots") {
    let blocked = GridPathfinder.buildBlockedSet(enabledDecorIDs: ["shallow_pool", "driftwood"], plants: [])
    let path1 = GridPathfinder.findPathToFoodBowl(from: GridCoord(col: 1, row: 5), blocked: blocked, reservedSlots: [])
    check(!path1.isEmpty, "第一只动物应能寻路到食盆旁")
    let slot1 = path1.last!
    let path2 = GridPathfinder.findPathToFoodBowl(from: GridCoord(col: 8, row: 6), blocked: blocked, reservedSlots: [slot1])
    check(!path2.isEmpty, "第二只动物应能寻路到食盆另一个空槽位")
    check(path2.last != slot1, "两只动物不应挤占食盆同一格位")
}

runTest("test_settleOfflineAll_executesWithoutExclusivityConflict") {
    let past = Date().addingTimeInterval(-3600)
    var meadowInst = TerrariumInstanceState.empty(biome: .meadow, now: past)
    meadowInst.humidity = 65
    meadowInst.plants = [PlantInstance(speciesID: "moss", coord: GridCoord(col: 4, row: 4), stage: .mature)]
    let sandInst = TerrariumInstanceState.empty(biome: .sand, now: past)

    let c1 = TerrariumContainer(customName: "苔原 #1", instance: meadowInst)
    let c2 = TerrariumContainer(customName: "沙地 #1", instance: sandInst)
    var save = TerrariumSaveData(
        containers: [c1, c2],
        activeContainerID: c1.id,
        ecoPoints: 10,
        lastSavedAt: past
    )

    let summary = TerrariumSimulation.settleOfflineAll(data: &save, now: Date())
    check(summary.totalEarnedEcoPoints > 0, "多缸离线总结算应正常产出生态点")
}

// 9. 食盆最前排防遮挡净空与后方进食槽位优先断言
runTest("test_foodBowlForwardClearance_neverOccludesAndUsesRearSlots") {
    let bowl = TerrariumConfig.foodBowlCoord
    check(bowl == GridCoord(col: 9, row: 9), "食盆应固定位于沙盘最前端视觉中心 (9,9)")
    let nonPlantable = GridPathfinder.buildNonPlantableSet(enabledDecorIDs: ["shallow_pool", "sand_pebbles", "driftwood", "boulder", "sand_rock", "sand_wood"], plants: [])
    for fwd in TerrariumConfig.foodBowlForwardCoords {
        check(nonPlantable.contains(fwd), "食盆正前方格 \(fwd) 应被纳入禁种保护区")
    }

    let blocked = GridPathfinder.buildBlockedSet(enabledDecorIDs: [], plants: [])
    for fwd in TerrariumConfig.foodBowlForwardCoords {
        check(blocked.contains(fwd), "食盆正前方格 \(fwd) 应阻断小动物巡逻站位")
    }

    // 小动物位于食盆右侧时，依然优先寻路至后侧进食槽位 (9,8)/(8,9)，不阻塞正前方
    let path1 = GridPathfinder.findPathToFoodBowl(from: GridCoord(col: 10, row: 7), blocked: blocked)
    if let slot1 = path1.last {
        check(slot1.col + slot1.row < bowl.col + bowl.row, "进食槽位应严格优先选择食盆后方邻接格: got \(slot1)")
        // 若该后方槽位已被占用，第二只动物应去另一个后方槽位
        let path2 = GridPathfinder.findPathToFoodBowl(from: GridCoord(col: 7, row: 9), blocked: blocked, reservedSlots: [slot1])
        if let slot2 = path2.last {
            check(slot2 != slot1 && (slot2.col + slot2.row < bowl.col + bowl.row), "同伴占用一个后方槽位后，第二只应优先选择另一个后方槽位")
        } else {
            check(false, "第二只小动物未能找到食盆后方槽位")
        }
    } else {
        check(false, "第一只小动物未能找到食盆路径")
    }
}

// 10. 旧版 CritterPersistentState JSON 向后兼容解码 + 生态位停驻坐标断言
runTest("test_affinityCodableBackwardCompatibility_andNichePerching") {
    let legacyJSON = #"{"kind":"snail","residency":"resident","mealsEaten":2,"hunger":15.0,"coord":{"col":4,"row":5}}"#
    let decoded = try? JSONDecoder().decode(CritterPersistentState.self, from: Data(legacyJSON.utf8))
    check(decoded != nil, "旧版无 nickname/affinity/personality 字段 JSON 应无缝解码")
    check(decoded?.affinity == 0, "旧存档缺省好感度应为 0")
    check(decoded?.personality == TerrariumConfig.defaultPersonality(for: .snail), "旧存档缺省个性应匹配默认个性")

    check(TerrariumConfig.nicheSpot(for: .treeFrog, enabledDecorIDs: []) == nil, "未启用浅水洼时树蛙无水洼停驻点")
    check(TerrariumConfig.nicheSpot(for: .treeFrog, enabledDecorIDs: ["shallow_pool"]) == GridCoord(col: 8, row: 1), "启用浅水洼后树蛙应优先停驻至水洼原点格")
    check(TerrariumConfig.nicheSpot(for: .sandGecko, enabledDecorIDs: ["sand_rock"]) == GridCoord(col: 8, row: 3), "启用红砂岩后守宫应有砂岩旁晒背点")
}

// 11. 独角仙、食物链同缸互斥与摆件自由摆放断言
runTest("test_rhinoBeetle_foodChainExclusion_andDecorFreePlacement") {
    var meadow = TerrariumInstanceState.empty(biome: .meadow)
    meadow.humidity = 65
    meadow.enabledDecorIDs = ["driftwood", "shallow_pool"]
    meadow.plants = [
        PlantInstance(speciesID: "moss", coord: GridCoord(col: 0, row: 2), stage: .mature),
        PlantInstance(speciesID: "fern", coord: GridCoord(col: 6, row: 2), stage: .mature)
    ]

    check(TerrariumSimulation.critterUnlockEligibility(kind: .rhinoBeetle, instance: meadow).eligible, "腐殖沉木 + 卷叶蕨 + 高湿应解锁独角仙购买门槛")
    TerrariumSimulation.placeOrSwapCritter(kind: .snail, instance: &meadow)
    TerrariumSimulation.placeOrSwapCritter(kind: .rhinoBeetle, instance: &meadow)
    let bothInsectsActive = meadow.critters.filter { $0.residency == .resident }.map(\.kind)
    check(bothInsectsActive.contains(.snail) && bothInsectsActive.contains(.rhinoBeetle), "蜗牛与独角仙属同一微虫共生群，可同缸共存")

    // 放入捕食者绿豆树蛙 -> 自动将蜗牛与独角仙收进生物仓 (.stored)
    let swapped = TerrariumSimulation.placeOrSwapCritter(kind: .treeFrog, instance: &meadow)
    check(swapped.contains(.snail) && swapped.contains(.rhinoBeetle), "放入树蛙时应因食物链互斥自动收纳蜗牛与独角仙")
    check(meadow.critters.first(where: { $0.kind == .treeFrog })?.residency == .resident, "绿豆树蛙应进入活跃展示态")
    check(meadow.critters.first(where: { $0.kind == .rhinoBeetle })?.residency == .stored, "独角仙应被安全移入生物仓(.stored)")

    // 摆件自由摆放校验：不得超出边界、不得踩上植物或食盆保护区
    check(!GridPathfinder.canPlaceDecor(id: "driftwood", at: GridCoord(col: 9, row: 9), enabledDecorIDs: meadow.enabledDecorIDs, decorOrigins: meadow.decorOrigins, plants: meadow.plants), "3x2 沉木不得摆出边界或侵入食盆前方")
    check(GridPathfinder.canPlaceDecor(id: "driftwood", at: GridCoord(col: 1, row: 3), enabledDecorIDs: meadow.enabledDecorIDs, decorOrigins: meadow.decorOrigins, plants: meadow.plants), "合法空地应允许重新摆放沉木")

    meadow.decorOrigins["driftwood"] = GridCoord(col: 1, row: 3)
    let movedFootprint = TerrariumConfig.footprint(for: "driftwood", decorOrigins: meadow.decorOrigins)
    check(movedFootprint.contains(GridCoord(col: 1, row: 3)) && movedFootprint.contains(GridCoord(col: 3, row: 4)), "摆件移动后占地坐标应即时跟随新原点更新")
    check(TerrariumConfig.nicheSpot(for: .rhinoBeetle, enabledDecorIDs: meadow.enabledDecorIDs, decorOrigins: meadow.decorOrigins) == GridCoord(col: 2, row: 2), "生物生态位停驻点应随沉木新位置自动更新")
}

// 12. 物理温控开关（解决夜晚沙地无法到达圣甲虫 27°C）、v3->v4 存档迁移与雨林缸变色龙生态断言
runTest("test_thermalControlHeating_v3Migration_andRainforestChameleon") {
    // A. 夜晚沙地自然基线仅 21°C，开启加热灯后稳态应升至 27°C 且快速推进达标以解锁圣甲虫
    var sandNight = TerrariumInstanceState.empty(biome: .sand)
    sandNight.atmosphere = .night
    sandNight.temperature = 21
    sandNight.humidity = 38
    sandNight.plants = [
        PlantInstance(speciesID: "cactus", coord: GridCoord(col: 4, row: 4), stage: .mature),
        PlantInstance(speciesID: "aloe", coord: GridCoord(col: 5, row: 4), stage: .mature)
    ]
    check(!TerrariumSimulation.critterUnlockEligibility(kind: .scarab, instance: sandNight).eligible, "夜晚 21°C 时应暂未达到圣甲虫 27°C 门槛")

    sandNight.thermalMode = .heating
    var pts = 0
    var codex: [String] = []
    TerrariumSimulation.advanceInstance(instance: &sandNight, ecoPoints: &pts, unlockedCodexIDs: &codex, elapsedSeconds: 1200, allowRandomSpawn: false)
    check(sandNight.temperature >= 27, "开启晒背加热灯挂机 20 分钟后夜晚沙地应成功升温至 ≥27°C，实际 \(sandNight.temperature)°C")
    check(TerrariumSimulation.critterUnlockEligibility(kind: .scarab, instance: sandNight).eligible, "加热后圣甲虫应顺利达标可购")

    // B. 雨林缸植物萌发 + 变色龙与雨林昆虫食物链互斥
    var rain = TerrariumInstanceState.empty(biome: .rainforest)
    rain.humidity = 75
    rain.temperature = 26
    rain.enabledDecorIDs = ["rainforest_vine", "rainforest_bark"]
    let spawned = TerrariumSimulation.attemptRandomPlantSpawn(instance: &rain)
    check(spawned?.speciesID == "monstera", "雨林缸冷启动应优先萌发龟背竹")
    rain.plants.append(PlantInstance(speciesID: "bromeliad", coord: GridCoord(col: 6, row: 5), stage: .mature))
    check(TerrariumSimulation.critterUnlockEligibility(kind: .chameleon, instance: rain).eligible, "藤蔓+双雨林植+26°C+75%湿应解锁变色龙")

    TerrariumSimulation.placeOrSwapCritter(kind: .leafInsect, instance: &rain)
    let swapped = TerrariumSimulation.placeOrSwapCritter(kind: .chameleon, instance: &rain)
    check(swapped.contains(.leafInsect), "放入变色龙应自动将枯叶脩收起至生物仓")

    // C. v3 历史 JSON 向 v4 多容器结构无缝迁移
    let v3Meadow = TerrariumInstanceState.empty(biome: .meadow)
    let v3Data = try! JSONEncoder().encode([
        "schemaVersion": AnyCodableBox(3),
        "currentBiome": AnyCodableBox(TerrariumBiome.meadow.rawValue),
        "unlockedBiomes": AnyCodableBox([TerrariumBiome.meadow.rawValue]),
        "terrariums": AnyCodableBox([TerrariumBiome.meadow.rawValue: v3Meadow]),
        "ecoPoints": AnyCodableBox(19),
        "unlockedCodexIDs": AnyCodableBox(["moss"])
    ])
    let migrated = try? JSONDecoder().decode(TerrariumSaveData.self, from: v3Data)
    check(migrated?.schemaVersion == 5 && migrated?.containers.count == 1 && migrated?.ecoPoints == 19, "v3 存档应无损迁移至最新 v5 容器列表并保留生态点")
}

private struct AnyCodableBox: Encodable {
    private let encodeClosure: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) {
        self.encodeClosure = value.encode
    }
    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}

// 13. 拆缸退点核算（防刷点）+ 碧波鱼缸水生生态与小鱼螯虾食物链互斥断言
runTest("test_deleteTankRefund_andAquaticFishTankFoodChain") {
    // A. 碧波鱼缸冷启动长出莫斯藻球 + 樱花米虾/红绿灯鱼 vs 蓝螯虾食物链互斥
    var aquatic = TerrariumInstanceState.empty(biome: .aquatic)
    aquatic.humidity = 75
    aquatic.temperature = 25
    aquatic.enabledDecorIDs = ["aquatic_bubble_rock", "aquatic_castle"]
    aquatic.unlockedDecorIDs = ["aquatic_bubble_rock", "aquatic_castle"]
    let firstMarimo = TerrariumSimulation.attemptRandomPlantSpawn(instance: &aquatic)
    check(firstMarimo?.speciesID == "marimo", "鱼缸冷启动应萌发莫斯藻球")
    aquatic.plants.append(PlantInstance(speciesID: "anubias", coord: GridCoord(col: 5, row: 5), stage: .mature))

    check(TerrariumSimulation.critterUnlockEligibility(kind: .cherryShrimp, instance: aquatic).eligible, "有陶瓷躲避屋与莫斯藻球应达标樱花米虾")
    check(TerrariumSimulation.critterUnlockEligibility(kind: .neonTetra, instance: aquatic).eligible, "有皇冠水草与高溶氧应达标红绿灯鱼")
    check(TerrariumSimulation.critterUnlockEligibility(kind: .crayfish, instance: aquatic).eligible, "有火山石、躲避屋与水草应达标蓝螯虾")

    TerrariumSimulation.placeOrSwapCritter(kind: .cherryShrimp, instance: &aquatic)
    TerrariumSimulation.placeOrSwapCritter(kind: .neonTetra, instance: &aquatic)
    // 半月斗鱼领地独立：不可与鱼虾混养，放入斗鱼应自动收纳米虾与灯鱼
    aquatic.plants.append(PlantInstance(speciesID: "lotus", coord: GridCoord(col: 4, row: 4), stage: .mature))
    check(!TerrariumConfig.areCompatibleInSameTank(.bettaFish, .neonTetra), "斗鱼与红绿灯鱼不得同缸混养")
    check(!TerrariumConfig.areCompatibleInSameTank(.bettaFish, .cherryShrimp), "斗鱼与樱花米虾不得同缸混养")
    check(!TerrariumConfig.areCompatibleInSameTank(.bettaFish, .crayfish), "斗鱼与蓝螯虾不得同缸混养")
    let bettaSwapped = TerrariumSimulation.placeOrSwapCritter(kind: .bettaFish, instance: &aquatic)
    check(bettaSwapped.contains(.cherryShrimp) && bettaSwapped.contains(.neonTetra), "放入半月斗鱼应自动将米虾与灯鱼转入生物仓")

    // 历史混养存档平滑兼容性迁移：若旧档里同时 resident 斗鱼与灯鱼/米虾，normalize 应保留斗鱼并温柔转仓鱼虾
    aquatic.critters = [
        CritterPersistentState(kind: .cherryShrimp, residency: .resident, mealsEaten: 1, coord: GridCoord(col: 2, row: 4)),
        CritterPersistentState(kind: .neonTetra, residency: .resident, mealsEaten: 3, coord: GridCoord(col: 3, row: 3), nickname: "老灯鱼"),
        CritterPersistentState(kind: .bettaFish, residency: .resident, mealsEaten: 2, coord: GridCoord(col: 5, row: 5))
    ]
    let migrated = TerrariumSimulation.normalizeFoodChainCompatibility(instance: &aquatic)
    check(migrated == [.cherryShrimp, .neonTetra], "旧档混养迁移应温和收纳冲突的樱花米虾与红绿灯鱼")
    check(aquatic.critters.first(where: { $0.kind == .bettaFish })?.residency == .resident, "迁移后半月斗鱼应保持 resident")
    check(aquatic.critters.first(where: { $0.kind == .neonTetra })?.residency == .stored && aquatic.critters.first(where: { $0.kind == .neonTetra })?.nickname == "老灯鱼", "被收纳的红绿灯鱼应转为 .stored 且保留全部养成数据")

    // 蓝螯虾与灯鱼米虾互斥 + 拆缸退点核算
    let crayfishSwapped = TerrariumSimulation.placeOrSwapCritter(kind: .crayfish, instance: &aquatic)
    check(crayfishSwapped.contains(.bettaFish), "放入蓝螯虾应与斗鱼互斥并收纳斗鱼")

    // 睡莲水面 (gz = 38.0) 正逆向等距投影闭环校验
    let surfaceScreen = TerrariumConfig.isoToScreen(gx: 4.5, gy: 4.5, gz: TerrariumConfig.waterSurfaceGZ)
    let surfaceBack = TerrariumConfig.screenToIso(x: surfaceScreen.x, y: surfaceScreen.y, gz: TerrariumConfig.waterSurfaceGZ)
    check(Int(floor(surfaceBack.gx)) == 4 && Int(floor(surfaceBack.gy)) == 4, "水面 gz=38.0 点击反向投影应精确命中 (4,4)")

    // B. 拆缸 75% 折旧退点精准核算：含购置缸价(55) + 摆件(14+9) + 生物(10+16+25+30) + 加热棒(8) = 167 -> 75% 退 125 点
    aquatic.hasHeatLamp = true
    let container = TerrariumContainer(
        customName: "我的水草缸",
        purchasedCost: TerrariumConfig.tankPurchaseCost(for: .aquatic, existingTankCount: 1),
        instance: aquatic
    )
    let refund = TerrariumSimulation.refundEcoPoints(for: container)
    check(refund == 125, "拆缸按 75% 折旧退点应退回 125 点，实际 \(refund)")

    // 免费初始缸购置成本为 0，不能空手拆缸刷购置点
    let starterFree = TerrariumContainer(customName: "苔原缸 #1", purchasedCost: 0, instance: TerrariumInstanceState.empty(biome: .meadow))
    check(TerrariumSimulation.refundEcoPoints(for: starterFree) == 0, "初始免费空缸拆缸应退 0 点防止刷点")
}

// 14. 长周期擦雾/除藻速率验证 + 本地实测气温联动与冬季加热兜底断言
runTest("test_slowFogAlgaeRates_andLocalOutdoorTempLinkage") {
    var pts = 0
    var codex: [String] = []

    // A. 高湿苔原擦雾不应瞬间满雾，挂机 15 分钟内应仍保持轻微（<0.40）
    var meadow = TerrariumInstanceState.empty(biome: .meadow)
    meadow.humidity = 88
    meadow.glassFogLevel = 0.0
    TerrariumSimulation.advanceInstance(instance: &meadow, ecoPoints: &pts, unlockedCodexIDs: &codex, elapsedSeconds: 900, allowRandomSpawn: false)
    check(meadow.glassFogLevel < 0.40, "高湿 15 分钟内水雾应缓慢累积，不应瞬间满雾，实际 \(meadow.glassFogLevel)")

    // B. 碧波鱼缸除藻应更持久：挂机 30 分钟内藻垢应低于 0.30
    var aquatic = TerrariumInstanceState.empty(biome: .aquatic)
    aquatic.humidity = 80
    aquatic.glassFogLevel = 0.0
    TerrariumSimulation.advanceInstance(instance: &aquatic, ecoPoints: &pts, unlockedCodexIDs: &codex, elapsedSeconds: 1800, allowRandomSpawn: false)
    check(aquatic.glassFogLevel < 0.30, "鱼缸 30 分钟内藻垢应保持轻微，不应频繁除藻，实际 \(aquatic.glassFogLevel)")

    // C. 本地室外低温 (10°C) 联动 + 沙地加热灯防锁死兜底 (仍能到达 >=27°C 解锁圣甲虫)
    let coldSandNatural = TerrariumConfig.baseAmbientTemp(for: .day, biome: .sand, thermalMode: .natural, localOutdoorTempC: 10)
    let coldSandHeated = TerrariumConfig.baseAmbientTemp(for: .day, biome: .sand, thermalMode: .heating, localOutdoorTempC: 10)
    check(coldSandNatural <= 18, "室外 10°C 时沙地裸缸自然温度应联动下降，实际 \(coldSandNatural)°C")
    check(coldSandHeated >= 28, "即使室外 10°C 冬天，开启加热灯也应保障沙地升温至 ≥28°C 防锁死，实际 \(coldSandHeated)°C")

    // D. 夏季高温 (33°C) 苔原开启降温扇应可降回 <=19°C 以培育微光菇
    let hotMeadowCooled = TerrariumConfig.baseAmbientTemp(for: .day, biome: .meadow, thermalMode: .cooling, localOutdoorTempC: 33)
    check(hotMeadowCooled <= 18, "即使室外 33°C 夏天，开启降温扇应可将苔原降至 ≤18°C，实际 \(hotMeadowCooled)°C")
}

// 15. 五阶羁绊性格特技 + 经济防漏洞全检 + 鱼缸后壁喂食圈解放前景断言
runTest("test_affinityPerks_economyAntiExploits_andAquaticRearFeedingRing") {
    // A. 好感度五阶特技验证
    let snail = CritterPersistentState(kind: .snail, residency: .resident, coord: GridCoord(col: 3, row: 3), affinity: 100)
    check(TerrariumConfig.affinityStage(for: snail.affinity) == .soulmate, "好感度 100 应对应 Lv.5 挚友")
    check(abs(TerrariumSimulation.critterHungerMultiplier(for: snail) - 0.80) < 0.001, "慢性子挚友饥饿消耗应降低 20%")
    let rhino = CritterPersistentState(kind: .rhinoBeetle, residency: .resident, coord: GridCoord(col: 4, row: 4), affinity: 100)
    check(abs(TerrariumSimulation.tankEcoSpeedBoost(for: [snail, rhino]) - 0.10) < 0.001, "护木侠挚友生态共振应加速产点 +10%")

    // B. 生物仓 .stored 不得在离线结算中偷吃食盆刷点
    var pts = 0
    var codex: [String] = []
    var tank = TerrariumInstanceState.empty(biome: .meadow)
    tank.humidity = 65
    tank.foodBowlPortions = 3
    tank.critters = [CritterPersistentState(kind: .treeFrog, residency: .stored, hunger: 80.0, coord: GridCoord(col: 5, row: 5))]
    let storedSummary = TerrariumSimulation.advanceInstance(instance: &tank, ecoPoints: &pts, unlockedCodexIDs: &codex, elapsedSeconds: 3600, allowRandomSpawn: false)
    check(tank.foodBowlPortions == 3 && storedSummary.earnedEcoPoints == 0, "存放在生物仓(.stored)的生物不得在离线偷吃粮食或白嫖产点")

    // C. 全缸枯萎植物与缺氧鱼缸/干涸沙地口径防呆
    var witheredTank = TerrariumInstanceState.empty(biome: .meadow)
    witheredTank.humidity = 65
    witheredTank.plants = [PlantInstance(speciesID: "moss", coord: GridCoord(col: 2, row: 2), stage: .withered)]
    let witheredSum = TerrariumSimulation.advanceInstance(instance: &witheredTank, ecoPoints: &pts, unlockedCodexIDs: &codex, elapsedSeconds: 1800, allowRandomSpawn: false)
    check(witheredSum.earnedEcoPoints == 0, "全缸仅剩枯萎植物时不得继续自然产点")

    check(!TerrariumSimulation.isOptimalEnvironment(temperature: 25, humidity: 45, biome: .aquatic), "鱼缸溶氧不足 60% 时不得按最佳产率加速")
    check(TerrariumSimulation.isOptimalEnvironment(temperature: 25, humidity: 70, biome: .aquatic), "鱼缸 25°C 且溶氧 ≥60% 时应达成最佳产率")

    var drySandCodex = ["succulent"]
    var drySand = TerrariumInstanceState.empty(biome: .sand)
    drySand.humidity = 25 // 等于安全蒸发下限 25%，但低于 sandEcoPointMinHumidity(26%)
    drySand.plants = [PlantInstance(speciesID: "succulent", coord: GridCoord(col: 4, row: 4), stage: .mature)]
    let drySandSum = TerrariumSimulation.advanceInstance(instance: &drySand, ecoPoints: &pts, unlockedCodexIDs: &drySandCodex, elapsedSeconds: 1800, allowRandomSpawn: false)
    check(drySandSum.earnedEcoPoints == 0, "完全放任干至安全底线(25%)的沙地缸不得继续产点")

    // D. 鱼缸后壁喂食圈 (1,2) 解放前景 (9,9)..(10,10)，且鱼类优先前景侧 (2,2)/(1,3) 啄食
    let aqNonPlant = GridPathfinder.buildNonPlantableSet(enabledDecorIDs: [], plants: [], biome: .aquatic)
    check(!aqNonPlant.contains(GridCoord(col: 9, row: 9)) && !aqNonPlant.contains(GridCoord(col: 10, row: 10)), "鱼缸前景 (9,9)-(10,10) 应彻底解放用于水草造景")
    check(aqNonPlant.contains(TerrariumConfig.aquaticFeedingCoord), "鱼缸后壁喂食圈格 (1,2) 应避免长出浮水睡莲重叠")

    let aqBlocked = GridPathfinder.buildBlockedSet(enabledDecorIDs: [], plants: [], biome: .aquatic)
    let fishPath = GridPathfinder.findPathToFoodBowl(from: GridCoord(col: 6, row: 6), blocked: aqBlocked, biome: .aquatic)
    if let eatSlot = fishPath.last {
        check(eatSlot.col + eatSlot.row > TerrariumConfig.aquaticFeedingCoord.col + TerrariumConfig.aquaticFeedingCoord.row, "鱼类前往后壁喂食圈应优先停留在前景侧 (col+row > 3): got \(eatSlot)")
    } else {
        check(false, "鱼类未能寻路至后壁喂食圈")
    }

    // E. 全生物正消耗（无图鉴倒赚）与槽位阶梯涨价断言
    for biome in TerrariumBiome.allCases {
        for spec in TerrariumConfig.critterShopCatalog(for: biome) {
            check(spec.cost > TerrariumConfig.codexRewardPoints(for: spec.id), "生物「\(spec.name)」售价(\(spec.cost))必须高于图鉴返点(\(TerrariumConfig.codexRewardPoints(for: spec.id)))")
        }
    }
    check(TerrariumConfig.tankPurchaseCost(for: .aquatic, existingTankCount: 1) == 55, "第 2 口鱼缸售价应为基价 55 点")
    check(TerrariumConfig.tankPurchaseCost(for: .aquatic, existingTankCount: 2) == 70, "第 3 口起应阶梯加价 +15 点至 70 点")
    check(TerrariumConfig.tankEfficiencyMultiplier(slotIndex: 0) == 1.0 && TerrariumConfig.tankEfficiencyMultiplier(slotIndex: 1) == 0.80, "第 2 口缸产点效率应递减为 80%")
}

runTest("test_economyRebalance_offlineDecay_andNewDecorCatalog") {
    let now = Date()
    var data = TerrariumSaveData()
    data.ecoPoints = 5
    data.lastSavedAt = now.addingTimeInterval(-8.0 * 3600.0)
    data.containers[0].instance.humidity = 65
    data.containers[0].instance.temperature = 23
    data.containers[0].instance.plants = [PlantInstance(speciesID: "moss", coord: GridCoord(col: 3, row: 3), stage: .mature)]

    let summary = TerrariumSimulation.settleOfflineAll(data: &data, now: now)
    check(summary.totalEarnedEcoPoints >= 18 && summary.totalEarnedEcoPoints <= 35, "8小时离线经分段衰减后单缸产出应在健康区间(18~35点)，实际为 \(summary.totalEarnedEcoPoints)")

    // 离线进食冷却校验：刚领过进食奖励的动物在 3 小时内离线再吃不重复产点
    var mealInst = TerrariumInstanceState.empty(biome: .meadow, now: now, nextEventDelay: 1800)
    mealInst.humidity = 65
    mealInst.foodBowlPortions = 2
    mealInst.critters = [CritterPersistentState(kind: .snail, residency: .resident, mealsEaten: 1, hunger: 65.0, coord: GridCoord(col: 4, row: 4), lastFedRewardAt: now.addingTimeInterval(-600))]
    var mealPts = 0
    var mealCodex: [String] = []
    let mealSum = TerrariumSimulation.advanceInstance(instance: &mealInst, ecoPoints: &mealPts, unlockedCodexIDs: &mealCodex, elapsedSeconds: 300, now: now, allowRandomSpawn: false)
    check(mealSum.earnedEcoPoints == 0 && mealInst.critters[0].mealsEaten == 2, "冷却期内离线进食应能吃饱但不重复发放点数")

    // 新摆件目录与可穿行摆件寻路校验
    for biome in TerrariumBiome.allCases {
        check(TerrariumConfig.decorCatalog(for: biome).count == 5, "\(biome.rawValue) 应包含 5 件摆件")
    }
    let walkBlocked = GridPathfinder.buildBlockedSet(enabledDecorIDs: ["meadow_stepping_stones", "sand_rib_arch"], plants: [], biome: .meadow)
    check(!walkBlocked.contains(GridCoord(col: 5, row: 2)), "汀步石与风蚀拱应允许小动物踩踏/穿行，不得阻挡寻路")
}

runTest("test_persistenceBackupRecovery_andCorruptedIsolation") {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("terrarium_bak_test_\(UUID().uuidString)", isDirectory: true)
    let saveURL = tmpDir.appendingPathComponent("save.json")
    let persistence = TerrariumPersistence(fileURL: saveURL)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    var d1 = TerrariumSaveData()
    d1.ecoPoints = 42
    check(persistence.save(d1), "首次保存应成功")

    var d2 = d1
    d2.ecoPoints = 88
    check(persistence.save(d2), "二次保存应轮转生成 .json.bak 备份")
    check(FileManager.default.fileExists(atPath: persistence.backupURL.path), "应存在 save.json.bak 备份文件")

    // 破坏主档 save.json
    try? "{ broken json".data(using: .utf8)?.write(to: saveURL)
    let recovered = persistence.load()
    check(recovered?.ecoPoints == 42, "主档损坏时应自动从 .bak 恢复上一份有效存档(42点)，实际=\(recovered?.ecoPoints ?? -1)")
    let files = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path)) ?? []
    check(files.contains(where: { $0.hasPrefix("save.corrupted.") }), "损坏的主档应被隔离保留而非静默删除")
}

runTest("test_v030_50Codex_frameSkins_andV4Migration") {
    let entries = TerrariumConfig.defaultCodexEntries()
    let baseEntries = entries.filter { !$0.isHiddenReef }
    let reefEntries = entries.filter { $0.isHiddenReef }
    check(baseEntries.count == 52 && reefEntries.count == 11 && entries.count == 63, "基础图鉴应保持 52 项、隐藏海缸 11 项，合计 63 项，实际=\(entries.count)")
    check(Set(entries.map { $0.id }).count == 63, "63 项图鉴 ID 不可重复")

    check(TerrariumConfig.codexMilestoneTitle(unlockedCount: 5) == "🔍 探索萌新", "5 项图鉴称号应为探索萌新")
    check(TerrariumConfig.codexMilestoneTitle(unlockedCount: 10) == "🌱 生态学徒", "10 项图鉴称号应为生态学徒")
    check(TerrariumConfig.codexMilestoneTitle(unlockedCount: 20) == "🪴 箱庭园丁", "20 项图鉴称号应为箱庭园丁")
    check(TerrariumConfig.codexMilestoneTitle(unlockedCount: 33) == "🌿 博物学家", "33 项图鉴称号应为博物学家")
    check(TerrariumConfig.codexMilestoneTitle(unlockedCount: 42) == "🌟 微境守望者", "42 项图鉴称号应为微境守望者")
    check(TerrariumConfig.codexMilestoneTitle(unlockedCount: 52) == "🏆 全生态宗师", "52 项图鉴称号应为全生态宗师")

    check(TankFrameSkin.allCases.count == 6, "缸体边框皮肤应有 6 款")
    check(TankFrameSkin.classic.cost == 0 && TankFrameSkin.obsidian.cost > 0, "经典款免费，黑曜石边框应消耗点数")

    // 验证新植物与空中访客解锁
    let codex: [String] = []
    var aqInst = TerrariumInstanceState.empty(biome: .aquatic)
    aqInst.atmosphere = .day
    aqInst.humidity = 75
    aqInst.plants = [PlantInstance(speciesID: "lotus", coord: GridCoord(col: 5, row: 5), stage: .mature)]
    let unlocked = TerrariumSimulation.evaluateCodexUnlocks(instance: aqInst, alreadyUnlocked: Set(codex))
    check(unlocked.contains("dragonfly"), "水域白昼高湿且有成熟睡莲时应解锁碧波蜻蜓")
    check(unlocked.contains("lotus"), "水域存在睡莲时应解锁对应图鉴")

    // 验证 v4 无皮肤字段存档向 v5 无损迁移
    let v4Seed = TerrariumSaveData()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let v5Data = try! encoder.encode(v4Seed)
    var jsonObj = try! JSONSerialization.jsonObject(with: v5Data) as! [String: Any]
    jsonObj["schemaVersion"] = 4
    jsonObj.removeValue(forKey: "unlockedFrameSkinIDs")
    jsonObj.removeValue(forKey: "activeFrameSkinID")
    let v4Raw = try! JSONSerialization.data(withJSONObject: jsonObj)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let migrated = try! decoder.decode(TerrariumSaveData.self, from: v4Raw)
    check(migrated.unlockedFrameSkinIDs == [TankFrameSkin.classic.rawValue], "v4 旧存档迁移后应默认解锁 classic 边框")
    check(migrated.activeFrameSkinID == TankFrameSkin.classic.rawValue, "v4 旧存档迁移后应默认启用 classic 边框")
}

runTest("test_v030_phase2_resonance_twilight_andNarrative") {
    // 1. 多缸轻度生态共振
    let c1 = TerrariumContainer(customName: "苔原", instance: TerrariumInstanceState.empty(biome: .meadow))
    var c2 = TerrariumContainer(customName: "沙地", instance: TerrariumInstanceState.empty(biome: .sand))
    check(!TerrariumConfig.ecosystemResonance(containers: [c1]).isActive, "单缸不得激活跨生态共鸣")

    c2.instance.isSleeping = true
    check(!TerrariumConfig.ecosystemResonance(containers: [c1, c2]).isActive, "另一生态缸处于休眠时不激活共鸣")

    c2.instance.isSleeping = false
    let res = TerrariumConfig.ecosystemResonance(containers: [c1, c2])
    check(res.isActive && res.distinctBiomeCount == 2 && res.plantSpawnMult == 1.10 && res.efficiencyBonus == 0.05, "2 种不同活跃生态缸应激活 +10% 萌发与 +5% 效率共鸣")

    // 2. 晨昏光影强度
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    let dawnPeak = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 6, minute: 45))!
    let duskPeak = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 18, minute: 15))!
    let noon = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 12, minute: 0))!
    check(TerrariumConfig.twilightTintIntensity(for: dawnPeak, calendar: cal) == 1.0, "06:45 日出峰值强度应为 1.0")
    check(TerrariumConfig.twilightTintIntensity(for: duskPeak, calendar: cal) == 1.0, "18:15 日落峰值强度应为 1.0")
    check(TerrariumConfig.twilightTintIntensity(for: noon, calendar: cal) == 0.0, "正午 12:00 晨昏光晕强度应为 0.0")

    // 3. 挚友微叙事
    let line = TerrariumConfig.soulmateMicroNarrative(nickname: "阿绿", kind: .treeFrog, localTempC: 12, atmosphere: .day)
    check(line.contains("阿绿") && line.contains("12°C"), "挚友微叙事应融合昵称与当地气温")

    // 4. 沙地与雨林专属空中奇遇物种判定
    var sandInst = TerrariumInstanceState.empty(biome: .sand)
    sandInst.atmosphere = .day
    sandInst.temperature = 27
    sandInst.humidity = 40
    sandInst.enabledDecorIDs.append("sand_cairn")
    sandInst.plants = [PlantInstance(speciesID: "agave", coord: GridCoord(col: 3, row: 3), stage: .mature)]
    let sandUnlocked = TerrariumSimulation.evaluateCodexUnlocks(instance: sandInst, alreadyUnlocked: [])
    check(sandUnlocked.contains("antlion_lacewing"), "沙地暖干+叠石+成熟植物应解锁砂金蚁狮蛉")

    var rfInst = TerrariumInstanceState.empty(biome: .rainforest)
    rfInst.atmosphere = .day
    rfInst.humidity = 75
    rfInst.plants = [PlantInstance(speciesID: "orchid", coord: GridCoord(col: 4, row: 4), stage: .mature)]
    let rfUnlocked = TerrariumSimulation.evaluateCodexUnlocks(instance: rfInst, alreadyUnlocked: [])
    check(rfUnlocked.contains("orchid_bee"), "雨林日间高湿+兰花应解锁翡翠兰花蜂")
}

runTest("test_guaranteedFirstPlantSpawn_andDynamicPool") {
    var meadow = TerrariumInstanceState.empty(biome: .meadow)
    meadow.humidity = 65
    meadow.enabledDecorIDs = ["driftwood"]
    meadow.plants = [
        PlantInstance(speciesID: "moss", coord: GridCoord(col: 1, row: 1), stage: .mature),
        PlantInstance(speciesID: "fern", coord: GridCoord(col: 2, row: 2), stage: .mature)
    ]

    // 即使随机骰子返回 0.99，缺失的前置三叶草与红菇也应逐次必出首株
    let p1 = TerrariumSimulation.attemptRandomPlantSpawn(instance: &meadow, randomUnit: { 0.99 })
    check(p1?.speciesID == "clover", "苔原缺失三叶草且满足条件时应 100% 首株必出，实际=\(p1?.speciesID ?? "nil")")

    let p2 = TerrariumSimulation.attemptRandomPlantSpawn(instance: &meadow, randomUnit: { 0.99 })
    check(p2?.speciesID == "red_shroom", "拥有沉木且缺失红菇时应继续必出首株红菇，实际=\(p2?.speciesID ?? "nil")")

    // 首株均已齐备后，randomUnit=0.99 应正常走概率过滤返回 nil，保留后续随机性
    let p3 = TerrariumSimulation.attemptRandomPlantSpawn(instance: &meadow, randomUnit: { 0.99 })
    check(p3 == nil, "全部达标物种均已有首株后，高随机骰子应走概率分支而非强行必出")
}

runTest("test_achievements_14Titles_andIdempotentRewards") {
    let achs = TerrariumConfig.defaultAchievements
    check(achs.count == 16, "组合式成就称号总数应为 16 项（14 基础 + 2 海缸隐藏），实际=\(achs.count)")
    check(achs.allSatisfy { (1...5).contains($0.rewardPoints) }, "所有成就一次性奖励必须在 1~5 生态点范围内")

    var save = TerrariumSaveData(ecoPoints: 10)
    save.unlockedCodexIDs = ["tree_frog", "dart_frog", "red_eyed_frog", "sand_gecko", "sand_scorpion", "horned_toad"]
    save.containers[0].instance.critters = [
        CritterPersistentState(kind: .treeFrog, residency: .resident, coord: GridCoord(col: 3, row: 3), affinity: 100)
    ]
    let newly = TerrariumSimulation.evaluateAchievements(data: &save)
    check(newly.contains(where: { $0.id == "ach_frog_chorus" }), "集齐三蛙应解锁「蛙鸣三重奏」")
    check(newly.contains(where: { $0.id == "ach_desert_lords" }), "集齐三沙地霸主应解锁「沙海三霸主」")
    check(newly.contains(where: { $0.id == "ach_first_soulmate" }), "拥有 Lv.5 挚友应解锁「莫逆之交」")
    let expectedGain = newly.reduce(0) { $0 + $1.rewardPoints }
    check(save.ecoPoints == 10 + expectedGain, "首次解锁成就应发放对应一次性生态点")

    // 重复评估幂等校验
    let repeatUnlocked = TerrariumSimulation.evaluateAchievements(data: &save)
    check(repeatUnlocked.isEmpty && save.ecoPoints == 10 + expectedGain, "已解锁成就不得重复发点")

    save.equippedTitleID = "ach_frog_chorus"
    check(TerrariumConfig.displayTitle(for: save) == "🐸 蛙鸣三重奏", "佩戴称号后应展示对应自定义称号")
}

runTest("test_idleDaysCalculation_andTankCreatedAt") {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    let day0 = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 22, minute: 0))!
    let sameDay = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 23, minute: 30))!
    let nextDay = cal.date(from: DateComponents(year: 2026, month: 6, day: 2, hour: 0, minute: 10))!
    let day3 = cal.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 12, minute: 0))!

    check(TerrariumConfig.elapsedDays(from: day0, to: sameDay, calendar: cal) == 0, "同日应显示 Day 0")
    check(TerrariumConfig.elapsedDays(from: day0, to: nextDay, calendar: cal) == 1, "跨自然日次日应显示 Day 1")
    check(TerrariumConfig.elapsedDays(from: day0, to: day3, calendar: cal) == 3, "第 4 天应显示 Day 3")
    check(TerrariumConfig.elapsedDays(from: day3, to: day0, calendar: cal) == 0, "时间倒流保护应兜底为 0")

    let fresh = TerrariumSaveData(lastSavedAt: day3, firstStartedAt: day3)
    check(TerrariumConfig.elapsedDays(from: fresh.firstStartedAt, to: day3, calendar: cal) == 0, "重置后挂机天数应归 0")
    check(TerrariumConfig.elapsedDays(from: fresh.containers[0].createdAt, to: day3, calendar: cal) == 0, "重置后首缸独立天数应归 0")
}

runTest("test_i18n_all8LanguagesKeyAndPlaceholderParity") {
    check(SupportedLanguage.allCases.count == 8, "应精确支持 8 种语言")

    guard let baseTable = TerrariumL10n.rawTable(for: .zhHans), !baseTable.isEmpty else {
        check(false, "未能加载基准语言 zh-Hans.json")
        return
    }
    let baseKeys = Set(baseTable.keys)
    let placeholderRegex = try! NSRegularExpression(pattern: "\\{[a-zA-Z0-9_]+\\}")

    func extractPlaceholders(_ text: String) -> Set<String> {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(placeholderRegex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        })
    }

    func containsHanzi(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
        }
    }

    for lang in SupportedLanguage.allCases {
        guard let table = TerrariumL10n.rawTable(for: lang), !table.isEmpty else {
            check(false, "未能加载语言包: \(lang.rawValue)")
            continue
        }
        check(Set(table.keys) == baseKeys, "\(lang.rawValue) Key 集合应与 zh-Hans 一致")
        for (k, v) in table {
            check(!v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(lang.rawValue).\(k) 不可为空")
            if let baseVal = baseTable[k] {
                check(extractPlaceholders(v) == extractPlaceholders(baseVal), "\(lang.rawValue).\(k) 占位符不一致")
            }
            if [.en, .ko, .es, .de, .fr].contains(lang) {
                check(!containsHanzi(v), "\(lang.rawValue).\(k) 不应残留汉字: \(v)")
            }
        }
    }
}

runTest("test_i18n_runtimeSwitching_persistenceCompatibility_andSystemResolution") {
    defer { TerrariumL10n.setOverrideLanguage(.zhHans)
TerrariumL10n.setOverrideTemperatureUnit(.celsius) }

    check(TerrariumL10n.resolveSystemLanguage(preferredLanguages: ["zh-Hant-TW"]) == .zhHant, "zh-Hant-TW 应解析为繁体中文")
    check(TerrariumL10n.resolveSystemLanguage(preferredLanguages: ["zh-HK", "en"]) == .zhHant, "zh-HK 应解析为繁体中文")
    check(TerrariumL10n.resolveSystemLanguage(preferredLanguages: ["zh-Hans-CN"]) == .zhHans, "zh-Hans-CN 应解析为简体中文")
    check(TerrariumL10n.resolveSystemLanguage(preferredLanguages: ["ja-JP"]) == .ja, "ja-JP 应解析为日语")
    check(TerrariumL10n.resolveSystemLanguage(preferredLanguages: ["ko-KR"]) == .ko, "ko-KR 应解析为韩语")
    check(TerrariumL10n.resolveSystemLanguage(preferredLanguages: ["es-MX"]) == .es, "es-MX 应解析为西语")
    check(TerrariumL10n.resolveSystemLanguage(preferredLanguages: ["de-DE"]) == .de, "de-DE 应解析为德语")
    check(TerrariumL10n.resolveSystemLanguage(preferredLanguages: ["fr-CA"]) == .fr, "fr-CA 应解析为法语")
    check(TerrariumL10n.resolveSystemLanguage(preferredLanguages: ["en-GB"]) == .en, "en-GB 应解析为英语")
    check(TerrariumL10n.resolveSystemLanguage(preferredLanguages: ["ru-RU"]) == .en, "未命中语种应回落英语")

    for lang in SupportedLanguage.allCases {
        TerrariumL10n.setOverrideLanguage(lang)
        let codex = TerrariumConfig.defaultCodexEntries()
        check(codex.filter { !$0.isHiddenReef }.count == 52 && codex.filter { $0.isHiddenReef }.count == 11, "\(lang.rawValue) 图鉴应保持 52 基础 + 11 隐藏")
        for entry in codex {
            check(!entry.name.contains("{") && !entry.name.hasPrefix("codex.") && !entry.name.hasPrefix("critter."), "\(lang.rawValue) 图鉴名未翻译: \(entry.id)")
            check(!entry.category.contains("{") && !entry.condition.contains("{") && !entry.desc.contains("{"), "\(lang.rawValue) 图鉴存在未替换占位符: \(entry.id)")
        }

        let allDecor = TerrariumBiome.allCases.flatMap { TerrariumConfig.decorCatalog(for: $0) }
        check(allDecor.count == 25, "\(lang.rawValue) 造景目录应保持 25 项")
        for d in allDecor {
            check(!d.name.hasPrefix("decor.") && !d.nicheDescription.contains("{"), "\(lang.rawValue) 造景异常: \(d.id)")
        }

        let allCritters = TerrariumBiome.allCases.flatMap { TerrariumConfig.critterShopCatalog(for: $0) }
        check(allCritters.count == 31, "\(lang.rawValue) 生物商店目录应保持 31 项")
        let emptyMeadow = TerrariumInstanceState.empty(biome: .meadow)
        for c in allCritters {
            check(!c.name.hasPrefix("critter.") && !c.unlockConditionText.contains("{") && !c.foodChainNote.contains("{"), "\(lang.rawValue) 生物目录异常: \(c.id)")
            let elig = TerrariumSimulation.critterUnlockEligibility(kind: c.kind, instance: emptyMeadow)
            check(!elig.missingReason.isEmpty && !elig.missingReason.contains("{") && !elig.missingReason.hasPrefix("elig."), "\(lang.rawValue) 资格文案异常: \(c.id)")
        }

        let achs = TerrariumConfig.defaultAchievements
        check(achs.count == 16, "\(lang.rawValue) 成就应保持 16 项")
        for a in achs {
            check(!a.title.hasPrefix("ach.") && !a.conditionDesc.contains("{"), "\(lang.rawValue) 成就异常: \(a.id)")
        }
        check(TerrariumConfig.weatherEvents.count == 4, "\(lang.rawValue) 气候事件应保持 4 项")

        let narrative = TerrariumConfig.soulmateMicroNarrative(nickname: "Mochi", kind: .treeFrog, localTempC: 12, atmosphere: .day)
        check(narrative.contains("Mochi") && narrative.contains("12°C") && !narrative.contains("{"), "\(lang.rawValue) 挚友微叙事格式异常: \(narrative)")
    }

    for testLang in [SupportedLanguage.en, SupportedLanguage.de] {
        TerrariumL10n.setOverrideLanguage(testLang)
        check(TerrariumBiome.meadow.rawValue == "温润苔原缸", "\(testLang.rawValue) 下 TerrariumBiome.rawValue 不可变动")
        check(ThermalMode.heating.rawValue == "加热", "\(testLang.rawValue) 下 ThermalMode.rawValue 不可变动")
        check(SceneAtmosphere.rain.rawValue == "林间小雨", "\(testLang.rawValue) 下 SceneAtmosphere.rawValue 不可变动")
        check(TerrariumConfig.defaultPersonality(for: .snail) == "慢性子", "\(testLang.rawValue) 下默认性格存储键不可变动")
        check(TerrariumConfig.personalityPerk(for: "慢性子") == .thrifty, "\(testLang.rawValue) 下性格特技匹配不可受语言影响")

        let legacyV3JSON = """
        {
          "schemaVersion": 3,
          "currentBiome": "温润苔原缸",
          "unlockedBiomes": ["温润苔原缸"],
          "ecoPoints": 18,
          "unlockedCodexIDs": ["moss"],
          "lastSavedAt": 0,
          "terrariums": {
            "温润苔原缸": {
              "biome": "温润苔原缸",
              "atmosphere": "日间森林",
              "temperature": 22,
              "humidity": 65,
              "isSleeping": false,
              "foodBowlPortions": 1,
              "glassFogLevel": 0.0,
              "mistDewBoostSeconds": 0.0,
              "plants": [],
              "critters": [],
              "unlockedDecorIDs": [],
              "enabledDecorIDs": [],
              "nextWeatherEventAt": 100,
              "weatherCooldownEndAt": 0,
              "accumulatedEcoSeconds": 0,
              "accumulatedHumidityDecaySeconds": 0,
              "ambientRelaxSeconds": 0,
              "plantPulseSeconds": 0
            }
          }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try? decoder.decode(TerrariumSaveData.self, from: Data(legacyV3JSON.utf8))
        check(decoded?.schemaVersion == 5 && decoded?.ecoPoints == 18 && decoded?.containers.count == 1, "\(testLang.rawValue) 下历史 v3 中文存档应无损迁移")
    }
}

runTest("test_plantWiltingByBiome_andTemperatureUnitConversion") {
    defer {
        TerrariumL10n.setOverrideLanguage(.zhHans)
        TerrariumL10n.setOverrideTemperatureUnit(.celsius)
    }

    // 1. 沙地缸全 5 种沙漠植物在高湿（>=80%）下进入 .wilting（过湿），在干燥（<80%）下恢复健康
    let desertSpecies = ["succulent", "cactus", "aloe", "lithops", "agave"]
    for sp in desertSpecies {
        var sandInst = TerrariumInstanceState.empty(biome: .sand)
        sandInst.humidity = 98
        sandInst.plants = [PlantInstance(speciesID: sp, coord: GridCoord(col: 2, row: 2), stage: .mature)]
        TerrariumSimulation.updatePlants(instance: &sandInst, dt: 7500)
        check(sandInst.plants[0].stage == .wilting, "沙漠植物 \(sp) 在 98% 湿度下应进入过湿状态 (.wilting)")

        sandInst.humidity = 35
        TerrariumSimulation.updatePlants(instance: &sandInst, dt: 300)
        check(sandInst.plants[0].stage == .mature, "沙漠植物 \(sp) 湿度降至 35% 后应恢复为健康成株 (.mature)")
    }

    // 2. 不同生态缸的 .wilting 本地化文案应精准区分：沙地=过湿，生态水=缺氧，苔原/雨林=缺水
    TerrariumL10n.setOverrideLanguage(.zhHans)
    check(PlantStage.wilting.localizedName(for: .sand) == "过湿", "沙地缸 wilting 应显示'过湿'")
    check(PlantStage.wilting.localizedName(for: .aquatic) == "缺氧", "生态水缸 wilting 应显示'缺氧'")
    check(PlantStage.wilting.localizedName(for: .meadow) == "缺水", "苔原缸 wilting 应显示'缺水'")
    check(PlantStage.wilting.localizedName(for: .rainforest) == "缺水", "雨林缸 wilting 应显示'缺水'")

    TerrariumL10n.setOverrideLanguage(.en)
    check(PlantStage.wilting.localizedName(for: .sand) == "Overwatered", "英文沙地缸 wilting 应显示'Overwatered'")
    check(PlantStage.wilting.localizedName(for: .aquatic) == "Low O₂", "英文水缸 wilting 应显示'Low O₂'")
    check(PlantStage.wilting.localizedName(for: .meadow) == "Wilting", "英文苔原缸 wilting 应显示'Wilting'")

    // 3. 摄氏 (°C) 与华氏 (°F) 转换断言（含绝对温度与温差 Δ）
    TerrariumL10n.setOverrideLanguage(.zhHans)
    TerrariumL10n.setOverrideTemperatureUnit(.celsius)
    check(TemperatureUnit.celsius.format(celsius: 22) == "22°C", "22°C 格式化断言")
    check(TerrariumL10n.t("codex.agave.cond") == "芦荟≥1 + 温暖(≥25°C)", "摄氏模式下龙舌兰图鉴条件应为 25°C")

    TerrariumL10n.setOverrideTemperatureUnit(.fahrenheit)
    check(TemperatureUnit.fahrenheit.format(celsius: 22) == "72°F", "22°C 应换算为 72°F")
    check(TemperatureUnit.fahrenheit.format(celsius: 25, includeUnitLetter: false) == "77°", "25°C 简写应换算为 77°")
    check(TerrariumL10n.t("codex.agave.cond") == "芦荟≥1 + 温暖(≥77°F)", "华氏模式下龙舌兰图鉴 25°C 应自动换算为 77°F")
    check(TerrariumL10n.t("decor.boulder.desc").contains("-2°F"), "华氏模式下青苔巨石温差 -1°C 应换算为 -2°F")
    check(TerrariumL10n.t("sensor.heat_help_on", ["temp": "28"]).contains("+11°F") && TerrariumL10n.t("sensor.heat_help_on", ["temp": "28"]).contains("82°F"), "华氏模式下加热灯提示应同时换算温差 +6°C->+11°F 与目标温度 28°C->82°F")
    check(TerrariumL10n.t("sensor.fan_help_on", ["temp": "18"]).contains("-7°F") && TerrariumL10n.t("sensor.fan_help_on", ["temp": "18"]).contains("64°F"), "华氏模式下降温扇提示应同时换算温差 -4°C->-7°F 与目标温度 18°C->64°F")
    check(TerrariumL10n.t("sensor.temp_unit_help") == "点击切换摄氏 (°C) / 华氏 (°F)", "不含数字前缀的 (°C) 提示标签不应被错误替换")

    // 4. 日常小贴士（Daily Tips）池与频率设定断言
    check(DailyTipsFrequency.fast30s.intervalSeconds == 30.0, "30s 档位轮播周期应为 30 秒")
    check(DailyTipsFrequency.standard1m.intervalSeconds == 60.0, "1m 档位轮播周期应为 60 秒")
    check(DailyTipsFrequency.relaxed5m.intervalSeconds == 300.0, "5m 档位轮播周期应为 300 秒")
    check(DailyTipsFrequency.off.intervalSeconds == nil, "关闭档位轮播周期应为 nil")

    for biome in TerrariumBiome.allCases {
        let keys = TerrariumL10n.dailyTipKeys(for: biome)
        check(keys.count == 13, "\(biome.rawValue) 应包含 12 条通用 + 1 条专属共 13 条日常小贴士")
        for idx in 0..<keys.count {
            let tip = TerrariumL10n.dailyTip(for: biome, index: idx)
            check(tip.contains("💡") && !tip.hasPrefix("tips."), "\(biome.rawValue) 小贴士 #\(idx) 翻译异常: \(tip)")
        }
    }
    check(TerrariumL10n.dailyTip(for: .meadow, index: 10).contains("72°F"), "华氏模式下第 11 条小贴士中的 22°C 示例应自动换算为 72°F")
    check(TerrariumL10n.t("tips.alert.sand_wet").contains("加热灯") && TerrariumL10n.t("tips.alert.sand_wet").contains("蒸发"), "沙地过湿预警贴士应与物理引擎一致，提示开启加热灯加速蒸发")
}

runTest("test_hiddenReefBiome_unlockSalinityCoralAndMarineCritters") {
    defer {
        TerrariumL10n.setOverrideLanguage(.zhHans)
    }

    // 1. 隐藏海缸解锁门禁：必须同时拥有 4 种基础缸且基础 31 种动物图鉴全收集
    var save = TerrariumSaveData()
    check(!TerrariumConfig.isReefUnlocked(data: save), "仅 1 个基础缸时海缸应处于锁定状态")
    save.containers = [
        TerrariumContainer(customName: "苔原", instance: .empty(biome: .meadow)),
        TerrariumContainer(customName: "沙地", instance: .empty(biome: .sand)),
        TerrariumContainer(customName: "雨林", instance: .empty(biome: .rainforest)),
        TerrariumContainer(customName: "水域", instance: .empty(biome: .aquatic))
    ]
    check(!TerrariumConfig.isReefUnlocked(data: save), "拥有 4 种基础缸但未集齐 31 种动物时海缸仍应锁定")

    let allBaseAnimals = Array(TerrariumConfig.baseAnimalCodexIDs)
    save.unlockedCodexIDs = Array(allBaseAnimals.dropLast())
    check(!TerrariumConfig.isReefUnlocked(data: save), "差 1 种基础动物时海缸仍应锁定 (30/31)")

    save.unlockedCodexIDs = allBaseAnimals
    let progress = TerrariumConfig.reefUnlockProgress(data: save)
    check(progress.isUnlocked && progress.ownedBaseTankCount == 4 && progress.collectedBaseAnimalCount == 31, "拥有 4 种基础缸且集齐 31 种动物后应解锁隐藏海缸")

    // 2. 52 项基础全生态宗师成就与 11 项隐藏图鉴解耦
    check(TerrariumConfig.baseAnimalCodexIDs.count == 31, "基础动物图鉴 ID 集合应恰好为 31 项")
    var achSave = TerrariumSaveData()
    achSave.unlockedCodexIDs = TerrariumConfig.defaultCodexEntries().filter { $0.isHiddenReef }.map { $0.id }
    TerrariumSimulation.evaluateAchievements(data: &achSave)
    check(!achSave.unlockedAchievementIDs.contains("ach_codex_10"), "隐藏海缸图鉴不应计入基础 52 项里程碑成就")
    check(achSave.unlockedAchievementIDs.contains("ach_reef_master"), "集齐 11 项隐藏海域物种应解锁 ach_reef_master")

    // 3. 海缸盐度蒸发浓缩与珊瑚失衡白化/恢复
    var reef = TerrariumInstanceState.empty(biome: .reef)
    check(reef.salinity == 35.0, "海缸初始盐度应为 35.0‰")
    reef.plants = [PlantInstance(speciesID: "coral_zoanthid", coord: GridCoord(col: 3, row: 3), stage: .mature)]
    var reefPts = 0
    var reefCodex: [String] = []
    TerrariumSimulation.advanceInstance(instance: &reef, ecoPoints: &reefPts, unlockedCodexIDs: &reefCodex, elapsedSeconds: 3600, allowRandomSpawn: false)
    check((reef.salinity ?? 35.0) > 35.2, "海缸经过 1 小时水分蒸发后盐度应缓慢浓缩上升，实际=\(reef.salinity ?? 0)")

    reef.salinity = 38.5
    TerrariumSimulation.updatePlants(instance: &reef, dt: 7500)
    check(reef.plants[0].stage == .wilting, "海缸盐度过高(38.5‰)应触发珊瑚白化缩触手 (.wilting)")
    check(PlantStage.wilting.localizedName(for: .reef, salinity: reef.salinity) == "盐度过浓", "盐度过高时应显示'盐度过浓'")

    reef.salinity = 34.5
    reef.humidity = 75
    TerrariumSimulation.updatePlants(instance: &reef, dt: 300)
    check(reef.plants[0].stage == .mature || reef.plants[0].stage == .lushDew, "盐度恢复适宜后珊瑚应重新舒展")

    // 4. 海星降低藻垢 & 海马与共生群互斥
    reef.glassFogLevel = 0.5
    reef.enabledDecorIDs = ["reef_sand_shells", "reef_live_rock"]
    reef.critters = [
        CritterPersistentState(kind: .starfish, residency: .resident, coord: GridCoord(col: 4, row: 4)),
        CritterPersistentState(kind: .clownfish, residency: .resident, coord: GridCoord(col: 5, row: 5)),
        CritterPersistentState(kind: .seahorse, residency: .resident, coord: GridCoord(col: 6, row: 6))
    ]
    let moved = TerrariumSimulation.normalizeFoodChainCompatibility(instance: &reef)
    check(!moved.isEmpty, "幽蓝海马与珊瑚礁共生群互斥时应自动收纳冲突生物")
    check(!TerrariumConfig.areCompatibleInSameTank(.clownfish, .seahorse), "小丑鱼与海马应属于不同食物链群落")
    check(TerrariumConfig.areCompatibleInSameTank(.hermitCrab, .starfish), "寄居蟹与海星应属于同一礁石共生群")

    // 5. v5 存档兼容解码（无 salinity 字段）
    let v5ReefJSON = """
    {
      "biome": "珊瑚礁海缸",
      "atmosphere": "日间森林",
      "temperature": 25,
      "humidity": 72,
      "isSleeping": false,
      "foodBowlPortions": 1,
      "glassFogLevel": 0.0,
      "mistDewBoostSeconds": 0.0,
      "plants": [],
      "critters": [],
      "unlockedDecorIDs": [],
      "enabledDecorIDs": [],
      "nextWeatherEventAt": 100,
      "weatherCooldownEndAt": 0,
      "accumulatedEcoSeconds": 0,
      "accumulatedHumidityDecaySeconds": 0,
      "ambientRelaxSeconds": 0,
      "plantPulseSeconds": 0
    }
    """
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .secondsSince1970
    let decodedReef = try? dec.decode(TerrariumInstanceState.self, from: Data(v5ReefJSON.utf8))
    check(decodedReef?.salinity == 35.0, "缺失 salinity 字段的旧版海缸存档应安全兜底为 35.0‰")
}

print("\nSummary: \(passedCount) passed, \(failedCount) failed.")
if failedCount > 0 {
    Foundation.exit(1)
}
