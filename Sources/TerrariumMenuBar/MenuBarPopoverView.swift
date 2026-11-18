import AppKit
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
        VStack(spacing: 0) {
            // 顶部标题与 Tab 栏（连击标题 5 次解锁会话级管理员模式）
            HStack {
                HStack(spacing: 6) {
                    Text("PIXEL TERRARIUM")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(textMain)
                        .onTapGesture {
                            state.registerSecretTitleTap()
                        }
                    if state.isAdminMode {
                        Text("[ADMIN]")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(adminAmber.opacity(0.22))
                            .foregroundColor(adminAmber)
                            .overlay(Rectangle().stroke(adminAmber.opacity(0.6), lineWidth: 1))
                    }
                    Button("") {
                        state.toggleAdminMode()
                    }
                    .keyboardShortcut("d", modifiers: [.command, .option])
                    .frame(width: 0, height: 0)
                    .opacity(0)
                }

                Spacer()

                HStack(spacing: 4) {
                    ForEach(PopoverTab.allCases, id: \.self) { tab in
                        Button {
                            state.currentTab = tab
                        } label: {
                            Text(tab == .codex ? "图鉴(\(state.unlockedCodexCount)/\(state.codexEntries.count))" : tab.rawValue)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 9)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(bgHeader)
            .overlay(Rectangle().frame(height: 2).foregroundColor(borderCol), alignment: .bottom)

            // 主内容区
            Group {
                switch state.currentTab {
                case .terrarium:
                    terrariumTabContent
                case .decor:
                    decorTabContent
                case .critters:
                    crittersTabContent
                case .codex:
                    codexTabContent
                }
            }
            .padding(12)

            // 底部状态栏
            HStack {
                Text(state.statusText)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(textMuted)
                    .lineLimit(1)
                Spacer()
                Text(state.isSleeping ? "休眠" : "~\(state.nextEventMinutesRemaining)m")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(textMuted)
                Text("· 点数:\(state.ecoPoints)")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(textMain)
                Button("退出") {
                    state.flushSave()
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(textMuted)
                .padding(.leading, 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bgHeader)
            .overlay(Rectangle().frame(height: 1.5).foregroundColor(borderCol), alignment: .top)
        }
        .frame(width: 472)
        .background(bgMain)
    }

    private var biomeSwitcherBar: some View {
        VStack(spacing: 6) {
            // 顶部管理条 + 已购缸体直接按键切换区（有多少个显示多少个，绝不展示未买空位）
            HStack(spacing: 6) {
                Text("我的生态缸 (\(state.containers.count)/\(TerrariumConfig.maxTankSlots))")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(textMuted)

                Spacer()

                Button(state.isShowingBuyTankSheet ? "收起商店" : "+ 购置新缸") {
                    state.isShowingBuyTankSheet.toggle()
                    state.isConfirmingDeleteTank = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(state.isShowingBuyTankSheet ? adminAmber : accentGreen)
                .foregroundColor(state.isShowingBuyTankSheet ? .black : .white)
                .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))

                if state.containers.count > 1 {
                    Button("拆缸") {
                        state.isConfirmingDeleteTank.toggle()
                        state.isShowingBuyTankSheet = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(state.isConfirmingDeleteTank ? Color.red.opacity(0.75) : bgCard)
                    .foregroundColor(state.isConfirmingDeleteTank ? .white : Color(red: 0.96, green: 0.56, blue: 0.52))
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))
                    .help("拆除当前生态缸并退回点数")
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 98, maximum: 150), spacing: 5)],
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
                            Text(container.customName)
                                .font(.system(size: 10.5, weight: isSelected ? .bold : .medium, design: .monospaced))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text("\(container.instance.temperature)°")
                                .font(.system(size: 9.5, design: .monospaced))
                                .opacity(0.85)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? accentGreen : bgCard)
                        .foregroundColor(isSelected ? .white : textMain)
                        .overlay(
                            Rectangle().stroke(isSelected ? adminAmber : borderCol, lineWidth: isSelected ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if state.isConfirmingDeleteTank && state.containers.count > 1 {
                HStack(spacing: 6) {
                    Text("确认拆除「\(state.activeContainerName)」并退回 +\(state.activeContainerRefundEstimate) 点？")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(red: 0.99, green: 0.80, blue: 0.76))
                    Spacer()
                    Button("确认退点") {
                        state.deleteActiveContainer()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.8))
                    .foregroundColor(.white)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                    Button("取消") {
                        state.isConfirmingDeleteTank = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
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
                    Text("选择生态类型购置新缸体（各缸独立挂机，上限 \(TerrariumConfig.maxTankSlots) 口）：")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(textMuted)
                    HStack(spacing: 5) {
                        ForEach(TerrariumBiome.allCases) { biome in
                            let cost = TerrariumConfig.tankPurchaseCost(for: biome, existingTankCount: state.containers.count)
                            let canBuy = biome.isPlayableInCurrentWave
                                && state.containers.count < TerrariumConfig.maxTankSlots
                                && state.ecoPoints >= cost
                            Button {
                                state.purchaseNewTank(biome: biome)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(biome.iconEmoji)
                                    Text(biome.rawValue.replacingOccurrences(of: "缸", with: ""))
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    Text(biome.isPlayableInCurrentWave ? "\(cost)点" : "下轮上线")
                                        .font(.system(size: 9, design: .monospaced))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(canBuy ? adminAmber : bgCard)
                                .foregroundColor(canBuy ? .black : textMuted.opacity(0.65))
                                .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(!canBuy)
                        }
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
                    Text("🌱 \(TerrariumState.displayName(forPlantSpecies: selPlant.speciesID)) · \(TerrariumState.stageLabel(for: selPlant.stage))")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(textMain)
                    Spacer()
                    Button(state.isMovingPlant ? "点沙盘空位..." : "移栽") {
                        if state.isMovingPlant {
                            state.isMovingPlant = false
                        } else {
                            state.beginMoveSelectedPlant()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(state.isMovingPlant ? adminAmber : accentGreen)
                    .foregroundColor(state.isMovingPlant ? .black : .white)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                    Button("修剪 +1点") {
                        state.pruneSelectedPlant()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
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
            } else if let selDecor = state.selectedDecorItem {
                let isMovingThis = (state.movingDecorID == selDecor.id)
                let dims = TerrariumConfig.decorDimensions(for: selDecor.id)
                HStack(spacing: 6) {
                    Text("🪵 \(selDecor.name) (\(dims.cols)×\(dims.rows))")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(textMain)
                    Spacer()
                    Button(isMovingThis ? "点击沙盘绿格..." : "移动位置") {
                        if isMovingThis {
                            state.movingDecorID = nil
                        } else {
                            state.beginMoveDecor(selDecor.id)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isMovingThis ? adminAmber : accentGreen)
                    .foregroundColor(isMovingThis ? .black : .white)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                    Button("收起") {
                        state.handleDecorAction(id: selDecor.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                HStack {
                    Text("⚡ \(eventMsg)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Color(red: 0.99, green: 0.90, blue: 0.54))
                        .lineLimit(2)
                    Spacer()
                    Button("已知晓") {
                        state.dismissEvent()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
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
            HStack(spacing: 8) {
                VStack(spacing: 3) {
                    HStack {
                        Text(state.currentBiome == .aquatic ? "水温" : "温度").foregroundColor(textMuted)
                        Spacer()
                        Text("\(state.temperature)°C").bold().foregroundColor(textMain)
                    }
                    HStack(spacing: 4) {
                        let tempSubtitle = (state.localOutdoorTempC != nil) ? "\(state.tempHint)·外\(state.localOutdoorTempC!)°" : state.tempHint
                        Text(tempSubtitle)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(textMuted)
                            .help(state.localOutdoorTempC != nil ? "已联动\(state.localCityName ?? "本地")实时气温 \(state.localOutdoorTempC!)°C" : "正在同步本地实时气温")
                        Spacer()
                        Button(state.hasHeatLamp ? "☀️" : "☀️\(TerrariumConfig.heatLampCost)点") {
                            state.toggleThermalMode(.heating)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(state.thermalMode == .heating ? Color.orange : bgHeader)
                        .foregroundColor(state.thermalMode == .heating ? .black : (state.hasHeatLamp ? textMain : adminAmber))
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                        .help(state.hasHeatLamp ? "夹缸加热器 (+6°C 稳态升温)" : "消耗 \(TerrariumConfig.heatLampCost) 生态点购置并夹装加热灯/棒")

                        Button(state.hasCoolingFan ? "❄️" : "❄️\(TerrariumConfig.coolingFanCost)点") {
                            state.toggleThermalMode(.cooling)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(state.thermalMode == .cooling ? Color.cyan : bgHeader)
                        .foregroundColor(state.thermalMode == .cooling ? .black : (state.hasCoolingFan ? textMain : adminAmber))
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                        .help(state.hasCoolingFan ? "夹缸降温扇 (-4°C 稳态降温)" : "消耗 \(TerrariumConfig.coolingFanCost) 生态点购置并夹装降温扇")

                        if state.isAdminMode {
                            miniBtn("-", action: { state.adjustTemp(-1) })
                            miniBtn("+", action: { state.adjustTemp(1) })
                        }
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(7)
                .background(bgCard)
                .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))

                readOnlySensorBox(
                    label: state.currentBiome == .aquatic ? "溶氧" : "湿度",
                    value: "\(state.humidity)%",
                    hint: state.humHint,
                    allowAdminButtons: state.isAdminMode,
                    onMinus: { state.adjustHumidity(-5) },
                    onPlus: { state.adjustHumidity(5) }
                )
                VStack(spacing: 3) {
                    HStack {
                        Text(state.currentBiome == .aquatic ? "浮圈" : "食盆").foregroundColor(textMuted)
                        Spacer()
                        Text("\(state.foodBowlPortions)/\(TerrariumConfig.maxFoodPortions)").bold().foregroundColor(textMain)
                    }
                    HStack {
                        Text("住民:\(state.activeDisplayCritters.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(textMuted)
                        Spacer()
                        Text("植株:\(state.plants.count)/\(TerrariumConfig.maxPlantsCap)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(textMuted)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(7)
                .background(bgCard)
                .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))
            }

            // 4 个自然演进核心交互按钮
            HStack(spacing: 6) {
                pixelActionButton(icon: "icon_mist", title: state.currentBiome == .aquatic ? "换水打氧" : "喷水加湿") { state.mist() }
                pixelActionButton(icon: "icon_feed", title: state.currentBiome == .aquatic ? "投放鱼粮" : "食盆投喂") { state.feed() }
                pixelActionButton(icon: "icon_clean", title: state.currentBiome == .aquatic ? "擦净藻垢" : "清理擦雾") { state.clean() }
                pixelActionButton(
                    icon: "icon_sleep",
                    title: state.isSleeping ? "唤醒" : "休眠",
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
                                Text(atm.rawValue.prefix(2))
                                    .font(.system(size: 10, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(state.atmosphere == atm ? accentGreen : bgCard)
                                    .foregroundColor(state.atmosphere == atm ? .white : textMuted)
                                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        Button("-10点") { state.adjustEcoPointsDebug(-10) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(bgCard).foregroundColor(textMuted)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                        Button("+10点") { state.adjustEcoPointsDebug(10) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(bgCard).foregroundColor(adminAmber)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                        Button("+50点") { state.adjustEcoPointsDebug(50) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(bgCard).foregroundColor(adminAmber)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                    }
                    HStack(spacing: 4) {
                        Button("⚡ 事件") { state.simulateWeatherEvent() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(bgCard).foregroundColor(adminAmber)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                        Button("🌱 催生") { state.triggerPlantPulseDebug() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(bgCard).foregroundColor(textMain)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                        Button(state.showIsoGridDebug ? "隐藏网格" : "网格") {
                            state.showIsoGridDebug.toggle()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(state.showIsoGridDebug ? accentGreen : bgCard)
                        .foregroundColor(textMain)
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))

                        Spacer()
                        Button("锁定") { state.setAdminMode(false) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(bgCard).foregroundColor(textMuted)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
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
            HStack {
                Text(label).foregroundColor(textMuted)
                Spacer()
                Text(value).bold().foregroundColor(textMain)
            }
            HStack {
                Text(hint).font(.system(size: 10, design: .monospaced)).foregroundColor(textMuted)
                Spacer()
                if allowAdminButtons {
                    HStack(spacing: 4) {
                        miniBtn("-", action: onMinus)
                        miniBtn("+", action: onPlus)
                    }
                }
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(7)
        .background(bgCard)
        .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))
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
            HStack(spacing: 5) {
                PixelAssetLoader.swiftUIImage(named: icon)
                    .frame(width: 14, height: 14)
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
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
                    Text("\(state.currentBiome.rawValue)专属生态摆件")
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(textMain)
                    Spacer()
                    Button("重置存档(新开局)") {
                        state.resetSaveData()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(textMuted.opacity(0.85))
                }

                ForEach(state.decorItems) { item in
                    let frameSize: CGSize? = {
                        switch item.id {
                        case "shallow_pool": return CGSize(width: 40, height: 22)
                        case "sand_pebbles": return CGSize(width: 22, height: 12)
                        case "rainforest_waterfall": return CGSize(width: 40, height: 30)
                        case "aquatic_bubble_rock": return CGSize(width: 38, height: 30)
                        default: return nil
                        }
                    }()
                    HStack(spacing: 10) {
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
                            Text(item.nicheDescription)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(textMuted)
                                .lineLimit(2)
                        }
                        Spacer()
                        if item.unlocked {
                            if item.enabled {
                                Button("摆位") {
                                    state.currentTab = .terrarium
                                    state.beginMoveDecor(item.id)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10.5, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(bgCard)
                                .foregroundColor(adminAmber)
                                .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                            }
                            Button(item.enabled ? "已摆放" : "已收起") {
                                state.handleDecorAction(id: item.id)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(item.enabled ? accentGreen : bgCard)
                            .foregroundColor(item.enabled ? .white : textMuted)
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                        } else {
                            let canAfford = state.ecoPoints >= item.cost
                            Button("解锁 (\(item.cost)点)") {
                                state.handleDecorAction(id: item.id)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canAfford)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(canAfford ? adminAmber : bgCard)
                            .foregroundColor(canAfford ? .black : textMuted.opacity(0.5))
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                        }
                    }
                    .padding(8)
                    .background(bgHeader)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))
                }
            }
        }
        .frame(height: 446)
    }

    private var crittersTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(state.currentBiome.rawValue)生物领养与轮换")
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(textMain)
                    Spacer()
                    Text(state.activeFoodChainGroup?.rawValue ?? "空缸待入驻")
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(bgCard)
                        .foregroundColor(adminAmber)
                        .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                }

                let chainRuleText: String = {
                    switch state.currentBiome {
                    case .aquatic:
                        return "⚖️ 食物链规则：半月斗鱼领地性强需单缸独养；蓝螯虾不可与鱼虾混养，切换入缸时冲突物种会自动安全存仓。"
                    case .rainforest:
                        return "⚖️ 食物链规则：变色龙不可与雨林拟态虫群混养；切换入缸时冲突物种会自动安全存仓。"
                    default:
                        return "⚖️ 食物链规则：捕食者（树蛙 / 沙守宫）不可与小型昆虫/蜗牛同放一缸；切换入缸时冲突物种会自动安全存仓。"
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

                    HStack(spacing: 10) {
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
                            HStack(spacing: 5) {
                                Text(spec.name)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(textMain)
                                if let owned {
                                    let stage = TerrariumConfig.affinityStage(for: owned.affinity)
                                    Text("♥\(owned.affinity)/\(TerrariumConfig.maxAffinity) · \(stage.title)")
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundColor(stage == .soulmate ? adminAmber : Color(red: 0.99, green: 0.68, blue: 0.74))
                                }
                            }
                            if let owned {
                                let stage = TerrariumConfig.affinityStage(for: owned.affinity)
                                Text("性格：\(owned.personality) · \(TerrariumConfig.perkDescription(for: owned.personality, stage: stage))")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundColor(Color(red: 0.99, green: 0.80, blue: 0.84))
                                    .lineLimit(1)
                            }
                            Text("条件：\(spec.unlockConditionText) · \(elig.eligible ? "已达标" : elig.missingReason)")
                                .font(.system(size: 9.8, design: .monospaced))
                                .foregroundColor(elig.eligible ? Color(red: 0.65, green: 0.92, blue: 0.68) : textMuted)
                                .lineLimit(1)
                            Text(spec.foodChainNote)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(conflictsActive ? adminAmber : textMuted.opacity(0.85))
                                .lineLimit(1)
                        }

                        Spacer()

                        if owned != nil {
                            Button(isInTank ? "在缸中 · 收起" : (conflictsActive ? "换入(存仓旧群)" : "放入生态箱")) {
                                state.critterPurchaseAndToggle(spec.kind)
                            }
                            .buttonStyle(.plain)
                            .disabled(!isInTank && !elig.eligible)
                            .font(.system(size: 10.5, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isInTank ? accentGreen : (elig.eligible ? bgCard : bgCard.opacity(0.5)))
                            .foregroundColor(isInTank ? .white : (elig.eligible ? textMain : textMuted.opacity(0.5)))
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                        } else {
                            Button("领养 (\(spec.cost)点)") {
                                state.critterPurchaseAndToggle(spec.kind)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canBuy)
                            .font(.system(size: 10.5, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(canBuy ? adminAmber : bgCard)
                            .foregroundColor(canBuy ? .black : textMuted.opacity(0.5))
                            .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                        }
                    }
                    .padding(8)
                    .background(bgHeader)
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1.5))
                }
            }
        }
        .frame(height: 446)
    }

    private var codexTabContent: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(state.codexEntries) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("\(entry.unlocked ? "✅" : "🔒") \(entry.name) · \(entry.category)")
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundColor(textMain)
                            Spacer()
                            let biomeLabel: String = {
                                switch entry.biome {
                                case .meadow: return "苔原"
                                case .sand: return "沙地"
                                case .rainforest: return "雨林"
                                case .aquatic: return "水域"
                                }
                            }()
                            Text(biomeLabel)
                                .font(.system(size: 9.5, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(bgCard)
                                .foregroundColor(textMuted)
                        }
                        Text("条件：\(entry.condition)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(textMuted)
                        Text(entry.unlocked ? entry.desc : "满足生态位摆件、特殊植物与气候条件后解锁。")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(textMain.opacity(0.85))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(bgHeader.opacity(entry.unlocked ? 1 : 0.6))
                    .overlay(Rectangle().stroke(borderCol, lineWidth: 1))
                }
            }
        }
        .frame(height: 446)
    }
}
