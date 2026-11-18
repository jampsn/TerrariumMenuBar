import Combine
import Foundation
import SwiftUI
import TerrariumCore

enum CritterBehavior: Equatable {
    case idle
    case patrol
    case seekingFood
    case eating
    case petted
    case startle
    case sleep
}

struct CritterRuntime: Identifiable {
    let id: String
    let kind: CritterKind
    let schoolIndex: Int
    var isLeader: Bool { schoolIndex == 0 }
    var gx: Double
    var gy: Double
    var smoothBaseGZ: Double = 0.0
    var gz: Double = 0.0
    var facingRight: Bool = true
    var behavior: CritterBehavior = .idle
    var stateTicks: Int = 0
    var idleCooldownTicks: Int = 24
    var path: [GridCoord] = []
    var hopProgress: Double = 0.0
    var stepOriginX: Double = 0.0
    var stepOriginY: Double = 0.0
    var swimPhase: Double = 0.0
    var prefersMidwaterSwim: Bool = false
    var boidTargetDX: Double = 0.0
    var boidTargetDY: Double = 0.0
    var boidAltitudeBias: Double = 0.0
    var boidFollowRate: Double = 0.08
    var bubbleCooldownTicks: Int = 75
}

struct PixelParticle: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var kind: Kind
    var life: Int
    var text: String = "+1"
    var targetY: Double = 176.0
    var gx: Double = 0.0
    var gy: Double = 0.0
    var gz: Double = 0.0
    var vz: Double = 0.0
    var wobblePhase: Double = 0.0
    var age: Int = 0
    var isPopping: Bool = false

    enum Kind {
        case drop, splash, food, sparkle, popup, bubble
    }
}

/// 独立 15fps 舞台动画与 A* 精准食盆寻路引擎
@MainActor
final class StageAnimator: ObservableObject {
    @Published private(set) var tick: Int = 0
    @Published private(set) var critterRuntimes: [CritterRuntime] = []
    @Published private(set) var particles: [PixelParticle] = []

    private let maxParticles = 56
    private let maxBubbleParticles = 12
    private var rockBubbleCooldownTicks: Int = 24
    nonisolated(unsafe) private var timer: Timer?
    private var isRunning: Bool = false
    private var cancellable: AnyCancellable?
    private weak var boundState: TerrariumState?
    private var justFedBoostTicks: Int = 0
    private(set) var justMistedTicks: Int = 0
    private var lastSyncedContainerID: UUID?
    private var recentTapTimestamps: [CritterKind: [Date]] = [:]

    deinit {
        if let activeTimer = timer {
            if Thread.isMainThread {
                activeTimer.invalidate()
            } else {
                nonisolated(unsafe) let t = activeTimer
                DispatchQueue.main.async {
                    t.invalidate()
                }
            }
        }
    }

    func bind(state: TerrariumState) {
        self.boundState = state
        syncCrittersFromState()

        cancellable?.cancel()
        cancellable = state.vfxSubject.sink { [weak self] event in
            self?.handleVFX(event)
        }
    }

    /// 根据当前活跃生态缸同步动物实体（切缸、访客入场、隐匿/复出时自动更新，支持红绿灯鱼 5 尾群游）
    func syncCrittersFromState() {
        guard let state = boundState else { return }
        let containerChanged = (lastSyncedContainerID != state.activeContainerID)
        lastSyncedContainerID = state.activeContainerID
        let activeList = state.activeDisplayCritters
        var updated: [CritterRuntime] = []

        for c in activeList {
            let totalInGroup = (c.kind == .neonTetra) ? 5 : 1
            for sIdx in 0..<totalInGroup {
                let runtimeID = (totalInGroup > 1) ? "\(c.kind.rawValue)_\(sIdx)" : c.kind.rawValue
                if !containerChanged, let existing = critterRuntimes.first(where: { $0.id == runtimeID }) {
                    updated.append(existing)
                } else {
                    let altBiases = [0.0, -2.2, 1.5, -1.0, 2.5]
                    let altBias = (totalInGroup > 1) ? altBiases[sIdx % altBiases.count] : 0.0
                    let initGZ = defaultCruiseGZ(for: c.kind, altitudeBias: altBias)
                    let dxOffsets = [0.0, -0.85, 0.75, -0.55, 0.95]
                    let dyOffsets = [0.0, 0.65, -0.75, -0.85, 0.55]
                    let followRates = [0.10, 0.092, 0.082, 0.072, 0.064]
                    let spawnGX = max(0.6, min(Double(TerrariumConfig.gridCols) - 0.6, Double(c.coord.col) + 0.5 + dxOffsets[sIdx % dxOffsets.count]))
                    let spawnGY = max(0.6, min(Double(TerrariumConfig.gridRows) - 0.6, Double(c.coord.row) + 0.5 + dyOffsets[sIdx % dyOffsets.count]))
                    var rt = CritterRuntime(
                        id: runtimeID,
                        kind: c.kind,
                        schoolIndex: sIdx,
                        gx: spawnGX,
                        gy: spawnGY,
                        smoothBaseGZ: initGZ,
                        gz: initGZ,
                        idleCooldownTicks: c.residency == .visitor ? 4 : Int.random(in: 14...36),
                        swimPhase: Double.random(in: 0..<(2.0 * .pi)),
                        boidTargetDX: dxOffsets[sIdx % dxOffsets.count],
                        boidTargetDY: dyOffsets[sIdx % dyOffsets.count],
                        boidAltitudeBias: altBias,
                        boidFollowRate: followRates[sIdx % followRates.count],
                        bubbleCooldownTicks: Int.random(in: 45...115)
                    )
                    if c.residency == .visitor && state.foodBowlPortions > 0 {
                        justFedBoostTicks = max(justFedBoostTicks, 180)
                        rt.idleCooldownTicks = 1
                    }
                    updated.append(rt)
                }
            }
        }
        critterRuntimes = updated
    }

