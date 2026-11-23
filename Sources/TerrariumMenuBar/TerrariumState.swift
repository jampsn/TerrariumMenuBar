import AppKit
import Combine
import Foundation
import os
import SwiftUI
import TerrariumCore

private let stateLogger = Logger(subsystem: "com.ccgs.TerrariumMenuBar", category: "State")

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
    @Published var activeContainerName: String = TerrariumL10n.t("tank.default_name", ["biome": TerrariumBiome.meadow.localizedShortName, "index": "1"])
    @Published var languagePreference: AppLanguagePreference = TerrariumL10n.shared.preference
    @Published var activeLanguage: SupportedLanguage = TerrariumL10n.shared.currentLanguage
    @Published var temperatureUnit: TemperatureUnit = TerrariumL10n.shared.currentTemperatureUnit
    @Published var tipsFrequency: DailyTipsFrequency = TerrariumL10n.shared.currentTipsFrequency
    @Published var currentTipIndex: Int = Int.random(in: 0..<13)
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
    @Published var codexMilestoneTitle: String = TerrariumConfig.codexMilestoneTitle(unlockedCount: 0)
    @Published var unlockedFrameSkinIDs: [String] = [TankFrameSkin.classic.rawValue]
    @Published var activeFrameSkin: TankFrameSkin = .classic
    @Published var isResonanceActive: Bool = false
    @Published var unlockedCodexIDs: [String] = []
    @Published var twilightIntensity: Double = 0.0
    @Published var isShowingRenameTankSheet: Bool = false
    @Published var renameTankDraft: String = ""
    @Published var renamingCritterKind: CritterKind? = nil
    @Published var renameCritterDraft: String = ""
    @Published var unlockedAchievementIDs: [String] = []
    @Published var equippedTitleID: String? = nil
    @Published var isShowingAchievementsInCodexTab: Bool = false
    @Published var idleDays: Int = 0
    @Published var activeContainerDays: Int = 0

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
    private var lastTipRotateAt: Date = Date()

    init(persistence: TerrariumPersistence = TerrariumPersistence(), startScheduler: Bool = true) {
        self.persistence = persistence
        let now = Date()

        if var loaded = persistence.load() {
            if loaded.containers.isEmpty {
                stateLogger.error("Loaded save had empty containers; restoring default meadow tank.")
                loaded = TerrariumSaveData()
            }
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
                self.bannerNotice = TerrariumL10n.t("state.betta_stowed", ["names": stowedNames])
            } else if summary.totalEarnedEcoPoints > 0 {
                self.bannerNotice = TerrariumL10n.t("state.welcome_offline", ["pts": "\(summary.totalEarnedEcoPoints)"])
            }
            if !summary.newlyUnlockedCodexIDs.isEmpty {
                self.hasWeatherEvent = true
                let names = Self.codexNames(for: summary.newlyUnlockedCodexIDs)
                self.appendEventMessage(TerrariumL10n.t("state.offline_codex", ["names": names]))
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

    var localizedLocalCityName: String {
        if let city = localCityName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !city.isEmpty,
           city != "本地" {
            return city
        }
        return TerrariumL10n.t("sensor.local_fallback")
    }

    func setLanguagePreference(_ pref: AppLanguagePreference) {
        TerrariumL10n.shared.preference = pref
        languagePreference = pref
        activeLanguage = TerrariumL10n.shared.currentLanguage
        bannerNotice = nil
        eventMessage = nil
        hasWeatherEvent = false
        syncPublishedFromSaveData()
    }

    func setTemperatureUnit(_ unit: TemperatureUnit) {
        TerrariumL10n.shared.temperatureUnit = unit
        temperatureUnit = TerrariumL10n.shared.currentTemperatureUnit
        syncPublishedFromSaveData()
    }

    func toggleTemperatureUnit() {
        let next: TemperatureUnit = (temperatureUnit == .celsius) ? .fahrenheit : .celsius
        setTemperatureUnit(next)
    }

    func setTipsFrequency(_ freq: DailyTipsFrequency) {
        TerrariumL10n.shared.tipsFrequency = freq
        tipsFrequency = TerrariumL10n.shared.currentTipsFrequency
        lastTipRotateAt = Date()
        syncPublishedFromSaveData()
    }

    func cycleNextDailyTip() {
        if bannerNotice != nil {
            bannerNotice = nil
        }
        let total = TerrariumL10n.dailyTipKeys(for: currentBiome).count
        currentTipIndex = (currentTipIndex + 1) % max(1, total)
        lastTipRotateAt = Date()
    }

    var isShowingDailyTip: Bool {
        guard bannerNotice == nil, !isSleeping, !plants.isEmpty else { return false }
        return tipsFrequency != .off
    }

    func isAchievementEquipped(_ achID: String) -> Bool {
        let unlocked = Set(unlockedAchievementIDs)
        if let eqID = equippedTitleID, unlocked.contains(eqID) {
            return eqID == achID
        }
        return TerrariumConfig.defaultAchievements.last(where: { unlocked.contains($0.id) })?.id == achID
    }

    var menuBarTooltip: String {
        let prefix = isSleeping ? TerrariumL10n.t("state.tooltip_sleep_prefix") : ""
        let humLabel = TerrariumL10n.t(currentBiome == .aquatic ? "sensor.oxygen" : "sensor.humidity")
        let bowlLabel = TerrariumL10n.t(currentBiome == .aquatic ? "sensor.feeding_ring" : "sensor.food_bowl")
        let critLabel = TerrariumL10n.t("sensor.critters_count", ["count": "\(activeDisplayCritters.count)"])
        return TerrariumL10n.t("state.tooltip", [
            "prefix": prefix,
            "biome": currentBiome.localizedName,
            "temp": "\(temperature)",
            "humLabel": humLabel,
            "hum": "\(humidity)",
            "bowlLabel": bowlLabel,
            "cur": "\(foodBowlPortions)",
            "max": "\(TerrariumConfig.maxFoodPortions)",
            "critLabel": critLabel
        ])
    }

    var statusText: String {
        if let notice = bannerNotice { return notice }
        if isSleeping { return TerrariumL10n.t("state.status.sleep") }

        // Day 0 ~ Tier 2 诗意渐进引导
        if plants.isEmpty {
            switch currentBiome {
            case .meadow:
                return TerrariumL10n.t(humidity < 45 ? "state.status.bare_meadow" : "state.status.wet_meadow")
            case .sand:
                return TerrariumL10n.t("state.status.bare_sand")
            case .rainforest:
                return TerrariumL10n.t(humidity < 60 ? "state.status.bare_rainforest" : "state.status.wet_rainforest")
            case .aquatic:
                return TerrariumL10n.t(humidity < 55 ? "state.status.bare_aquatic" : "state.status.oxy_aquatic")
            }
        }
        if critters.isEmpty {
            return TerrariumL10n.t("state.status.need_critters")
        }
        if activeDisplayCritters.isEmpty {
            return TerrariumL10n.t("state.status.all_stowed")
        }

        // P2: 生态紧急预警（智能上下文 Tip）
        if tipsFrequency != .off {
            if currentBiome == .sand && (humidity >= 80 || plants.contains(where: { $0.stage == .wilting })) {
                return TerrariumL10n.t("tips.alert.sand_wet")
            }
            if currentBiome == .aquatic && plants.contains(where: { $0.stage == .wilting }) {
                return TerrariumL10n.t("tips.alert.aquatic_o2")
            }
            if plants.contains(where: { $0.stage == .wilting }) {
                return TerrariumL10n.t("tips.alert.land_dry")
            }
            if foodBowlPortions == 0 && activeDisplayCritters.contains(where: { $0.hunger >= 60.0 }) {
                return TerrariumL10n.t("tips.alert.hungry")
            }
            // P3: 常态轮播日常生态小贴士
            return TerrariumL10n.dailyTip(for: currentBiome, index: currentTipIndex)
        }

        if foodBowlPortions > 0 {
            return TerrariumL10n.t("state.status.food_bowl", [
                "cur": "\(foodBowlPortions)",
                "max": "\(TerrariumConfig.maxFoodPortions)"
            ])
        }
        if humidity >= TerrariumConfig.dewHeavyHumidityThreshold && currentBiome == .meadow {
            return TerrariumL10n.t("state.status.high_dew")
        }
        if humidity >= TerrariumConfig.dewLightHumidityThreshold && currentBiome == .meadow {
            return TerrariumL10n.t("state.status.mild_dew")
        }
        return TerrariumL10n.t("state.status.steady")
    }

    var tempHint: String {
        let opt = TerrariumConfig.optimalTempRange(for: currentBiome)
        if temperature < opt.lowerBound { return TerrariumL10n.t("sensor.temp_cool") }
        if temperature > opt.upperBound { return TerrariumL10n.t("sensor.temp_warm") }
        return TerrariumL10n.t("sensor.temp_optimal")
    }

    var humHint: String {
        let opt = TerrariumConfig.optimalHumidityRange(for: currentBiome)
        if currentBiome == .aquatic {
            return TerrariumL10n.t(humidity < opt.lowerBound ? "sensor.hum_low_o2" : "sensor.hum_ok_o2")
        }
        if humidity < opt.lowerBound { return TerrariumL10n.t("sensor.hum_dry") }
        if humidity > opt.upperBound { return TerrariumL10n.t("sensor.hum_wet") }
        return TerrariumL10n.t("sensor.hum_optimal")
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
            bannerNotice = TerrariumL10n.t("state.admin_off")
        } else {
            bannerNotice = TerrariumL10n.t("state.admin_on")
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
        bannerNotice = TerrariumL10n.t("state.admin_speed_set", ["scale": "\(Int(scale))"])
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
        bannerNotice = TerrariumL10n.t("state.admin_ff", [
            "label": label,
            "pts": "\(gainedPts)",
            "plants": "\(newPlants)"
        ])
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
        guard let reading = await LocalWeatherService.fetchCurrentLocalTemperature() else {
            // 请求失败时仅冷却 60 秒后允许重试，避免直接锁定 30 分钟
            lastWeatherFetchAt = now.addingTimeInterval(-1740.0)
            stateLogger.warning("LocalWeatherService fetch failed; will retry in 60s.")
            return
        }
        lastWeatherFetchAt = now

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
        let resonance = TerrariumConfig.ecosystemResonance(containers: saveData.containers)

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
                tankSlotIndex: idx,
                resonanceSpawnMult: resonance.plantSpawnMult,
                resonanceEfficiencyBonus: resonance.efficiencyBonus
            )

            if isCurrentActive && (!summary.arrivedCritters.isEmpty || !summary.settledCritters.isEmpty) {
                activeCrittersChanged = true
            }
            if isCurrentActive && summary.spawnedPlantsCount > 0 {
                bannerNotice = TerrariumL10n.t("state.bg_plants_spawned", [
                    "tank": container.customName,
                    "count": "\(summary.spawnedPlantsCount)"
                ])
            }
            if !summary.arrivedCritters.isEmpty {
                let names = Self.critterNames(for: summary.arrivedCritters)
                bannerNotice = TerrariumL10n.t("state.bg_visitor_appeared", [
                    "names": names,
                    "tank": container.customName
                ])
            }
            if !summary.settledCritters.isEmpty {
                let names = Self.critterNames(for: summary.settledCritters)
                hasWeatherEvent = true
                appendEventMessage(TerrariumL10n.t("state.bg_visitor_settled", ["names": names]))
            }
            newCodexAll.append(contentsOf: summary.newlyUnlockedCodexIDs)

            if now >= inst.nextWeatherEventAt, let ev = TerrariumConfig.weatherEvents.randomElement() {
                TerrariumSimulation.applyWeatherEvent(ev, to: &inst, now: now)
                if isCurrentActive {
                    hasWeatherEvent = true
                    appendEventMessage(TerrariumL10n.t("state.weather_pair", [
                        "title": ev.title,
                        "effect": ev.effectText
                    ]))
                }
            }
            saveData.containers[idx].instance = inst
        }

        saveData.ecoPoints = pointsBuffer
        saveData.unlockedCodexIDs = codexBuffer
        if !newCodexAll.isEmpty {
            hasWeatherEvent = true
            let names = Self.codexNames(for: newCodexAll)
            appendEventMessage(TerrariumL10n.t("state.codex_unlocked", ["names": names]))
        }

        if updateLastSavedAt {
            saveData.lastSavedAt = now
        }
        if let interval = tipsFrequency.intervalSeconds,
           now.timeIntervalSince(lastTipRotateAt) >= interval {
            if bannerNotice != nil {
                bannerNotice = nil
            }
            let total = TerrariumL10n.dailyTipKeys(for: activeInstance.biome).count
            currentTipIndex = (currentTipIndex + 1) % max(1, total)
            lastTipRotateAt = now
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
                    bannerNotice = TerrariumL10n.t("state.mist_first_plant", ["name": Self.codexName(for: firstPlant.speciesID)])
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
            bannerNotice = TerrariumL10n.t("state.feed_full")
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
            bannerNotice = TerrariumL10n.t(inst.biome == .aquatic ? "state.feed_aquatic_ok" : "state.feed_land_ok")
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
            bannerNotice = TerrariumL10n.t(
                inst.biome == .aquatic ? "state.clean_algae_withered" : "state.clean_fog_withered",
                ["count": "\(witheredCount)"]
            )
        } else {
            bannerNotice = TerrariumL10n.t(inst.biome == .aquatic ? "state.clean_algae" : "state.clean_fog")
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
                    bannerNotice = TerrariumL10n.t("state.meal_settled", ["name": name])
                    unlockCodexIfNeeded(kind.rawValue, bonus: TerrariumConfig.codexRewardPoints(for: kind.rawValue))
                }
            }
        }

        if reward > 0 {
            saveData.ecoPoints += reward
        }
        activeInstance = inst
        vfxSubject.send(.ecoPopup(text: reward > 0 ? "+\(reward)" : TerrariumL10n.t("vfx.full"), at: screenPoint))
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
        let localizedPersonality = TerrariumConfig.localizedPersonality(for: personality)

        if let startledAt = lastStartleAtByKind[kind],
           now.timeIntervalSince(startledAt) < TerrariumConfig.startleRecoverySeconds {
            bannerNotice = TerrariumL10n.t("state.pet_startle", ["name": nickname])
            return .recoveringFromStartle
        }

        let todayKey = Self.dayKey(for: now)
        if inst.critters[idx].dailyPetDateKey != todayKey {
            inst.critters[idx].dailyPetDateKey = todayKey
            inst.critters[idx].dailyPetCount = 0
        }

        if inst.critters[idx].dailyPetCount >= TerrariumConfig.maxDailyEffectivePets {
            bannerNotice = TerrariumL10n.t("state.pet_daily_max", [
                "name": nickname,
                "cur": "\(TerrariumConfig.maxDailyEffectivePets)",
                "max": "\(TerrariumConfig.maxDailyEffectivePets)"
            ])
            activeInstance = inst
            commitStateChange()
            return .dailyLimitReached
        }

        if let lastPet = inst.critters[idx].lastPettedAt {
            let elapsed = now.timeIntervalSince(lastPet)
            if elapsed < TerrariumConfig.petAffinityCooldownSeconds {
                let minsLeft = max(1, Int(ceil((TerrariumConfig.petAffinityCooldownSeconds - elapsed) / 60.0)))
                bannerNotice = TerrariumL10n.t("state.pet_cooldown", [
                    "name": nickname,
                    "personality": localizedPersonality,
                    "mins": "\(minsLeft)"
                ])
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
            bannerNotice = TerrariumL10n.t("state.pet_levelup", [
                "name": nickname,
                "stage": newStage.title,
                "cur": "\(nextAffinity)",
                "max": "\(TerrariumConfig.maxAffinity)",
                "perk": perkDesc
            ])
            vfxSubject.send(.ecoPopup(text: "\(newStage.title)!", at: screenPoint))
        } else {
            let baseReply = TerrariumConfig.petReplyText(nickname: nickname, stage: newStage)
            bannerNotice = TerrariumL10n.t("state.pet_reply_with_val", [
                "reply": baseReply,
                "cur": "\(nextAffinity)",
                "max": "\(TerrariumConfig.maxAffinity)"
            ])
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
        bannerNotice = TerrariumL10n.t("state.move_plant_prompt")
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
            bannerNotice = TerrariumL10n.t(inst.biome == .aquatic ? "state.move_plant_blocked_aquatic" : "state.move_plant_blocked_land")
            return
        }

        inst.plants[idx].coord = coord
        let name = Self.codexName(for: inst.plants[idx].speciesID)
        activeInstance = inst
        isMovingPlant = false
        bannerNotice = TerrariumL10n.t("state.move_plant_ok", [
            "name": name,
            "col": "\(coord.col)",
            "row": "\(coord.row)"
        ])
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
            bannerNotice = TerrariumL10n.t("state.prune_ok", ["name": name, "pts": "\(refundPts)"])
        } else {
            bannerNotice = TerrariumL10n.t("state.prune_sprout_ok", ["name": name])
        }
        vfxSubject.send(.clean)
        commitStateChange()
    }

    static func displayName(forPlantSpecies speciesID: String) -> String {
        codexName(for: speciesID)
    }

    static func stageLabel(for stage: PlantStage, biome: TerrariumBiome? = nil) -> String {
        stage.localizedName(for: biome)
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
        bannerNotice = TerrariumL10n.t("state.move_decor_prompt", ["cols": "\(dims.cols)", "rows": "\(dims.rows)"])
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
            bannerNotice = TerrariumL10n.t("state.move_decor_blocked")
            return
        }

        inst.decorOrigins[decorID] = origin
        activeInstance = inst
        movingDecorID = nil
        let name = TerrariumConfig.decorCatalog(for: inst.biome).first(where: { $0.id == decorID })?.name ?? decorID
        bannerNotice = TerrariumL10n.t("state.move_decor_ok", [
            "name": name,
            "col": "\(origin.col)",
            "row": "\(origin.row)"
        ])
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
            bannerNotice = TerrariumL10n.t("state.decor_unlocked", ["name": item.name])
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
                bannerNotice = TerrariumL10n.t("state.critter_stowed", ["name": spec.name])
            } else {
                let check = TerrariumSimulation.critterUnlockEligibility(kind: kind, instance: inst)
                guard check.eligible else {
                    bannerNotice = TerrariumL10n.t("state.critter_cant_return", ["name": spec.name, "reason": check.missingReason])
                    return
                }
                let swapped = TerrariumSimulation.placeOrSwapCritter(kind: kind, instance: &inst)
                if swapped.isEmpty {
                    bannerNotice = TerrariumL10n.t("state.critter_placed", ["name": spec.name])
                } else {
                    let swappedNames = Self.critterNames(for: swapped)
                    bannerNotice = TerrariumL10n.t("state.critter_swapped", ["name": spec.name, "swapped": swappedNames])
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
            bannerNotice = TerrariumL10n.t("state.critter_ineligible", ["reason": check.missingReason])
            return
        }
        guard saveData.ecoPoints >= spec.cost else {
            bannerNotice = TerrariumL10n.t("state.critter_no_pts", ["cost": "\(spec.cost)"])
            return
        }

        saveData.ecoPoints -= spec.cost
        let swapped = TerrariumSimulation.placeOrSwapCritter(kind: kind, instance: &inst)
        activeInstance = inst
        unlockCodexIfNeeded(kind.rawValue, bonus: TerrariumConfig.codexRewardPoints(for: kind.rawValue))

        if swapped.isEmpty {
            bannerNotice = TerrariumL10n.t("state.critter_adopted", ["name": spec.name])
        } else {
            let swappedNames = Self.critterNames(for: swapped)
            bannerNotice = TerrariumL10n.t("state.critter_adopted_swapped", ["name": spec.name, "swapped": swappedNames])
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
            let equipName = TerrariumL10n.t(updated.biome == .aquatic ? "ui.equip.heater" : "ui.equip.heat_lamp")
            bannerNotice = TerrariumL10n.t("state.thermal_heat_on", ["equip": equipName, "temp": "\(targetAmbient)"])
        case .cooling:
            bannerNotice = TerrariumL10n.t("state.thermal_cool_on", ["temp": "\(targetAmbient)"])
        case .natural:
            bannerNotice = TerrariumL10n.t("state.thermal_off", ["temp": "\(targetAmbient)"])
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
            let equipName = TerrariumL10n.t(inst.biome == .aquatic ? "ui.equip.heater" : "ui.equip.heat_lamp")
            guard saveData.ecoPoints >= cost else {
                bannerNotice = TerrariumL10n.t("state.thermal_need_pts", ["equip": equipName, "cost": "\(cost)"])
                pendingPurchaseThermalMode = nil
                return
            }
            saveData.ecoPoints -= cost
            inst.hasHeatLamp = true
            bannerNotice = TerrariumL10n.t("state.thermal_heat_installed", ["equip": equipName])
        } else if targetMode == .cooling && !inst.hasCoolingFan {
            let cost = TerrariumConfig.coolingFanCost
            guard saveData.ecoPoints >= cost else {
                bannerNotice = TerrariumL10n.t("state.thermal_fan_need_pts", ["cost": "\(cost)"])
                pendingPurchaseThermalMode = nil
                return
            }
            saveData.ecoPoints -= cost
            inst.hasCoolingFan = true
            bannerNotice = TerrariumL10n.t("state.thermal_fan_installed")
        }

        pendingPurchaseThermalMode = nil
        activeInstance = inst
        evaluateCurrentCodexAndSave()
    }

    func cancelPurchaseThermalEquipment() {
        pendingPurchaseThermalMode = nil
    }

    // MARK: - 多容器生态缸自由切换、购置与拆缸退点（上限 9 口）

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
        bannerNotice = TerrariumL10n.t("state.tank_switched", ["name": saveData.containers[activeContainerIndex].customName])
        commitStateChange()
        vfxSubject.send(.syncCritters)
    }

    @discardableResult
    func purchaseNewTank(biome: TerrariumBiome, customName: String? = nil) -> Bool {
        guard saveData.containers.count < TerrariumConfig.maxTankSlots else {
            bannerNotice = TerrariumL10n.t("state.tank_max_cap", ["max": "\(TerrariumConfig.maxTankSlots)"])
            return false
        }
        let cost = TerrariumConfig.tankPurchaseCost(for: biome, existingTankCount: saveData.containers.count)
        guard saveData.ecoPoints >= cost else {
            bannerNotice = TerrariumL10n.t("state.tank_no_pts", ["biome": biome.localizedName, "cost": "\(cost)"])
            return false
        }

        let sameTypeCount = saveData.containers.filter { $0.instance.biome == biome }.count
        let assignedName = (customName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? customName!
            : TerrariumL10n.t("tank.default_name", ["biome": biome.localizedShortName, "index": "\(sameTypeCount + 1)"])

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
        bannerNotice = TerrariumL10n.t("state.tank_bought", [
            "emoji": biome.iconEmoji,
            "name": assignedName,
            "cost": "\(cost)"
        ])
        commitStateChange()
        vfxSubject.send(.syncCritters)
        return true
    }

    @discardableResult
    func deleteActiveContainer() -> Int {
        guard saveData.containers.count > 1 else {
            bannerNotice = TerrariumL10n.t("state.tank_min_one")
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
        bannerNotice = TerrariumL10n.t("state.tank_deleted", ["name": removed.customName, "refund": "\(refund)"])
        commitStateChange()
        vfxSubject.send(.syncCritters)
        return refund
    }

    func renameActiveContainer(to rawName: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !saveData.containers.isEmpty else { return }
        saveData.containers[activeContainerIndex].customName = String(trimmed.prefix(16))
        commitStateChange()
        bannerNotice = TerrariumL10n.t("state.tank_renamed", ["name": activeContainerName])
    }

    func renameCritter(kind: CritterKind, to rawName: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var inst = activeInstance
        guard let idx = inst.critters.firstIndex(where: { $0.kind == kind }) else { return }
        let safeName = String(trimmed.prefix(14))
        inst.critters[idx].nickname = safeName
        activeInstance = inst
        commitStateChange()
        bannerNotice = TerrariumL10n.t("state.critter_renamed", ["kind": kind.localizedName, "name": safeName])
    }

    func exportPixelSnapshot<V: View>(content: V) {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1.0
        guard let nsImage = renderer.nsImage,
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            bannerNotice = TerrariumL10n.t("state.snapshot_fail")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        let safeTankName = activeContainerName.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "\(safeTankName)_\(formatter.string(from: Date())).png"
        panel.title = TerrariumL10n.t("stage.snapshot_title")
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try pngData.write(to: url)
                bannerNotice = TerrariumL10n.t("state.snapshot_saved", ["file": url.lastPathComponent])
            } catch {
                bannerNotice = TerrariumL10n.t("state.snapshot_save_err", ["err": error.localizedDescription])
            }
        }
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
            appendEventMessage(TerrariumL10n.t("state.weather_pair", [
                "title": chosen.title,
                "effect": chosen.effectText
            ]))
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
            bannerNotice = TerrariumL10n.t("state.admin_spawn_ok", ["name": Self.codexName(for: spawned.speciesID)])
            activeInstance = inst
            evaluateCurrentCodexAndSave()
        } else {
            bannerNotice = TerrariumL10n.t("state.admin_spawn_full")
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
        adminVirtualNowOffset = 0
        adminSimulatedElapsedSeconds = 0
        saveData = TerrariumSaveData(lastSavedAt: Date())
        hasWeatherEvent = false
        eventMessage = nil
        selectedPlantID = nil
        isMovingPlant = false
        selectedDecorID = nil
        movingDecorID = nil
        isShowingBuyTankSheet = false
        bannerNotice = TerrariumL10n.t("state.save_reset")
        commitStateChange()
        vfxSubject.send(.syncCritters)
    }

    // MARK: - 内部同步与持久化

    private func unlockCodexIfNeeded(_ id: String, bonus: Int) {
        guard !saveData.unlockedCodexIDs.contains(id) else { return }
        saveData.unlockedCodexIDs.append(id)
        saveData.ecoPoints += bonus
        hasWeatherEvent = true
        appendEventMessage(TerrariumL10n.t("state.codex_unlocked_bonus", [
            "name": Self.codexName(for: id),
            "bonus": "\(bonus)"
        ]))
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
        ids.map { codexName(for: $0) }.joined(separator: TerrariumL10n.shared.currentLanguage.listSeparator)
    }

    private static func critterNames(for kinds: [CritterKind]) -> String {
        kinds.map { codexName(for: $0.rawValue) }.joined(separator: TerrariumL10n.shared.currentLanguage.listSeparator)
    }

    private func commitStateChange() {
        let now = Date()
        let newAchs = TerrariumSimulation.evaluateAchievements(data: &saveData)
        if let first = newAchs.first {
            let bonusSum = newAchs.reduce(0) { $0 + $1.rewardPoints }
            bannerNotice = TerrariumL10n.t("state.ach_unlocked", [
                "title": first.title,
                "bonus": "\(bonusSum)"
            ])
        }
        saveData.lastSavedAt = now
        syncPublishedFromSaveData(now: now)
        persistence.save(saveData)
    }

    func equipTitle(_ achievementID: String) {
        guard saveData.unlockedAchievementIDs.contains(achievementID) else { return }
        saveData.equippedTitleID = achievementID
        commitStateChange()
        if let def = TerrariumConfig.defaultAchievements.first(where: { $0.id == achievementID }) {
            bannerNotice = TerrariumL10n.t("state.title_equipped", ["title": def.title])
        }
    }

    private func syncPublishedFromSaveData(now: Date = Date()) {
        let inst = activeInstance
        containers = saveData.containers
        activeContainerID = saveData.activeContainerID
        activeContainerName = saveData.containers.isEmpty
            ? TerrariumL10n.t("tank.default_name", ["biome": TerrariumBiome.meadow.localizedShortName, "index": "1"])
            : saveData.containers[activeContainerIndex].customName
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
        codexMilestoneTitle = TerrariumConfig.displayTitle(for: saveData)
        unlockedFrameSkinIDs = saveData.unlockedFrameSkinIDs
        activeFrameSkin = TankFrameSkin(rawValue: saveData.activeFrameSkinID) ?? .classic
        unlockedCodexIDs = saveData.unlockedCodexIDs
        unlockedAchievementIDs = saveData.unlockedAchievementIDs
        equippedTitleID = saveData.equippedTitleID
        let effectiveNow = now.addingTimeInterval(adminVirtualNowOffset)
        idleDays = TerrariumConfig.elapsedDays(from: saveData.firstStartedAt, to: effectiveNow)
        activeContainerDays = saveData.containers.isEmpty
            ? 0
            : TerrariumConfig.elapsedDays(from: saveData.containers[activeContainerIndex].createdAt, to: effectiveNow)
        isResonanceActive = TerrariumConfig.ecosystemResonance(containers: saveData.containers).isActive
        twilightIntensity = TerrariumConfig.twilightTintIntensity(for: now)

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

    @discardableResult
    func purchaseOrSelectFrameSkin(_ skin: TankFrameSkin) -> Bool {
        if saveData.unlockedFrameSkinIDs.contains(skin.rawValue) {
            saveData.activeFrameSkinID = skin.rawValue
            commitStateChange()
            bannerNotice = TerrariumL10n.t("state.skin_changed", ["name": skin.displayName])
            return true
        }
        guard saveData.ecoPoints >= skin.cost else {
            bannerNotice = TerrariumL10n.t("state.skin_no_pts", ["cost": "\(skin.cost)"])
            return false
        }
        saveData.ecoPoints -= skin.cost
        saveData.unlockedFrameSkinIDs.append(skin.rawValue)
        saveData.activeFrameSkinID = skin.rawValue
        commitStateChange()
        bannerNotice = TerrariumL10n.t("state.skin_unlocked", ["name": skin.displayName])
        return true
    }
}
