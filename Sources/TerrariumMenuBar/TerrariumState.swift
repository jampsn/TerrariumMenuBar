import Combine
import Foundation
import SwiftUI
import TerrariumCore

enum PetOutcome: Equatable {
    case gained(delta: Int, newStage: TerrariumConfig.AffinityStage, leveledUp: Bool)
    case onCooldown(remainingMinutes: Int)
    case dailyLimitReached
    case recoveringFromStartle
}

enum VFXEvent {
    case mist
    case feed(bowlScreenPos: CGPoint)
    case clean
    case ecoPopup(text: String, at: CGPoint)
    case syncCritters
}

@MainActor
final class TerrariumState: ObservableObject {
    @Published var currentTab: PopoverTab = .terrarium
    @Published var currentBiome: TerrariumBiome = .meadow
    @Published var containers: [TerrariumContainer] = []
    @Published var activeContainerID: UUID = UUID()
    @Published var activeContainerName: String = "苔原缸 #1"
    @Published var thermalMode: ThermalMode = .natural
    @Published var hasHeatLamp: Bool = false
    @Published var hasCoolingFan: Bool = false
    @Published var isShowingBuyTankSheet: Bool = false
    @Published var isShowingSettings: Bool = false
    @Published var isConfirmingResetSave: Bool = false
    @Published var isConfirmingPrunePlant: Bool = false
    @Published var pendingPurchaseThermalMode: ThermalMode? = nil
    @Published var adminTimeScale: Double = 1.0
    @Published var adminSimulatedElapsedSeconds: TimeInterval = 0
    @Published var isConfirmingDeleteTank: Bool = false
    @Published var atmosphere: SceneAtmosphere = .day
    @Published var temperature: Int = 22
    @Published var humidity: Int = 30
    @Published var isSleeping: Bool = false
    @Published var hasWeatherEvent: Bool = false
    @Published var eventMessage: String? = nil
    @Published var ecoPoints: Int = 2
    @Published var foodBowlPortions: Int = 0
    @Published var glassFogLevel: Double = 0.0
    @Published var mistDewBoostSeconds: TimeInterval = 0
    @Published var plants: [PlantInstance] = []
    @Published var critters: [CritterPersistentState] = []
    @Published var decorItems: [DecorItem] = []
    @Published var decorOrigins: [String: GridCoord] = [:]
    @Published var codexEntries: [CodexEntry] = TerrariumConfig.defaultCodexEntries()
    @Published var bannerNotice: String? = nil
    @Published var nextEventMinutesRemaining: Int = 25
    @Published var selectedPlantID: UUID? = nil
    @Published var isMovingPlant: Bool = false
    @Published var selectedDecorID: String? = nil
    @Published var movingDecorID: String? = nil

    // 隐藏管理员模式（仅当前会话有效）
    @Published private(set) var isAdminMode: Bool = false
    @Published var showIsoGridDebug: Bool = false
    @Published var localOutdoorTempC: Int? = nil
    @Published var localCityName: String? = nil

    let vfxSubject = PassthroughSubject<VFXEvent, Never>()

    private let persistence: TerrariumPersistence
    private var saveData: TerrariumSaveData
    nonisolated(unsafe) private var backgroundTimer: Timer?
    nonisolated(unsafe) private var adminSpeedTimer: Timer?
    private var adminVirtualNowOffset: TimeInterval = 0
    private var isSchedulerRunning: Bool = false
    private var lastWeatherFetchAt: Date = .distantPast
    private var hasSyncedInitialWeather: Bool = false
    private(set) var lastFedAt: Date = .distantPast
    private var lastStartleAtByKind: [CritterKind: Date] = [:]
    private var titleTapCount: Int = 0
    private var lastTitleTapAt: Date = .distantPast

    init(persistence: TerrariumPersistence = TerrariumPersistence(), startScheduler: Bool = true) {
        self.persistence = persistence
        let now = Date()

        if var loaded = persistence.load() {
            var migratedStowed: [CritterKind] = []
            for idx in loaded.containers.indices {
                var inst = loaded.containers[idx].instance
                let moved = TerrariumSimulation.normalizeFoodChainCompatibility(instance: &inst)
                migratedStowed.append(contentsOf: moved)
                loaded.containers[idx].instance = inst
            }
            let summary = TerrariumSimulation.settleOfflineAll(data: &loaded, now: now)
            self.saveData = loaded

            if !migratedStowed.isEmpty {
                let stowedNames = Self.critterNames(for: migratedStowed)
                self.bannerNotice = "⚖️ 斗鱼领地独立：已将同缸「\(stowedNames)」安全移入生物仓（可新购鱼缸分养）"
            } else if summary.totalEarnedEcoPoints > 0 {
                self.bannerNotice = "欢迎回来 · 离线产出 +\(summary.totalEarnedEcoPoints) 生态点"
            }
            if !summary.newlyUnlockedCodexIDs.isEmpty {
                self.hasWeatherEvent = true
                let names = Self.codexNames(for: summary.newlyUnlockedCodexIDs)
                self.appendEventMessage("离线发现新物种：\(names)")
            }
            for idx in self.saveData.containers.indices {
                var inst = self.saveData.containers[idx].instance
                if !inst.isSleeping, now >= inst.nextWeatherEventAt {
                    TerrariumSimulation.applyWeatherEvent(
                        TerrariumConfig.weatherEvents.randomElement()!,
                        to: &inst,
                        now: now
                    )
                    self.saveData.containers[idx].instance = inst
                }
            }
            persistence.save(self.saveData)
        } else {
            self.saveData = TerrariumSaveData(lastSavedAt: now)
            persistence.save(self.saveData)
        }

        syncPublishedFromSaveData(now: now)

        if startScheduler {
            startBackgroundScheduler()
            Task { @MainActor [weak self] in
                await self?.refreshLocalWeatherIfNeeded(force: true)
            }
        }
    }

    deinit {
        if let activeTimer = backgroundTimer {
            if Thread.isMainThread {
                activeTimer.invalidate()
            } else {
                nonisolated(unsafe) let t = activeTimer
                DispatchQueue.main.async {
                    t.invalidate()
                }
            }
        }
        if let speedTimer = adminSpeedTimer {
            if Thread.isMainThread {
                speedTimer.invalidate()
            } else {
                nonisolated(unsafe) let st = speedTimer
                DispatchQueue.main.async {
                    st.invalidate()
                }
            }
        }
    }

    private var activeContainerIndex: Int {
        saveData.containers.firstIndex(where: { $0.id == saveData.activeContainerID }) ?? 0
    }

    private var activeInstance: TerrariumInstanceState {
        get {
            guard !saveData.containers.isEmpty else {
                return TerrariumInstanceState.empty(biome: .meadow)
            }
            return saveData.containers[activeContainerIndex].instance
        }
        set {
            guard !saveData.containers.isEmpty else { return }
            saveData.containers[activeContainerIndex].instance = newValue
        }
    }