    private func defaultCruiseGZ(for kind: CritterKind, altitudeBias: Double = 0.0) -> Double {
        switch kind {
        case .neonTetra: return 15.5 + altitudeBias
        case .bettaFish: return 22.5
        default: return 0.0
        }
    }

    private func desiredTargetBaseGZ(for c: CritterRuntime) -> Double {
        if c.behavior == .sleep {
            switch c.kind {
            case .neonTetra: return 6.5 + c.boidAltitudeBias * 0.4
            case .bettaFish: return 7.5
            default: return 0.0
            }
        }
        switch c.kind {
        case .neonTetra:
            switch c.behavior {
            case .seekingFood: return 23.0 + c.boidAltitudeBias * 0.5
            case .eating: return 33.0 + c.boidAltitudeBias * 0.4
            case .startle: return 20.5 + c.boidAltitudeBias
            case .idle, .patrol, .petted: return 15.5 + c.boidAltitudeBias
            case .sleep: return 6.5
            }
        case .bettaFish:
            switch c.behavior {
            case .seekingFood: return 27.5
            case .eating: return 33.5
            case .startle: return 25.5
            case .idle, .patrol, .petted: return 22.5
            case .sleep: return 7.5
            }
        case .cherryShrimp:
            switch c.behavior {
            case .eating, .seekingFood, .sleep: return 0.0
            case .startle: return 8.5
            case .patrol: return c.prefersMidwaterSwim ? 8.5 : 0.0
            case .idle, .petted: return c.prefersMidwaterSwim ? 6.5 : 0.0
            }
        default:
            return 0.0
        }
    }

    private func updateSmoothAltitude(_ c: inout CritterRuntime) {
        let targetBase = desiredTargetBaseGZ(for: c)
        let lerpRate = (c.kind == .cherryShrimp && c.behavior == .startle) ? 0.28 : 0.14
        c.smoothBaseGZ += (targetBase - c.smoothBaseGZ) * lerpRate

        let phaseStep: Double = {
            switch c.kind {
            case .bettaFish: return c.behavior == .startle ? 0.22 : 0.11
            case .neonTetra: return c.behavior == .startle ? 0.28 : 0.16
            default: return 0.15
            }
        }()
        c.swimPhase += phaseStep

        let bobOffset: Double
        if c.behavior == .sleep {
            bobOffset = 0.0
        } else if c.kind == .neonTetra {
            bobOffset = sin(c.swimPhase) * 1.3
        } else if c.kind == .bettaFish {
            bobOffset = cos(c.swimPhase) * 1.6
        } else if c.kind == .cherryShrimp && c.smoothBaseGZ > 0.8 {
            bobOffset = sin(c.swimPhase * 1.3) * 0.7
        } else {
            bobOffset = 0.0
        }

        let hopArc = (c.kind == .treeFrog && (c.behavior == .patrol || c.behavior == .seekingFood))
            ? sin(c.hopProgress * .pi) * 7.0
            : 0.0
        c.gz = max(0.0, c.smoothBaseGZ + bobOffset + hopArc)
    }

    func start() {
        guard timer == nil else { return }
        isRunning = true
        let newTimer = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.stepFrame()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        cancellable?.cancel()
        cancellable = nil
        particles.removeAll()
    }

    func stepFrame() {
        guard let state = boundState else { return }

        if state.isSleeping {
            for idx in critterRuntimes.indices {
                critterRuntimes[idx].behavior = .sleep
                critterRuntimes[idx].path.removeAll()
                updateSmoothAltitude(&critterRuntimes[idx])
            }
            updateParticles()
            return
        }

        tick += 1
        if justFedBoostTicks > 0 {
            justFedBoostTicks -= 1
        }
        if justMistedTicks > 0 {
            justMistedTicks -= 1
        }

        let blocked = GridPathfinder.buildBlockedSet(
            enabledDecorIDs: state.enabledDecorIDs,
            plants: state.plants,
            decorOrigins: state.decorOrigins,
            biome: state.currentBiome
        )

        for idx in critterRuntimes.indices {
            if critterRuntimes[idx].behavior == .sleep {
                critterRuntimes[idx].behavior = .idle
                critterRuntimes[idx].stateTicks = 0
            }
            if critterRuntimes[idx].isLeader {
                stepCritter(index: idx, state: state, blocked: blocked)
            }
        }
        for idx in critterRuntimes.indices where !critterRuntimes[idx].isLeader {
            stepCompanionCritter(index: idx, state: state, blocked: blocked)
        }

        emitAquaticBubbles(state: state)
        updateParticles()
    }

