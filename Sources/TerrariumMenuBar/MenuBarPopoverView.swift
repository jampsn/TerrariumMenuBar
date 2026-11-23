import AppKit
import ServiceManagement
import SwiftUI
import TerrariumCore

struct MenuBarPopoverView: View {
    @ObservedObject var state: TerrariumState

    private let bgMain = Color(red: 0.118, green: 0.161, blue: 0.137)      // #1e2923
    private let bgHeader = Color(red: 0.157, green: 0.220, blue: 0.184)    // #28382f
    private let bgCard = Color(red: 0.090, green: 0.125, blue: 0.106)      // #17201b
    private let borderCol = Color(red: 0.231, green: 0.322, blue: 0.267)   // #3b5244
    private let textMain = Color(red: 0.851, green: 0.949, blue: 0.816)    // #d9f2d0
    private let textMuted = Color(red: 0.561, green: 0.722, blue: 0.588)   // #8fb896
    private let accentGreen = Color(red: 0.306, green: 0.549, blue: 0.345) // #4e8c58
    private let adminAmber = Color(red: 0.98, green: 0.75, blue: 0.14)

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
            // 顶部标题与 Tab 栏（连击标题 5 次解锁会话级管理员模式）
            HStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(state.isAdminMode ? TerrariumL10n.t("ui.brand_short") : TerrariumL10n.t("ui.brand_full"))
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(textMain)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .onTapGesture {
                            state.registerSecretTitleTap()
                        }
                    if state.isAdminMode {
                        Text(TerrariumL10n.t("ui.admin_badge"))
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(adminAmber.opacity(0.22))
                            .foregroundColor(adminAmber)
                            .overlay(Rectangle().stroke(adminAmber.opacity(0.6), lineWidth: 1))
                    }
                    Text(TerrariumL10n.t("ui.day_badge", ["days": "\(state.idleDays)"]))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(bgCard)
                        .foregroundColor(textMuted)
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                        .help(TerrariumL10n.t("ui.day_badge_help", ["days": "\(state.idleDays)"]))
                    Button("") {
                        state.toggleAdminMode()
                    }
                    .keyboardShortcut("d", modifiers: [.command, .option])
                    .frame(width: 0, height: 0)
                    .opacity(0)
                }

                Spacer(minLength: 4)

                HStack(spacing: 3.5) {
                    ForEach(PopoverTab.allCases, id: \.self) { tab in
                        Button {
                            state.currentTab = tab
                        } label: {
                            let baseEntries = state.codexEntries.filter { !$0.isHiddenReef }
                            let baseUnlocked = baseEntries.filter { $0.unlocked }.count
                            let labelText = (tab == .codex)
                                ? TerrariumL10n.t("ui.tab.codex_count", [
                                    "label": tab.localizedTitle,
                                    "unlocked": "\(baseUnlocked)",
                                    "total": "\(baseEntries.count)"
                                ])
                                : tab.localizedTitle
                            Text(labelText)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 3)
                                .background(state.currentTab == tab ? accentGreen : bgCard)
                                .foregroundColor(state.currentTab == tab ? .white : textMuted)
                                .overlay(
                                    Rectangle()
                                        .stroke(borderCol, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(bgHeader)
            .overlay(Rectangle().frame(height: 2).foregroundColor(borderCol), alignment: .bottom)

            // 主内容区：生态箱 Tab 上方固定、下方随内容自适应扩展；其余列表 Tab 固定高度内部滚动
            Group {
                switch state.currentTab {
                case .terrarium:
                    terrariumTabContent
                case .decor:
                    decorTabContent
                        .frame(height: 540)
                case .critters:
                    crittersTabContent
                        .frame(height: 540)
                case .codex:
                    codexTabContent
                        .frame(height: 540)
                }
            }
            .padding(12)

            // 底部双层状态栏：上层完整信息提示条（日常小贴士模式下点击可立即切换下一条）+ 下层系统点数与操作按钮
            VStack(alignment: .leading, spacing: 5) {
                Button {
                    if state.tipsFrequency != .off {
                        state.cycleNextDailyTip()
                    }
                } label: {
                    Text(state.statusText)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(textMuted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help(state.tipsFrequency != .off ? TerrariumL10n.t("tips.click_next_help") : "")

                HStack(spacing: 6) {
                    Text(state.isSleeping
                         ? TerrariumL10n.t("ui.footer.sleeping")
                         : TerrariumL10n.t("ui.footer.next_climate", ["mins": "\(state.nextEventMinutesRemaining)"]))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(TerrariumL10n.t("ui.footer.eco_points", ["points": "\(state.ecoPoints)"]))
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(adminAmber)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Button(TerrariumL10n.t("ui.footer.settings")) {
                        state.isConfirmingResetSave = false
                        state.isShowingSettings.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(state.isShowingSettings ? adminAmber : textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                    Button(TerrariumL10n.t("ui.footer.quit")) {
                        state.flushSave()
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bgHeader)
            .overlay(Rectangle().frame(height: 1.5).foregroundColor(borderCol), alignment: .top)
        }

            if state.isShowingSettings {
                settingsOverlay
            }

            if state.isShowingRenameTankSheet {
                renameTankOverlay
            }

            if let targetKind = state.renamingCritterKind {
                renameCritterOverlay(kind: targetKind)
            }
        }
        .frame(width: 472, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(bgMain)
        .background(MenuBarWindowTopPinHelper(triggerKey: "\(state.currentTab.rawValue)_\(state.activeLanguage.rawValue)_\(state.isAdminMode)_\(state.isShowingBuyTankSheet)_\(state.containers.count)_\(state.selectedPlantID?.uuidString ?? "")_\(state.selectedDecorID ?? "")"))
        .preferredColorScheme(.dark)
    }

    private var biomeSwitcherBar: some View {
        VStack(spacing: 6) {
            // 顶部管理条 + 已购缸体直接按键切换区（有多少个显示多少个，绝不展示未买空位）
            HStack(spacing: 5) {
                Text(TerrariumL10n.t("ui.switcher.title", [
                    "count": "\(state.containers.count)",
                    "max": "\(TerrariumConfig.maxTankSlots)"
                ]))
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if state.isResonanceActive {
                    Text(TerrariumL10n.t("ui.switcher.resonance"))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(adminAmber.opacity(0.2))
                        .foregroundColor(adminAmber)
                        .overlay(Rectangle().stroke(adminAmber.opacity(0.6), lineWidth: 1))
                        .help(TerrariumL10n.t("ui.switcher.resonance_help"))
                }

                Spacer(minLength: 4)

                Button("✏️") {
                    state.renameTankDraft = state.activeContainerName
                    state.isShowingRenameTankSheet = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(bgCard)
                .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                .help(TerrariumL10n.t("ui.switcher.rename_help"))

                Button("📸") {
                    state.exportPixelSnapshot(content: PixelStageSnapshotCard(state: state))
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(bgCard)
                .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                .help(TerrariumL10n.t("ui.switcher.snapshot_help"))

                Button(TerrariumL10n.t(state.isShowingBuyTankSheet ? "ui.switcher.hide_shop" : "ui.switcher.buy_tank")) {
                    state.isShowingBuyTankSheet.toggle()
                    state.isConfirmingDeleteTank = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(state.isShowingBuyTankSheet ? adminAmber : accentGreen)
                .foregroundColor(state.isShowingBuyTankSheet ? .black : .white)
                .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))

                if state.containers.count > 1 {
                    Button(TerrariumL10n.t("ui.switcher.delete")) {
                        state.isConfirmingDeleteTank.toggle()
                        state.isShowingBuyTankSheet = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(state.isConfirmingDeleteTank ? Color.red.opacity(0.75) : bgCard)
                    .foregroundColor(state.isConfirmingDeleteTank ? .white : Color(red: 0.96, green: 0.56, blue: 0.52))
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))
                    .help(TerrariumL10n.t("ui.switcher.delete_help"))
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 118, maximum: 165), spacing: 5)],
                spacing: 5
            ) {
                ForEach(state.containers) { container in
                    let isSelected = (container.id == state.activeContainerID)
                    Button {
                        state.selectContainer(id: container.id)
                    } label: {
                        HStack(spacing: 4) {
                            Text(container.instance.biome.iconEmoji)
                                .font(.system(size: 11))
                                .fixedSize(horizontal: true, vertical: false)
                            Text(container.customName)
                                .font(.system(size: 10.5, weight: isSelected ? .bold : .medium, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 3)
                            Text(state.temperatureUnit.format(celsius: container.instance.temperature, includeUnitLetter: false))
                                .font(.system(size: 9.5, design: .monospaced))
                                .opacity(0.85)
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(1)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(
                            container.instance.biome == .reef
                            ? (isSelected ? Color(red: 0.10, green: 0.34, blue: 0.56) : Color(red: 0.11, green: 0.21, blue: 0.36))
                            : (isSelected ? accentGreen : bgCard)
                        )
                        .foregroundColor(isSelected ? .white : textMain)
                        .overlay(
                            Rectangle().stroke(
                                container.instance.biome == .reef
                                ? (isSelected ? Color(red: 0.96, green: 0.49, blue: 0.32) : Color(red: 0.96, green: 0.49, blue: 0.32).opacity(0.65))
                                : (isSelected ? adminAmber : borderCol),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if state.isConfirmingDeleteTank && state.containers.count > 1 {
                HStack(spacing: 6) {
                    Text(TerrariumL10n.t("ui.delete_tank.confirm", [
                        "name": state.activeContainerName,
                        "refund": "\(state.activeContainerRefundEstimate)"
                    ]))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(red: 0.99, green: 0.80, blue: 0.76))
                        .lineLimit(3)
                    Spacer(minLength: 4)
                    Button(TerrariumL10n.t("ui.delete_tank.confirm_btn")) {
                        state.deleteActiveContainer()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.8))
                    .foregroundColor(.white)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                    Button(TerrariumL10n.t("ui.common.cancel")) {
                        state.isConfirmingDeleteTank = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(bgCard)
                    .foregroundColor(textMuted)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                }
                .padding(6)
                .background(Color.red.opacity(0.14))
                .overlay(Rectangle().stroke(Color.red.opacity(0.45), lineWidth: 1))
            }

            if state.isShowingBuyTankSheet {
                VStack(alignment: .leading, spacing: 5) {
                    Text(TerrariumL10n.t("ui.buy_tank.prompt", ["max": "\(TerrariumConfig.maxTankSlots)"]))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(textMuted)
                    HStack(spacing: 5) {
                        ForEach(TerrariumBiome.allCases.filter { !$0.isHiddenUnlockable }) { biome in
                            let cost = TerrariumConfig.tankPurchaseCost(for: biome, existingTankCount: state.containers.count)
                            let canBuy = biome.isPlayableInCurrentWave
                                && state.containers.count < TerrariumConfig.maxTankSlots
                                && state.ecoPoints >= cost
                            Button {
                                state.purchaseNewTank(biome: biome)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(biome.iconEmoji)
                                    Text(biome.localizedShortName)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.72)
                                    Text(biome.isPlayableInCurrentWave
                                         ? TerrariumL10n.t("ui.common.cost_points", ["cost": "\(cost)"])
                                         : TerrariumL10n.t("ui.buy_tank.coming_soon"))
                                        .font(.system(size: 9, design: .monospaced))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 5)
                                .background(canBuy ? adminAmber : bgCard)
                                .foregroundColor(canBuy ? .black : textMuted.opacity(0.65))
                                .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(!canBuy)
                        }
                    }

                    let reefCost = TerrariumConfig.tankPurchaseCost(for: .reef, existingTankCount: state.containers.count)
                    let reefUnlocked = state.reefUnlockProgress.isUnlocked || state.isAdminMode
                    let canBuyReef = reefUnlocked && state.containers.count < TerrariumConfig.maxTankSlots && state.ecoPoints >= reefCost
                    if reefUnlocked {
                        Button {
                            state.purchaseNewTank(biome: .reef)
                        } label: {
                            HStack(spacing: 6) {
                                Text("🪸 \(TerrariumBiome.reef.localizedName)")
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                Spacer()
                                Text(TerrariumL10n.t("ui.common.cost_points", ["cost": "\(reefCost)"]))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                            .background(canBuyReef ? Color(red: 0.10, green: 0.34, blue: 0.56) : bgCard)
                            .foregroundColor(canBuyReef ? .white : textMuted.opacity(0.65))
                            .overlay(Rectangle().stroke(Color(red: 0.96, green: 0.49, blue: 0.32), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canBuyReef)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(TerrariumL10n.t("ui.buy_tank.reef_locked_title"))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.52, green: 0.78, blue: 0.96))
                            Text(TerrariumL10n.t("ui.buy_tank.reef_locked_desc", [
                                "tanks": "\(state.reefUnlockProgress.ownedBaseTankCount)",
                                "animals": "\(state.reefUnlockProgress.collectedBaseAnimalCount)"
                            ]))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.09, green: 0.14, blue: 0.22))
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                    }
                }
                .padding(7)
                .background(bgHeader)
                .overlay(Rectangle().stroke(adminAmber.opacity(0.6), lineWidth: 1))
            }
        }
    }

    private var terrariumTabContent: some View {
        VStack(spacing: 8) {
            biomeSwitcherBar

            PixelStageView(state: state)

            if let selPlant = state.selectedPlant {
                HStack(spacing: 6) {
                    Text(TerrariumL10n.t("ui.plant.title", [
                        "name": TerrariumState.displayName(forPlantSpecies: selPlant.speciesID),
                        "stage": TerrariumState.stageLabel(for: selPlant.stage, biome: state.currentBiome, salinity: state.salinity)
                    ]))
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(textMain)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    Button(TerrariumL10n.t(state.isMovingPlant ? "ui.plant.moving" : "ui.plant.move")) {
                        if state.isMovingPlant {
                            state.isMovingPlant = false
                        } else {
                            state.beginMoveSelectedPlant()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(state.isMovingPlant ? adminAmber : accentGreen)
                    .foregroundColor(state.isMovingPlant ? .black : .white)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                    Button(TerrariumL10n.t(selPlant.stage == .sprout ? "ui.plant.remove_sprout" : "ui.plant.prune")) {
                        state.isMovingPlant = false
                        state.isConfirmingPrunePlant = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(bgCard)
                    .foregroundColor(adminAmber)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                    Button("×") {
                        state.selectPlant(nil)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(textMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(bgHeader)
                .overlay(Rectangle().stroke(accentGreen.opacity(0.6), lineWidth: 1))

                if state.isConfirmingPrunePlant {
                    let plantName = TerrariumState.displayName(forPlantSpecies: selPlant.speciesID)
                    let isSprout = (selPlant.stage == .sprout)
                    HStack(spacing: 6) {
                        Text(TerrariumL10n.t(isSprout ? "ui.plant.confirm_remove_sprout" : "ui.plant.confirm_prune", ["name": plantName]))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(isSprout ? Color(red: 0.99, green: 0.80, blue: 0.76) : adminAmber)
                            .lineLimit(3)
                        Spacer(minLength: 4)
                        Button(TerrariumL10n.t(isSprout ? "ui.plant.confirm_remove_btn" : "ui.plant.confirm_prune_btn")) {
                            state.pruneSelectedPlant()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isSprout ? Color.red.opacity(0.8) : accentGreen)
                        .foregroundColor(.white)
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                        Button(TerrariumL10n.t("ui.common.cancel")) {
                            state.isConfirmingPrunePlant = false
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(bgCard)
                        .foregroundColor(textMuted)
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                    }
                    .padding(6)
                    .background((isSprout ? Color.red : adminAmber).opacity(0.14))
                    .overlay(Rectangle().stroke((isSprout ? Color.red : adminAmber).opacity(0.45), lineWidth: 1))
                }
            } else if let selDecor = state.selectedDecorItem {
                let isMovingThis = (state.movingDecorID == selDecor.id)
                let dims = TerrariumConfig.decorDimensions(for: selDecor.id)
                HStack(spacing: 6) {
                    Text(TerrariumL10n.t("ui.decor_sel.title", [
                        "name": selDecor.name,
                        "cols": "\(dims.cols)",
                        "rows": "\(dims.rows)"
                    ]))
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(textMain)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    Button(TerrariumL10n.t(isMovingThis ? "ui.decor_sel.moving" : "ui.decor_sel.move")) {
                        if isMovingThis {
                            state.movingDecorID = nil
                        } else {
                            state.beginMoveDecor(selDecor.id)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isMovingThis ? adminAmber : accentGreen)
                    .foregroundColor(isMovingThis ? .black : .white)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                    Button(TerrariumL10n.t("ui.decor_sel.stow")) {
                        state.handleDecorAction(id: selDecor.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(bgCard)
                    .foregroundColor(textMuted)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                    Button("×") {
                        state.selectDecor(nil)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(textMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(bgHeader)
                .overlay(Rectangle().stroke(adminAmber.opacity(0.6), lineWidth: 1))
            }

            if let eventMsg = state.eventMessage {
                HStack(spacing: 6) {
                    Text("⚡ \(eventMsg)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Color(red: 0.99, green: 0.90, blue: 0.54))
                        .lineLimit(3)
                    Spacer(minLength: 4)
                    Button(TerrariumL10n.t("ui.common.acknowledge")) {
                        state.dismissEvent()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(bgCard)
                    .foregroundColor(textMain)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                }
                .padding(6)
                .background(adminAmber.opacity(0.14))
                .overlay(Rectangle().stroke(adminAmber.opacity(0.45), lineWidth: 1))
            }

            // 温湿度传感器条（含所有模式需购买后可用的夹缸物理加热灯/棒与降温扇开关）
            HStack(spacing: 6) {
                let targetTemp = TerrariumConfig.baseAmbientTemp(
                    for: state.atmosphere,
                    biome: state.currentBiome,
                    thermalMode: state.thermalMode,
                    localOutdoorTempC: state.localOutdoorTempC
                )
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        let isWaterTank = (state.currentBiome == .aquatic || state.currentBiome == .reef)
                        Text(TerrariumL10n.t(isWaterTank ? "sensor.water_temp" : "sensor.temp"))
                            .foregroundColor(textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Spacer(minLength: 2)
                        if state.thermalMode != .natural && targetTemp != state.temperature {
                            Text("→\(state.temperatureUnit.format(celsius: targetTemp, includeUnitLetter: false))")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(state.thermalMode == .heating ? Color.orange : Color.cyan)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        Button {
                            state.toggleTemperatureUnit()
                        } label: {
                            Text(state.temperatureUnit.format(celsius: state.temperature))
                                .bold()
                                .foregroundColor(textMain)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(.plain)
                        .help(TerrariumL10n.t("sensor.temp_unit_help"))
                    }
                    HStack(spacing: 3) {
                        let tempSubtitle = (state.localOutdoorTempC != nil)
                            ? TerrariumL10n.t("sensor.temp_sub_outdoor", [
                                "hint": state.tempHint,
                                "temp": "\(state.temperatureUnit.convert(celsius: state.localOutdoorTempC!))"
                            ])
                            : state.tempHint
                        Text(tempSubtitle)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .truncationMode(.tail)
                            .help(state.localOutdoorTempC != nil
                                  ? TerrariumL10n.t("sensor.outdoor_help", ["city": state.localizedLocalCityName, "temp": "\(state.localOutdoorTempC!)"])
                                  : TerrariumL10n.t("sensor.outdoor_syncing"))
                        Spacer(minLength: 2)
                        Button(state.hasHeatLamp ? "☀️" : "☀️\(TerrariumConfig.heatLampCost)") {
                            state.toggleThermalMode(.heating)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(state.thermalMode == .heating ? Color.orange : bgHeader)
                        .foregroundColor(state.thermalMode == .heating ? .black : (state.hasHeatLamp ? textMain : adminAmber))
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                        .help(state.hasHeatLamp
                              ? TerrariumL10n.t("sensor.heat_help_on", ["temp": "\(targetTemp)"])
                              : TerrariumL10n.t("sensor.heat_help_off", ["cost": "\(TerrariumConfig.heatLampCost)"]))

                        Button(state.hasCoolingFan ? "❄️" : "❄️\(TerrariumConfig.coolingFanCost)") {
                            state.toggleThermalMode(.cooling)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(state.thermalMode == .cooling ? Color.cyan : bgHeader)
                        .foregroundColor(state.thermalMode == .cooling ? .black : (state.hasCoolingFan ? textMain : adminAmber))
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                        .help(state.hasCoolingFan
                              ? TerrariumL10n.t("sensor.fan_help_on", ["temp": "\(targetTemp)"])
                              : TerrariumL10n.t("sensor.fan_help_off", ["cost": "\(TerrariumConfig.coolingFanCost)"]))

                        if state.isAdminMode {
                            miniBtn("-", action: { state.adjustTemp(-1) })
                            miniBtn("+", action: { state.adjustTemp(1) })
                        }
                    }
                    .frame(minHeight: 16)
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(bgCard)
                .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))

                let isWaterTank = (state.currentBiome == .aquatic || state.currentBiome == .reef)
                if state.currentBiome == .reef {
                    VStack(spacing: 3) {
                        HStack(spacing: 3) {
                            Text(TerrariumL10n.t("sensor.oxygen"))
                                .foregroundColor(textMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Spacer(minLength: 2)
                            Text("\(state.humidity)%")
                                .bold()
                                .foregroundColor(textMain)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        HStack(spacing: 3) {
                            Text("\(String(format: "%.1f", state.salinity))‰·\(state.salinityHint)")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(TerrariumConfig.optimalSalinityRange.contains(state.salinity) ? textMuted : adminAmber)
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)
                            Spacer(minLength: 2)
                            Button(TerrariumL10n.t("sensor.add_salt_btn")) {
                                state.addSeaSalt()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(bgHeader)
                            .foregroundColor(Color(red: 0.56, green: 0.85, blue: 0.99))
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                            .help(TerrariumL10n.t("sensor.add_salt_help"))
                            if state.isAdminMode {
                                miniBtn("-", action: { state.adjustHumidity(-5) })
                                miniBtn("+", action: { state.adjustHumidity(5) })
                            }
                        }
                        .frame(minHeight: 16)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(bgCard)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))
                } else {
                    readOnlySensorBox(
                        label: TerrariumL10n.t(isWaterTank ? "sensor.oxygen" : "sensor.humidity"),
                        value: "\(state.humidity)%",
                        hint: state.humHint,
                        allowAdminButtons: state.isAdminMode,
                        onMinus: { state.adjustHumidity(-5) },
                        onPlus: { state.adjustHumidity(5) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        Text(TerrariumL10n.t(isWaterTank ? "sensor.feeding_ring" : "sensor.food_bowl"))
                            .foregroundColor(textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Spacer(minLength: 2)
                        Text("\(state.foodBowlPortions)/\(TerrariumConfig.maxFoodPortions)")
                            .bold()
                            .foregroundColor(textMain)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    HStack(spacing: 3) {
                        Text(TerrariumL10n.t("sensor.critters_count", ["count": "\(state.activeDisplayCritters.count)"]))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Spacer(minLength: 2)
                        Text(TerrariumL10n.t("sensor.plants_count", [
                            "count": "\(state.plants.count)",
                            "max": "\(TerrariumConfig.maxPlantsCap)"
                        ]))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(minHeight: 16)
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(bgCard)
                .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))
            }
            .fixedSize(horizontal: false, vertical: true)

            if let pendingThermal = state.pendingPurchaseThermalMode {
                let isHeat = (pendingThermal == .heating)
                let equipName = TerrariumL10n.t(isHeat
                                                ? ((state.currentBiome == .aquatic || state.currentBiome == .reef) ? "ui.equip.heater" : "ui.equip.heat_lamp")
                                                : "ui.equip.cooling_fan")
                let cost = isHeat ? TerrariumConfig.heatLampCost : TerrariumConfig.coolingFanCost
                HStack(spacing: 6) {
                    Text(TerrariumL10n.t("ui.equip.confirm_prompt", ["cost": "\(cost)", "name": equipName]))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(textMain)
                        .lineLimit(3)
                    Spacer(minLength: 4)
                    Button(TerrariumL10n.t("ui.equip.confirm_btn", ["cost": "\(cost)"])) {
                        state.confirmPurchaseThermalEquipment()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(adminAmber)
                    .foregroundColor(.black)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                    Button(TerrariumL10n.t("ui.common.cancel")) {
                        state.cancelPurchaseThermalEquipment()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(bgCard)
                    .foregroundColor(textMuted)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                }
                .padding(6)
                .background(adminAmber.opacity(0.14))
                .overlay(Rectangle().stroke(adminAmber.opacity(0.45), lineWidth: 1))
            }

            // 4 个自然演进核心交互按钮
            HStack(spacing: 6) {
                let firstActionKey: String = {
                    switch state.currentBiome {
                    case .aquatic: return "action.water_o2"
                    case .reef: return "action.ro_water"
                    default: return "action.mist"
                    }
                }()
                let isWaterTank = (state.currentBiome == .aquatic || state.currentBiome == .reef)
                pixelActionButton(icon: "icon_mist", title: TerrariumL10n.t(firstActionKey)) { state.mist() }
                pixelActionButton(icon: "icon_feed", title: TerrariumL10n.t(isWaterTank ? "action.feed_fish" : "action.feed_land")) { state.feed() }
                pixelActionButton(icon: "icon_clean", title: TerrariumL10n.t(isWaterTank ? "action.clean_algae" : "action.clean_fog")) { state.clean() }
                pixelActionButton(
                    icon: "icon_sleep",
                    title: TerrariumL10n.t(state.isSleeping ? "action.wake" : "action.sleep"),
                    highlighted: state.isSleeping
                ) { state.toggleSleep() }
            }

            // 仅管理员模式可见调试条（含生态点增减调试）
            if state.isAdminMode {
                VStack(spacing: 5) {
                    HStack(spacing: 4) {
                        ForEach(SceneAtmosphere.allCases) { atm in
                            Button {
                                state.setAtmosphere(atm)
                            } label: {
                                Text(atm.localizedShortName)
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(state.atmosphere == atm ? accentGreen : bgCard)
                                    .foregroundColor(state.atmosphere == atm ? .white : textMuted)
                                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 2)
                        Button(TerrariumL10n.t("admin.pts_minus10")) { state.adjustEcoPointsDebug(-10) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(bgCard).foregroundColor(textMuted)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                        Button(TerrariumL10n.t("admin.pts_plus10")) { state.adjustEcoPointsDebug(10) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(bgCard).foregroundColor(adminAmber)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                        Button(TerrariumL10n.t("admin.pts_plus50")) { state.adjustEcoPointsDebug(50) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(bgCard).foregroundColor(adminAmber)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                    }
                    HStack(spacing: 4) {
                        Button(TerrariumL10n.t("admin.event")) { state.simulateWeatherEvent() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(bgCard).foregroundColor(adminAmber)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                        Button(TerrariumL10n.t("admin.spawn_plant")) { state.triggerPlantPulseDebug() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(bgCard).foregroundColor(textMain)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                        Button(TerrariumL10n.t(state.showIsoGridDebug ? "admin.grid_hide" : "admin.grid_show")) {
                            state.showIsoGridDebug.toggle()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(state.showIsoGridDebug ? accentGreen : bgCard)
                        .foregroundColor(textMain)
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                        Spacer()
                        Button(TerrariumL10n.t("admin.lock_spawn")) { state.setAdminMode(false) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(bgCard).foregroundColor(textMuted)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                    }
                    HStack(spacing: 4) {
                        Text(TerrariumL10n.t("admin.speed_label"))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(adminAmber)
                            .lineLimit(1)
                        ForEach([1.0, 10.0, 60.0, 300.0], id: \.self) { scale in
                            Button("\(Int(scale))x") {
                                state.setAdminTimeScale(scale)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 9.5, weight: state.adminTimeScale == scale ? .bold : .regular, design: .monospaced))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(state.adminTimeScale == scale ? adminAmber : bgCard)
                            .foregroundColor(state.adminTimeScale == scale ? .black : textMain)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                        }
                        Spacer()
                        Button(TerrariumL10n.t("admin.ff_10m")) { state.fastForwardDebug(seconds: 600) }
                            .buttonStyle(.plain)
                            .font(.system(size: 9.5, design: .monospaced))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(bgCard).foregroundColor(textMain)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                        Button(TerrariumL10n.t("admin.ff_1h")) { state.fastForwardDebug(seconds: 3600) }
                            .buttonStyle(.plain)
                            .font(.system(size: 9.5, design: .monospaced))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(bgCard).foregroundColor(textMain)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                        Button(TerrariumL10n.t("admin.ff_8h")) { state.fastForwardDebug(seconds: 8 * 3600) }
                            .buttonStyle(.plain)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(bgCard).foregroundColor(adminAmber)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                    }
                    if state.adminSimulatedElapsedSeconds > 0 {
                        let mins = Int(state.adminSimulatedElapsedSeconds / 60.0)
                        let elapsedLabel = mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins)m"
                        Text(TerrariumL10n.t("admin.virtual_clock", ["elapsed": elapsedLabel]))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(textMuted)
                    }
                }
                .padding(6)
                .background(adminAmber.opacity(0.08))
                .overlay(Rectangle().stroke(adminAmber.opacity(0.35), lineWidth: 1))
            }
        }
    }

    private func readOnlySensorBox(
        label: String,
        value: String,
        hint: String,
        allowAdminButtons: Bool,
        onMinus: @escaping () -> Void,
        onPlus: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text(label)
                    .foregroundColor(textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 2)
                Text(value)
                    .bold()
                    .foregroundColor(textMain)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            HStack(spacing: 3) {
                Text(hint)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 2)
                if allowAdminButtons {
                    HStack(spacing: 4) {
                        miniBtn("-", action: onMinus)
                        miniBtn("+", action: onPlus)
                    }
                }
            }
            .frame(minHeight: 16)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(6)
        .background(bgCard)
        .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))
    }

    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.1"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "121"
        return "v\(short) (\(build))"
    }

    @ViewBuilder
    private var updateActionButton: some View {
        switch state.updateStatus {
        case .idle:
            Button(TerrariumL10n.t("settings.update_check")) {
                Task { await state.checkForUpdates(userInitiated: true) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bgCard)
            .foregroundColor(adminAmber)
            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
        case .checking:
            Text(TerrariumL10n.t("settings.update_checking"))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(textMuted)
        case .upToDate:
            Button(TerrariumL10n.t("settings.update_latest")) {
                Task { await state.checkForUpdates(userInitiated: true) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 9.5, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bgCard)
            .foregroundColor(accentGreen)
            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
        case .available(let info):
            Button(TerrariumL10n.t("settings.update_download", ["ver": info.version])) {
                Task { await state.downloadAndOpenAvailableUpdate() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(accentGreen)
            .foregroundColor(.white)
            .overlay(Rectangle().stroke(adminAmber, lineWidth: 1))
        case .downloading:
            Text(TerrariumL10n.t("settings.update_downloading"))
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(adminAmber)
        case .downloaded(let fileURL):
            Button(TerrariumL10n.t("settings.update_opened")) {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
            .buttonStyle(.plain)
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bgCard)
            .foregroundColor(accentGreen)
            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
        case .failed:
            Button(TerrariumL10n.t("settings.update_failed")) {
                Task { await state.checkForUpdates(userInitiated: true) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 9.5, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bgCard)
            .foregroundColor(Color(red: 0.99, green: 0.72, blue: 0.68))
            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
        }
    }

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                state.bannerNotice = TerrariumL10n.t("settings.autostart_off")
            } else {
                try SMAppService.mainApp.register()
                state.bannerNotice = TerrariumL10n.t("settings.autostart_on")
            }
        } catch {
            state.bannerNotice = TerrariumL10n.t("settings.autostart_need_app")
        }
    }

    private var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .onTapGesture {
                    state.isConfirmingResetSave = false
                    state.isShowingSettings = false
                }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(TerrariumL10n.t("settings.title"))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(textMain)
                    Spacer()
                    Button("×") {
                        state.isConfirmingResetSave = false
                        state.isShowingSettings = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(textMuted)
                }

                Divider().background(borderCol)

                HStack(spacing: 6) {
                    Text(TerrariumL10n.t("settings.version_label"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(textMuted)
                    Spacer(minLength: 4)
                    Text("Pixel Terrarium \(appVersionLabel)")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(textMain)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    updateActionButton
                }

                HStack {
                    Text(TerrariumL10n.t("settings.schema_label"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(textMuted)
                    Spacer()
                    Text("schemaVersion v\(TerrariumSaveData().schemaVersion)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(textMuted)
                }

                HStack {
                    Text(TerrariumL10n.t("settings.language_label"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    Menu {
                        Button {
                            state.setLanguagePreference(.system)
                        } label: {
                            let sysTitle = TerrariumL10n.t("settings.language_system", [
                                "lang": TerrariumL10n.resolveSystemLanguage().nativeDisplayName
                            ])
                            Text(state.languagePreference == .system ? "✓ \(sysTitle)" : sysTitle)
                        }
                        Divider()
                        ForEach(SupportedLanguage.allCases) { lang in
                            let pref = AppLanguagePreference(rawValue: lang.rawValue) ?? .system
                            Button {
                                state.setLanguagePreference(pref)
                            } label: {
                                Text(state.languagePreference == pref ? "✓ \(lang.nativeDisplayName)" : lang.nativeDisplayName)
                            }
                        }
                    } label: {
                        let currentLabel: String = {
                            if state.languagePreference == .system {
                                return TerrariumL10n.t("settings.language_system", [
                                    "lang": state.activeLanguage.nativeDisplayName
                                ])
                            }
                            return state.activeLanguage.nativeDisplayName
                        }()
                        HStack(spacing: 4) {
                            Text(currentLabel)
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            Text("▾")
                                .font(.system(size: 9.5, design: .monospaced))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(bgCard)
                        .foregroundColor(adminAmber)
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                HStack {
                    Text(TerrariumL10n.t("settings.temp_unit_label"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    HStack(spacing: 4) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            let isSelected = (state.temperatureUnit == unit)
                            Button(unit.localizedButtonLabel) {
                                state.setTemperatureUnit(unit)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(isSelected ? accentGreen : bgCard)
                            .foregroundColor(isSelected ? .white : textMuted)
                            .overlay(Rectangle().stroke(isSelected ? adminAmber : borderCol, lineWidth: 1))
                        }
                    }
                }

                HStack {
                    Text(TerrariumL10n.t("settings.tips_freq_label"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    HStack(spacing: 4) {
                        ForEach(DailyTipsFrequency.allCases) { freq in
                            let isSelected = (state.tipsFrequency == freq)
                            Button(freq.localizedButtonLabel) {
                                state.setTipsFrequency(freq)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(isSelected ? accentGreen : bgCard)
                            .foregroundColor(isSelected ? .white : textMuted)
                            .overlay(Rectangle().stroke(isSelected ? adminAmber : borderCol, lineWidth: 1))
                        }
                    }
                }

                HStack {
                    Text(TerrariumL10n.t("settings.launch_at_login"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    Button(TerrariumL10n.t(isLaunchAtLoginEnabled ? "settings.enabled" : "settings.disabled")) {
                        toggleLaunchAtLogin()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isLaunchAtLoginEnabled ? accentGreen : bgCard)
                    .foregroundColor(isLaunchAtLoginEnabled ? .white : textMuted)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                }

                Divider().background(borderCol)

                if !state.isConfirmingResetSave {
                    Button {
                        state.isConfirmingResetSave = true
                    } label: {
                        Text(TerrariumL10n.t("settings.reset_save"))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.22))
                            .foregroundColor(Color(red: 0.99, green: 0.72, blue: 0.68))
                            .overlay(Rectangle().stroke(Color.red.opacity(0.55), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(TerrariumL10n.t("settings.reset_confirm_msg"))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(red: 0.99, green: 0.80, blue: 0.76))
                        HStack(spacing: 8) {
                            Button(TerrariumL10n.t("settings.reset_confirm_btn")) {
                                state.resetSaveData()
                                state.isConfirmingResetSave = false
                                state.isShowingSettings = false
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.85))
                            .foregroundColor(.white)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                            Button(TerrariumL10n.t("ui.common.cancel")) {
                                state.isConfirmingResetSave = false
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(bgCard)
                            .foregroundColor(textMuted)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                        }
                    }
                }
            }
            .padding(12)
            .frame(width: 340)
            .background(bgHeader)
            .overlay(Rectangle().stroke(borderCol, lineWidth: 2))
        }
    }

    private var renameTankOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .onTapGesture { state.isShowingRenameTankSheet = false }
            VStack(alignment: .leading, spacing: 10) {
                Text(TerrariumL10n.t("ui.rename_tank.title"))
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .foregroundColor(textMain)
                TextField(TerrariumL10n.t("ui.rename_tank.placeholder"), text: $state.renameTankDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                HStack {
                    Spacer()
                    Button(TerrariumL10n.t("ui.common.cancel")) {
                        state.isShowingRenameTankSheet = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(bgCard)
                    .foregroundColor(textMuted)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                    Button(TerrariumL10n.t("ui.common.save")) {
                        state.renameActiveContainer(to: state.renameTankDraft)
                        state.isShowingRenameTankSheet = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accentGreen)
                    .foregroundColor(.white)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                }
            }
            .padding(12)
            .frame(width: 300)
            .background(bgHeader)
            .overlay(Rectangle().stroke(borderCol, lineWidth: 2))
        }
    }

    private func renameCritterOverlay(kind: CritterKind) -> some View {
        ZStack {
            Color.black.opacity(0.55)
                .onTapGesture { state.renamingCritterKind = nil }
            VStack(alignment: .leading, spacing: 10) {
                Text(TerrariumL10n.t("ui.rename_critter.title", ["kind": kind.localizedName]))
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .foregroundColor(textMain)
                    .lineLimit(2)
                TextField(TerrariumL10n.t("ui.rename_critter.placeholder"), text: $state.renameCritterDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                HStack {
                    Spacer()
                    Button(TerrariumL10n.t("ui.common.cancel")) {
                        state.renamingCritterKind = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(bgCard)
                    .foregroundColor(textMuted)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                    Button(TerrariumL10n.t("ui.common.save")) {
                        state.renameCritter(kind: kind, to: state.renameCritterDraft)
                        state.renamingCritterKind = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accentGreen)
                    .foregroundColor(.white)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                }
            }
            .padding(12)
            .frame(width: 300)
            .background(bgHeader)
            .overlay(Rectangle().stroke(borderCol, lineWidth: 2))
        }
    }

    private func miniBtn(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .frame(width: 18, height: 16)
                .background(bgHeader)
                .foregroundColor(adminAmber)
                .overlay(Rectangle().stroke(adminAmber.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func pixelActionButton(icon: String, title: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                PixelAssetLoader.swiftUIImage(named: icon)
                    .frame(width: 14, height: 14)
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(highlighted ? Color(red: 0.96, green: 0.62, blue: 0.04) : bgHeader)
            .foregroundColor(highlighted ? .black : textMain)
            .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var decorTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(TerrariumL10n.t("ui.decor_tab.header", ["biome": state.currentBiome.localizedName]))
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(textMain)
                    Spacer()
                }

                ForEach(state.decorItems) { item in
                    let frameSize: CGSize? = {
                        switch item.id {
                        case "shallow_pool": return CGSize(width: 44, height: 24)
                        case "sand_pebbles": return CGSize(width: 28, height: 16)
                        case "rainforest_waterfall": return CGSize(width: 48, height: 38)
                        case "aquatic_bubble_rock": return CGSize(width: 44, height: 36)
                        default: return nil
                        }
                    }()
                    HStack(spacing: 8) {
                        PixelAssetLoader.previewSwiftUIImage(named: item.assetName, frameSize: frameSize)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 42, height: 32)
                            .background(bgCard)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(textMain)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(item.nicheDescription)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(textMuted)
                                .lineLimit(3)
                        }
                        Spacer(minLength: 4)
                        if item.unlocked {
                            HStack(spacing: 4) {
                                if item.enabled {
                                    Button(TerrariumL10n.t("ui.decor_tab.reposition")) {
                                        state.currentTab = .terrarium
                                        state.beginMoveDecor(item.id)
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(bgCard)
                                    .foregroundColor(adminAmber)
                                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                                }
                                Button(TerrariumL10n.t(item.enabled ? "ui.decor_tab.placed" : "ui.decor_tab.stowed")) {
                                    state.handleDecorAction(id: item.id)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10.5, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(item.enabled ? accentGreen : bgCard)
                                .foregroundColor(item.enabled ? .white : textMuted)
                                .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                            }
                            .layoutPriority(1)
                        } else {
                            let canAfford = state.ecoPoints >= item.cost
                            Button(TerrariumL10n.t("ui.decor_tab.unlock", ["cost": "\(item.cost)"])) {
                                state.handleDecorAction(id: item.id)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canAfford)
                            .font(.system(size: 10.5, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(canAfford ? adminAmber : bgCard)
                            .foregroundColor(canAfford ? .black : textMuted.opacity(0.5))
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                            .layoutPriority(1)
                        }
                    }
                    .padding(8)
                    .background(bgHeader)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))
                }

                Divider().background(borderCol).padding(.vertical, 2)

                HStack {
                    Text(TerrariumL10n.t("ui.decor_tab.skins_header"))
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(textMain)
                    Spacer()
                }

                VStack(spacing: 6) {
                    ForEach(TankFrameSkin.allCases, id: \.rawValue) { skin in
                        let isUnlocked = state.unlockedFrameSkinIDs.contains(skin.rawValue)
                        let isActive = state.activeFrameSkin == skin
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(frameSwatchColor(skin))
                                .frame(width: 24, height: 24)
                                .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skin.displayName)
                                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(textMain)
                                Text(isUnlocked
                                     ? TerrariumL10n.t(isActive ? "ui.decor_tab.skin_active_desc" : "ui.decor_tab.skin_unlocked_desc")
                                     : TerrariumL10n.t("ui.decor_tab.skin_locked_desc", ["cost": "\(skin.cost)"]))
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundColor(textMuted)
                            }
                            Spacer(minLength: 4)
                            Button {
                                state.purchaseOrSelectFrameSkin(skin)
                            } label: {
                                Text(isActive
                                     ? TerrariumL10n.t("ui.decor_tab.skin_in_use")
                                     : (isUnlocked
                                        ? TerrariumL10n.t("ui.decor_tab.skin_switch")
                                        : TerrariumL10n.t("ui.decor_tab.skin_unlock", ["cost": "\(skin.cost)"])))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(isActive ? adminAmber : (isUnlocked ? bgCard : accentGreen))
                                    .foregroundColor(isActive ? .black : textMain)
                                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(isActive || (!isUnlocked && state.ecoPoints < skin.cost))
                            .layoutPriority(1)
                        }
                        .padding(6)
                        .background(bgHeader)
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                    }
                }
            }
        }
    }

    private func frameSwatchColor(_ skin: TankFrameSkin) -> Color {
        switch skin {
        case .classic: return Color(red: 0.23, green: 0.32, blue: 0.27)
        case .wood: return Color(red: 0.45, green: 0.29, blue: 0.16)
        case .brass: return Color(red: 0.72, green: 0.56, blue: 0.24)
        case .frosted: return Color(red: 0.65, green: 0.80, blue: 0.88)
        case .obsidian: return Color(red: 0.18, green: 0.16, blue: 0.28)
        case .pearlReef: return Color(red: 0.14, green: 0.42, blue: 0.64)
        }
    }

    private var crittersTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(TerrariumL10n.t("ui.critters.header", ["biome": state.currentBiome.localizedName]))
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(textMain)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    Text(state.activeFoodChainGroup?.localizedName ?? TerrariumL10n.t("ui.critters.empty_group"))
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(bgCard)
                        .foregroundColor(adminAmber)
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                }

                let chainRuleText: String = {
                    switch state.currentBiome {
                    case .aquatic:
                        return TerrariumL10n.t("ui.critters.rule_aquatic")
                    case .reef:
                        return TerrariumL10n.t("ui.critters.rule_reef")
                    case .rainforest:
                        return TerrariumL10n.t("ui.critters.rule_rainforest")
                    default:
                        return TerrariumL10n.t("ui.critters.rule_default")
                    }
                }()
                Text(chainRuleText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(textMuted)

                let catalog = TerrariumConfig.critterShopCatalog(for: state.currentBiome)
                ForEach(catalog) { spec in
                    let owned = state.critters.first(where: { $0.kind == spec.kind })
                    let isInTank = (owned?.residency == .resident || owned?.residency == .visitor)
                    let elig = state.critterEligibility(spec.kind)
                    let conflictsActive = !isInTank && (state.activeFoodChainGroup != nil && state.activeFoodChainGroup != spec.group)
                    let canBuy = elig.eligible && state.ecoPoints >= spec.cost

                    HStack(spacing: 8) {
                        PixelAssetLoader.previewSwiftUIImage(
                            named: spec.assetName,
                            frameSize: CGSize(width: spec.frameWidth, height: spec.frameHeight)
                        )
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 42, height: 34)
                        .background(bgCard)
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                let labelName: String = {
                                    if let owned, let nick = owned.nickname, !nick.isEmpty, nick != spec.name {
                                        return TerrariumL10n.t("ui.critters.name_with_nick", ["name": spec.name, "nick": nick])
                                    }
                                    return spec.name
                                }()
                                Text(labelName)
                                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(textMain)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                                if let owned {
                                    Button("✏️") {
                                        state.renameCritterDraft = owned.nickname ?? spec.name
                                        state.renamingCritterKind = spec.kind
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10))
                                    .help(TerrariumL10n.t("ui.critters.rename_help"))
                                    let stage = TerrariumConfig.affinityStage(for: owned.affinity)
                                    Text(TerrariumL10n.t("ui.critters.affinity_line", [
                                        "val": "\(owned.affinity)",
                                        "max": "\(TerrariumConfig.maxAffinity)",
                                        "stage": stage.title
                                    ]))
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundColor(stage == .soulmate ? adminAmber : Color(red: 0.99, green: 0.68, blue: 0.74))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                            }
                            if let owned {
                                let stage = TerrariumConfig.affinityStage(for: owned.affinity)
                                Text(TerrariumL10n.t("ui.critters.personality_line", [
                                    "personality": TerrariumConfig.localizedPersonality(for: owned.personality),
                                    "perk": TerrariumConfig.perkDescription(for: owned.personality, stage: stage)
                                ]))
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundColor(Color(red: 0.99, green: 0.80, blue: 0.84))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(TerrariumL10n.t("ui.critters.condition_line", [
                                "cond": spec.unlockConditionText,
                                "status": elig.missingReason
                            ]))
                                .font(.system(size: 9.8, design: .monospaced))
                                .foregroundColor(elig.eligible ? Color(red: 0.65, green: 0.92, blue: 0.68) : textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(spec.foodChainNote)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(conflictsActive ? adminAmber : textMuted.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 4)

                        if owned != nil {
                            Button(TerrariumL10n.t(isInTank ? "ui.critters.btn_stow" : (conflictsActive ? "ui.critters.btn_swap" : "ui.critters.btn_place"))) {
                                state.critterPurchaseAndToggle(spec.kind)
                            }
                            .buttonStyle(.plain)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .disabled(!isInTank && !elig.eligible)
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(isInTank ? accentGreen : (elig.eligible ? bgCard : bgCard.opacity(0.5)))
                            .foregroundColor(isInTank ? .white : (elig.eligible ? textMain : textMuted.opacity(0.5)))
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                            .layoutPriority(1)
                        } else {
                            Button(TerrariumL10n.t("ui.critters.btn_adopt", ["cost": "\(spec.cost)"])) {
                                state.critterPurchaseAndToggle(spec.kind)
                            }
                            .buttonStyle(.plain)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .disabled(!canBuy)
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(canBuy ? adminAmber : bgCard)
                            .foregroundColor(canBuy ? .black : textMuted.opacity(0.5))
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                            .layoutPriority(1)
                        }
                    }
                    .padding(8)
                    .background(bgHeader)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))
                }
            }
        }
    }

    private var codexTabContent: some View {
        ScrollView {
            VStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(TerrariumL10n.t("ui.codex.equipped_prefix", ["title": state.codexMilestoneTitle]))
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(adminAmber)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 6) {
                        let baseEntries = state.codexEntries.filter { !$0.isHiddenReef }
                        let baseUnlocked = baseEntries.filter { $0.unlocked }.count
                        Button(TerrariumL10n.t("ui.codex.tab_species", [
                            "unlocked": "\(baseUnlocked)",
                            "total": "\(baseEntries.count)"
                        ])) {
                            state.isShowingAchievementsInCodexTab = false
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(!state.isShowingAchievementsInCodexTab ? accentGreen : bgCard)
                        .foregroundColor(!state.isShowingAchievementsInCodexTab ? .white : textMuted)
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                        Button(TerrariumL10n.t("ui.codex.tab_achievements", [
                            "unlocked": "\(state.unlockedAchievementIDs.count)",
                            "total": "\(TerrariumConfig.defaultAchievements.count)"
                        ])) {
                            state.isShowingAchievementsInCodexTab = true
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(state.isShowingAchievementsInCodexTab ? accentGreen : bgCard)
                        .foregroundColor(state.isShowingAchievementsInCodexTab ? .white : textMuted)
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                    }
                }
                .padding(8)
                .background(bgHeader)
                .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))

                if state.isShowingAchievementsInCodexTab {
                    ForEach(TerrariumConfig.defaultAchievements) { ach in
                        let isUnlocked = state.unlockedAchievementIDs.contains(ach.id)
                        let isEquipped = state.isAchievementEquipped(ach.id)
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("\(isUnlocked ? "🏅" : "🔒") \(ach.title)")
                                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                        .foregroundColor(isUnlocked ? adminAmber : textMain)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Text(ach.category)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(bgCard)
                                        .foregroundColor(textMuted)
                                    Text(TerrariumL10n.t("ui.codex.reward_pts", ["pts": "\(ach.rewardPoints)"]))
                                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                        .foregroundColor(isUnlocked ? accentGreen : textMuted)
                                        .lineLimit(1)
                                }
                                Text(TerrariumL10n.t("ui.codex.ach_cond", ["cond": ach.conditionDesc]))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(textMuted)
                            }
                            Spacer(minLength: 4)
                            if isUnlocked {
                                Button(TerrariumL10n.t(isEquipped ? "ui.codex.equipped_btn" : "ui.codex.equip_btn")) {
                                    state.equipTitle(ach.id)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isEquipped ? adminAmber : accentGreen)
                                .foregroundColor(isEquipped ? .black : .white)
                                .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                                .disabled(isEquipped)
                                .layoutPriority(1)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(bgHeader.opacity(isUnlocked ? 1 : 0.6))
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                    }
                } else {
                    let baseEntries = state.codexEntries.filter { !$0.isHiddenReef }
                    let hiddenEntries = state.codexEntries.filter { $0.isHiddenReef }
                    let hiddenUnlocked = hiddenEntries.filter { $0.unlocked }.count

                    ForEach(baseEntries) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("\(entry.unlocked ? "✅" : "🔒") \(entry.name) · \(entry.category)")
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundColor(textMain)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            Spacer(minLength: 4)
                            Text(entry.biome.localizedShortName)
                                .font(.system(size: 9.5, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(bgCard)
                                .foregroundColor(textMuted)
                        }
                        Text(TerrariumL10n.t("ui.codex.entry_cond", ["cond": entry.condition]))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(textMuted)
                        Text(entry.unlocked ? entry.desc : TerrariumL10n.t("ui.codex.locked_desc"))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(textMain.opacity(0.85))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(bgHeader.opacity(entry.unlocked ? 1 : 0.6))
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                    }

                    // 独立隐藏海域图鉴（未解锁显示 ???，绝不剧透且不影响 52 项基础全收集）
                    HStack {
                        Text(TerrariumL10n.t("ui.codex.hidden_header", [
                            "unlocked": "\(hiddenUnlocked)",
                            "total": "\(hiddenEntries.count)"
                        ]))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.56, green: 0.85, blue: 0.99))
                        Spacer()
                    }
                    .padding(.top, 6)

                    let isReefEverUnlocked = state.reefUnlockProgress.isUnlocked
                        || state.isAdminMode
                        || state.containers.contains(where: { $0.instance.biome == .reef })

                    ForEach(hiddenEntries) { entry in
                    let isRevealed = entry.unlocked
                    let showCondition = isRevealed || isReefEverUnlocked
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(isRevealed
                                 ? "✅ \(entry.name) · \(entry.category)"
                                 : "🔒 \(TerrariumL10n.t("ui.codex.hidden_name")) · \(TerrariumL10n.t("ui.codex.hidden_cat"))")
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundColor(isRevealed ? textMain : Color(red: 0.56, green: 0.85, blue: 0.99))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            Spacer(minLength: 4)
                            Text(isRevealed ? entry.biome.localizedShortName : "???")
                                .font(.system(size: 9.5, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(bgCard)
                                .foregroundColor(textMuted)
                        }
                        Text(TerrariumL10n.t("ui.codex.entry_cond", [
                            "cond": showCondition ? entry.condition : TerrariumL10n.t("ui.codex.hidden_cond")
                        ]))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(textMuted)
                        Text(isRevealed ? entry.desc : TerrariumL10n.t("ui.codex.hidden_desc"))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(textMain.opacity(0.85))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.09, green: 0.14, blue: 0.22).opacity(isRevealed ? 1 : 0.7))
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                    }
                }
            }
        }
    }
}

/// 锁定 macOS MenuBarExtra(.window) 顶边位置并同步精确收缩/扩展 NSWindow 高度，彻底消除切 Tab 时窗口不收缩导致的居中下移留白。
private struct MenuBarWindowTopPinHelper: NSViewRepresentable {
    let triggerKey: String

    final class Coordinator {
        var observers: [NSObjectProtocol] = []
        var anchoredTopY: CGFloat?

        deinit {
            for obs in observers {
                NotificationCenter.default.removeObserver(obs)
            }
        }

        func syncWindowFrame(from view: NSView) {
            guard let window = view.window,
                  let screen = window.screen ?? NSScreen.main else { return }
            let maxSafeTop = screen.visibleFrame.maxY - 2.0
            if anchoredTopY == nil || abs((anchoredTopY ?? 0) - maxSafeTop) > 40.0 {
                anchoredTopY = (window.frame.maxY >= maxSafeTop - 20.0) ? min(window.frame.maxY, maxSafeTop) : maxSafeTop
            }
            guard let targetTop = anchoredTopY else { return }

            let contentH = view.bounds.height
            guard contentH > 200 else { return }
            let chromeH = max(0, window.frame.height - (window.contentView?.bounds.height ?? window.frame.height))
            let desiredWinH = contentH + chromeH
            let desiredOriginY = targetTop - desiredWinH

            if abs(window.frame.height - desiredWinH) > 1.0 || abs(window.frame.origin.y - desiredOriginY) > 0.5 {
                var newFrame = window.frame
                newFrame.size.height = desiredWinH
                newFrame.origin.y = desiredOriginY
                window.setFrame(newFrame, display: true)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            guard let view, let window = view.window else { return }
            context.coordinator.syncWindowFrame(from: view)
            if context.coordinator.observers.isEmpty {
                let nc = NotificationCenter.default
                let resizeObs = nc.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak view] _ in
                    guard let view else { return }
                    context.coordinator.syncWindowFrame(from: view)
                }
                let moveObs = nc.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak view] _ in
                    guard let view else { return }
                    context.coordinator.syncWindowFrame(from: view)
                }
                context.coordinator.observers = [resizeObs, moveObs]
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView else { return }
            context.coordinator.syncWindowFrame(from: nsView)
        }
    }
}
