import SwiftUI
import TerrariumCore

private struct RenderSortable {
    let sortDepth: Double
    let draw: (inout GraphicsContext) -> Void
}

/// 224x176 逻辑像素 45° 等距箱庭画布，2x 整数放大至 448x352 pt，7-Pass 管线 + 严格 Y-Sort 前后遮挡
struct PixelStageView: View {
    @ObservedObject var state: TerrariumState
    @StateObject private var animator = StageAnimator()

    var scale: CGFloat = 2.0
    var isSnapshot: Bool = false

    var body: some View {
        Canvas { context, size in
            func drawFullImage(_ name: String) {
                guard let nsImg = PixelAssetLoader.nsImage(named: name) else { return }
                let img = Image(nsImage: nsImg).interpolation(.none)
                context.draw(img, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            }

            func drawSheetFrame(
                in ctx: inout GraphicsContext,
                sheet: String,
                frameIndex: Int,
                frameSize: CGSize,
                screenPos: CGPoint,
                anchor: CGPoint,
                flippedX: Bool = false,
                uniformScale: CGFloat = 1.0
            ) {
                guard let nsImg = PixelAssetLoader.spriteSheetFrame(named: sheet, frameIndex: frameIndex, frameSize: frameSize) else { return }
                let img = Image(nsImage: nsImg).interpolation(.none)
                let drawW = frameSize.width * scale * uniformScale
                let drawH = frameSize.height * scale * uniformScale
                let originX = floor(screenPos.x - anchor.x * uniformScale) * scale
                let originY = floor(screenPos.y - anchor.y * uniformScale) * scale
                let rect = CGRect(x: originX, y: originY, width: drawW, height: drawH)

                if flippedX {
                    var flipped = ctx
                    flipped.translateBy(x: rect.midX, y: rect.midY)
                    flipped.scaleBy(x: -1, y: 1)
                    flipped.translateBy(x: -rect.midX, y: -rect.midY)
                    flipped.draw(img, in: rect)
                } else {
                    ctx.draw(img, in: rect)
                }
            }

            func drawIsoShadow(center: CGPoint, width: Double, height: Double, gz: Double = 0.0) {
                let shrink = max(0.45, 1.0 - gz * 0.03)
                let alpha = max(0.14, 0.34 - gz * 0.015)
                let w = width * shrink * scale
                let h = height * shrink * scale
                let rect = CGRect(
                    x: floor(center.x) * scale - w / 2.0,
                    y: floor(center.y) * scale - h / 2.0,
                    width: w,
                    height: h
                )
                context.fill(Path(ellipseIn: rect), with: .color(Color.black.opacity(alpha)))
            }

            // ==================== Pass 0: 缸外环境氛围 ====================
            drawFullImage(state.atmosphere.backgroundAssetName)

            // ==================== Pass 1: 后壁玻璃框体 + Pass 1b 后壁内贴挂温控硬件层 ====================
            drawFullImage("tank_back_glass")

            // 将加热棒/晒背夹灯/静音降温扇实体本体绘于后壁玻璃之前方、游鱼与水体图层之后方，彻底消除遮挡游鱼与水草问题
            if state.hasHeatLamp {
                let isHeatingOn = (!state.isSleeping && state.thermalMode == .heating)
                if state.currentBiome == .aquatic || state.currentBiome == .reef {
                    drawSheetFrame(
                        in: &context,
                        sheet: "equip_aquarium_heater",
                        frameIndex: isHeatingOn ? 1 : 0,
                        frameSize: CGSize(width: 12, height: 28),
                        screenPos: CGPoint(x: 152, y: 58),
                        anchor: CGPoint(x: 6, y: 14)
                    )
                } else {
                    drawSheetFrame(
                        in: &context,
                        sheet: "equip_heat_lamp",
                        frameIndex: isHeatingOn ? 1 : 0,
                        frameSize: CGSize(width: 24, height: 24),
                        screenPos: CGPoint(x: 174, y: 42),
                        anchor: CGPoint(x: 20, y: 18)
                    )
                }
            }
            if state.hasCoolingFan {
                let isCoolOn = (!state.isSleeping && state.thermalMode == .cooling)
                let fanFrame = isCoolOn ? (1 + (animator.tick / 2) % 2) : 0
                drawSheetFrame(
                    in: &context,
                    sheet: "equip_cooling_fan",
                    frameIndex: fanFrame,
                    frameSize: CGSize(width: 22, height: 20),
                    screenPos: CGPoint(x: 50, y: 42),
                    anchor: CGPoint(x: 3, y: 15)
                )
            }

            // ==================== Pass 2: 2:1 等距地面与三层土剖面 ====================
            let isWetTerrain = state.humidity >= 50
            let terrainAsset: String
            switch (state.currentBiome, isWetTerrain) {
            case (.meadow, true): terrainAsset = "terrain_meadow_wet"
            case (.meadow, false): terrainAsset = "terrain_meadow_dry"
            case (.sand, true): terrainAsset = "terrain_sand_wet"
            case (.sand, false): terrainAsset = "terrain_sand_dry"
            case (.rainforest, true): terrainAsset = "terrain_rainforest_wet"
            case (.rainforest, false): terrainAsset = "terrain_rainforest_dry"
            case (.aquatic, _): terrainAsset = (state.humidity >= 55) ? "terrain_aquatic_clean" : "terrain_aquatic_murky"
            case (.reef, _): terrainAsset = (state.humidity >= 55) ? "terrain_reef_clean" : "terrain_reef_murky"
            }
            drawFullImage(terrainAsset)

            // 植物 / 摆件选中高亮与自由摆放空地引导
            if let selPlant = state.selectedPlant {
                let isSurfacePlant = (TerrariumConfig.plantSurfaceGZ(for: selPlant) > 0)
                if state.isMovingPlant && !isSurfacePlant {
                    let others = state.plants.filter { $0.id != selPlant.id }
                    let occupied = GridPathfinder.buildNonPlantableSet(
                        enabledDecorIDs: state.enabledDecorIDs,
                        plants: others,
                        decorOrigins: state.decorOrigins,
                        biome: state.currentBiome
                    )
                    for col in 0..<TerrariumConfig.gridCols {
                        for row in 0..<TerrariumConfig.gridRows {
                            let coord = GridCoord(col: col, row: row)
                            let p0 = TerrariumConfig.isoToScreen(gx: Double(col), gy: Double(row))
                            let p1 = TerrariumConfig.isoToScreen(gx: Double(col + 1), gy: Double(row))
                            let p2 = TerrariumConfig.isoToScreen(gx: Double(col + 1), gy: Double(row + 1))
                            let p3 = TerrariumConfig.isoToScreen(gx: Double(col), gy: Double(row + 1))
                            var tilePath = Path()
                            tilePath.move(to: CGPoint(x: p0.x * scale, y: p0.y * scale))
                            tilePath.addLine(to: CGPoint(x: p1.x * scale, y: p1.y * scale))
                            tilePath.addLine(to: CGPoint(x: p2.x * scale, y: p2.y * scale))
                            tilePath.addLine(to: CGPoint(x: p3.x * scale, y: p3.y * scale))
                            tilePath.closeSubpath()
                            let isBad = occupied.contains(coord)
                            context.fill(tilePath, with: .color(isBad ? Color.red.opacity(0.14) : Color.green.opacity(0.16)))
                            context.stroke(tilePath, with: .color(isBad ? Color.red.opacity(0.32) : Color.green.opacity(0.42)), lineWidth: 1)
                        }
                    }
                } else {
                    let c = selPlant.coord
                    let p0 = TerrariumConfig.isoToScreen(gx: Double(c.col), gy: Double(c.row))
                    let p1 = TerrariumConfig.isoToScreen(gx: Double(c.col + 1), gy: Double(c.row))
                    let p2 = TerrariumConfig.isoToScreen(gx: Double(c.col + 1), gy: Double(c.row + 1))
                    let p3 = TerrariumConfig.isoToScreen(gx: Double(c.col), gy: Double(c.row + 1))
                    var tilePath = Path()
                    tilePath.move(to: CGPoint(x: p0.x * scale, y: p0.y * scale))
                    tilePath.addLine(to: CGPoint(x: p1.x * scale, y: p1.y * scale))
                    tilePath.addLine(to: CGPoint(x: p2.x * scale, y: p2.y * scale))
                    tilePath.addLine(to: CGPoint(x: p3.x * scale, y: p3.y * scale))
                    tilePath.closeSubpath()
                    let fillAlpha = isSurfacePlant ? 0.10 : 0.22
                    let strokeAlpha = isSurfacePlant ? 0.35 : 1.0
                    context.fill(tilePath, with: .color(Color(red: 0.98, green: 0.75, blue: 0.14).opacity(fillAlpha)))
                    context.stroke(tilePath, with: .color(Color(red: 0.99, green: 0.90, blue: 0.54).opacity(strokeAlpha)), lineWidth: 1.5)
                }
            } else if let moveDecorID = state.movingDecorID {
                for col in 0..<TerrariumConfig.gridCols {
                    for row in 0..<TerrariumConfig.gridRows {
                        let origin = GridCoord(col: col, row: row)
                        let p0 = TerrariumConfig.isoToScreen(gx: Double(col), gy: Double(row))
                        let p1 = TerrariumConfig.isoToScreen(gx: Double(col + 1), gy: Double(row))
                        let p2 = TerrariumConfig.isoToScreen(gx: Double(col + 1), gy: Double(row + 1))
                        let p3 = TerrariumConfig.isoToScreen(gx: Double(col), gy: Double(row + 1))
                        var tilePath = Path()
                        tilePath.move(to: CGPoint(x: p0.x * scale, y: p0.y * scale))
                        tilePath.addLine(to: CGPoint(x: p1.x * scale, y: p1.y * scale))
                        tilePath.addLine(to: CGPoint(x: p2.x * scale, y: p2.y * scale))
                        tilePath.addLine(to: CGPoint(x: p3.x * scale, y: p3.y * scale))
                        tilePath.closeSubpath()
                        let isValid = GridPathfinder.canPlaceDecor(
                            id: moveDecorID,
                            at: origin,
                            enabledDecorIDs: state.enabledDecorIDs,
                            decorOrigins: state.decorOrigins,
                            plants: state.plants,
                            biome: state.currentBiome
                        )
                        context.fill(tilePath, with: .color(isValid ? Color.green.opacity(0.18) : Color.red.opacity(0.10)))
                        context.stroke(tilePath, with: .color(isValid ? Color.green.opacity(0.45) : Color.red.opacity(0.26)), lineWidth: 1)
                    }
                }
            } else if let selDecor = state.selectedDecorItem {
                for c in TerrariumConfig.footprint(for: selDecor.id, decorOrigins: state.decorOrigins) {
                    let p0 = TerrariumConfig.isoToScreen(gx: Double(c.col), gy: Double(c.row))
                    let p1 = TerrariumConfig.isoToScreen(gx: Double(c.col + 1), gy: Double(c.row))
                    let p2 = TerrariumConfig.isoToScreen(gx: Double(c.col + 1), gy: Double(c.row + 1))
                    let p3 = TerrariumConfig.isoToScreen(gx: Double(c.col), gy: Double(c.row + 1))
                    var tilePath = Path()
                    tilePath.move(to: CGPoint(x: p0.x * scale, y: p0.y * scale))
                    tilePath.addLine(to: CGPoint(x: p1.x * scale, y: p1.y * scale))
                    tilePath.addLine(to: CGPoint(x: p2.x * scale, y: p2.y * scale))
                    tilePath.addLine(to: CGPoint(x: p3.x * scale, y: p3.y * scale))
                    tilePath.closeSubpath()
                    context.fill(tilePath, with: .color(Color(red: 0.98, green: 0.75, blue: 0.14).opacity(0.22)))
                    context.stroke(tilePath, with: .color(Color(red: 0.99, green: 0.90, blue: 0.54)), lineWidth: 1.5)
                }
            }

            // 管理员模式网格辅助线
            if state.isAdminMode && state.showIsoGridDebug {
                let blocked = GridPathfinder.buildBlockedSet(
                    enabledDecorIDs: state.enabledDecorIDs,
                    plants: state.plants,
                    decorOrigins: state.decorOrigins,
                    biome: state.currentBiome
                )
                for col in 0..<TerrariumConfig.gridCols {
                    for row in 0..<TerrariumConfig.gridRows {
                        let p0 = TerrariumConfig.isoToScreen(gx: Double(col), gy: Double(row))
                        let p1 = TerrariumConfig.isoToScreen(gx: Double(col + 1), gy: Double(row))
                        let p2 = TerrariumConfig.isoToScreen(gx: Double(col + 1), gy: Double(row + 1))
                        let p3 = TerrariumConfig.isoToScreen(gx: Double(col), gy: Double(row + 1))
                        var tilePath = Path()
                        tilePath.move(to: CGPoint(x: p0.x * scale, y: p0.y * scale))
                        tilePath.addLine(to: CGPoint(x: p1.x * scale, y: p1.y * scale))
                        tilePath.addLine(to: CGPoint(x: p2.x * scale, y: p2.y * scale))
                        tilePath.addLine(to: CGPoint(x: p3.x * scale, y: p3.y * scale))
                        tilePath.closeSubpath()
                        let isBlocked = blocked.contains(GridCoord(col: col, row: row))
                        context.stroke(tilePath, with: .color(isBlocked ? Color.red.opacity(0.45) : Color.white.opacity(0.20)), lineWidth: 1)
                    }
                }
            }

            // ==================== Pass 2.5: 贴地水洼、卵石滩与汀步石图层（避免动物沉入底层） ====================
            for decor in state.decorItems where decor.enabled && (decor.id == "shallow_pool" || decor.id == "sand_pebbles" || decor.id == "meadow_stepping_stones") {
                let gp = TerrariumConfig.anchorGridPos(for: decor.id, decorOrigins: state.decorOrigins)
                let screenPos = TerrariumConfig.isoToScreen(gx: gp.gx, gy: gp.gy)
                if decor.id == "shallow_pool" {
                    let poolFrame: Int
                    if state.humidity < 42 {
                        poolFrame = 2
                    } else {
                        poolFrame = state.isSleeping ? 0 : ((animator.tick / 7) % 2)
                    }
                    drawSheetFrame(in: &context, sheet: "env_shallow_pool", frameIndex: poolFrame, frameSize: CGSize(width: 44, height: 24), screenPos: screenPos, anchor: CGPoint(x: 22, y: 13))
                } else if decor.id == "sand_pebbles" {
                    drawSheetFrame(in: &context, sheet: "env_pebbles", frameIndex: 1, frameSize: CGSize(width: 28, height: 16), screenPos: screenPos, anchor: CGPoint(x: 14, y: 9))
                } else {
                    drawSheetFrame(in: &context, sheet: "env_meadow_stepping_stones", frameIndex: 0, frameSize: CGSize(width: 28, height: 16), screenPos: screenPos, anchor: CGPoint(x: 14, y: 9))
                }
            }

            // ==================== Pass 3: 统一 2:1 等距接触阴影（严格裁剪于缸底菱形内部，绝不穿透缸壁） ====================
            let f0 = TerrariumConfig.isoToScreen(gx: 0, gy: 0)
            let f1 = TerrariumConfig.isoToScreen(gx: Double(TerrariumConfig.gridCols), gy: 0)
            let f2 = TerrariumConfig.isoToScreen(gx: Double(TerrariumConfig.gridCols), gy: Double(TerrariumConfig.gridRows))
            let f3 = TerrariumConfig.isoToScreen(gx: 0, gy: Double(TerrariumConfig.gridRows))
            var floorClipPath = Path()
            floorClipPath.move(to: CGPoint(x: f0.x * scale, y: f0.y * scale))
            floorClipPath.addLine(to: CGPoint(x: f1.x * scale, y: f1.y * scale))
            floorClipPath.addLine(to: CGPoint(x: f2.x * scale, y: f2.y * scale))
            floorClipPath.addLine(to: CGPoint(x: f3.x * scale, y: f3.y * scale))
            floorClipPath.closeSubpath()

            context.drawLayer { shadowCtx in
                shadowCtx.clip(to: floorClipPath)
                func drawClippedShadow(center: CGPoint, width: Double, height: Double, gz: Double = 0.0) {
                    let liftFade = max(0.28, 1.0 - gz * 0.03)
                    let shrink = max(0.55, 1.0 - gz * 0.015)
                    let w = width * shrink
                    let h = height * shrink
                    let rect = CGRect(
                        x: (center.x - w * 0.5) * scale,
                        y: (center.y - h * 0.5) * scale,
                        width: w * scale,
                        height: h * scale
                    )
                    shadowCtx.fill(Path(ellipseIn: rect), with: .color(Color.black.opacity(0.26 * liftFade)))
                }

                for decor in state.decorItems where decor.enabled && decor.id != "shallow_pool" && decor.id != "sand_pebbles" && decor.id != "meadow_stepping_stones" && decor.id != "reef_sand_shells" {
                    let gp = TerrariumConfig.anchorGridPos(for: decor.id, decorOrigins: state.decorOrigins)
                    let pt = TerrariumConfig.isoToScreen(gx: gp.gx, gy: gp.gy)
                    let dims: (Double, Double) = {
                        switch decor.id {
                        case "sand_rock": return (42, 19)
                        case "driftwood", "sand_wood", "rainforest_vine", "aquatic_driftwood", "reef_live_rock": return (44, 18)
                        case "rainforest_waterfall", "aquatic_bubble_rock", "reef_wavemaker": return (38, 16)
                        case "boulder", "rainforest_bark", "aquatic_castle", "reef_coral_cave": return (28, 13)
                        case "sand_rib_arch", "rainforest_slate_ledge", "aquatic_seiryu_stone", "reef_giant_clam": return (24, 11)
                        default: return (18, 8)
                        }
                    }()
                    drawClippedShadow(center: pt, width: dims.0, height: dims.1)
                }

                let bowlPt = TerrariumConfig.isoToScreen(
                    gx: Double(TerrariumConfig.foodBowlCoord.col) + 0.5,
                    gy: Double(TerrariumConfig.foodBowlCoord.row) + 0.5
                )
                if state.currentBiome != .aquatic && state.currentBiome != .reef {
                    drawClippedShadow(center: bowlPt, width: 16, height: 7)
                }

                for plant in state.plants where plant.speciesID != "moss" && plant.speciesID != "lotus" {
                    let pt = TerrariumConfig.isoToScreen(gx: Double(plant.coord.col) + 0.5, gy: Double(plant.coord.row) + 0.5)
                    if plant.stage == .sprout {
                        drawClippedShadow(center: pt, width: 8, height: 4)
                    } else {
                        let dims: (Double, Double) = {
                            switch plant.speciesID {
                            case "fern", "monstera": return (20, 8)
                            case "glow_shroom", "red_shroom", "bromeliad", "orchid", "anubias": return (14, 6)
                            default: return (12, 6)
                            }
                        }()
                        drawClippedShadow(center: pt, width: dims.0, height: dims.1)
                    }
                }

                for c in animator.critterRuntimes {
                    let pt = TerrariumConfig.isoToScreen(gx: c.gx, gy: c.gy, gz: 0)
                    let dims: (Double, Double) = (c.kind == .treeFrog || c.kind == .sandGecko || c.kind == .chameleon || c.kind == .dartFrog || c.kind == .sandScorpion) ? (15, 7) : (11, 5)
                    drawClippedShadow(center: pt, width: dims.0, height: dims.1, gz: c.gz)
                }
            }

            // 睡莲位于水面 (gz = 38)，独立绘制于水面高度投影
            for plant in state.plants where plant.speciesID == "lotus" {
                let pt = TerrariumConfig.isoToScreen(gx: Double(plant.coord.col) + 0.5, gy: Double(plant.coord.row) + 0.5)
                let w: Double = (plant.stage == .sprout) ? 10 : 15
                let h: Double = (plant.stage == .sprout) ? 5 : 7
                drawIsoShadow(center: pt, width: w, height: h, gz: TerrariumConfig.waterSurfaceGZ)
            }

            let bowlPos = TerrariumConfig.isoToScreen(
                gx: Double(TerrariumConfig.foodBowlCoord.col) + 0.5,
                gy: Double(TerrariumConfig.foodBowlCoord.row) + 0.5
            )

            // ==================== Pass 4: Y-Sort 严格前后遮挡绘制层 ====================
            var sortables: [RenderSortable] = []

            func appendSlicedDecor(
                sheet: String,
                frameIndex: Int = 0,
                frameSize: CGSize,
                anchor: CGPoint,
                screenPos: CGPoint,
                colStart: Int,
                colEnd: Int,
                baseGY: Double
            ) {
                for col in colStart...colEnd {
                    let depth = (Double(col) + 0.5 + baseGY) * 1000.0 + 1.0
                    let gLeft = (col == colStart) ? -10.0 : (Double(col) - 0.02)
                    let gRight = (col == colEnd) ? 25.0 : (Double(col + 1) + 0.02)
                    sortables.append(RenderSortable(sortDepth: depth) { ctx in
                        let p0 = TerrariumConfig.isoToScreen(gx: gLeft, gy: -10.0)
                        let p1 = TerrariumConfig.isoToScreen(gx: gRight, gy: -10.0)
                        let p2 = TerrariumConfig.isoToScreen(gx: gRight, gy: 25.0)
                        let p3 = TerrariumConfig.isoToScreen(gx: gLeft, gy: 25.0)
                        var clipPath = Path()
                        clipPath.move(to: CGPoint(x: p0.x * scale, y: p0.y * scale))
                        clipPath.addLine(to: CGPoint(x: p1.x * scale, y: p1.y * scale))
                        clipPath.addLine(to: CGPoint(x: p2.x * scale, y: p2.y * scale))
                        clipPath.addLine(to: CGPoint(x: p3.x * scale, y: p3.y * scale))
                        clipPath.closeSubpath()
                        var clipped = ctx
                        clipped.clip(to: clipPath)
                        drawSheetFrame(in: &clipped, sheet: sheet, frameIndex: frameIndex, frameSize: frameSize, screenPos: screenPos, anchor: anchor)
                    })
                }
            }

            // 4a. 立体摆件（跟随实际摆放原点动态按等距列切片排序，杜绝斜边穿插）
            for decor in state.decorItems where decor.enabled {
                let origin = TerrariumConfig.effectiveDecorOrigin(for: decor.id, decorOrigins: state.decorOrigins)
                let dims = TerrariumConfig.decorDimensions(for: decor.id)
                let gp = TerrariumConfig.anchorGridPos(for: decor.id, decorOrigins: state.decorOrigins)
                let screenPos = TerrariumConfig.isoToScreen(gx: gp.gx, gy: gp.gy)
                let colStart = origin.col
                let colEnd = origin.col + dims.cols - 1
                let baseGY = Double(origin.row + dims.rows) - 0.9

                switch decor.id {
                case "driftwood":
                    appendSlicedDecor(sheet: "env_driftwood", frameSize: CGSize(width: 56, height: 38), anchor: CGPoint(x: 28, y: 24), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "boulder":
                    appendSlicedDecor(sheet: "env_boulder", frameSize: CGSize(width: 40, height: 30), anchor: CGPoint(x: 20, y: 21), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "sand_rock":
                    appendSlicedDecor(sheet: "env_sand_rock", frameSize: CGSize(width: 50, height: 40), anchor: CGPoint(x: 25, y: 28), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "sand_wood":
                    appendSlicedDecor(sheet: "env_sand_wood", frameSize: CGSize(width: 56, height: 38), anchor: CGPoint(x: 28, y: 24), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "rainforest_vine":
                    appendSlicedDecor(sheet: "env_rainforest_vine", frameSize: CGSize(width: 56, height: 38), anchor: CGPoint(x: 28, y: 24), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "rainforest_waterfall":
                    let wfFrame = state.isSleeping ? 0 : ((animator.tick / 5) % 3)
                    appendSlicedDecor(sheet: "env_rainforest_waterfall", frameIndex: wfFrame, frameSize: CGSize(width: 48, height: 38), anchor: CGPoint(x: 24, y: 27), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "rainforest_bark":
                    appendSlicedDecor(sheet: "env_rainforest_bark", frameSize: CGSize(width: 40, height: 30), anchor: CGPoint(x: 20, y: 21), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "aquatic_bubble_rock":
                    let brFrame = state.isSleeping ? 0 : ((animator.tick / 5) % 3)
                    appendSlicedDecor(sheet: "env_aquatic_bubble_rock", frameIndex: brFrame, frameSize: CGSize(width: 44, height: 36), anchor: CGPoint(x: 22, y: 25), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "aquatic_driftwood":
                    appendSlicedDecor(sheet: "env_aquatic_driftwood", frameSize: CGSize(width: 56, height: 38), anchor: CGPoint(x: 28, y: 24), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "aquatic_castle":
                    appendSlicedDecor(sheet: "env_aquatic_castle", frameSize: CGSize(width: 42, height: 32), anchor: CGPoint(x: 21, y: 22), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "meadow_mushroom_log":
                    appendSlicedDecor(sheet: "env_meadow_mushroom_log", frameSize: CGSize(width: 22, height: 24), anchor: CGPoint(x: 11, y: 18), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "sand_cairn":
                    appendSlicedDecor(sheet: "env_sand_cairn", frameSize: CGSize(width: 22, height: 26), anchor: CGPoint(x: 11, y: 20), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "sand_rib_arch":
                    appendSlicedDecor(sheet: "env_sand_rib_arch", frameSize: CGSize(width: 30, height: 22), anchor: CGPoint(x: 15, y: 16), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "rainforest_bromeliad_stump":
                    appendSlicedDecor(sheet: "env_rainforest_bromeliad_stump", frameSize: CGSize(width: 24, height: 26), anchor: CGPoint(x: 12, y: 20), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "rainforest_slate_ledge":
                    appendSlicedDecor(sheet: "env_rainforest_slate_ledge", frameSize: CGSize(width: 30, height: 24), anchor: CGPoint(x: 15, y: 18), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "aquatic_seiryu_stone":
                    appendSlicedDecor(sheet: "env_aquatic_seiryu_stone", frameSize: CGSize(width: 30, height: 26), anchor: CGPoint(x: 15, y: 20), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "aquatic_bamboo_tube":
                    appendSlicedDecor(sheet: "env_aquatic_bamboo_tube", frameSize: CGSize(width: 32, height: 28), anchor: CGPoint(x: 16, y: 23), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "reef_live_rock":
                    appendSlicedDecor(sheet: "env_reef_live_rock", frameSize: CGSize(width: 56, height: 38), anchor: CGPoint(x: 28, y: 27), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "reef_wavemaker":
                    appendSlicedDecor(sheet: "env_reef_wavemaker", frameSize: CGSize(width: 40, height: 32), anchor: CGPoint(x: 20, y: 23), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "reef_coral_cave":
                    appendSlicedDecor(sheet: "env_reef_coral_cave", frameSize: CGSize(width: 44, height: 32), anchor: CGPoint(x: 22, y: 24), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "reef_giant_clam":
                    appendSlicedDecor(sheet: "env_reef_giant_clam", frameSize: CGSize(width: 32, height: 22), anchor: CGPoint(x: 16, y: 16), screenPos: screenPos, colStart: colStart, colEnd: colEnd, baseGY: baseGY)
                case "reef_sand_shells":
                    let sandPos = TerrariumConfig.isoToScreen(gx: gp.gx, gy: gp.gy)
                    let sandDepth = (gp.gx + gp.gy) * 1000.0 - 400.0
                    sortables.append(RenderSortable(sortDepth: sandDepth) { ctx in
                        drawSheetFrame(in: &ctx, sheet: "env_reef_sand_shells", frameIndex: 0, frameSize: CGSize(width: 28, height: 16), screenPos: sandPos, anchor: CGPoint(x: 14, y: 8))
                    })
                default:
                    break
                }
            }

            // 4b. 陆生固定食盆（恒定处于视觉最前沿净空区；碧波鱼缸与海缸改为水面悬浮喂食圈在 Pass 6b 绘制）
            if state.currentBiome != .aquatic && state.currentBiome != .reef {
                let bowlDepth = (Double(TerrariumConfig.foodBowlCoord.col) + 0.5 + Double(TerrariumConfig.foodBowlCoord.row) + 0.5) * 1000.0 + 1.0
                sortables.append(RenderSortable(sortDepth: bowlDepth) { ctx in
                    let bowlFrame: Int
                    if state.foodBowlPortions <= 0 { bowlFrame = 0 }
                    else if state.foodBowlPortions <= 2 { bowlFrame = 1 }
                    else { bowlFrame = 2 }
                    drawSheetFrame(in: &ctx, sheet: "env_food_bowl", frameIndex: bowlFrame, frameSize: CGSize(width: 18, height: 12), screenPos: bowlPos, anchor: CGPoint(x: 9, y: 8))
                })
            }

            // 4c. 动态植物（独立幼苗与枯萎像素帧；睡莲在此绘制水下细茎，浮叶绘于 Pass 6b 水面层）
            for (idx, plant) in state.plants.enumerated() {
                let gx = Double(plant.coord.col) + 0.5
                let gy = Double(plant.coord.row) + 0.5
                let screenPos = TerrariumConfig.isoToScreen(gx: gx, gy: gy)
                let isGroundCover = (plant.speciesID == "moss" || plant.speciesID == "clover")
                let subBias = isGroundCover ? 0.2 : 1.5
                let depth = (gx + gy) * 1000.0 + subBias

                sortables.append(RenderSortable(sortDepth: depth) { ctx in
                    let isSprout = (plant.stage == .sprout)
                    let isWilting = (plant.stage == .wilting || plant.stage == .withered)
                    // 同种植物依据坐标哈希决定水平镜像与动画相位错峰，呈现多样自然形态
                    let variantHash = abs(plant.coord.col * 31 + plant.coord.row * 17)
                    let flipPlant = (variantHash % 2 == 1)
                    let phaseShift = variantHash % 3

                    switch plant.speciesID {
                    case "fern":
                        let fIdx = isSprout ? 3 : (isWilting ? 4 : (state.isSleeping ? 0 : ((animator.tick / 7 + idx + phaseShift) % 3)))
                        drawSheetFrame(in: &ctx, sheet: "plant_fern_sheet", frameIndex: fIdx, frameSize: CGSize(width: 32, height: 32), screenPos: screenPos, anchor: CGPoint(x: 16, y: isSprout ? 26 : 22), flippedX: flipPlant)
                    case "clover":
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : (state.isSleeping ? 0 : ((animator.tick / 9 + idx + phaseShift) % 2)))
                        drawSheetFrame(in: &ctx, sheet: "plant_clover_sheet", frameIndex: fIdx, frameSize: CGSize(width: 18, height: 14), screenPos: screenPos, anchor: CGPoint(x: 9, y: 11), flippedX: flipPlant)
                    case "moss":
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : ((plant.dewLevel > 0 || phaseShift == 1) ? 1 : 0))
                        drawSheetFrame(in: &ctx, sheet: "plant_moss_clump", frameIndex: fIdx, frameSize: CGSize(width: 20, height: 12), screenPos: screenPos, anchor: CGPoint(x: 10, y: 9), flippedX: flipPlant)
                    case "glow_shroom":
                        let fIdx = isSprout ? 3 : (isWilting ? 4 : (state.isSleeping ? 0 : ((animator.tick / 6 + idx + phaseShift) % 3)))
                        drawSheetFrame(in: &ctx, sheet: "plant_glow_shroom_sheet", frameIndex: fIdx, frameSize: CGSize(width: 16, height: 16), screenPos: screenPos, anchor: CGPoint(x: 8, y: isSprout ? 13 : (isWilting ? 11 : 12)), flippedX: flipPlant)
                    case "succulent":
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : ((state.humidity >= 50 || phaseShift == 1) ? 1 : 0))
                        drawSheetFrame(in: &ctx, sheet: "plant_succulent_sheet", frameIndex: fIdx, frameSize: CGSize(width: 20, height: 16), screenPos: screenPos, anchor: CGPoint(x: 10, y: 12), flippedX: flipPlant)
                    case "cactus":
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : (plant.stage == .mature || plant.stage == .lushDew ? 1 : 0))
                        drawSheetFrame(in: &ctx, sheet: "plant_cactus_sheet", frameIndex: fIdx, frameSize: CGSize(width: 18, height: 20), screenPos: screenPos, anchor: CGPoint(x: 9, y: isSprout ? 15 : 13), flippedX: flipPlant)
                    case "aloe":
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : ((state.humidity >= 40 || phaseShift == 1) ? 1 : 0))
                        drawSheetFrame(in: &ctx, sheet: "plant_aloe_sheet", frameIndex: fIdx, frameSize: CGSize(width: 20, height: 18), screenPos: screenPos, anchor: CGPoint(x: 10, y: 13), flippedX: flipPlant)
                    case "monstera":
                        let fIdx = isSprout ? 3 : (isWilting ? 4 : (state.isSleeping ? 0 : ((animator.tick / 8 + idx + phaseShift) % 3)))
                        drawSheetFrame(in: &ctx, sheet: "plant_monstera_sheet", frameIndex: fIdx, frameSize: CGSize(width: 28, height: 28), screenPos: screenPos, anchor: CGPoint(x: 14, y: (isSprout || isWilting) ? 24 : 25), flippedX: flipPlant)
                    case "bromeliad":
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : ((plant.dewLevel > 0 || phaseShift == 1) ? 1 : 0))
                        drawSheetFrame(in: &ctx, sheet: "plant_bromeliad_sheet", frameIndex: fIdx, frameSize: CGSize(width: 20, height: 20), screenPos: screenPos, anchor: CGPoint(x: 10, y: isWilting ? 18 : 17), flippedX: flipPlant)
                    case "orchid":
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : ((plant.dewLevel > 0 || phaseShift == 1) ? 1 : 0))
                        drawSheetFrame(in: &ctx, sheet: "plant_orchid_sheet", frameIndex: fIdx, frameSize: CGSize(width: 20, height: 22), screenPos: screenPos, anchor: CGPoint(x: 10, y: isSprout ? 18 : (isWilting ? 20 : 21)), flippedX: flipPlant)
                    case "marimo":
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : ((state.humidity >= 65 || phaseShift == 1) ? 1 : 0))
                        drawSheetFrame(in: &ctx, sheet: "plant_marimo_sheet", frameIndex: fIdx, frameSize: CGSize(width: 18, height: 14), screenPos: screenPos, anchor: CGPoint(x: 9, y: isSprout ? 12 : 13), flippedX: flipPlant)
                    case "anubias":
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : (state.isSleeping ? 0 : ((animator.tick / 10 + idx + phaseShift) % 2)))
                        drawSheetFrame(in: &ctx, sheet: "plant_anubias_sheet", frameIndex: fIdx, frameSize: CGSize(width: 22, height: 20), screenPos: screenPos, anchor: CGPoint(x: 11, y: 16), flippedX: flipPlant)
                    case "sundew":
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : ((plant.dewLevel > 0 || phaseShift == 1) ? 1 : 0))
                        drawSheetFrame(in: &ctx, sheet: "plant_sundew_sheet", frameIndex: fIdx, frameSize: CGSize(width: 18, height: 16), screenPos: screenPos, anchor: CGPoint(x: 9, y: 13), flippedX: flipPlant)
                    case "lithops":
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : ((state.humidity <= 45 || phaseShift == 1) ? 1 : 0))
                        drawSheetFrame(in: &ctx, sheet: "plant_lithops_sheet", frameIndex: fIdx, frameSize: CGSize(width: 18, height: 14), screenPos: screenPos, anchor: CGPoint(x: 9, y: 11), flippedX: flipPlant)
                    case "agave":
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : ((plant.stage == .mature || plant.stage == .lushDew || phaseShift == 1) ? 1 : 0))
                        drawSheetFrame(in: &ctx, sheet: "plant_agave_sheet", frameIndex: fIdx, frameSize: CGSize(width: 22, height: 20), screenPos: screenPos, anchor: CGPoint(x: 11, y: 16), flippedX: flipPlant)
                    case "pitcher_plant":
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : ((plant.dewLevel > 0 || phaseShift == 1) ? 1 : 0))
                        drawSheetFrame(in: &ctx, sheet: "plant_pitcher_sheet", frameIndex: fIdx, frameSize: CGSize(width: 20, height: 22), screenPos: screenPos, anchor: CGPoint(x: 10, y: 17), flippedX: flipPlant)
                    case "calathea":
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : (state.isSleeping ? 0 : ((animator.tick / 10 + idx + phaseShift) % 2)))
                        drawSheetFrame(in: &ctx, sheet: "plant_calathea_sheet", frameIndex: fIdx, frameSize: CGSize(width: 22, height: 20), screenPos: screenPos, anchor: CGPoint(x: 11, y: 16), flippedX: flipPlant)
                    case "vallisneria":
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : (state.isSleeping ? 0 : ((animator.tick / 10 + idx + phaseShift) % 2)))
                        drawSheetFrame(in: &ctx, sheet: "plant_vallisneria_sheet", frameIndex: fIdx, frameSize: CGSize(width: 18, height: 22), screenPos: screenPos, anchor: CGPoint(x: 9, y: 18), flippedX: flipPlant)
                    case "red_ludwigia":
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : (state.isSleeping ? 0 : ((animator.tick / 10 + idx + phaseShift) % 2)))
                        drawSheetFrame(in: &ctx, sheet: "plant_red_ludwigia_sheet", frameIndex: fIdx, frameSize: CGSize(width: 20, height: 20), screenPos: screenPos, anchor: CGPoint(x: 10, y: 16), flippedX: flipPlant)
                    case "coral_zoanthid", "coral_acropora", "coral_brain", "coral_anemone", "coral_seafan":
                        let isFluoro = (plant.dewLevel > 0 || state.atmosphere == .night)
                        let swayPhase = state.isSleeping ? 0 : ((animator.tick / 7 + idx + phaseShift) % 2)
                        let fIdx = isSprout ? 4 : (isWilting ? 5 : ((isFluoro ? 2 : 0) + swayPhase))
                        let sheetName = "plant_\(plant.speciesID)_sheet"
                        drawSheetFrame(in: &ctx, sheet: sheetName, frameIndex: fIdx, frameSize: CGSize(width: 22, height: 22), screenPos: screenPos, anchor: CGPoint(x: 11, y: 19), flippedX: flipPlant)
                    case "lotus":
                        // 仅在幼苗期绘制半透明水下细芽茎；成熟期与枯萎期不再保留水下茎与根部，保持水体通透美观
                        if isSprout {
                            let stemFrame = state.isSleeping ? 0 : ((animator.tick / 12 + idx) % 2)
                            ctx.opacity = 0.50
                            drawSheetFrame(in: &ctx, sheet: "plant_lotus_stem", frameIndex: stemFrame, frameSize: CGSize(width: 8, height: 40), screenPos: screenPos, anchor: CGPoint(x: 4, y: 38), flippedX: flipPlant)
                            ctx.opacity = 1.0
                        }
                    default:
                        let fIdx = isSprout ? 3 : (isWilting ? 4 : (state.isSleeping ? 0 : ((animator.tick / 8 + idx + phaseShift) % 3)))
                        drawSheetFrame(in: &ctx, sheet: "plant_red_shroom_sheet", frameIndex: fIdx, frameSize: CGSize(width: 16, height: 16), screenPos: screenPos, anchor: CGPoint(x: 8, y: isSprout ? 13 : (isWilting ? 11 : 12)), flippedX: flipPlant)
                    }

                    // 湿度视觉反馈：幼苗期尚未长成叶冠不显示高处凝露滴落动画，仅成熟大植株显示
                    if plant.speciesID != "lotus", !plant.speciesID.hasPrefix("coral_"), !isSprout, plant.dewLevel >= 1 && !isWilting {
                        let dewOffsetY: Double = (plant.speciesID == "fern" || plant.speciesID == "monstera") ? -15.0 : -6.0
                        if plant.dewLevel == 2 && !state.isSleeping {
                            let dropPhase = (animator.tick + idx * 59) % 210
                            if dropPhase >= 40 {
                                let dewFrame: Int
                                if dropPhase < 95 { dewFrame = 0 }
                                else if dropPhase < 140 { dewFrame = 1 }
                                else if dropPhase < 172 { dewFrame = 2 }
                                else if dropPhase < 184 { dewFrame = 3 }
                                else if dropPhase < 192 { dewFrame = 4 }
                                else if dropPhase < 200 { dewFrame = 5 }
                                else { dewFrame = 6 }
                                drawSheetFrame(
                                    in: &ctx,
                                    sheet: "vfx_dew_drop_sheet",
                                    frameIndex: dewFrame,
                                    frameSize: CGSize(width: 8, height: 14),
                                    screenPos: CGPoint(x: screenPos.x + 2, y: screenPos.y + dewOffsetY),
                                    anchor: CGPoint(x: 4, y: 4)
                                )
                            }
                        } else {
                            let sparkRect = CGRect(x: floor(screenPos.x + 1) * scale, y: floor(screenPos.y + dewOffsetY) * scale, width: scale, height: scale)
                            ctx.fill(Path(sparkRect), with: .color(Color(red: 0.73, green: 0.90, blue: 0.99)))
                        }
                    }
                })
            }

            // 4d. 仿真多帧小动物（和平共处、精准面向食盆进食；离屏快照模式兜底读取 state.critters）
            let renderCritters: [CritterRuntime] = {
                if !animator.critterRuntimes.isEmpty {
                    return animator.critterRuntimes
                }
                guard isSnapshot else { return [] }
                return state.critters.filter { $0.residency != .stored }.map { c in
                    CritterRuntime(
                        id: "snap_\(c.kind.rawValue)",
                        kind: c.kind,
                        schoolIndex: 0,
                        gx: Double(c.coord.col) + 0.5,
                        gy: Double(c.coord.row) + 0.5,
                        gz: (c.kind == .neonTetra || c.kind == .bettaFish || c.kind == .clownfish || c.kind == .blueTang || c.kind == .seahorse) ? 16.0 : 0.0,
                        facingRight: true,
                        behavior: state.isSleeping ? .sleep : .idle
                    )
                }
            }()
            for c in renderCritters {
                let screenPos = TerrariumConfig.isoToScreen(gx: c.gx, gy: c.gy, gz: c.gz)
                let depth = (c.gx + c.gy) * 1000.0 + c.gz * 10.0 + 3.0
                let camoSheet: String = {
                    guard c.kind == .chameleon else { return "" }
                    if animator.justMistedTicks > 0 || c.behavior == .startle || c.behavior == .petted {
                        return "char_chameleon_rainbow"
                    }
                    for p in state.plants {
                        let dx = (Double(p.coord.col) + 0.5) - c.gx
                        let dy = (Double(p.coord.row) + 0.5) - c.gy
                        if dx * dx + dy * dy <= 2.6 * 2.6 {
                            if p.speciesID == "bromeliad" || p.speciesID == "orchid" {
                                return "char_chameleon_coral"
                            }
                            if p.speciesID == "monstera" {
                                return "char_chameleon_green"
                            }
                        }
                    }
                    for decor in state.decorItems where decor.enabled && (decor.id == "rainforest_vine" || decor.id == "rainforest_bark") {
                        let gp = TerrariumConfig.anchorGridPos(for: decor.id, decorOrigins: state.decorOrigins)
                        let dx = gp.gx - c.gx
                        let dy = gp.gy - c.gy
                        if dx * dx + dy * dy <= 2.8 * 2.8 {
                            return "char_chameleon_bark"
                        }
                    }
                    return (state.thermalMode == .heating) ? "char_chameleon_coral" : "char_chameleon_green"
                }()

                sortables.append(RenderSortable(sortDepth: depth) { ctx in
                    let frameIdx = critterFrameIndex(for: c, globalTick: animator.tick)
                    switch c.kind {
                    case .treeFrog:
                        drawSheetFrame(in: &ctx, sheet: "char_frog_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 24, height: 22), screenPos: screenPos, anchor: CGPoint(x: 12, y: 18), flippedX: !c.facingRight)
                    case .snail:
                        drawSheetFrame(in: &ctx, sheet: "char_snail_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 17, height: 14), screenPos: screenPos, anchor: CGPoint(x: 8, y: 11), flippedX: !c.facingRight)
                    case .pillBug:
                        drawSheetFrame(in: &ctx, sheet: "char_pillbug_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 14, height: 10), screenPos: screenPos, anchor: CGPoint(x: 7, y: 7), flippedX: !c.facingRight)
                    case .rhinoBeetle:
                        drawSheetFrame(in: &ctx, sheet: "char_rhino_beetle_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 20, height: 16), screenPos: screenPos, anchor: CGPoint(x: 10, y: 12), flippedX: !c.facingRight)
                    case .amberBeetle:
                        drawSheetFrame(in: &ctx, sheet: "char_beetle_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 18, height: 14), screenPos: screenPos, anchor: CGPoint(x: 9, y: 11), flippedX: !c.facingRight)
                    case .sandGecko:
                        drawSheetFrame(in: &ctx, sheet: "char_gecko_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 28, height: 18), screenPos: screenPos, anchor: CGPoint(x: 14, y: 14), flippedX: !c.facingRight)
                    case .scarab:
                        drawSheetFrame(in: &ctx, sheet: "char_scarab_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 18, height: 14), screenPos: screenPos, anchor: CGPoint(x: 9, y: 11), flippedX: !c.facingRight)
                    case .leafInsect:
                        drawSheetFrame(in: &ctx, sheet: "char_leaf_insect_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 18, height: 16), screenPos: screenPos, anchor: CGPoint(x: 9, y: 12), flippedX: !c.facingRight)
                    case .herculesBeetle:
                        drawSheetFrame(in: &ctx, sheet: "char_hercules_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 22, height: 16), screenPos: screenPos, anchor: CGPoint(x: 11, y: 12), flippedX: !c.facingRight)
                    case .chameleon:
                        drawSheetFrame(in: &ctx, sheet: camoSheet, frameIndex: frameIdx, frameSize: CGSize(width: 26, height: 20), screenPos: screenPos, anchor: CGPoint(x: 13, y: 15), flippedX: !c.facingRight)
                    case .cherryShrimp:
                        drawSheetFrame(in: &ctx, sheet: "char_shrimp_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 14, height: 11), screenPos: screenPos, anchor: CGPoint(x: 7, y: 9), flippedX: !c.facingRight)
                    case .neonTetra:
                        drawSheetFrame(in: &ctx, sheet: "char_tetra_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 14, height: 10), screenPos: screenPos, anchor: CGPoint(x: 7, y: 5), flippedX: !c.facingRight)
                    case .bettaFish:
                        drawSheetFrame(in: &ctx, sheet: "char_betta_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 30, height: 22), screenPos: screenPos, anchor: CGPoint(x: 17, y: 12), flippedX: !c.facingRight)
                    case .crayfish:
                        drawSheetFrame(in: &ctx, sheet: "char_crayfish_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 24, height: 16), screenPos: screenPos, anchor: CGPoint(x: 12, y: 12), flippedX: !c.facingRight)
                    case .fireNewt:
                        drawSheetFrame(in: &ctx, sheet: "char_fire_newt_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 22, height: 16), screenPos: screenPos, anchor: CGPoint(x: 11, y: 12), flippedX: !c.facingRight)
                    case .sandScorpion:
                        drawSheetFrame(in: &ctx, sheet: "char_sand_scorpion_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 22, height: 16), screenPos: screenPos, anchor: CGPoint(x: 11, y: 12), flippedX: !c.facingRight)
                    case .dartFrog:
                        drawSheetFrame(in: &ctx, sheet: "char_dart_frog_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 20, height: 18), screenPos: screenPos, anchor: CGPoint(x: 10, y: 15), flippedX: !c.facingRight)
                    case .corydoras:
                        drawSheetFrame(in: &ctx, sheet: "char_corydoras_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 16, height: 12), screenPos: screenPos, anchor: CGPoint(x: 8, y: 9), flippedX: !c.facingRight)
                    case .ladybug:
                        drawSheetFrame(in: &ctx, sheet: "char_ladybug_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 14, height: 11), screenPos: screenPos, anchor: CGPoint(x: 7, y: 8), flippedX: !c.facingRight)
                    case .desertMantis:
                        drawSheetFrame(in: &ctx, sheet: "char_desert_mantis_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 22, height: 16), screenPos: screenPos, anchor: CGPoint(x: 11, y: 12), flippedX: !c.facingRight)
                    case .hornedToad:
                        drawSheetFrame(in: &ctx, sheet: "char_horned_toad_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 28, height: 18), screenPos: screenPos, anchor: CGPoint(x: 14, y: 14), flippedX: !c.facingRight)
                    case .blueMorpho:
                        drawSheetFrame(in: &ctx, sheet: "char_blue_morpho_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 22, height: 18), screenPos: screenPos, anchor: CGPoint(x: 11, y: 13), flippedX: !c.facingRight)
                    case .redEyedFrog:
                        drawSheetFrame(in: &ctx, sheet: "char_red_eyed_frog_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 20, height: 18), screenPos: screenPos, anchor: CGPoint(x: 10, y: 15), flippedX: !c.facingRight)
                    case .otoCatfish:
                        drawSheetFrame(in: &ctx, sheet: "char_oto_catfish_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 16, height: 12), screenPos: screenPos, anchor: CGPoint(x: 8, y: 9), flippedX: !c.facingRight)
                    case .crystalShrimp:
                        drawSheetFrame(in: &ctx, sheet: "char_crystal_shrimp_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 14, height: 11), screenPos: screenPos, anchor: CGPoint(x: 7, y: 9), flippedX: !c.facingRight)
                    case .clownfish:
                        drawSheetFrame(in: &ctx, sheet: "char_clownfish_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 15, height: 11), screenPos: screenPos, anchor: CGPoint(x: 7.5, y: 6), flippedX: !c.facingRight)
                    case .starfish:
                        drawSheetFrame(in: &ctx, sheet: "char_starfish_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 16, height: 12), screenPos: screenPos, anchor: CGPoint(x: 8, y: 9), flippedX: !c.facingRight)
                    case .cleanerShrimp:
                        drawSheetFrame(in: &ctx, sheet: "char_cleaner_shrimp_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 18, height: 14), screenPos: screenPos, anchor: CGPoint(x: 9, y: 11), flippedX: !c.facingRight)
                    case .blueTang:
                        drawSheetFrame(in: &ctx, sheet: "char_blue_tang_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 22, height: 16), screenPos: screenPos, anchor: CGPoint(x: 11, y: 8), flippedX: !c.facingRight)
                    case .seahorse:
                        drawSheetFrame(in: &ctx, sheet: "char_seahorse_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 14, height: 20), screenPos: screenPos, anchor: CGPoint(x: 7, y: 15), flippedX: !c.facingRight)
                    case .hermitCrab:
                        drawSheetFrame(in: &ctx, sheet: "char_hermit_crab_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 18, height: 15), screenPos: screenPos, anchor: CGPoint(x: 9, y: 12), flippedX: !c.facingRight)
                    }
                })
            }

            for item in sortables.sorted(by: { $0.sortDepth < $1.sortDepth }) {
                item.draw(&context)
            }

            // ==================== Pass 5: 陆缸空中专属生物（多向巡航、停落栖息与串门）与 VFX 粒子 ====================
            func drawAerialVisitor(_ v: AerialVisitorRuntime, isSleeping: Bool, tick: Int, in ctx: inout GraphicsContext) {
                let pos = TerrariumConfig.isoToScreen(gx: v.gx, gy: v.gy, gz: v.gz)
                let frameIdx: Int = {
                    if isSleeping { return (v.kind == .firefly) ? 7 : 6 }
                    switch v.phase {
                    case .perching:
                        return 6 + ((tick / 10) % 2)
                    case .fleeing:
                        return tick % 4
                    case .cruising:
                        let speedDiv = (v.kind == .dragonfly || v.kind == .firefly) ? 2 : 3
                        return (tick / speedDiv) % 4
                    }
                }()
                ctx.opacity = v.isVisiting ? 0.78 : 1.0
                switch v.kind {
                case .firefly:
                    drawSheetFrame(in: &ctx, sheet: "char_firefly_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 12, height: 12), screenPos: pos, anchor: CGPoint(x: 6, y: 6), flippedX: !v.facingRight)
                case .moonMoth:
                    drawSheetFrame(in: &ctx, sheet: "char_moth_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 16, height: 14), screenPos: pos, anchor: CGPoint(x: 8, y: 7), flippedX: !v.facingRight)
                case .dragonfly:
                    drawSheetFrame(in: &ctx, sheet: "char_dragonfly_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 18, height: 14), screenPos: pos, anchor: CGPoint(x: 9, y: 7), flippedX: !v.facingRight)
                case .lunaCicada:
                    drawSheetFrame(in: &ctx, sheet: "char_luna_cicada_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 16, height: 14), screenPos: pos, anchor: CGPoint(x: 8, y: 7), flippedX: !v.facingRight)
                case .antlionLacewing:
                    drawSheetFrame(in: &ctx, sheet: "char_antlion_lacewing_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 18, height: 14), screenPos: pos, anchor: CGPoint(x: 9, y: 7), flippedX: !v.facingRight)
                case .orchidBee:
                    drawSheetFrame(in: &ctx, sheet: "char_orchid_bee_sheet", frameIndex: frameIdx, frameSize: CGSize(width: 14, height: 12), screenPos: pos, anchor: CGPoint(x: 7, y: 6), flippedX: !v.facingRight)
                }
                ctx.opacity = 1.0
            }

            let isWaterTank = (state.currentBiome == .aquatic || state.currentBiome == .reef)
            if !isWaterTank {
                let sleepingNow = state.isSleeping
                let tickNow = animator.tick
                for v in animator.aerialVisitors {
                    drawAerialVisitor(v, isSleeping: sleepingNow, tick: tickNow, in: &context)
                }
            }

            // 食盆存在食物时的微弱香气提示粒子（陆生缸使用；鱼缸/海缸改为水面喂食圈，不冒水底香气）
            if !isWaterTank && state.foodBowlPortions > 0 && !state.isSleeping {
                let aromaOffset = Double((animator.tick / 4) % 8)
                let aromaRect = CGRect(
                    x: floor(bowlPos.x + sin(Double(animator.tick) * 0.2) * 3.0) * scale,
                    y: floor(bowlPos.y - 6.0 - aromaOffset) * scale,
                    width: scale,
                    height: scale
                )
                context.fill(Path(aromaRect), with: .color(Color(red: 0.99, green: 0.90, blue: 0.54).opacity(0.65 - aromaOffset * 0.06)))
            }

            for p in animator.particles {
                switch p.kind {
                case .drop:
                    context.fill(
                        Path(CGRect(x: floor(p.x) * scale, y: floor(p.y) * scale, width: scale, height: scale * 2)),
                        with: .color(Color(red: 0.38, green: 0.74, blue: 0.98))
                    )
                case .splash:
                    context.fill(
                        Path(CGRect(x: floor(p.x) * scale, y: floor(p.y) * scale, width: scale, height: scale)),
                        with: .color(Color(red: 0.75, green: 0.90, blue: 1.0))
                    )
                case .food:
                    context.fill(
                        Path(CGRect(x: floor(p.x) * scale, y: floor(p.y) * scale, width: scale * 2, height: scale * 2)),
                        with: .color(Color(red: 0.98, green: 0.75, blue: 0.14))
                    )
                case .sparkle:
                    context.fill(
                        Path(CGRect(x: floor(p.x) * scale, y: floor(p.y) * scale, width: scale, height: scale)),
                        with: .color(Color(red: 0.99, green: 0.92, blue: 0.58))
                    )
                case .popup:
                    context.draw(
                        Text(p.text).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(Color(red: 0.72, green: 0.98, blue: 0.80)),
                        at: CGPoint(x: floor(p.x) * scale, y: floor(p.y) * scale)
                    )
                case .bubble:
                    // 水中缓慢上浮的气泡绘制在 tank_water_overlay 之前；触及水面破灭微环绘制在 Pass 6b
                    if !p.isPopping {
                        let bubbleFrame: Int = (p.age < 10) ? 0 : (p.gz < 21.0 ? 1 : 2)
                        drawSheetFrame(
                            in: &context,
                            sheet: "vfx_bubble_sheet",
                            frameIndex: bubbleFrame,
                            frameSize: CGSize(width: 6, height: 6),
                            screenPos: CGPoint(x: p.x, y: p.y),
                            anchor: CGPoint(x: 3, y: 3)
                        )
                    }
                }
            }

            // ==================== Pass 6: 透明水体叠加层、水面浮叶与喂食圈、前玻璃框 ====================
            if state.glassFogLevel > 0.05 && !isWaterTank {
                if let mistNS = PixelAssetLoader.nsImage(named: "vfx_glass_mist") {
                    context.opacity = min(0.85, state.glassFogLevel)
                    context.draw(Image(nsImage: mistNS).interpolation(.none), in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
                    context.opacity = 1.0
                }
                if state.glassFogLevel >= 0.45 && !state.isSleeping {
                    let streakFrame = (animator.tick / 6) % 3
                    drawSheetFrame(in: &context, sheet: "vfx_glass_streak_sheet", frameIndex: streakFrame, frameSize: CGSize(width: 6, height: 24), screenPos: CGPoint(x: 56, y: 92), anchor: CGPoint(x: 3, y: 0))
                    drawSheetFrame(in: &context, sheet: "vfx_glass_streak_sheet", frameIndex: (streakFrame + 1) % 3, frameSize: CGSize(width: 6, height: 24), screenPos: CGPoint(x: 168, y: 96), anchor: CGPoint(x: 3, y: 0))
                }
            }

            // 鱼缸与海缸透明水体与 Pass 6b 水面浮点层（水面 gz = 38.0：喂食圈、浮水睡莲、触面破灭水环）
            if isWaterTank {
                drawFullImage(state.currentBiome == .reef ? "tank_reef_water_overlay" : "tank_water_overlay")

                // 鱼缸藻垢：严格贴合 45° 等距水体六边形轮廓渐进变绿 + 缸壁像素绿藻斑块
                if state.glassFogLevel > 0.05 {
                    let cols = Double(TerrariumConfig.gridCols)
                    let rows = Double(TerrariumConfig.gridRows)
                    let gzTop = TerrariumConfig.waterSurfaceGZ
                    let topBack = TerrariumConfig.isoToScreen(gx: 0, gy: 0, gz: gzTop)
                    let topLeft = TerrariumConfig.isoToScreen(gx: 0, gy: rows, gz: gzTop)
                    let botLeft = TerrariumConfig.isoToScreen(gx: 0, gy: rows, gz: 0)
                    let botFront = TerrariumConfig.isoToScreen(gx: cols, gy: rows, gz: 0)
                    let botRight = TerrariumConfig.isoToScreen(gx: cols, gy: 0, gz: 0)
                    let topRight = TerrariumConfig.isoToScreen(gx: cols, gy: 0, gz: gzTop)

                    var waterHull = Path()
                    waterHull.move(to: CGPoint(x: topBack.x * scale, y: topBack.y * scale))
                    waterHull.addLine(to: CGPoint(x: topLeft.x * scale, y: topLeft.y * scale))
                    waterHull.addLine(to: CGPoint(x: botLeft.x * scale, y: botLeft.y * scale))
                    waterHull.addLine(to: CGPoint(x: botFront.x * scale, y: botFront.y * scale))
                    waterHull.addLine(to: CGPoint(x: botRight.x * scale, y: botRight.y * scale))
                    waterHull.addLine(to: CGPoint(x: topRight.x * scale, y: topRight.y * scale))
                    waterHull.closeSubpath()

                    context.fill(
                        waterHull,
                        with: .color(Color(red: 0.22, green: 0.56, blue: 0.30).opacity(min(0.28, state.glassFogLevel * 0.30)))
                    )

                    if let algaeNS = PixelAssetLoader.nsImage(named: "vfx_aquatic_algae") {
                        context.opacity = min(0.92, state.glassFogLevel * 0.95)
                        context.draw(Image(nsImage: algaeNS).interpolation(.none), in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
                        context.opacity = 1.0
                    }
                }

                // 水面移栽睡莲可放置网格（所见即所点）
                if state.isMovingPlant, let selPlant = state.selectedPlant, TerrariumConfig.plantSurfaceGZ(for: selPlant) > 0 {
                    let others = state.plants.filter { $0.id != selPlant.id }
                    let occupied = GridPathfinder.buildNonPlantableSet(
                        enabledDecorIDs: state.enabledDecorIDs,
                        plants: others,
                        decorOrigins: state.decorOrigins,
                        biome: state.currentBiome
                    )
                    for col in 0..<TerrariumConfig.gridCols {
                        for row in 0..<TerrariumConfig.gridRows {
                            let coord = GridCoord(col: col, row: row)
                            let p0 = TerrariumConfig.isoToScreen(gx: Double(col), gy: Double(row), gz: TerrariumConfig.waterSurfaceGZ)
                            let p1 = TerrariumConfig.isoToScreen(gx: Double(col + 1), gy: Double(row), gz: TerrariumConfig.waterSurfaceGZ)
                            let p2 = TerrariumConfig.isoToScreen(gx: Double(col + 1), gy: Double(row + 1), gz: TerrariumConfig.waterSurfaceGZ)
                            let p3 = TerrariumConfig.isoToScreen(gx: Double(col), gy: Double(row + 1), gz: TerrariumConfig.waterSurfaceGZ)
                            var tilePath = Path()
                            tilePath.move(to: CGPoint(x: p0.x * scale, y: p0.y * scale))
                            tilePath.addLine(to: CGPoint(x: p1.x * scale, y: p1.y * scale))
                            tilePath.addLine(to: CGPoint(x: p2.x * scale, y: p2.y * scale))
                            tilePath.addLine(to: CGPoint(x: p3.x * scale, y: p3.y * scale))
                            tilePath.closeSubpath()
                            let isBad = occupied.contains(coord)
                            context.fill(tilePath, with: .color(isBad ? Color.red.opacity(0.14) : Color.green.opacity(0.16)))
                            context.stroke(tilePath, with: .color(isBad ? Color.red.opacity(0.32) : Color.green.opacity(0.45)), lineWidth: 1)
                        }
                    }
                }

                // 触及水面的气泡破灭涟漪微环
                for p in animator.particles where p.kind == .bubble && p.isPopping {
                    drawSheetFrame(
                        in: &context,
                        sheet: "vfx_bubble_sheet",
                        frameIndex: 3,
                        frameSize: CGSize(width: 6, height: 6),
                        screenPos: CGPoint(x: p.x, y: p.y),
                        anchor: CGPoint(x: 3, y: 3)
                    )
                }

                // 水面按纵深排序绘制：悬浮睡莲 + 前排悬浮喂食圈
                var surfaceSortables: [RenderSortable] = []
                for (idx, plant) in state.plants.enumerated() where TerrariumConfig.plantSurfaceGZ(for: plant) > 0 {
                    let gx = Double(plant.coord.col) + 0.5
                    let gy = Double(plant.coord.row) + 0.5
                    let depth = (gx + gy) * 1000.0 + 1.5
                    let bob = state.isSleeping ? 0.0 : Double(((animator.tick / 14 + idx) % 2 == 0) ? 0 : -1)
                    let surfacePos = TerrariumConfig.isoToScreen(gx: gx, gy: gy, gz: TerrariumConfig.waterSurfaceGZ + bob)
                    let isSprout = (plant.stage == .sprout)
                    let isWilting = (plant.stage == .wilting || plant.stage == .withered)

                    surfaceSortables.append(RenderSortable(sortDepth: depth) { ctx in
                        if state.selectedPlantID == plant.id && !state.isMovingPlant {
                            let c = plant.coord
                            let p0 = TerrariumConfig.isoToScreen(gx: Double(c.col), gy: Double(c.row), gz: TerrariumConfig.waterSurfaceGZ)
                            let p1 = TerrariumConfig.isoToScreen(gx: Double(c.col + 1), gy: Double(c.row), gz: TerrariumConfig.waterSurfaceGZ)
                            let p2 = TerrariumConfig.isoToScreen(gx: Double(c.col + 1), gy: Double(c.row + 1), gz: TerrariumConfig.waterSurfaceGZ)
                            let p3 = TerrariumConfig.isoToScreen(gx: Double(c.col), gy: Double(c.row + 1), gz: TerrariumConfig.waterSurfaceGZ)
                            var selPath = Path()
                            selPath.move(to: CGPoint(x: p0.x * scale, y: p0.y * scale))
                            selPath.addLine(to: CGPoint(x: p1.x * scale, y: p1.y * scale))
                            selPath.addLine(to: CGPoint(x: p2.x * scale, y: p2.y * scale))
                            selPath.addLine(to: CGPoint(x: p3.x * scale, y: p3.y * scale))
                            selPath.closeSubpath()
                            ctx.fill(selPath, with: .color(Color(red: 0.98, green: 0.75, blue: 0.14).opacity(0.22)))
                            ctx.stroke(selPath, with: .color(Color(red: 0.99, green: 0.90, blue: 0.54)), lineWidth: 1.5)
                        }
                        let fIdx = isSprout ? 2 : (isWilting ? 3 : (state.humidity >= 70 ? 1 : 0))
                        drawSheetFrame(in: &ctx, sheet: "plant_lotus_sheet", frameIndex: fIdx, frameSize: CGSize(width: 22, height: 16), screenPos: surfacePos, anchor: CGPoint(x: 11, y: 11))
                        if plant.dewLevel >= 1 && !isWilting {
                            let sparkRect = CGRect(x: floor(surfacePos.x + 1) * scale, y: floor(surfacePos.y - 3) * scale, width: scale, height: scale)
                            ctx.fill(Path(sparkRect), with: .color(Color(red: 0.73, green: 0.90, blue: 0.99)))
                        }
                    })
                }

                let ringCoord = TerrariumConfig.aquaticFeedingCoord
                let ringGX = Double(ringCoord.col) + 0.5
                let ringGY = Double(ringCoord.row) + 0.5
                let ringDepth = (ringGX + ringGY) * 1000.0 + 1.0
                let ringPos = TerrariumConfig.isoToScreen(gx: ringGX, gy: ringGY, gz: TerrariumConfig.waterSurfaceGZ)
                surfaceSortables.append(RenderSortable(sortDepth: ringDepth) { ctx in
                    let ringFrame: Int
                    if state.foodBowlPortions <= 0 { ringFrame = 0 }
                    else if state.foodBowlPortions <= 2 { ringFrame = 1 }
                    else { ringFrame = 2 }
                    drawSheetFrame(in: &ctx, sheet: "env_aquatic_feeding_ring", frameIndex: ringFrame, frameSize: CGSize(width: 30, height: 18), screenPos: ringPos, anchor: CGPoint(x: 15, y: 9))
                })

                for item in surfaceSortables.sorted(by: { $0.sortDepth < $1.sortDepth }) {
                    item.draw(&context)
                }

                // 鱼缸仅允许蜻蜓在水面之上 (gz >= 39.5) 盘旋或停落于睡莲叶，绝不在水下飞行
                let sleepingNow = state.isSleeping
                let tickNow = animator.tick
                for v in animator.aerialVisitors where v.kind == .dragonfly {
                    drawAerialVisitor(v, isSleeping: sleepingNow, tick: tickNow, in: &context)
                }
            }

            drawFullImage("tank_front_glass")

            // Pass 7b: 仅留柔和光锥/风锥氛围叠加在前玻璃外层（器材本体已在 Pass 1b 后壁内层绘制，绝不挡鱼）
            if state.currentBiome == .reef && !state.isSleeping {
                // 海缸日间 45° 水下焦散光束；Night 模式切换为深海荧光蓝紫珊瑚灯锥
                var reefCone = Path()
                reefCone.move(to: CGPoint(x: 68 * scale, y: 32 * scale))
                reefCone.addLine(to: CGPoint(x: 156 * scale, y: 32 * scale))
                reefCone.addLine(to: CGPoint(x: 186 * scale, y: 120 * scale))
                reefCone.addLine(to: CGPoint(x: 42 * scale, y: 120 * scale))
                reefCone.closeSubpath()
                let isNightReef = (state.atmosphere == .night)
                context.fill(
                    reefCone,
                    with: .color(isNightReef
                                 ? Color(red: 0.34, green: 0.24, blue: 0.96).opacity(0.11)
                                 : Color(red: 0.42, green: 0.88, blue: 1.0).opacity(0.06))
                )
            }
            if state.hasHeatLamp && !isWaterTank && !state.isSleeping && state.thermalMode == .heating {
                var cone = Path()
                cone.move(to: CGPoint(x: 154 * scale, y: 34 * scale))
                cone.addLine(to: CGPoint(x: 168 * scale, y: 34 * scale))
                cone.addLine(to: CGPoint(x: 186 * scale, y: 108 * scale))
                cone.addLine(to: CGPoint(x: 96 * scale, y: 108 * scale))
                cone.closeSubpath()
                context.fill(cone, with: .color(Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.08)))
            }

            if state.hasCoolingFan && !state.isSleeping && state.thermalMode == .cooling {
                var breeze = Path()
                breeze.move(to: CGPoint(x: 48 * scale, y: 34 * scale))
                breeze.addLine(to: CGPoint(x: 68 * scale, y: 34 * scale))
                breeze.addLine(to: CGPoint(x: 112 * scale, y: 102 * scale))
                breeze.addLine(to: CGPoint(x: 42 * scale, y: 102 * scale))
                breeze.closeSubpath()
                context.fill(breeze, with: .color(Color(red: 0.54, green: 0.88, blue: 1.0).opacity(0.06)))
            }

            if !state.isSleeping && state.twilightIntensity > 0.01 {
                let twilightRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                context.fill(
                    Path(twilightRect),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 1.0, green: 0.66, blue: 0.28).opacity(0.16 * state.twilightIntensity),
                            Color(red: 0.96, green: 0.48, blue: 0.36).opacity(0.05 * state.twilightIntensity),
                            Color.clear
                        ]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: size.width, y: size.height)
                    )
                )
            }

            if state.isSleeping {
                drawFullImage("tank_lid_sleep")
                context.draw(
                    Text(TerrariumL10n.t("stage.sleep_overlay"))
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(red: 0.99, green: 0.90, blue: 0.54)),
                    at: CGPoint(x: size.width / 2, y: 34)
                )
            }
        }
        .frame(width: 224 * scale, height: 176 * scale)
        .overlay(alignment: .topLeading) {
            Text(TerrariumL10n.t("ui.day_badge", ["days": "\(state.activeContainerDays)"]))
                .font(.system(size: max(10, 5.2 * scale), weight: .bold, design: .monospaced))
                .padding(.horizontal, 3.0 * scale)
                .padding(.vertical, 1.5 * scale)
                .background(Color(red: 0.09, green: 0.13, blue: 0.11).opacity(0.78))
                .foregroundColor(Color(red: 0.99, green: 0.90, blue: 0.54))
                .overlay(Rectangle().stroke(Color(red: 0.23, green: 0.32, blue: 0.27), lineWidth: 1))
                .padding(4 * scale)
        }
        .overlay(
            Rectangle()
                .strokeBorder(frameAccentColor, lineWidth: max(1, scale / 2))
                .padding(scale)
        )
        .border(frameBorderColor, width: scale)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture()
                .onEnded { value in
                    let logicalPt = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
                    animator.handleTap(atLogicalPoint: logicalPt)
                }
        )
        .onAppear {
            animator.bind(state: state)
            animator.start()
        }
        .onDisappear {
            animator.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            animator.pauseRendering()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            animator.resumeRendering()
        }
    }

    private var frameBorderColor: Color {
        switch state.activeFrameSkin {
        case .classic: return Color(red: 0.23, green: 0.32, blue: 0.27)
        case .wood: return Color(red: 0.45, green: 0.29, blue: 0.16)
        case .brass: return Color(red: 0.72, green: 0.56, blue: 0.24)
        case .frosted: return Color(red: 0.65, green: 0.80, blue: 0.88)
        case .obsidian: return Color(red: 0.12, green: 0.13, blue: 0.17)
        case .pearlReef: return Color(red: 0.08, green: 0.24, blue: 0.42)
        }
    }

    private var frameAccentColor: Color {
        switch state.activeFrameSkin {
        case .classic: return Color.clear
        case .wood: return Color(red: 0.65, green: 0.44, blue: 0.25).opacity(0.6)
        case .brass: return Color(red: 0.94, green: 0.80, blue: 0.42).opacity(0.75)
        case .frosted: return Color.white.opacity(0.45)
        case .obsidian: return Color(red: 0.42, green: 0.35, blue: 0.68).opacity(0.75)
        case .pearlReef: return Color(red: 0.56, green: 0.88, blue: 0.96).opacity(0.78)
        }
    }

    private func critterFrameIndex(for c: CritterRuntime, globalTick: Int) -> Int {
        if c.kind == .ladybug && c.gz > 1.2 && c.behavior != .sleep {
            return 10 + ((globalTick / 2) % 2)
        }
        switch c.kind {
        case .treeFrog, .dartFrog, .redEyedFrog:
            switch c.behavior {
            case .idle, .petted:
                let seq = [0, 0, 1, 1, 2, 3]
                return seq[(globalTick / 5) % seq.count]
            case .patrol, .seekingFood:
                return 4 + min(4, Int(c.hopProgress * 5.0))
            case .eating:
                return 9 + ((c.stateTicks / 3) % 5)
            case .startle:
                return 14 + min(2, c.stateTicks / 5)
            case .sleep:
                return 17 + ((globalTick / 10) % 2)
            }

        case .snail:
            switch c.behavior {
            case .patrol, .seekingFood:
                return (globalTick / 4) % 4
            case .idle, .petted:
                return 4 + ((globalTick / 6) % 3)
            case .eating:
                return 7 + ((c.stateTicks / 4) % 3)
            case .startle:
                return 10 + ((c.stateTicks / 6) % 2)
            case .sleep:
                return 12 + ((globalTick / 12) % 2)
            }

        case .pillBug:
            switch c.behavior {
            case .idle, .petted: return (globalTick / 8) % 2
            case .patrol, .seekingFood: return 2 + ((globalTick / 3) % 4)
            case .eating: return 6 + ((c.stateTicks / 4) % 2)
            case .startle: return 8 + ((c.stateTicks / 8) % 2)
            case .sleep: return 10 + ((globalTick / 12) % 2)
            }

        case .amberBeetle, .rhinoBeetle, .leafInsect, .herculesBeetle:
            switch c.behavior {
            case .idle, .petted: return (globalTick / 5) % 3
            case .patrol, .seekingFood: return 3 + ((globalTick / 2) % 4)
            case .eating: return 7 + ((c.stateTicks / 3) % 3)
            case .startle: return 10 + ((c.stateTicks / 5) % 2)
            case .sleep: return 12 + ((globalTick / 10) % 2)
            }

        case .clownfish, .blueTang, .seahorse, .cleanerShrimp, .hermitCrab:
            switch c.behavior {
            case .idle, .petted: return (globalTick / 4) % 3
            case .patrol, .seekingFood: return 3 + ((globalTick / 2) % 4)
            case .eating: return 7 + ((c.stateTicks / 3) % 3)
            case .startle: return 10 + ((c.stateTicks / 4) % 2)
            case .sleep: return 12 + ((globalTick / 12) % 2)
            }

        case .starfish:
            switch c.behavior {
            case .idle, .petted: return (globalTick / 12) % 3
            case .patrol, .seekingFood: return 3 + ((globalTick / 10) % 4)
            case .eating: return 7 + ((c.stateTicks / 6) % 3)
            case .startle: return 10 + ((c.stateTicks / 6) % 2)
            case .sleep: return 12 + ((globalTick / 14) % 2)
            }

        case .chameleon:
            switch c.behavior {
            case .idle, .petted: return (globalTick / 6) % 4
            case .patrol, .seekingFood: return 4 + ((globalTick / 3) % 4)
            case .eating: return 8 + ((c.stateTicks / 3) % 5)
            case .startle: return 13 + ((c.stateTicks / 5) % 3)
            case .sleep: return 16 + ((globalTick / 12) % 3)
            }

        case .sandGecko:
            switch c.behavior {
            case .idle, .petted: return (globalTick / 6) % 3
            case .patrol, .seekingFood: return 3 + ((globalTick / 3) % 4)
            case .eating: return 7 + ((c.stateTicks / 4) % 3)
            case .startle: return 10 + ((c.stateTicks / 5) % 2)
            case .sleep: return 12 + ((globalTick / 10) % 2)
            }

        case .scarab, .cherryShrimp, .neonTetra:
            switch c.behavior {
            case .idle, .petted: return (globalTick / 6) % 2
            case .patrol, .seekingFood: return 2 + ((globalTick / 2) % 4)
            case .eating: return 6 + ((c.stateTicks / 4) % 2)
            case .startle: return 8 + ((c.stateTicks / 5) % 2)
            case .sleep: return 10 + ((globalTick / 10) % 2)
            }

        case .bettaFish, .crayfish, .fireNewt, .sandScorpion, .corydoras,
             .ladybug, .desertMantis, .hornedToad, .blueMorpho, .otoCatfish, .crystalShrimp:
            switch c.behavior {
            case .idle, .petted: return (globalTick / 6) % 3
            case .patrol, .seekingFood: return 3 + ((globalTick / 3) % 4)
            case .eating: return 7 + ((c.stateTicks / 4) % 3)
            case .startle: return 10 + ((c.stateTicks / 5) % 2)
            case .sleep: return 12 + ((globalTick / 10) % 2)
            }
        }
    }
}

/// 4x 无损像素生态快照导出卡（896x704 画布 + 底部像素角标）
struct PixelStageSnapshotCard: View {
    @ObservedObject var state: TerrariumState

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            PixelStageView(state: state, scale: 4.0, isSnapshot: true)
            HStack {
                Text(TerrariumL10n.t("stage.snapshot_footer", [
                    "tank": state.activeContainerName,
                    "biome": state.currentBiome.localizedName
                ]))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.85, green: 0.95, blue: 0.82))
                Spacer()
                Text(TerrariumL10n.t("stage.snapshot_sub", [
                    "title": state.codexMilestoneTitle,
                    "date": dateLabel
                ]))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.56, green: 0.72, blue: 0.59))
            }
            .padding(.horizontal, 20)
            .frame(width: 896, height: 48)
            .background(Color(red: 0.12, green: 0.16, blue: 0.14))
        }
    }
}