    private func reservedFoodSlots(excluding index: Int) -> Set<GridCoord> {
        var reserved = Set<GridCoord>()
        for (i, other) in critterRuntimes.enumerated() where i != index && other.isLeader {
            if other.behavior == .eating {
                let g = GridCoord(
                    col: max(0, min(TerrariumConfig.gridCols - 1, Int(floor(other.gx)))),
                    row: max(0, min(TerrariumConfig.gridRows - 1, Int(floor(other.gy))))
                )
                reserved.insert(g)
            } else if other.behavior == .seekingFood, let dest = other.path.last {
                reserved.insert(dest)
            }
        }
        return reserved
    }

    private func stepCritter(index idx: Int, state: TerrariumState, blocked: Set<GridCoord>) {
        var c = critterRuntimes[idx]
        c.stateTicks += 1

        let currentGrid = GridCoord(
            col: max(0, min(TerrariumConfig.gridCols - 1, Int(floor(c.gx)))),
            row: max(0, min(TerrariumConfig.gridRows - 1, Int(floor(c.gy))))
        )

        let feedCoord = TerrariumConfig.feedingCoord(for: state.currentBiome)
        let isSurfaceFeeder = (c.kind == .neonTetra || c.kind == .bettaFish)
        let bowlGZ: Double = (state.currentBiome == .aquatic && isSurfaceFeeder) ? TerrariumConfig.waterSurfaceGZ : 3.0
        let bowlCenter = TerrariumConfig.isoToScreen(
            gx: Double(feedCoord.col) + 0.5,
            gy: Double(feedCoord.row) + 0.5,
            gz: bowlGZ
        )
        let bottomBowlCenter = TerrariumConfig.isoToScreen(
            gx: Double(feedCoord.col) + 0.5,
            gy: Double(feedCoord.row) + 0.5,
            gz: 1.0
        )

        switch c.behavior {
        case .sleep:
            break

        case .petted:
            if c.stateTicks >= 22 {
                c.behavior = .idle
                c.stateTicks = 0
                c.idleCooldownTicks = 30
            }

        case .startle:
            let duration = (c.kind == .snail || c.kind == .pillBug) ? 36 : 18
            if c.stateTicks >= duration {
                c.behavior = .idle
                c.stateTicks = 0
                c.idleCooldownTicks = 18
                if c.kind == .cherryShrimp {
                    c.prefersMidwaterSwim = false
                }
            }

        case .eating:
            let myPos = TerrariumConfig.isoToScreen(gx: c.gx, gy: c.gy)
            c.facingRight = bowlCenter.x >= myPos.x

            // 严格检查：如果食盆/喂食圈已被同伴吃完或不再邻接目标格，立刻停止进食
            guard state.foodBowlPortions > 0,
                  GridPathfinder.manhattan(currentGrid, feedCoord) == 1 else {
                c.behavior = .idle
                c.stateTicks = 0
                break
            }

            // 进食中途溅出碎屑（水面上层鱼类啄食会从大浮圈掉落缓沉微粒至后方河沙）
            if c.stateTicks == 10 || c.stateTicks == 18 {
                if state.currentBiome == .aquatic && isSurfaceFeeder {
                    appendParticle(PixelParticle(
                        x: bowlCenter.x + Double.random(in: -5...5),
                        y: bowlCenter.y + 1,
                        vx: Double.random(in: -0.08...0.08),
                        vy: 0.35,
                        kind: .food,
                        life: 32,
                        targetY: bottomBowlCenter.y
                    ))
                } else {
                    appendParticle(PixelParticle(
                        x: bowlCenter.x + Double.random(in: -2...2),
                        y: bowlCenter.y,
                        vx: Double.random(in: -0.25...0.25),
                        vy: -0.5,
                        kind: .food,
                        life: 10,
                        targetY: bowlCenter.y + 2
                    ))
                }
            }

            if c.stateTicks >= 24 {
                state.completeCritterMeal(kind: c.kind, at: CGPoint(x: bowlCenter.x, y: bowlCenter.y - 10))
                c.behavior = .idle
                c.stateTicks = 0
                c.idleCooldownTicks = 45
            }

        case .idle:
            if shouldSeekFood(kind: c.kind, state: state) {
                if c.kind == .cherryShrimp { c.prefersMidwaterSwim = false }
                let reserved = reservedFoodSlots(excluding: idx)
                let path = GridPathfinder.findPathToFoodBowl(from: currentGrid, blocked: blocked, reservedSlots: reserved, biome: state.currentBiome)
                if !path.isEmpty {
                    c.behavior = .seekingFood
                    c.path = path
                    c.stateTicks = 0
                    c.hopProgress = 0
                    c.stepOriginX = c.gx
                    c.stepOriginY = c.gy
                    break
                }
            }

            if c.stateTicks >= c.idleCooldownTicks {
                if let patrolPath = pickPatrolPath(from: currentGrid, kind: c.kind, state: state, blocked: blocked) {
                    if c.kind == .cherryShrimp {
                        // 樱花米虾：~80% 贴底觅食爬行，~20% 优雅升入半水中飘游转场
                        c.prefersMidwaterSwim = (Double.random(in: 0...1) < 0.22)
                    }
                    c.behavior = .patrol
                    c.path = patrolPath
                    c.stateTicks = 0
                    c.hopProgress = 0
                    c.stepOriginX = c.gx
                    c.stepOriginY = c.gy
                } else {
                    c.stateTicks = 0
                    c.idleCooldownTicks = 25
                }
            }

        case .patrol, .seekingFood:
            if c.behavior == .seekingFood && state.foodBowlPortions <= 0 {
                c.behavior = .idle
                c.path.removeAll()
                c.stateTicks = 0
                break
            }
            if c.behavior == .patrol && shouldSeekFood(kind: c.kind, state: state) && c.hopProgress == 0 {
                if c.kind == .cherryShrimp { c.prefersMidwaterSwim = false }
                let reserved = reservedFoodSlots(excluding: idx)
                let foodPath = GridPathfinder.findPathToFoodBowl(from: currentGrid, blocked: blocked, reservedSlots: reserved, biome: state.currentBiome)
                if !foodPath.isEmpty {
                    c.behavior = .seekingFood
                    c.path = foodPath
                    c.stateTicks = 0
                }
            }

            guard let nextNode = c.path.first else {
                if c.behavior == .seekingFood && GridPathfinder.manhattan(currentGrid, feedCoord) == 1 && state.foodBowlPortions > 0 {
                    c.behavior = .eating
                    c.stateTicks = 0
                } else {
                    c.behavior = .idle
                    c.stateTicks = 0
                    c.idleCooldownTicks = Int.random(in: 24...55)
                    if c.kind == .cherryShrimp {
                        c.prefersMidwaterSwim = false
                    }
                }
                break
            }

            if c.hopProgress == 0 && blocked.contains(nextNode) {
                let reserved = reservedFoodSlots(excluding: idx)
                let target = (c.behavior == .seekingFood)
                    ? GridPathfinder.findPathToFoodBowl(from: currentGrid, blocked: blocked, reservedSlots: reserved, biome: state.currentBiome)
                    : (pickPatrolPath(from: currentGrid, kind: c.kind, state: state, blocked: blocked) ?? [])
                c.path = target
                c.stepOriginX = c.gx
                c.stepOriginY = c.gy
                if target.isEmpty {
                    c.behavior = .idle
                    c.stateTicks = 0
                    if c.kind == .cherryShrimp { c.prefersMidwaterSwim = false }
                }
                break
            }

            let targetX = Double(nextNode.col) + 0.5
            let targetY = Double(nextNode.row) + 0.5
            if c.hopProgress == 0 {
                c.stepOriginX = c.gx
                c.stepOriginY = c.gy
                let p0 = TerrariumConfig.isoToScreen(gx: c.stepOriginX, gy: c.stepOriginY)
                let p1 = TerrariumConfig.isoToScreen(gx: targetX, gy: targetY)
                if abs(p1.x - p0.x) > 0.2 {
                    c.facingRight = p1.x >= p0.x
                }
            }

            let stepRate: Double
            switch c.kind {
            case .treeFrog: stepRate = 1.0 / 10.0
            case .snail: stepRate = 1.0 / 28.0
            case .pillBug: stepRate = 1.0 / 16.0
            case .amberBeetle, .scarab: stepRate = 1.0 / 12.0
            case .rhinoBeetle, .herculesBeetle, .crayfish: stepRate = 1.0 / 15.0
            case .cherryShrimp: stepRate = c.prefersMidwaterSwim ? (1.0 / 12.0) : (1.0 / 16.0)
            case .neonTetra: stepRate = 1.0 / 13.0
            case .bettaFish: stepRate = 1.0 / 18.0
            case .leafInsect: stepRate = 1.0 / 22.0
            case .sandGecko: stepRate = 1.0 / 11.0
            case .chameleon: stepRate = 1.0 / 18.0
            }

            c.hopProgress = min(1.0, c.hopProgress + stepRate)
            c.gx = c.stepOriginX + (targetX - c.stepOriginX) * c.hopProgress
            c.gy = c.stepOriginY + (targetY - c.stepOriginY) * c.hopProgress

            if c.hopProgress >= 1.0 {
                c.gx = targetX
                c.gy = targetY
                c.hopProgress = 0.0
                c.path.removeFirst()
                state.updateCritterCoord(kind: c.kind, coord: nextNode)

                if c.behavior == .seekingFood && c.path.isEmpty {
                    if GridPathfinder.manhattan(nextNode, feedCoord) == 1 && state.foodBowlPortions > 0 {
                        c.behavior = .eating
                        c.stateTicks = 0
                    } else {
                        c.behavior = .idle
                        c.stateTicks = 0
                    }
                } else if c.behavior == .patrol && c.path.isEmpty {
                    c.behavior = .idle
                    c.stateTicks = 0
                    c.idleCooldownTicks = Int.random(in: 24...55)
                    if c.kind == .cherryShrimp {
                        c.prefersMidwaterSwim = false
                    }
                }
            }
        }

        updateSmoothAltitude(&c)
        critterRuntimes[idx] = c
    }