    var unlockedCodexCount: Int {
        codexEntries.filter(\.unlocked).count
    }

    var enabledDecorIDs: [String] {
        activeInstance.enabledDecorIDs
    }

    var activeDisplayCritters: [CritterPersistentState] {
        critters.filter { $0.residency == .resident || $0.residency == .visitor }
    }

    var activeFoodChainGroup: FoodChainGroup? {
        guard let first = activeDisplayCritters.first else { return nil }
        return TerrariumConfig.foodChainGroup(for: first.kind)
    }

    var selectedPlant: PlantInstance? {
        guard let id = selectedPlantID else { return nil }
        return plants.first(where: { $0.id == id })
    }

    var selectedDecorItem: DecorItem? {
        guard let id = selectedDecorID else { return nil }
        return decorItems.first(where: { $0.id == id && $0.enabled })
    }

    var menuBarVisualState: PixelAssetLoader.MenuBarVisualState {
        if isSleeping { return .sleep }
        if hasWeatherEvent { return .event }
        let dryThreshold: Int = {
            switch currentBiome {
            case .meadow: return 35
            case .sand: return 20
            case .rainforest: return 50
            case .aquatic: return 50
            }
        }()
        if humidity < dryThreshold { return .dry }
        if !activeDisplayCritters.isEmpty && foodBowlPortions == 0 && activeDisplayCritters.contains(where: { $0.hunger >= 60.0 }) {
            return .hungry
        }
        if atmosphere == .night { return .night }
        return .normal
    }

    var menuBarTooltip: String {
        let prefix = isSleeping ? "[休眠] " : ""
        return "\(prefix)\(currentBiome.rawValue) · \(temperature)°C · 湿度\(humidity)% · 食盆\(foodBowlPortions)/\(TerrariumConfig.maxFoodPortions) · 住民\(activeDisplayCritters.count)"
    }

    var statusText: String {
        if let notice = bannerNotice { return notice }
        if isSleeping { return "休眠盖已合上 · 暂停消耗与演替" }

        // Day 0 ~ Tier 2 诗意渐进引导
        if plants.isEmpty {
            switch currentBiome {
            case .meadow:
                return humidity < 45
                    ? "干涸裸土 · 试着「喷水加湿」唤醒沉睡孢子"
                    : "土壤已润泽 · 第一抹新绿即将破土而出..."
            case .sand:
                return "金色裸沙待唤醒 · 静候耐旱多肉萌芽"
            case .rainforest:
                return humidity < 60
                    ? "雨林表土待润泽 · 请「喷水加湿」催生龟背竹"
                    : "热带湿气充沛 · 第一株龟背竹即将展叶..."
            case .aquatic:
                return humidity < 55
                    ? "水质溶氧待激活 · 请「换水打氧」催生第一株莫斯藻球"
                    : "水体溶氧充足 · 莫斯藻球即将萌发..."
            }
        }
        if critters.isEmpty {
            return "幼苗已苏醒 · 积攒生态点前往「生物」领养第一位居民吧"
        }
        if activeDisplayCritters.isEmpty {
            return "当前生态箱居民已入仓 · 可在「生物」切换入缸展示"
        }
        if foodBowlPortions > 0 {
            return "🥣 食盆余粮 \(foodBowlPortions)/\(TerrariumConfig.maxFoodPortions) · 小动物自动前往进食中"
        }
        if humidity >= TerrariumConfig.dewHeavyHumidityThreshold && currentBiome == .meadow {
            return "💧 高湿充沛 · 植物叶片凝结晶莹露珠"
        }
        if humidity >= TerrariumConfig.dewLightHumidityThreshold && currentBiome == .meadow {
            return "🌿 空气温润 · 叶尖挂上微露"
        }
        return "生态平稳运行中 · 点击小动物可趣味互动"
    }

    var tempHint: String {
        if temperature < 20 { return "偏凉" }
        if temperature > 26 { return "偏暖" }
        return "适宜"
    }

    var humHint: String {
        if humidity < 55 { return "干燥" }
        if humidity > 75 { return "潮湿" }
        return "温润"
    }

    // MARK: - 管理员模式切换

    func setAdminMode(_ enabled: Bool) {
        isAdminMode = enabled
        if !enabled {
            showIsoGridDebug = false
            setAdminTimeScale(1.0)
            adminVirtualNowOffset = 0
            adminSimulatedElapsedSeconds = 0
            saveData.lastSavedAt = Date()
            bannerNotice = "已退出管理员模式，恢复自然演进"
        } else {
            bannerNotice = "已开启管理员模式（仅本次运行有效）"
        }
    }

