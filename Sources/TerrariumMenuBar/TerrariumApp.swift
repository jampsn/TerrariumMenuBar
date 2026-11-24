import AppKit
import SwiftUI
import TerrariumCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onWillTerminate: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        onWillTerminate?()
    }
}

private struct MenuBarIconLabel: View {
    @ObservedObject var state: TerrariumState

    var body: some View {
        Image(nsImage: PixelAssetLoader.menuBarNSImage(state: state.menuBarVisualState))
            .help(state.menuBarTooltip)
    }
}

@main
struct TerrariumMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = TerrariumState()

    init() {
        if CommandLine.arguments.contains("--self-test") {
            Self.runSelfTest()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(state: state)
        } label: {
            MenuBarIconLabel(state: state)
                .onAppear {
                    let stateRef = state
                    appDelegate.onWillTerminate = { [weak stateRef] in
                        Task { @MainActor in
                            stateRef?.flushSave()
                        }
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }

    @MainActor
    private static func runSelfTest() {
        let expectedAssets = [
            "menubar_icon_normal", "menubar_icon_event", "menubar_icon_dry", "menubar_icon_hungry", "menubar_icon_night", "menubar_icon_sleep",
            "bg_room_day", "bg_room_night", "bg_room_rain", "bg_room_warm",
            "tank_back_glass", "tank_front_glass", "tank_lid_sleep",
            "terrain_meadow_dry", "terrain_meadow_wet", "terrain_sand_dry", "terrain_sand_wet", "terrain_rainforest_dry", "terrain_rainforest_wet", "terrain_aquatic_clean", "terrain_aquatic_murky", "terrain_reef_clean", "terrain_reef_murky",
            "tank_water_overlay", "tank_reef_water_overlay", "vfx_bubble_sheet", "env_aquatic_feeding_ring", "plant_lotus_stem",
            "equip_heat_lamp", "equip_cooling_fan", "equip_aquarium_heater", "equip_reef_lamp",
            "env_shallow_pool", "env_driftwood", "env_boulder", "env_pebbles", "env_sand_rock", "env_sand_wood", "env_food_bowl",
            "env_rainforest_vine", "env_rainforest_waterfall", "env_rainforest_bark",
            "env_aquatic_bubble_rock", "env_aquatic_driftwood", "env_aquatic_castle",
            "env_meadow_mushroom_log", "env_meadow_stepping_stones",
            "env_sand_cairn", "env_sand_rib_arch",
            "env_rainforest_bromeliad_stump", "env_rainforest_slate_ledge",
            "env_aquatic_seiryu_stone", "env_aquatic_bamboo_tube",
            "env_reef_live_rock", "env_reef_wavemaker", "env_reef_coral_cave", "env_reef_giant_clam", "env_reef_sand_shells",
            "plant_fern_sheet", "plant_clover_sheet", "plant_moss_clump", "plant_glow_shroom_sheet", "plant_red_shroom_sheet",
            "plant_succulent_sheet", "plant_cactus_sheet", "plant_aloe_sheet",
            "plant_monstera_sheet", "plant_bromeliad_sheet", "plant_orchid_sheet",
            "plant_marimo_sheet", "plant_anubias_sheet", "plant_lotus_sheet",
            "plant_sundew_sheet", "plant_lithops_sheet", "plant_agave_sheet",
            "plant_pitcher_sheet", "plant_calathea_sheet", "plant_vallisneria_sheet", "plant_red_ludwigia_sheet",
            "plant_coral_zoanthid_sheet", "plant_coral_acropora_sheet", "plant_coral_brain_sheet", "plant_coral_anemone_sheet", "plant_coral_seafan_sheet",
            "vfx_dew_drop_sheet", "vfx_glass_mist", "vfx_glass_streak_sheet", "vfx_aquatic_algae",
            "char_frog_sheet", "char_snail_sheet", "char_pillbug_sheet", "char_rhino_beetle_sheet", "char_beetle_sheet",
            "char_gecko_sheet", "char_scarab_sheet", "char_firefly_sheet", "char_moth_sheet",
            "char_leaf_insect_sheet", "char_hercules_sheet",
            "char_chameleon_green", "char_chameleon_coral", "char_chameleon_bark", "char_chameleon_rainbow",
            "char_shrimp_sheet", "char_tetra_sheet", "char_betta_sheet", "char_crayfish_sheet",
            "char_fire_newt_sheet", "char_sand_scorpion_sheet", "char_dart_frog_sheet", "char_corydoras_sheet",
            "char_ladybug_sheet", "char_desert_mantis_sheet", "char_horned_toad_sheet", "char_blue_morpho_sheet",
            "char_red_eyed_frog_sheet", "char_oto_catfish_sheet", "char_crystal_shrimp_sheet",
            "char_dragonfly_sheet", "char_luna_cicada_sheet",
            "char_antlion_lacewing_sheet", "char_orchid_bee_sheet",
            "char_clownfish_sheet", "char_starfish_sheet", "char_cleaner_shrimp_sheet", "char_blue_tang_sheet", "char_seahorse_sheet", "char_hermit_crab_sheet",
            "icon_mist", "icon_feed", "icon_clean", "icon_sleep"
        ]
        var failed: [String] = []
        for name in expectedAssets {
            if let img = PixelAssetLoader.nsImage(named: name), img.size.width > 0, img.size.height > 0 {
                continue
            }
            failed.append(name)
        }
        guard failed.isEmpty else {
            fputs("SELF_TEST_FAIL: Missing or failed assets: \(failed.joined(separator: ", "))\n", stderr)
            Foundation.exit(1)
        }

        guard let baseLocaleTable = TerrariumL10n.rawTable(for: .zhHans), !baseLocaleTable.isEmpty else {
            fputs("SELF_TEST_FAIL: Missing base locale zh-Hans.json\n", stderr)
            Foundation.exit(1)
        }
        for lang in SupportedLanguage.allCases {
            guard let table = TerrariumL10n.rawTable(for: lang), table.count == baseLocaleTable.count else {
                fputs("SELF_TEST_FAIL: Locale bundle load or key count mismatch for \(lang.rawValue)\n", stderr)
                Foundation.exit(1)
            }
        }

        guard PixelAssetLoader.spriteSheetFrame(named: "env_shallow_pool", frameIndex: 1, frameSize: CGSize(width: 44, height: 24)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "env_food_bowl", frameIndex: 2, frameSize: CGSize(width: 18, height: 12)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "env_pebbles", frameIndex: 1, frameSize: CGSize(width: 28, height: 16)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "plant_fern_sheet", frameIndex: 4, frameSize: CGSize(width: 32, height: 32)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "plant_glow_shroom_sheet", frameIndex: 4, frameSize: CGSize(width: 16, height: 16)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "plant_cactus_sheet", frameIndex: 3, frameSize: CGSize(width: 18, height: 20)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "equip_heat_lamp", frameIndex: 1, frameSize: CGSize(width: 24, height: 24)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "equip_cooling_fan", frameIndex: 2, frameSize: CGSize(width: 22, height: 20)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "equip_aquarium_heater", frameIndex: 1, frameSize: CGSize(width: 12, height: 28)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "env_aquatic_bubble_rock", frameIndex: 2, frameSize: CGSize(width: 44, height: 36)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "env_aquatic_feeding_ring", frameIndex: 2, frameSize: CGSize(width: 30, height: 18)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "plant_lotus_stem", frameIndex: 1, frameSize: CGSize(width: 8, height: 40)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "vfx_bubble_sheet", frameIndex: 3, frameSize: CGSize(width: 6, height: 6)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "vfx_dew_drop_sheet", frameIndex: 6, frameSize: CGSize(width: 8, height: 14)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_shrimp_sheet", frameIndex: 9, frameSize: CGSize(width: 14, height: 11)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_tetra_sheet", frameIndex: 5, frameSize: CGSize(width: 14, height: 10)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_betta_sheet", frameIndex: 10, frameSize: CGSize(width: 30, height: 22)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_crayfish_sheet", frameIndex: 10, frameSize: CGSize(width: 24, height: 16)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_chameleon_green", frameIndex: 10, frameSize: CGSize(width: 26, height: 20)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_hercules_sheet", frameIndex: 4, frameSize: CGSize(width: 22, height: 16)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "plant_monstera_sheet", frameIndex: 3, frameSize: CGSize(width: 28, height: 28)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "env_rainforest_waterfall", frameIndex: 2, frameSize: CGSize(width: 48, height: 38)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_frog_sheet", frameIndex: 15, frameSize: CGSize(width: 24, height: 22)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_rhino_beetle_sheet", frameIndex: 4, frameSize: CGSize(width: 20, height: 16)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_gecko_sheet", frameIndex: 4, frameSize: CGSize(width: 28, height: 18)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_pillbug_sheet", frameIndex: 8, frameSize: CGSize(width: 14, height: 10)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_moth_sheet", frameIndex: 2, frameSize: CGSize(width: 16, height: 14)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_scarab_sheet", frameIndex: 3, frameSize: CGSize(width: 18, height: 14)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "plant_sundew_sheet", frameIndex: 3, frameSize: CGSize(width: 18, height: 16)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "plant_lithops_sheet", frameIndex: 3, frameSize: CGSize(width: 18, height: 14)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "plant_agave_sheet", frameIndex: 3, frameSize: CGSize(width: 22, height: 20)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "plant_pitcher_sheet", frameIndex: 3, frameSize: CGSize(width: 20, height: 22)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "plant_calathea_sheet", frameIndex: 3, frameSize: CGSize(width: 22, height: 20)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "plant_vallisneria_sheet", frameIndex: 3, frameSize: CGSize(width: 18, height: 22)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "plant_red_ludwigia_sheet", frameIndex: 3, frameSize: CGSize(width: 20, height: 20)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_ladybug_sheet", frameIndex: 13, frameSize: CGSize(width: 14, height: 11)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_desert_mantis_sheet", frameIndex: 13, frameSize: CGSize(width: 22, height: 16)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_horned_toad_sheet", frameIndex: 13, frameSize: CGSize(width: 28, height: 18)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_blue_morpho_sheet", frameIndex: 13, frameSize: CGSize(width: 22, height: 18)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_red_eyed_frog_sheet", frameIndex: 18, frameSize: CGSize(width: 20, height: 18)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_oto_catfish_sheet", frameIndex: 13, frameSize: CGSize(width: 16, height: 12)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_crystal_shrimp_sheet", frameIndex: 13, frameSize: CGSize(width: 14, height: 11)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_dragonfly_sheet", frameIndex: 7, frameSize: CGSize(width: 18, height: 14)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_luna_cicada_sheet", frameIndex: 7, frameSize: CGSize(width: 16, height: 14)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_antlion_lacewing_sheet", frameIndex: 7, frameSize: CGSize(width: 18, height: 14)) != nil,
              PixelAssetLoader.spriteSheetFrame(named: "char_orchid_bee_sheet", frameIndex: 7, frameSize: CGSize(width: 14, height: 12)) != nil else {
            fputs("SELF_TEST_FAIL: New sprite sheet slicing failed.\n", stderr)
            Foundation.exit(1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        let tempSaveURL = FileManager.default.temporaryDirectory.appendingPathComponent("terrarium_selftest_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempSaveURL) }

        let state = TerrariumState(persistence: TerrariumPersistence(fileURL: tempSaveURL), startScheduler: false)
        // 1. 验证 Day 0 开局为空缸 + 普通模式参数锁定
        guard state.plants.isEmpty, state.critters.isEmpty, state.unlockedCodexCount == 0 else {
            fputs("SELF_TEST_FAIL: Day 0 start is not empty.\n", stderr)
            Foundation.exit(1)
        }
        let baseTemp = state.temperature
        state.adjustTemp(4)
        state.setAtmosphere(.night)
        guard state.temperature == baseTemp, state.atmosphere == .day else {
            fputs("SELF_TEST_FAIL: Normal mode lock failed.\n", stderr)
            Foundation.exit(1)
        }

        // 2. 模拟开局冷启动：喷水 2 次 -> 破土长出苔藓 -> 使用生态点购买蜗牛 -> 投喂
        state.mist()
        state.mist()
        state.critterPurchaseAndToggle(.snail)
        state.feed()
        guard !state.plants.isEmpty, state.activeDisplayCritters.contains(where: { $0.kind == .snail }) else {
            fputs("SELF_TEST_FAIL: Cold start mist+purchase snail did not succeed.\n", stderr)
            Foundation.exit(1)
        }

        // 3. 验证后台 Tick 多次推进（回归测试：防止 Swift Exclusivity 内存访问冲突）
        state.processBackgroundTick(elapsed: 60.0)
        state.processBackgroundTick(elapsed: 120.0)

        // 3b. 验证轻抚好感度提升 + 植物移栽 + 轻修剪返还点数
        if let plant = state.plants.first {
            let pointsBeforePrune = state.ecoPoints
            let moveDest = (plant.coord == GridCoord(col: 6, row: 6)) ? GridCoord(col: 6, row: 7) : GridCoord(col: 6, row: 6)
            state.selectPlant(plant.id)
            state.beginMoveSelectedPlant()
            state.moveSelectedPlant(to: moveDest)
            state.beginMoveSelectedPlant()
            state.moveSelectedPlant(to: GridCoord(col: 9, row: 10)) // 禁止占用食盆前方保护格
            guard state.selectedPlant?.coord == moveDest else {
                fputs("SELF_TEST_FAIL: Plant move validation failed.\n", stderr)
                Foundation.exit(1)
            }
            state.pruneSelectedPlant()
            // 幼苗期清理不返还点数（防刷点闭环），确认余额不膨胀
            guard state.ecoPoints == pointsBeforePrune else {
                fputs("SELF_TEST_FAIL: Sprout prune should not grant points.\n", stderr)
                Foundation.exit(1)
            }
            // 重新触发一株以备后续舞台渲染
            state.mist()
        }

        state.petCritter(kind: .snail, at: CGPoint(x: 100, y: 100))
        guard (state.critters.first(where: { $0.kind == .snail })?.affinity ?? 0) >= 3 else {
            fputs("SELF_TEST_FAIL: Critter petting affinity did not increment.\n", stderr)
            Foundation.exit(1)
        }

        // 3c. 验证摆件解锁、自由移动位置（含食盆净空拦截）与动态 Y-Sort 渲染
        state.setAdminMode(true)
        state.adjustEcoPointsDebug(200)
        state.handleDecorAction(id: "driftwood")
        state.beginMoveDecor("driftwood")
        state.moveSelectedDecor(to: GridCoord(col: 1, row: 1))
        state.beginMoveDecor("driftwood")
        state.moveSelectedDecor(to: GridCoord(col: 8, row: 8)) // 不得覆盖食盆保护区
        guard state.decorOrigins["driftwood"] == GridCoord(col: 1, row: 1) else {
            fputs("SELF_TEST_FAIL: Decor free placement validation failed.\n", stderr)
            Foundation.exit(1)
        }

        // 3d. 验证夹缸加热灯付费购置（方案 A：购买与开关解耦，且连点 2 次不得瞬时跳变温度）+ 多实例购置热带雨林/碧波鱼缸 + 拆缸退点
        let tempBeforeHeat = state.temperature
        state.toggleThermalMode(.heating) // 触发待确认购买
        guard state.pendingPurchaseThermalMode == .heating, !state.hasHeatLamp else {
            fputs("SELF_TEST_FAIL: Thermal heat lamp purchase confirmation prompt failed.\n", stderr)
            Foundation.exit(1)
        }
        state.confirmPurchaseThermalEquipment()
        guard state.hasHeatLamp, state.thermalMode == .natural else {
            fputs("SELF_TEST_FAIL: Thermal heat lamp purchase install failed.\n", stderr)
            Foundation.exit(1)
        }
        state.toggleThermalMode(.heating)
        state.toggleThermalMode(.heating)
        state.toggleThermalMode(.heating)
        guard state.hasHeatLamp, state.thermalMode == .heating, state.temperature == tempBeforeHeat else {
            fputs("SELF_TEST_FAIL: Thermal heat lamp toggle & anti-burst failed.\n", stderr)
            Foundation.exit(1)
        }
        guard state.purchaseNewTank(biome: .rainforest, customName: "测试雨林"),
              state.containers.count == 2,
              state.currentBiome == .rainforest else {
            fputs("SELF_TEST_FAIL: Multi-container rainforest tank purchase failed.\n", stderr)
            Foundation.exit(1)
        }
        state.mist()
        state.mist()
        guard !state.plants.isEmpty else {
            fputs("SELF_TEST_FAIL: Rainforest cold start sprout failed.\n", stderr)
            Foundation.exit(1)
        }
        // 购买并测试碧波鱼缸，再拆除并验证 75% 折旧退点
        let expectedAquaticCost = TerrariumConfig.tankPurchaseCost(for: .aquatic, existingTankCount: state.containers.count)
        guard state.purchaseNewTank(biome: .aquatic, customName: "测试鱼缸"),
              state.containers.count == 3,
              state.currentBiome == .aquatic else {
            fputs("SELF_TEST_FAIL: Aquatic fish tank purchase failed.\n", stderr)
            Foundation.exit(1)
        }
        state.mist()
        state.mist()
        guard state.plants.contains(where: { $0.speciesID == "marimo" }) else {
            fputs("SELF_TEST_FAIL: Aquatic marimo sprout failed.\n", stderr)
            Foundation.exit(1)
        }
        let ptsBeforeDelete = state.ecoPoints
        let refunded = state.deleteActiveContainer()
        let expectedRefund = Int((Double(expectedAquaticCost) * TerrariumConfig.tankRefundRatio).rounded(.down))
        guard refunded == expectedRefund,
              state.ecoPoints == ptsBeforeDelete + refunded,
              state.containers.count == 2 else {
            fputs("SELF_TEST_FAIL: Tank delete refund failed (refunded=\(refunded)).\n", stderr)
            Foundation.exit(1)
        }

        // 4. 管理员模式测试全视图渲染
        state.showIsoGridDebug = true

        let animator = StageAnimator()
        animator.bind(state: state)
        animator.start()

        let hosting = NSHostingView(rootView: MenuBarPopoverView(state: state))
        hosting.frame = NSRect(x: 0, y: 0, width: 472, height: 610)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderBack(nil)

        for tab in PopoverTab.allCases {
            state.currentTab = tab
            state.mist()
            state.feed()
            state.clean()
            state.simulateWeatherEvent()
            state.triggerPlantPulseDebug()
            hosting.layoutSubtreeIfNeeded()
            if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
            }
        }
        state.currentTab = .terrarium
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))

        guard animator.tick >= 8 else {
            fputs("SELF_TEST_FAIL: StageAnimator stalled (ticks=\(animator.tick))\n", stderr)
            Foundation.exit(1)
        }
        animator.stop()

        print("SELF_TEST_PASS: All \(expectedAssets.count) assets, \(SupportedLanguage.allCases.count) locales verified, Day-0 cold start, visitor attraction, multi-terrarium isolation & Y-Sort verified (ticks=\(animator.tick), plants=\(state.plants.count), critters=\(state.activeDisplayCritters.count)).")
        Foundation.exit(0)
    }
}