    /// 伴游鱼 Boids（仅跟随领游主鱼并保持分离/对齐，零 A* 开销，不争夺食盆额度）
    private func stepCompanionCritter(index idx: Int, state: TerrariumState, blocked: Set<GridCoord>) {
        var c = critterRuntimes[idx]
        guard let leader = critterRuntimes.first(where: { $0.kind == c.kind && $0.isLeader }) else {
            return
        }
        c.stateTicks += 1
        c.behavior = leader.behavior

        let scatterMult: Double = (leader.behavior == .startle) ? 1.9 : 1.0
        let wanderGX = sin(c.swimPhase * 0.45 + Double(c.schoolIndex) * 1.4) * 0.25
        let wanderGY = cos(c.swimPhase * 0.40 + Double(c.schoolIndex) * 1.9) * 0.25
        var desiredGX = leader.gx + c.boidTargetDX * scatterMult + wanderGX
        var desiredGY = leader.gy + c.boidTargetDY * scatterMult + wanderGY

        // 群内斥力分离，避免鱼群堆叠重叠
        for (otherIdx, other) in critterRuntimes.enumerated() where otherIdx != idx && other.kind == c.kind {
            let ddx = c.gx - other.gx
            let ddy = c.gy - other.gy
            let distSq = ddx * ddx + ddy * ddy
            if distSq > 0.0001 && distSq < 0.48 * 0.48 {
                let dist = sqrt(distSq)
                let push = (0.48 - dist) * 0.45
                desiredGX += (ddx / dist) * push
                desiredGY += (ddy / dist) * push
            }
        }

        desiredGX = max(0.6, min(Double(TerrariumConfig.gridCols) - 0.6, desiredGX))
        desiredGY = max(0.6, min(Double(TerrariumConfig.gridRows) - 0.6, desiredGY))
        let follow = (leader.behavior == .startle) ? min(0.18, c.boidFollowRate * 1.8) : c.boidFollowRate
        let prevPos = TerrariumConfig.isoToScreen(gx: c.gx, gy: c.gy)
        c.gx += (desiredGX - c.gx) * follow
        c.gy += (desiredGY - c.gy) * follow
        let newPos = TerrariumConfig.isoToScreen(gx: c.gx, gy: c.gy)

        if abs(newPos.x - prevPos.x) > 0.08 {
            c.facingRight = newPos.x >= prevPos.x
        } else if c.behavior == .eating || c.behavior == .idle {
            c.facingRight = leader.facingRight
        }

        updateSmoothAltitude(&c)
        critterRuntimes[idx] = c
    }