    func setAdminTimeScale(_ scale: Double) {
        guard isAdminMode || scale == 1.0 else { return }
        adminTimeScale = scale
        adminSpeedTimer?.invalidate()
        adminSpeedTimer = nil
        guard isAdminMode, scale > 1.0 else { return }

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isAdminMode, self.adminTimeScale > 1.0 else { return }
                let dt = self.adminTimeScale
                self.adminVirtualNowOffset += dt
                self.adminSimulatedElapsedSeconds += dt
                let virtualNow = Date().addingTimeInterval(self.adminVirtualNowOffset)
                self.processBackgroundTick(elapsed: dt, now: virtualNow, updateLastSavedAt: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        adminSpeedTimer = timer
        bannerNotice = "⏩ 管理员加速已设为 \(Int(scale))x（独立虚拟时钟，不污染真实存档时间）"
    }

    func fastForwardDebug(seconds: TimeInterval) {
        guard isAdminMode, seconds > 0 else { return }
        let beforePts = saveData.ecoPoints
        let beforePlants = activeInstance.plants.count
        adminVirtualNowOffset += seconds
        adminSimulatedElapsedSeconds += seconds
        let virtualNow = Date().addingTimeInterval(adminVirtualNowOffset)
        processBackgroundTick(elapsed: seconds, now: virtualNow, updateLastSavedAt: false)
        let gainedPts = saveData.ecoPoints - beforePts
        let newPlants = max(0, activeInstance.plants.count - beforePlants)
        let label = seconds >= 3600 ? "+\(Int(seconds / 3600))h" : "+\(Int(seconds / 60))m"
        bannerNotice = "⏩ 快进 \(label) 完成：生态点 +\(gainedPts)，萌发 +\(newPlants) 株"
    }

    func toggleAdminMode() {
        setAdminMode(!isAdminMode)
    }

    func registerSecretTitleTap() {
        let now = Date()
        if now.timeIntervalSince(lastTitleTapAt) > 2.0 {
            titleTapCount = 1
        } else {
            titleTapCount += 1
        }
        lastTitleTapAt = now
        if titleTapCount >= 5 {
            titleTapCount = 0
            toggleAdminMode()
        }
    }

    // MARK: - 后台多缸并行挂机调度器

    func startBackgroundScheduler() {
        guard backgroundTimer == nil else { return }
        isSchedulerRunning = true
        let timer = Timer(timeInterval: TerrariumConfig.backgroundTickSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isSchedulerRunning else { return }
                self.processBackgroundTick(now: Date())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        backgroundTimer = timer
    }

    func stopBackgroundScheduler() {
        isSchedulerRunning = false
        backgroundTimer?.invalidate()
        backgroundTimer = nil
    }

    func refreshLocalWeatherIfNeeded(force: Bool = false) async {
        let now = Date()
        guard force || now.timeIntervalSince(lastWeatherFetchAt) >= 1800.0 else { return }
        lastWeatherFetchAt = now
        guard let reading = await LocalWeatherService.fetchCurrentLocalTemperature() else { return }

        saveData.lastKnownLocalTempC = reading.tempC
        saveData.lastKnownLocalCity = reading.city
        localOutdoorTempC = reading.tempC
        localCityName = reading.city

        // 首次联动或空缸阶段平滑对齐室内当地室温；已有生态的缸仅在自然偏差较大时轻推 1°C
        for idx in saveData.containers.indices {
            var inst = saveData.containers[idx].instance
            guard !inst.isSleeping else { continue }
            let target = TerrariumConfig.baseAmbientTemp(
                for: inst.atmosphere,
                biome: inst.biome,
                thermalMode: inst.thermalMode,
                localOutdoorTempC: reading.tempC
            )
            if inst.plants.isEmpty && inst.critters.isEmpty && inst.thermalMode == .natural {
                inst.temperature = target
            } else if !hasSyncedInitialWeather, abs(target - inst.temperature) >= 2 {
                inst.temperature = TerrariumSimulation.clampTemp(inst.temperature + (target > inst.temperature ? 1 : -1))
            }
            saveData.containers[idx].instance = inst
        }
        hasSyncedInitialWeather = true
        syncPublishedFromSaveData(now: Date())
        persistence.save(saveData)
    }

    func processBackgroundTick(elapsed explicitElapsed: TimeInterval? = nil, now: Date = Date(), updateLastSavedAt: Bool = true) {
        let rawElapsed = explicitElapsed ?? max(0, now.timeIntervalSince(saveData.lastSavedAt))
        let elapsed = min(TerrariumConfig.maxOfflineSettlementSeconds, rawElapsed)

        var newCodexAll: [String] = []
        var activeCrittersChanged = false

        var pointsBuffer = saveData.ecoPoints
        var codexBuffer = saveData.unlockedCodexIDs

        for idx in saveData.containers.indices {
            let container = saveData.containers[idx]
            var inst = container.instance
            let isCurrentActive = (container.id == saveData.activeContainerID)
            if inst.isSleeping {
                continue
            }

            let summary = TerrariumSimulation.advanceInstance(
                instance: &inst,
                ecoPoints: &pointsBuffer,
                unlockedCodexIDs: &codexBuffer,
                elapsedSeconds: elapsed,
                now: now,
                localOutdoorTempC: saveData.lastKnownLocalTempC,
                tankSlotIndex: idx
            )

            if isCurrentActive && (!summary.arrivedCritters.isEmpty || !summary.settledCritters.isEmpty) {
                activeCrittersChanged = true
            }
            if isCurrentActive && summary.spawnedPlantsCount > 0 {
                bannerNotice = "🌱 「\(container.customName)」自然萌发了 \(summary.spawnedPlantsCount) 株新植物"
            }
            if !summary.arrivedCritters.isEmpty {
                let names = Self.critterNames(for: summary.arrivedCritters)
                bannerNotice = "🐾 「\(names)」现身于 \(container.customName)"
            }
            if !summary.settledCritters.isEmpty {
                let names = Self.critterNames(for: summary.settledCritters)
                hasWeatherEvent = true
                appendEventMessage("「\(names)」已正式定居！")
            }
            newCodexAll.append(contentsOf: summary.newlyUnlockedCodexIDs)

            if now >= inst.nextWeatherEventAt, let ev = TerrariumConfig.weatherEvents.randomElement() {
                TerrariumSimulation.applyWeatherEvent(ev, to: &inst, now: now)
                if isCurrentActive {
                    hasWeatherEvent = true
                    appendEventMessage("\(ev.title)：\(ev.effectText)")
                }
            }
            saveData.containers[idx].instance = inst
        }

        saveData.ecoPoints = pointsBuffer
        saveData.unlockedCodexIDs = codexBuffer
        if !newCodexAll.isEmpty {
            hasWeatherEvent = true
            let names = Self.codexNames(for: newCodexAll)
            appendEventMessage("图鉴新解锁：\(names)")
        }

        if updateLastSavedAt {
            saveData.lastSavedAt = now
        }
        syncPublishedFromSaveData(now: now)
        if activeCrittersChanged {
            vfxSubject.send(.syncCritters)
        }
        persistence.save(saveData)
        if isSchedulerRunning && updateLastSavedAt {
            Task { @MainActor [weak self] in
                await self?.refreshLocalWeatherIfNeeded()
            }
        }
    }

    func flushSave() {
        processBackgroundTick(now: Date(), updateLastSavedAt: true)
    }

    // MARK: - 普通模式允许的自然演进交互

    func mist() {
        var inst = activeInstance
        guard !inst.isSleeping else { return }
        bannerNotice = nil

        inst.humidity = TerrariumSimulation.clampHumidity(inst.humidity + 12)
        inst.mistDewBoostSeconds = 180.0
        if inst.biome != .aquatic && inst.humidity >= TerrariumConfig.dewLightHumidityThreshold {
            inst.glassFogLevel = min(1.0, inst.glassFogLevel + 0.03)
        }
        TerrariumSimulation.updatePlants(instance: &inst, dt: 0)

        // 冷启动破冰加速：每缸终身仅限 1 次（防止“喷水催芽->修剪幼苗”刷点循环）
        let sproutHumThreshold = (inst.biome == .rainforest) ? 60 : ((inst.biome == .aquatic) ? 55 : 45)
        if !inst.hasTriggeredColdStart && inst.plants.isEmpty && inst.humidity >= sproutHumThreshold {
            inst.plantPulseSeconds += 8.0
            if inst.plantPulseSeconds >= TerrariumConfig.coldStartPlantPulseSeconds {
                inst.plantPulseSeconds = 0
                if let firstPlant = TerrariumSimulation.attemptRandomPlantSpawn(instance: &inst) {
                    unlockCodexIfNeeded(firstPlant.speciesID, bonus: TerrariumConfig.codexRewardPoints(for: firstPlant.speciesID))
                    bannerNotice = "🌱 第一抹生命「\(Self.codexName(for: firstPlant.speciesID))」破土而出！"
                }
            }
        }

        // 喷水同时带有一点物理凉爽体感 (-1°C，不超过室温基线太多)
        if inst.humidity >= 80 && inst.temperature > 20 {
            inst.temperature = TerrariumSimulation.clampTemp(inst.temperature - 1)
        }

        activeInstance = inst
        vfxSubject.send(.mist)
        evaluateCurrentCodexAndSave()
    }

    func feed() {
        var inst = activeInstance
        guard !inst.isSleeping else { return }
        guard inst.foodBowlPortions < TerrariumConfig.maxFoodPortions else {
            bannerNotice = "🥣 食盆已满，等小动物吃掉一些再投喂吧"
            return
        }
        bannerNotice = nil
        inst.foodBowlPortions += 1
        lastFedAt = Date()

        // 食盆香气与喂食提醒（改为生态点购买生物后，食盆专用于喂食互动与维持饱腹产出）
        TerrariumSimulation.evaluateCritterEcology(instance: &inst)
        activeInstance = inst

        let feedCoord = TerrariumConfig.feedingCoord(for: inst.biome)
        let targetGZ = (inst.biome == .aquatic) ? TerrariumConfig.waterSurfaceGZ : 3.0
        let bowlPt = TerrariumConfig.isoToScreen(
            gx: Double(feedCoord.col) + 0.5,
            gy: Double(feedCoord.row) + 0.5,
            gz: targetGZ
        )
        vfxSubject.send(.feed(bowlScreenPos: bowlPt))

        if inst.critters.filter({ $0.residency == .resident || $0.residency == .visitor }).isEmpty {
            bannerNotice = (inst.biome == .aquatic)
                ? "🥣 已投放浮水鱼粮至喂食圈 · 前往「生物」可用生态点领养水生精灵"
                : "🥣 已添粮至食盆 · 前往「生物」可用生态点领养小生命"
        }

        evaluateCurrentCodexAndSave()
    }

    func clean() {
        var inst = activeInstance
        guard !inst.isSleeping else { return }
        bannerNotice = nil
        let witheredCount = inst.plants.filter { $0.stage == .withered }.count
        inst.plants.removeAll { $0.stage == .withered }
        inst.glassFogLevel = 0.0
        if witheredCount > 0 {
            saveData.ecoPoints += witheredCount
            bannerNotice = (inst.biome == .aquatic)
                ? "✨ 已擦净玻璃藻垢并清理 \(witheredCount) 株枯植（+\(witheredCount)点）"
                : "✨ 已擦净水雾并清理 \(witheredCount) 株枯植（+\(witheredCount)点）"
        } else {
            bannerNotice = (inst.biome == .aquatic)
                ? "✨ 已擦净鱼缸玻璃藻垢"
                : "✨ 已擦拭玻璃内壁水雾"
        }
        activeInstance = inst
        vfxSubject.send(.clean)
        commitStateChange()
    }

    func toggleSleep() {
        var inst = activeInstance
        bannerNotice = nil
        inst.isSleeping.toggle()
        if !inst.isSleeping && Date() >= inst.nextWeatherEventAt {
            inst.nextWeatherEventAt = Date().addingTimeInterval(TerrariumSimulation.nextWeatherEventDelay())
        }
        activeInstance = inst
        commitStateChange()
    }

    /// 动画状态机通知某只动物在食盆/喂食圈旁完成进食（防免费刷点：仅饥饿≥55且距上次领奖≥3小时才奖励 +1 点）
    func completeCritterMeal(kind: CritterKind, at screenPoint: CGPoint, now: Date = Date()) {
        var inst = activeInstance
        guard !inst.isSleeping, inst.foodBowlPortions > 0 else { return }
        inst.foodBowlPortions -= 1

        var reward = 0
        if let idx = inst.critters.firstIndex(where: { $0.kind == kind }) {
            let prevHunger = inst.critters[idx].hunger
            let lastRewardAt = inst.critters[idx].lastFedRewardAt ?? .distantPast
            if prevHunger >= 55.0 && now.timeIntervalSince(lastRewardAt) >= TerrariumConfig.mealRewardCooldownSeconds {
                reward = 1
                inst.critters[idx].lastFedRewardAt = now
            }
            inst.critters[idx].hunger = max(0.0, prevHunger - 45.0)
            inst.critters[idx].mealsEaten += 1

            if inst.critters[idx].residency == .visitor {
                let req = TerrariumConfig.mealsRequiredToSettle(kind: kind, enabledDecorIDs: inst.enabledDecorIDs)
                if inst.critters[idx].mealsEaten >= req {
                    inst.critters[idx].residency = .resident
                    let name = Self.critterNames(for: [kind])
                    bannerNotice = "🎉 访客「\(name)」喜欢这里，正式定居了！"
                    unlockCodexIfNeeded(kind.rawValue, bonus: TerrariumConfig.codexRewardPoints(for: kind.rawValue))
                }
            }
        }

        if reward > 0 {
            saveData.ecoPoints += reward
        }
        activeInstance = inst
        vfxSubject.send(.ecoPopup(text: reward > 0 ? "+\(reward)" : "饱腹!", at: screenPoint))
        evaluateCurrentCodexAndSave()
    }

    func recordCritterStartle(kind: CritterKind, now: Date = Date()) {
        lastStartleAtByKind[kind] = now
    }

    private static func dayKey(for date: Date) -> String {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    /// 五阶羁绊轻抚（纯养成与性格被动特技增益，0 点击直发点数；受 20 分钟/只冷却、日限 6 次与受惊缓神制约）
    @discardableResult
    func petCritter(kind: CritterKind, at screenPoint: CGPoint, now: Date = Date()) -> PetOutcome {
        var inst = activeInstance
        guard !inst.isSleeping,
              let idx = inst.critters.firstIndex(where: { $0.kind == kind }) else {
            return .onCooldown(remainingMinutes: 0)
        }

        let nickname = inst.critters[idx].nickname ?? TerrariumConfig.defaultNickname(for: kind)
        let personality = inst.critters[idx].personality

        if let startledAt = lastStartleAtByKind[kind],
           now.timeIntervalSince(startledAt) < TerrariumConfig.startleRecoverySeconds {
            bannerNotice = "⏳ 「\(nickname)」刚刚受惊正在缓神中，稍后再轻抚它吧"
            return .recoveringFromStartle
        }

        let todayKey = Self.dayKey(for: now)
        if inst.critters[idx].dailyPetDateKey != todayKey {
            inst.critters[idx].dailyPetDateKey = todayKey
            inst.critters[idx].dailyPetCount = 0
        }

        if inst.critters[idx].dailyPetCount >= TerrariumConfig.maxDailyEffectivePets {
            bannerNotice = "💕 今天「\(nickname)」已收获满满心意（每日好感 \(TerrariumConfig.maxDailyEffectivePets)/\(TerrariumConfig.maxDailyEffectivePets)）"
            activeInstance = inst
            commitStateChange()
            return .dailyLimitReached
        }

        if let lastPet = inst.critters[idx].lastPettedAt {
            let elapsed = now.timeIntervalSince(lastPet)
            if elapsed < TerrariumConfig.petAffinityCooldownSeconds {
                let minsLeft = max(1, Int(ceil((TerrariumConfig.petAffinityCooldownSeconds - elapsed) / 60.0)))
                bannerNotice = "💕 轻轻摸了「\(nickname)」(\(personality)) · \(minsLeft)分钟后可继续增进好感"
                return .onCooldown(remainingMinutes: minsLeft)
            }
        }

        let prevStage = TerrariumConfig.affinityStage(for: inst.critters[idx].affinity)
        let delta = (inst.critters[idx].hunger < 30.0) ? 4 : 3
        let nextAffinity = min(TerrariumConfig.maxAffinity, inst.critters[idx].affinity + delta)
        let actualDelta = nextAffinity - inst.critters[idx].affinity
        inst.critters[idx].affinity = nextAffinity
        inst.critters[idx].lastPettedAt = now
        inst.critters[idx].dailyPetCount += 1

        let newStage = TerrariumConfig.affinityStage(for: nextAffinity)
        let leveledUp = newStage > prevStage
        activeInstance = inst

        if leveledUp {
            let perkDesc = TerrariumConfig.perkDescription(for: personality, stage: newStage)
            bannerNotice = "✨ 「\(nickname)」好感晋升【\(newStage.title)】（\(nextAffinity)/\(TerrariumConfig.maxAffinity)）· 解锁「\(perkDesc)」"
            vfxSubject.send(.ecoPopup(text: "\(newStage.title)!", at: screenPoint))
        } else {
            let baseReply = TerrariumConfig.petReplyText(nickname: nickname, stage: newStage)
            bannerNotice = "\(baseReply) · 好感 \(nextAffinity)/\(TerrariumConfig.maxAffinity)"
        }
        commitStateChange()
        return .gained(delta: actualDelta, newStage: newStage, leveledUp: leveledUp)
    }

    // MARK: - 植物轻修剪与移栽交互

    func selectPlant(_ id: UUID?) {
        selectedPlantID = id
        isMovingPlant = false
        isConfirmingPrunePlant = false
        if id != nil {
            selectedDecorID = nil
            movingDecorID = nil
        }
    }

    func beginMoveSelectedPlant() {
        guard selectedPlant != nil else { return }
        isMovingPlant = true
        isConfirmingPrunePlant = false
        movingDecorID = nil
        bannerNotice = "🪴 请点击沙盘中绿色空地格子完成植物移栽"
    }

    func moveSelectedPlant(to coord: GridCoord) {
        guard let targetID = selectedPlantID else { return }
        var inst = activeInstance
        guard let idx = inst.plants.firstIndex(where: { $0.id == targetID }),
              GridPathfinder.isInsideGrid(coord) else { return }

        let others = inst.plants.filter { $0.id != targetID }
        let blockedCoords = GridPathfinder.buildNonPlantableSet(
            enabledDecorIDs: inst.enabledDecorIDs,
            plants: others,
            decorOrigins: inst.decorOrigins,
            biome: inst.biome
        )
        guard !blockedCoords.contains(coord) else {
            bannerNotice = (inst.biome == .aquatic)
                ? "⚠️ 该位置已有摆件、水草或处于喂食圈水域，请另选空位"
                : "⚠️ 该位置已有摆件、植被或处于食盆净空区，请另选空位"
            return
        }

        inst.plants[idx].coord = coord
        let name = Self.codexName(for: inst.plants[idx].speciesID)
        activeInstance = inst
        isMovingPlant = false
        bannerNotice = "🪴 已将「\(name)」移栽至 (\(coord.col),\(coord.row))"
        vfxSubject.send(.clean)
        commitStateChange()
    }

    func pruneSelectedPlant() {
        guard let targetID = selectedPlantID else { return }
        var inst = activeInstance
        guard let idx = inst.plants.firstIndex(where: { $0.id == targetID }) else { return }
        let removed = inst.plants.remove(at: idx)
        let name = Self.codexName(for: removed.speciesID)
        let refundPts = (removed.stage == .sprout) ? 0 : 1
        saveData.ecoPoints += refundPts
        activeInstance = inst
        selectedPlantID = nil
        isMovingPlant = false
        let pt = TerrariumConfig.isoToScreen(gx: Double(removed.coord.col) + 0.5, gy: Double(removed.coord.row) + 0.5, gz: 6)
        if refundPts > 0 {
            vfxSubject.send(.ecoPopup(text: "+\(refundPts)", at: pt))
            bannerNotice = "✂️ 轻修剪「\(name)」返还 +\(refundPts) 生态点"
        } else {
            bannerNotice = "✂️ 已移除幼苗「\(name)」（幼苗清理不返还生态点）"
        }
        vfxSubject.send(.clean)
        commitStateChange()
    }

    static func displayName(forPlantSpecies speciesID: String) -> String {
        codexName(for: speciesID)
    }

    static func stageLabel(for stage: PlantStage) -> String {
        switch stage {
        case .sprout: return "幼苗"
        case .mature: return "茂盛"
        case .lushDew: return "凝露"
        case .wilting: return "缺水"
        case .withered: return "枯萎"
        }
    }

    func updateCritterCoord(kind: CritterKind, coord: GridCoord) {
        var inst = activeInstance
        if let idx = inst.critters.firstIndex(where: { $0.kind == kind }) {
            inst.critters[idx].coord = coord
            activeInstance = inst
        }
    }

    // MARK: - 摆件选中与自由摆放（动态重算占地与 Y-Sort）

    func selectDecor(_ id: String?) {
        selectedDecorID = id
        movingDecorID = nil
        if id != nil {
            selectedPlantID = nil
            isMovingPlant = false
        }
    }

    func beginMoveDecor(_ id: String) {
        guard activeInstance.enabledDecorIDs.contains(id) else { return }
        selectedDecorID = id
        movingDecorID = id
        selectedPlantID = nil
        isMovingPlant = false
        let dims = TerrariumConfig.decorDimensions(for: id)
        bannerNotice = "🪵 请点击沙盘中绿色格子放置该 \(dims.cols)×\(dims.rows) 摆件"
    }

    func moveSelectedDecor(to origin: GridCoord) {
        guard let decorID = movingDecorID else { return }
        var inst = activeInstance
        guard GridPathfinder.canPlaceDecor(
            id: decorID,
            at: origin,
            enabledDecorIDs: inst.enabledDecorIDs,
            decorOrigins: inst.decorOrigins,
            plants: inst.plants,
            biome: inst.biome
        ) else {
            bannerNotice = "⚠️ 目标范围存在越界、植物、食盆净空区或其他摆件"
            return
        }

        inst.decorOrigins[decorID] = origin
        activeInstance = inst
        movingDecorID = nil
        let name = TerrariumConfig.decorCatalog(for: inst.biome).first(where: { $0.id == decorID })?.name ?? decorID
        bannerNotice = "🪵 已将「\(name)」重新摆放至 (\(origin.col),\(origin.row))"
        vfxSubject.send(.clean)
        commitStateChange()
    }

    func handleDecorAction(id: String) {
        var inst = activeInstance
        let catalog = TerrariumConfig.decorCatalog(for: inst.biome)
        guard let item = catalog.first(where: { $0.id == id }) else { return }
        let isUnlocked = inst.unlockedDecorIDs.contains(id)

        if isUnlocked {
            if inst.enabledDecorIDs.contains(id) {
                inst.enabledDecorIDs.removeAll { $0 == id }
                if selectedDecorID == id {
                    selectedDecorID = nil
                    movingDecorID = nil
                }
            } else {
                // 若默认位与植物或其它摆件重叠，自动搜寻首个可摆放空位
                let currentOrigin = TerrariumConfig.effectiveDecorOrigin(for: id, decorOrigins: inst.decorOrigins)
                if !GridPathfinder.canPlaceDecor(id: id, at: currentOrigin, enabledDecorIDs: inst.enabledDecorIDs, decorOrigins: inst.decorOrigins, plants: inst.plants, biome: inst.biome),
                   let freeOrigin = firstValidDecorOrigin(for: id, in: inst) {
                    inst.decorOrigins[id] = freeOrigin
                }
                inst.enabledDecorIDs.append(id)
                let footprint = Set(TerrariumConfig.footprint(for: id, decorOrigins: inst.decorOrigins))
                inst.plants.removeAll { footprint.contains($0.coord) }
            }
        } else if saveData.ecoPoints >= item.cost {
            saveData.ecoPoints -= item.cost
            inst.unlockedDecorIDs.append(id)
            let currentOrigin = TerrariumConfig.effectiveDecorOrigin(for: id, decorOrigins: inst.decorOrigins)
            if !GridPathfinder.canPlaceDecor(id: id, at: currentOrigin, enabledDecorIDs: inst.enabledDecorIDs, decorOrigins: inst.decorOrigins, plants: inst.plants, biome: inst.biome),
               let freeOrigin = firstValidDecorOrigin(for: id, in: inst) {
                inst.decorOrigins[id] = freeOrigin
            }
            inst.enabledDecorIDs.append(id)
            let footprint = Set(TerrariumConfig.footprint(for: id, decorOrigins: inst.decorOrigins))
            inst.plants.removeAll { footprint.contains($0.coord) }
            bannerNotice = "已解锁并摆放「\(item.name)」（可在生态箱点击调整位置）"
        }

        TerrariumSimulation.evaluateCritterEcology(instance: &inst)
        activeInstance = inst
        vfxSubject.send(.syncCritters)
        commitStateChange()
    }

    private func firstValidDecorOrigin(for decorID: String, in inst: TerrariumInstanceState) -> GridCoord? {
        for r in 0..<TerrariumConfig.gridRows {
            for c in 0..<TerrariumConfig.gridCols {
                let candidate = GridCoord(col: c, row: r)
                if GridPathfinder.canPlaceDecor(id: decorID, at: candidate, enabledDecorIDs: inst.enabledDecorIDs, decorOrigins: inst.decorOrigins, plants: inst.plants, biome: inst.biome) {
                    return candidate
                }
            }
        }
        return nil
    }

    // MARK: - 生物生态点购买与食物链互斥切换

    func critterEligibility(_ kind: CritterKind) -> (eligible: Bool, missingReason: String) {
        TerrariumSimulation.critterUnlockEligibility(kind: kind, instance: activeInstance)
    }

    func critterPurchaseAndToggle(_ kind: CritterKind) {
        var inst = activeInstance
        guard let spec = TerrariumConfig.critterShopCatalog(for: inst.biome).first(where: { $0.kind == kind }) else { return }

        if let existingIdx = inst.critters.firstIndex(where: { $0.kind == kind }) {
            let cur = inst.critters[existingIdx].residency
            if cur == .resident || cur == .visitor {
                inst.critters[existingIdx].residency = .stored
                bannerNotice = "📦 已将「\(spec.name)」收起至生物仓"
            } else {
                let check = TerrariumSimulation.critterUnlockEligibility(kind: kind, instance: inst)
                guard check.eligible else {
                    bannerNotice = "⚠️ 暂无法放回「\(spec.name)」：\(check.missingReason)"
                    return
                }
                let swapped = TerrariumSimulation.placeOrSwapCritter(kind: kind, instance: &inst)
                if swapped.isEmpty {
                    bannerNotice = "🐾 已将「\(spec.name)」放入生态箱"
                } else {
                    let swappedNames = Self.critterNames(for: swapped)
                    bannerNotice = "⚖️ 食物链互斥：已放入「\(spec.name)」，并自动收纳「\(swappedNames)」"
                }
            }
            activeInstance = inst
            vfxSubject.send(.syncCritters)
            evaluateCurrentCodexAndSave()
            return
        }

        // 全新购买：需生态门槛达标 + 生态点足够
        let check = TerrariumSimulation.critterUnlockEligibility(kind: kind, instance: inst)
        guard check.eligible else {
            bannerNotice = "⚠️ 尚未达成生态前置条件：\(check.missingReason)"
            return
        }
        guard saveData.ecoPoints >= spec.cost else {
            bannerNotice = "⚠️ 生态点不足（需要 \(spec.cost) 点）"
            return
        }

        saveData.ecoPoints -= spec.cost
        let swapped = TerrariumSimulation.placeOrSwapCritter(kind: kind, instance: &inst)
        activeInstance = inst
        unlockCodexIfNeeded(kind.rawValue, bonus: TerrariumConfig.codexRewardPoints(for: kind.rawValue))

        if swapped.isEmpty {
            bannerNotice = "🎉 已领养「\(spec.name)」入驻生态箱！"
        } else {
            let swappedNames = Self.critterNames(for: swapped)
            bannerNotice = "⚖️ 已领养「\(spec.name)」入驻（因食物链互斥自动收纳了「\(swappedNames)」）"
        }
        vfxSubject.send(.syncCritters)
        evaluateCurrentCodexAndSave()
    }

    // MARK: - 物理温控设备购买与开关（夹缸加热灯/棒 / 降温扇，需生态点解锁后自由切换）

    var activeContainerRefundEstimate: Int {
        guard !saveData.containers.isEmpty else { return 0 }
        return TerrariumSimulation.refundEcoPoints(for: saveData.containers[activeContainerIndex])
    }

    func toggleThermalMode(_ targetMode: ThermalMode) {
        let inst = activeInstance
        guard !inst.isSleeping else { return }

        // 方案 A：购买安装与开关运行解耦，未购买时先弹出二次确认安装（待机挂壁），不直接开机
        if targetMode == .heating && !inst.hasHeatLamp {
            pendingPurchaseThermalMode = (pendingPurchaseThermalMode == .heating) ? nil : .heating
            return
        } else if targetMode == .cooling && !inst.hasCoolingFan {
            pendingPurchaseThermalMode = (pendingPurchaseThermalMode == .cooling) ? nil : .cooling
            return
        }

        pendingPurchaseThermalMode = nil
        var updated = inst
        let nextMode: ThermalMode = (updated.thermalMode == targetMode) ? .natural : targetMode
        updated.thermalMode = nextMode
        updated.ambientRelaxSeconds = 0

        let targetAmbient = TerrariumConfig.baseAmbientTemp(
            for: updated.atmosphere,
            biome: updated.biome,
            thermalMode: nextMode,
            localOutdoorTempC: saveData.lastKnownLocalTempC
        )

        switch nextMode {
        case .heating:
            let equipName = (updated.biome == .aquatic) ? "恒温加热棒" : "夹缸晒背灯"
            bannerNotice = "☀️ 已开启\(equipName)：正随时间稳态升温至 \(targetAmbient)°C"
        case .cooling:
            bannerNotice = "❄️ 已开启夹缸降温扇：正随时间稳态降温至 \(targetAmbient)°C"
        case .natural:
            bannerNotice = "🌿 已关闭温控器材，回归自然室温 (\(targetAmbient)°C)"
        }

        TerrariumSimulation.updatePlants(instance: &updated, dt: 0)
        TerrariumSimulation.evaluateCritterEcology(instance: &updated)
        activeInstance = updated
        vfxSubject.send(.syncCritters)
        evaluateCurrentCodexAndSave()
    }

    func confirmPurchaseThermalEquipment() {
        guard let targetMode = pendingPurchaseThermalMode else { return }
        var inst = activeInstance
        guard !inst.isSleeping else { return }

        if targetMode == .heating && !inst.hasHeatLamp {
            let cost = TerrariumConfig.heatLampCost
            guard saveData.ecoPoints >= cost else {
                let equipName = (inst.biome == .aquatic) ? "恒温加热棒" : "夹缸晒背灯"
                bannerNotice = "⚠️ 购置「\(equipName)」需要 \(cost) 生态点"
                pendingPurchaseThermalMode = nil
                return
            }
            saveData.ecoPoints -= cost
            inst.hasHeatLamp = true
            let equipName = (inst.biome == .aquatic) ? "恒温加热棒" : "夹缸晒背灯"
            bannerNotice = "🔌 已购置并安装「\(equipName)」，随时点击 ☀️ 即可开关"
        } else if targetMode == .cooling && !inst.hasCoolingFan {
            let cost = TerrariumConfig.coolingFanCost
            guard saveData.ecoPoints >= cost else {
                bannerNotice = "⚠️ 购置「夹缸静音降温扇」需要 \(cost) 生态点"
                pendingPurchaseThermalMode = nil
                return
            }
            saveData.ecoPoints -= cost
            inst.hasCoolingFan = true
            bannerNotice = "🔌 已购置并安装「夹缸静音降温扇」，随时点击 ❄️ 即可开关"
        }

        pendingPurchaseThermalMode = nil
        activeInstance = inst
        evaluateCurrentCodexAndSave()
    }

    func cancelPurchaseThermalEquipment() {
        pendingPurchaseThermalMode = nil
    }

    // MARK: - 多容器生态缸自由切换、购置与拆缸退点（上限 8 口）

    func selectContainer(id: UUID) {
        guard saveData.containers.contains(where: { $0.id == id }),
              saveData.activeContainerID != id else { return }
        saveData.activeContainerID = id
        selectedPlantID = nil
        isMovingPlant = false
        selectedDecorID = nil
        movingDecorID = nil
        isShowingBuyTankSheet = false
        isConfirmingDeleteTank = false
        bannerNotice = "已切换至「\(saveData.containers[activeContainerIndex].customName)」"
        commitStateChange()
        vfxSubject.send(.syncCritters)
    }

    @discardableResult
    func purchaseNewTank(biome: TerrariumBiome, customName: String? = nil) -> Bool {
        guard saveData.containers.count < TerrariumConfig.maxTankSlots else {
            bannerNotice = "⚠️ 已达到最大缸体容量上限 (\(TerrariumConfig.maxTankSlots)/\(TerrariumConfig.maxTankSlots))"
            return false
        }
        let cost = TerrariumConfig.tankPurchaseCost(for: biome, existingTankCount: saveData.containers.count)
        guard saveData.ecoPoints >= cost else {
            bannerNotice = "⚠️ 生态点不足（购置「\(biome.rawValue)」需 \(cost) 点）"
            return false
        }

        let sameTypeCount = saveData.containers.filter { $0.instance.biome == biome }.count
        let shortTitle = biome.rawValue.replacingOccurrences(of: "缸", with: "")
        let assignedName = (customName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? customName!
            : "\(shortTitle)缸 #\(sameTypeCount + 1)"

        var emptyInstance = TerrariumInstanceState.empty(
            biome: biome,
            now: Date(),
            nextEventDelay: TerrariumSimulation.nextWeatherEventDelay()
        )
        if let localTemp = saveData.lastKnownLocalTempC {
            emptyInstance.temperature = TerrariumConfig.baseAmbientTemp(
                for: emptyInstance.atmosphere,
                biome: biome,
                thermalMode: .natural,
                localOutdoorTempC: localTemp
            )
        }
        let newContainer = TerrariumContainer(
            customName: assignedName,
            purchasedCost: cost,
            instance: emptyInstance
        )
        saveData.ecoPoints -= cost
        saveData.containers.append(newContainer)
        saveData.activeContainerID = newContainer.id
        selectedPlantID = nil
        isMovingPlant = false
        selectedDecorID = nil
        movingDecorID = nil
        isShowingBuyTankSheet = false
        isConfirmingDeleteTank = false
        bannerNotice = "\(biome.iconEmoji) 已购置新缸「\(assignedName)」！（-\(cost)点）"
        commitStateChange()
        vfxSubject.send(.syncCritters)
        return true
    }

    @discardableResult
    func deleteActiveContainer() -> Int {
        guard saveData.containers.count > 1 else {
            bannerNotice = "⚠️ 至少需保留 1 口生态缸"
            isConfirmingDeleteTank = false
            return 0
        }
        let idx = activeContainerIndex
        let removed = saveData.containers.remove(at: idx)
        let refund = TerrariumSimulation.refundEcoPoints(for: removed)
        saveData.ecoPoints += refund
        saveData.activeContainerID = saveData.containers[0].id
        selectedPlantID = nil
        isMovingPlant = false
        selectedDecorID = nil
        movingDecorID = nil
        isShowingBuyTankSheet = false
        isConfirmingDeleteTank = false
        bannerNotice = "♻️ 已拆除「\(removed.customName)」，退回 +\(refund) 生态点"
        commitStateChange()
        vfxSubject.send(.syncCritters)
        return refund
    }

    func renameActiveContainer(to rawName: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !saveData.containers.isEmpty else { return }
        saveData.containers[activeContainerIndex].customName = String(trimmed.prefix(16))
        commitStateChange()
    }

    // MARK: - 管理员模式专属接口（普通模式严格拦截）

    func adjustTemp(_ delta: Int) {
        guard isAdminMode, !activeInstance.isSleeping else { return }
        bannerNotice = nil
        var inst = activeInstance
        inst.temperature = TerrariumSimulation.clampTemp(inst.temperature + delta)
        TerrariumSimulation.updatePlants(instance: &inst, dt: 0)
        TerrariumSimulation.evaluateCritterEcology(instance: &inst)
        activeInstance = inst
        vfxSubject.send(.syncCritters)
        evaluateCurrentCodexAndSave()
    }

    func adjustHumidity(_ delta: Int) {
        guard isAdminMode, !activeInstance.isSleeping else { return }
        bannerNotice = nil
        var inst = activeInstance
        inst.humidity = TerrariumSimulation.clampHumidity(inst.humidity + delta)
        TerrariumSimulation.updatePlants(instance: &inst, dt: 0)
        TerrariumSimulation.evaluateCritterEcology(instance: &inst)
        activeInstance = inst
        vfxSubject.send(.syncCritters)
        evaluateCurrentCodexAndSave()
    }

    func setAtmosphere(_ newAtmosphere: SceneAtmosphere) {
        guard isAdminMode, !activeInstance.isSleeping else { return }
        bannerNotice = nil
        var inst = activeInstance
        inst.atmosphere = newAtmosphere
        inst.weatherCooldownEndAt = Date().addingTimeInterval(TerrariumConfig.weatherEventDurationSeconds)
        activeInstance = inst
        evaluateCurrentCodexAndSave()
    }

    func simulateWeatherEvent() {
        guard isAdminMode, !activeInstance.isSleeping else { return }
        var inst = activeInstance
        if let chosen = TerrariumConfig.weatherEvents.randomElement() {
            TerrariumSimulation.applyWeatherEvent(chosen, to: &inst, now: Date())
            TerrariumSimulation.updatePlants(instance: &inst, dt: 0)
            hasWeatherEvent = true
            appendEventMessage("\(chosen.title)：\(chosen.effectText)")
        }
        activeInstance = inst
        evaluateCurrentCodexAndSave()
    }

    func triggerPlantPulseDebug() {
        guard isAdminMode, !activeInstance.isSleeping else { return }
        var inst = activeInstance
        if let spawned = TerrariumSimulation.attemptRandomPlantSpawn(instance: &inst, randomUnit: { 0.0 }) {
            TerrariumSimulation.updatePlants(instance: &inst, dt: 300)
            unlockCodexIfNeeded(spawned.speciesID, bonus: 3)
            bannerNotice = "🌱 [管理员] 已催生：\(Self.codexName(for: spawned.speciesID))"
            activeInstance = inst
            evaluateCurrentCodexAndSave()
        } else {
            bannerNotice = "🌱 [管理员] 暂无合适空格或植物已达上限"
        }
    }

    func adjustEcoPointsDebug(_ delta: Int) {
        guard isAdminMode else { return }
        saveData.ecoPoints = max(0, saveData.ecoPoints + delta)
        commitStateChange()
    }

    func dismissEvent() {
        hasWeatherEvent = false
        eventMessage = nil
    }

    func resetSaveData() {
        persistence.reset()
        saveData = TerrariumSaveData(lastSavedAt: Date())
        hasWeatherEvent = false
        eventMessage = nil
        selectedPlantID = nil
        isMovingPlant = false
        selectedDecorID = nil
        movingDecorID = nil
        isShowingBuyTankSheet = false
        bannerNotice = "存档已重置 · 欢迎开启 Day 0 空缸生态培育"
        commitStateChange()
        vfxSubject.send(.syncCritters)
    }

    // MARK: - 内部同步与持久化

    private func unlockCodexIfNeeded(_ id: String, bonus: Int) {
        guard !saveData.unlockedCodexIDs.contains(id) else { return }
        saveData.unlockedCodexIDs.append(id)
        saveData.ecoPoints += bonus
        hasWeatherEvent = true
        appendEventMessage("图鉴新解锁：\(Self.codexName(for: id))（+\(bonus)点）")
    }

    private func evaluateCurrentCodexAndSave() {
        let inst = activeInstance
        if !inst.isSleeping {
            let newlyUnlocked = TerrariumSimulation.evaluateCodexUnlocks(
                instance: inst,
                alreadyUnlocked: Set(saveData.unlockedCodexIDs)
            )
            if !newlyUnlocked.isEmpty {
                for id in newlyUnlocked {
                    unlockCodexIfNeeded(id, bonus: TerrariumConfig.codexRewardPoints(for: id))
                }
            }
        }
        commitStateChange()
    }

    private func appendEventMessage(_ text: String) {
        if let existing = eventMessage, !existing.isEmpty {
            if !existing.contains(text) {
                eventMessage = "\(existing) · \(text)"
            }
        } else {
            eventMessage = text
        }
    }

    private static func codexName(for id: String) -> String {
        TerrariumConfig.defaultCodexEntries().first(where: { $0.id == id })?.name ?? id
    }

    private static func codexNames(for ids: [String]) -> String {
        ids.map { codexName(for: $0) }.joined(separator: "、")
    }

    private static func critterNames(for kinds: [CritterKind]) -> String {
        kinds.map { codexName(for: $0.rawValue) }.joined(separator: "、")
    }

    private func commitStateChange() {
        let now = Date()
        saveData.lastSavedAt = now
        syncPublishedFromSaveData(now: now)
        persistence.save(saveData)
    }

    private func syncPublishedFromSaveData(now: Date = Date()) {
        let inst = activeInstance
        containers = saveData.containers
        activeContainerID = saveData.activeContainerID
        activeContainerName = saveData.containers.isEmpty ? "苔原缸 #1" : saveData.containers[activeContainerIndex].customName
        currentBiome = inst.biome
        thermalMode = inst.thermalMode
        hasHeatLamp = inst.hasHeatLamp
        hasCoolingFan = inst.hasCoolingFan
        atmosphere = inst.atmosphere
        temperature = inst.temperature
        humidity = inst.humidity
        isSleeping = inst.isSleeping
        ecoPoints = saveData.ecoPoints
        foodBowlPortions = inst.foodBowlPortions
        glassFogLevel = inst.glassFogLevel
        mistDewBoostSeconds = inst.mistDewBoostSeconds
        plants = inst.plants
        critters = inst.critters
        decorOrigins = inst.decorOrigins
        localOutdoorTempC = saveData.lastKnownLocalTempC
        localCityName = saveData.lastKnownLocalCity

        let unlockedCodexSet = Set(saveData.unlockedCodexIDs)
        codexEntries = TerrariumConfig.defaultCodexEntries().map { entry in
            var copy = entry
            copy.unlocked = unlockedCodexSet.contains(entry.id)
            return copy
        }

        let unlockedDecorSet = Set(inst.unlockedDecorIDs)
        let enabledDecorSet = Set(inst.enabledDecorIDs)
        decorItems = TerrariumConfig.decorCatalog(for: inst.biome).map { item in
            var copy = item
            copy.unlocked = unlockedDecorSet.contains(item.id)
            copy.enabled = enabledDecorSet.contains(item.id)
            return copy
        }

        let remaining = max(0, inst.nextWeatherEventAt.timeIntervalSince(now))
        nextEventMinutesRemaining = max(1, Int(ceil(remaining / 60.0)))
    }
}