    private func emitAquaticBubbles(state: TerrariumState) {
        guard state.currentBiome == .aquatic, !state.isSleeping else { return }

        // 1. 游鱼低频慢吐气泡（每 3.7 ~ 8.3 秒仅偶发 1 颗极小气珠）
        for idx in critterRuntimes.indices {
            let c = critterRuntimes[idx]
            let isBubbleEmitterFish = (c.kind == .bettaFish) || (c.kind == .neonTetra && (c.isLeader || c.schoolIndex == 2))
            guard isBubbleEmitterFish else { continue }
            critterRuntimes[idx].bubbleCooldownTicks -= 1
            if critterRuntimes[idx].bubbleCooldownTicks <= 0 {
                critterRuntimes[idx].bubbleCooldownTicks = Int.random(in: 55...125)
                let mouthGX = max(0.4, min(Double(TerrariumConfig.gridCols) - 0.4, c.gx + (c.facingRight ? 0.25 : -0.25)))
                let startGZ = min(TerrariumConfig.waterSurfaceGZ - 4.0, max(2.0, c.gz + 1.5))
                let pt = TerrariumConfig.isoToScreen(gx: mouthGX, gy: c.gy, gz: startGZ)
                appendParticle(PixelParticle(
                    x: pt.x,
                    y: pt.y,
                    vx: 0,
                    vy: 0,
                    kind: .bubble,
                    life: 240,
                    gx: mouthGX,
                    gy: c.gy,
                    gz: startGZ,
                    vz: Double.random(in: 0.20...0.27),
                    wobblePhase: Double.random(in: 0..<(2.0 * .pi))
                ))
            }
        }

        // 2. 冒泡火山石启用的低频缓慢串泡（每 1.3 ~ 2.4 秒 1 颗）
        if state.enabledDecorIDs.contains("aquatic_bubble_rock") {
            rockBubbleCooldownTicks -= 1
            if rockBubbleCooldownTicks <= 0 {
                rockBubbleCooldownTicks = Int.random(in: 20...36)
                let origin = TerrariumConfig.effectiveDecorOrigin(for: "aquatic_bubble_rock", decorOrigins: state.decorOrigins)
                let ventGX = Double(origin.col) + 0.95 + Double.random(in: -0.15...0.15)
                let ventGY = Double(origin.row) + 0.95 + Double.random(in: -0.15...0.15)
                let startGZ = 9.0
                let pt = TerrariumConfig.isoToScreen(gx: ventGX, gy: ventGY, gz: startGZ)
                appendParticle(PixelParticle(
                    x: pt.x,
                    y: pt.y,
                    vx: 0,
                    vy: 0,
                    kind: .bubble,
                    life: 240,
                    gx: ventGX,
                    gy: ventGY,
                    gz: startGZ,
                    vz: Double.random(in: 0.23...0.31),
                    wobblePhase: Double.random(in: 0..<(2.0 * .pi))
                ))
            }
        }
    }

    private func shouldSeekFood(kind: CritterKind, state: TerrariumState) -> Bool {
        guard state.foodBowlPortions > 0 else { return false }
        let critter = state.critters.first(where: { $0.kind == kind })
        let isVisitor = (critter?.residency == .visitor)
        let hunger = critter?.hunger ?? 0
        return isVisitor || hunger >= 35.0 || (justFedBoostTicks > 0 && hunger >= 5.0)
    }

    private func pickPatrolPath(from start: GridCoord, kind: CritterKind, state: TerrariumState, blocked: Set<GridCoord>) -> [GridCoord]? {
        // 有一定概率（好感越高概率越高）主动巡游到专属生态位摆件旁休整
        let affinity = state.critters.first(where: { $0.kind == kind })?.affinity ?? 0
        let nicheChance = TerrariumConfig.affinityStage(for: affinity) >= .familiar ? 0.45 : 0.25
        if Double.random(in: 0...1) < nicheChance,
           let nicheGoal = TerrariumConfig.nicheSpot(for: kind, enabledDecorIDs: state.enabledDecorIDs, decorOrigins: state.decorOrigins),
           nicheGoal != start,
           !blocked.contains(nicheGoal) {
            let path = GridPathfinder.findPath(from: start, to: nicheGoal, blocked: blocked)
            if !path.isEmpty {
                return path
            }
        }

        for _ in 0..<6 {
            let dc = Int.random(in: -3...3)
            let dr = Int.random(in: -3...3)
            if dc == 0 && dr == 0 { continue }
            let goal = GridCoord(
                col: max(0, min(TerrariumConfig.gridCols - 1, start.col + dc)),
                row: max(0, min(TerrariumConfig.gridRows - 1, start.row + dr))
            )
            guard !blocked.contains(goal) else { continue }
            let path = GridPathfinder.findPath(from: start, to: goal, blocked: blocked)
            if !path.isEmpty {
                return path
            }
        }
        return nil
    }

    // MARK: - 玩家点击动物（轻抚/连点受惊）与植物（选择/移栽）

    func handleTap(atLogicalPoint pt: CGPoint) {
        guard let state = boundState, !state.isSleeping else { return }

        // 1. 若处于植物移栽或摆件位置调整模式，优先响应格子点击（睡莲按水面 gz=38 反向投影）
        if state.isMovingPlant {
            let plantGZ = (state.selectedPlant?.speciesID == "lotus") ? TerrariumConfig.waterSurfaceGZ : 0.0
            let iso = TerrariumConfig.screenToIso(x: pt.x, y: pt.y, gz: plantGZ)
            let coord = GridCoord(col: Int(floor(iso.gx)), row: Int(floor(iso.gy)))
            state.moveSelectedPlant(to: coord)
            return
        }

        if state.movingDecorID != nil {
            let iso = TerrariumConfig.screenToIso(x: pt.x, y: pt.y)
            let coord = GridCoord(col: Int(floor(iso.gx)), row: Int(floor(iso.gy)))
            state.moveSelectedDecor(to: coord)
            return
        }

        // 2a. 最优先：水面浮水植物（迷你睡莲，处于水体图层之上 gz = 38.0），避免穿点到后方缸底
        let surfaceIso = TerrariumConfig.screenToIso(x: pt.x, y: pt.y, gz: TerrariumConfig.waterSurfaceGZ)
        let surfaceCoord = GridCoord(col: Int(floor(surfaceIso.gx)), row: Int(floor(surfaceIso.gy)))
        let floatingPlants = state.plants
            .filter { TerrariumConfig.plantSurfaceGZ(for: $0) > 0 }
            .sorted { ($0.coord.col + $0.coord.row) > ($1.coord.col + $1.coord.row) }
        if let hitFloating = floatingPlants.first(where: { plant in
            if plant.coord == surfaceCoord { return true }
            let pPos = TerrariumConfig.isoToScreen(
                gx: Double(plant.coord.col) + 0.5,
                gy: Double(plant.coord.row) + 0.5,
                gz: TerrariumConfig.plantSurfaceGZ(for: plant)
            )
            let dx = pt.x - pPos.x
            let dy = pt.y - (pPos.y - 3.0)
            return dx * dx + dy * dy <= 11.5 * 11.5
        }) {
            state.selectPlant(hitFloating.id)
            return
        }

        // 2b. 命中动物：五阶好感度轻抚与连点受惊（受 Lv.4+ 耐受与动画互斥保护，0 刷点）
        let now = Date()
        for idx in critterRuntimes.indices.reversed() {
            let c = critterRuntimes[idx]
            let screenPos = TerrariumConfig.isoToScreen(gx: c.gx, gy: c.gy, gz: c.gz)
            let dx = pt.x - screenPos.x
            let dy = pt.y - (screenPos.y - 4.0)
            let hitRadius = (c.kind == .bettaFish) ? 16.0 : 14.0
            if dx * dx + dy * dy <= hitRadius * hitRadius {
                state.selectPlant(nil)
                state.selectDecor(nil)
                // 正在受惊期间忽略点击防连点；正在轻抚播放中也忽略重入计次
                if c.behavior == .startle || c.behavior == .petted {
                    return
                }

                let curAffinity = state.critters.first(where: { $0.kind == c.kind })?.affinity ?? 0
                let stage = TerrariumConfig.affinityStage(for: curAffinity)
                let startleLimit = (stage >= .trusted) ? 4 : 3

                var stamps = (recentTapTimestamps[c.kind] ?? []).filter { now.timeIntervalSince($0) <= 1.5 }
                stamps.append(now)
                recentTapTimestamps[c.kind] = stamps

                let isStartle = (stamps.count >= startleLimit)
                if isStartle {
                    recentTapTimestamps[c.kind] = []
                }

                // 群游生物（如红绿灯鱼）所有成员同步响应，其余单个响应
                for rIdx in critterRuntimes.indices where critterRuntimes[rIdx].kind == c.kind {
                    critterRuntimes[rIdx].behavior = isStartle ? .startle : .petted
                    critterRuntimes[rIdx].stateTicks = 0
                    critterRuntimes[rIdx].path.removeAll()
                    critterRuntimes[rIdx].hopProgress = 0
                }

                if isStartle {
                    state.recordCritterStartle(kind: c.kind, now: now)
                    let reactText: String
                    switch c.kind {
                    case .snail: reactText = "缩壳!"
                    case .pillBug: reactText = "缩成球!"
                    case .rhinoBeetle, .herculesBeetle: reactText = "扬角!"
                    case .leafInsect: reactText = "拟态晃!"
                    case .chameleon: reactText = "虹彩!"
                    case .crayfish: reactText = "举螯!"
                    case .bettaFish: reactText = "展鳍!"
                    case .cherryShrimp: reactText = "弹尾!"
                    case .neonTetra: reactText = "散游!"
                    default: reactText = "!"
                    }
                    appendParticle(PixelParticle(x: screenPos.x, y: screenPos.y - 16, vx: 0, vy: -0.45, kind: .popup, life: 22, text: reactText))
                } else {
                    let outcome = state.petCritter(kind: c.kind, at: CGPoint(x: screenPos.x, y: screenPos.y - 16), now: now)
                    let isSoulmate = (stage == .soulmate)
                    let heartSymbol: String
                    let sparkleCount: Int
                    switch outcome {
                    case .gained(_, let newStage, let leveledUp):
                        heartSymbol = (newStage == .soulmate) ? "💛" : "♥"
                        sparkleCount = leveledUp ? 8 : 4
                    case .onCooldown, .dailyLimitReached, .recoveringFromStartle:
                        heartSymbol = isSoulmate ? "💛" : "♥"
                        sparkleCount = 0
                    }
                    appendParticle(PixelParticle(x: screenPos.x, y: screenPos.y - 15, vx: 0, vy: -0.42, kind: .popup, life: 24, text: heartSymbol))
                    for _ in 0..<sparkleCount {
                        appendParticle(PixelParticle(
                            x: screenPos.x + Double.random(in: -5...5),
                            y: screenPos.y - 8,
                            vx: Double.random(in: -0.15...0.15),
                            vy: Double.random(in: -0.5 ... -0.2),
                            kind: .sparkle,
                            life: 18
                        ))
                    }
                }
                return
            }
        }

        // 3. 命中水底/地面植物或已摆放摆件：唤醒移栽 / 移动位置操作条
        let iso = TerrariumConfig.screenToIso(x: pt.x, y: pt.y)
        let tappedCoord = GridCoord(col: Int(floor(iso.gx)), row: Int(floor(iso.gy)))
        if let hitPlant = state.plants.filter({ TerrariumConfig.plantSurfaceGZ(for: $0) == 0 }).first(where: { plant in
            if plant.coord == tappedCoord { return true }
            let pPos = TerrariumConfig.isoToScreen(gx: Double(plant.coord.col) + 0.5, gy: Double(plant.coord.row) + 0.5)
            let dx = pt.x - pPos.x
            let dy = pt.y - (pPos.y - 6.0)
            return dx * dx + dy * dy <= 10.0 * 10.0
        }) {
            state.selectPlant(hitPlant.id)
        } else if let hitDecor = state.decorItems.first(where: { decor in
            guard decor.enabled else { return false }
            let fp = TerrariumConfig.footprint(for: decor.id, decorOrigins: state.decorOrigins)
            if fp.contains(tappedCoord) { return true }
            let gp = TerrariumConfig.anchorGridPos(for: decor.id, decorOrigins: state.decorOrigins)
            let dPos = TerrariumConfig.isoToScreen(gx: gp.gx, gy: gp.gy)
            let dx = pt.x - dPos.x
            let dy = pt.y - (dPos.y - 8.0)
            return dx * dx + dy * dy <= 14.0 * 14.0
        }) {
            state.selectDecor(hitDecor.id)
        } else {
            state.selectPlant(nil)
            state.selectDecor(nil)
        }
    }

    // MARK: - VFX 粒子生成（精准投喂至食盆碗心）

    func handleVFX(_ event: VFXEvent) {
        switch event {
        case .syncCritters:
            syncCrittersFromState()
        case .mist:
            justMistedTicks = 75
            guard isRunning else { return }
            for _ in 0..<22 {
                appendParticle(PixelParticle(
                    x: Double.random(in: 36...188),
                    y: Double.random(in: 22...50),
                    vx: Double.random(in: -0.15...0.15),
                    vy: Double.random(in: 1.0...1.8),
                    kind: .drop,
                    life: 44
                ))
            }
        case .feed(let bowlPos):
            justFedBoostTicks = 240
            guard isRunning else { return }
            // 食物颗粒从食盆正上方精准落入食盆碗心 (bowlPos.x, bowlPos.y)
            for _ in 0..<5 {
                appendParticle(PixelParticle(
                    x: bowlPos.x + Double.random(in: -2.0...2.0),
                    y: bowlPos.y - Double.random(in: 14...20),
                    vx: 0,
                    vy: Double.random(in: 0.9...1.3),
                    kind: .food,
                    life: 16,
                    targetY: bowlPos.y
                ))
            }
        case .clean:
            guard isRunning else { return }
            for _ in 0..<14 {
                appendParticle(PixelParticle(
                    x: Double.random(in: 36...188),
                    y: Double.random(in: 42...132),
                    vx: Double.random(in: -0.12...0.12),
                    vy: Double.random(in: -0.55 ... -0.25),
                    kind: .sparkle,
                    life: 26
                ))
            }
        case .ecoPopup(let text, let pt):
            guard isRunning else { return }
            appendParticle(PixelParticle(x: pt.x, y: pt.y, vx: 0, vy: -0.45, kind: .popup, life: 30, text: text))
        }
    }

    private func updateParticles() {
        var nextParticles: [PixelParticle] = []
        nextParticles.reserveCapacity(min(particles.count, maxParticles))

        for var p in particles {
            p.life -= 1
            p.age += 1

            switch p.kind {
            case .bubble:
                if !p.isPopping {
                    // 0.8s 缓升起步 -> 缓慢匀速上浮 -> 触及水面 gz=38.0 破灭成微环
                    let ramp = min(1.0, Double(p.age) / 12.0)
                    p.gz += p.vz * (0.35 + 0.65 * ramp)
                    let swayX = sin(Double(p.age) * 0.16 + p.wobblePhase) * 0.9
                    let clampedGZ = min(TerrariumConfig.waterSurfaceGZ, p.gz)
                    let pt = TerrariumConfig.isoToScreen(gx: p.gx, gy: p.gy, gz: clampedGZ)
                    p.x = max(0.0, min(TerrariumConfig.stageLogicalWidth, pt.x + swayX))
                    p.y = max(0.0, min(TerrariumConfig.stageLogicalHeight, pt.y))
                    if p.gz >= TerrariumConfig.waterSurfaceGZ {
                        p.gz = TerrariumConfig.waterSurfaceGZ
                        p.isPopping = true
                        p.life = 6
                    }
                }
            case .drop:
                p.x = max(0.0, min(TerrariumConfig.stageLogicalWidth, p.x + p.vx))
                p.y = max(0.0, min(TerrariumConfig.stageLogicalHeight, p.y + p.vy))
                p.vy = min(2.4, p.vy + 0.08)
                if p.y >= 112.0 && p.life < 20 {
                    if nextParticles.count + 2 <= maxParticles {
                        nextParticles.append(PixelParticle(x: p.x - 1, y: p.y, vx: -0.4, vy: -0.5, kind: .splash, life: 7))
                        nextParticles.append(PixelParticle(x: p.x + 1, y: p.y, vx: 0.4, vy: -0.5, kind: .splash, life: 7))
                    }
                    p.life = 0
                }
            case .food:
                p.x = max(0.0, min(TerrariumConfig.stageLogicalWidth, p.x + p.vx))
                p.y = max(0.0, min(TerrariumConfig.stageLogicalHeight, p.y + p.vy))
                if p.vy < 0.6 {
                    // 鱼缸浮水圈掉落的缓沉碎屑：缓慢下沉到底部后融合
                    p.vy = min(0.85, p.vy + 0.02)
                } else {
                    p.vy = min(1.8, p.vy + 0.14)
                }
                if p.y >= p.targetY {
                    p.y = p.targetY
                    p.life = min(p.life, 2)
                }
            case .splash:
                p.x = max(0.0, min(TerrariumConfig.stageLogicalWidth, p.x + p.vx))
                p.y = max(0.0, min(TerrariumConfig.stageLogicalHeight, p.y + p.vy))
                p.vy += 0.12
            case .sparkle, .popup:
                p.x = max(0.0, min(TerrariumConfig.stageLogicalWidth, p.x + p.vx))
                p.y = max(0.0, min(TerrariumConfig.stageLogicalHeight, p.y + p.vy))
            }

            if p.life > 0 {
                nextParticles.append(p)
            }
        }
        if nextParticles.count > maxParticles {
            nextParticles = Array(nextParticles.suffix(maxParticles))
        }
        particles = nextParticles
    }

    private func appendParticle(_ particle: PixelParticle) {
        if particle.kind == .bubble {
            let bubbleCount = particles.reduce(into: 0) { count, item in
                if item.kind == .bubble { count += 1 }
            }
            guard bubbleCount < maxBubbleParticles, particles.count < maxParticles - 8 else {
                return
            }
        }
        while particles.count >= maxParticles {
            if let bubbleIdx = particles.firstIndex(where: { $0.kind == .bubble }) {
                particles.remove(at: bubbleIdx)
            } else {
                particles.removeFirst()
            }
        }
        particles.append(particle)
    }
}
