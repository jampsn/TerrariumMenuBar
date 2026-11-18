import Foundation

/// 11x11 等距网格 4 方向 A* 寻路器（支持食盆四邻接槽位独占分配）
public enum GridPathfinder {
    private static let directions = [
        GridCoord(col: 1, row: 0),
        GridCoord(col: -1, row: 0),
        GridCoord(col: 0, row: 1),
        GridCoord(col: 0, row: -1)
    ]

    public static func isInsideGrid(_ coord: GridCoord) -> Bool {
        coord.col >= 0 && coord.col < TerrariumConfig.gridCols
            && coord.row >= 0 && coord.row < TerrariumConfig.gridRows
    }

    public static func manhattan(_ a: GridCoord, _ b: GridCoord) -> Int {
        abs(a.col - b.col) + abs(a.row - b.row)
    }

    public static func buildBlockedSet(
        enabledDecorIDs: [String],
        plants: [PlantInstance],
        decorOrigins: [String: GridCoord] = [:],
        biome: TerrariumBiome = .meadow
    ) -> Set<GridCoord> {
        var blocked = Set<GridCoord>()
        if biome != .aquatic {
            blocked.insert(TerrariumConfig.foodBowlCoord)
            // 陆生缸封锁食盆正前三格，确保动物巡逻与进食路径永不挡在食盆正前方
            blocked.formUnion(TerrariumConfig.foodBowlForwardCoords)
        }

        for decorID in enabledDecorIDs where TerrariumConfig.decorBlocksMovement(decorID) {
            for coord in TerrariumConfig.footprint(for: decorID, decorOrigins: decorOrigins) {
                blocked.insert(coord)
            }
        }

        for plant in plants {
            let isTall = (plant.speciesID == "fern" || plant.speciesID == "succulent" || plant.speciesID == "cactus" || plant.speciesID == "aloe" || plant.speciesID == "monstera" || plant.speciesID == "orchid" || plant.speciesID == "anubias")
            let isGrown = (plant.stage == .mature || plant.stage == .lushDew || plant.stage == .wilting)
            if isTall && isGrown {
                blocked.insert(plant.coord)
            }
        }
        return blocked
    }

    public static func buildNonPlantableSet(
        enabledDecorIDs: [String],
        plants: [PlantInstance],
        decorOrigins: [String: GridCoord] = [:],
        biome: TerrariumBiome = .meadow
    ) -> Set<GridCoord> {
        var occupied = TerrariumConfig.feedingProtectedCoords(for: biome)
        for decorID in enabledDecorIDs {
            for coord in TerrariumConfig.footprint(for: decorID, decorOrigins: decorOrigins) {
                occupied.insert(coord)
            }
        }
        for plant in plants {
            occupied.insert(plant.coord)
        }
        return occupied
    }

    /// 校验多格摆件能否摆放到目标左上角格 origin（不能出界、不能侵犯食盆/喂食圈净空区、不能与其他已启用摆件或植物重叠）
    public static func canPlaceDecor(
        id decorID: String,
        at origin: GridCoord,
        enabledDecorIDs: [String],
        decorOrigins: [String: GridCoord],
        plants: [PlantInstance],
        biome: TerrariumBiome = .meadow
    ) -> Bool {
        var tempOrigins = decorOrigins
        tempOrigins[decorID] = origin
        let candidateCells = TerrariumConfig.footprint(for: decorID, decorOrigins: tempOrigins)
        guard !candidateCells.isEmpty else { return false }

        var forbidden = TerrariumConfig.feedingProtectedCoords(for: biome)
        for otherID in enabledDecorIDs where otherID != decorID {
            for coord in TerrariumConfig.footprint(for: otherID, decorOrigins: decorOrigins) {
                forbidden.insert(coord)
            }
        }
        for plant in plants {
            forbidden.insert(plant.coord)
        }

        for cell in candidateCells {
            if !isInsideGrid(cell) || forbidden.contains(cell) {
                return false
            }
        }
        return true
    }

    /// 陆生食盆优先选择后方槽位(col+row < bowlDepth)；鱼缸后方浮圈 (1,2) 优先选择前景水区槽位(col+row > bowlDepth)
    public static func findPathToFoodBowl(
        from start: GridCoord,
        blocked: Set<GridCoord>,
        reservedSlots: Set<GridCoord> = [],
        biome: TerrariumBiome = .meadow
    ) -> [GridCoord] {
        let bowl = TerrariumConfig.feedingCoord(for: biome)
        let bowlDepth = bowl.col + bowl.row
        let allCandidates = directions
            .map { GridCoord(col: bowl.col + $0.col, row: bowl.row + $0.row) }
            .filter { isInsideGrid($0) && (!blocked.contains($0) || $0 == start) }

        let preferredSlots = allCandidates.filter {
            (biome == .aquatic) ? (($0.col + $0.row) > bowlDepth) : (($0.col + $0.row) < bowlDepth)
        }
        let preferredUnreserved = preferredSlots.filter { !reservedSlots.contains($0) || $0 == start }
        let unreserved = allCandidates.filter { !reservedSlots.contains($0) || $0 == start }

        let primaryPool: [GridCoord]
        if !preferredUnreserved.isEmpty {
            primaryPool = preferredUnreserved
        } else if !preferredSlots.isEmpty {
            primaryPool = preferredSlots
        } else if !unreserved.isEmpty {
            primaryPool = unreserved
        } else {
            primaryPool = allCandidates
        }

        let ordered = primaryPool.sorted { manhattan(start, $0) < manhattan(start, $1) }

        for target in ordered {
            if target == start {
                return [start]
            }
            let path = findPath(from: start, to: target, blocked: blocked)
            if !path.isEmpty {
                return path
            }
        }
        return []
    }

    public static func findPath(from start: GridCoord, to goal: GridCoord, blocked: Set<GridCoord>) -> [GridCoord] {
        guard isInsideGrid(start), isInsideGrid(goal) else { return [] }
        if start == goal { return [start] }
        if blocked.contains(goal) { return [] }

        var openSet: Set<GridCoord> = [start]
        var cameFrom: [GridCoord: GridCoord] = [:]
        var gScore: [GridCoord: Int] = [start: 0]
        var fScore: [GridCoord: Int] = [start: manhattan(start, goal)]

        while !openSet.isEmpty {
            guard let current = openSet.min(by: { (fScore[$0] ?? Int.max) < (fScore[$1] ?? Int.max) }) else {
                break
            }
            if current == goal {
                var path: [GridCoord] = []
                var cursor: GridCoord? = current
                while let node = cursor, node != start {
                    path.append(node)
                    cursor = cameFrom[node]
                }
                return path.reversed()
            }

            openSet.remove(current)
            let currentG = gScore[current] ?? Int.max

            for dir in directions {
                let neighbor = GridCoord(col: current.col + dir.col, row: current.row + dir.row)
                guard isInsideGrid(neighbor) else { continue }
                if blocked.contains(neighbor) && neighbor != goal { continue }

                let tentativeG = currentG + 1
                if tentativeG < (gScore[neighbor] ?? Int.max) {
                    cameFrom[neighbor] = current
                    gScore[neighbor] = tentativeG
                    fScore[neighbor] = tentativeG + manhattan(neighbor, goal)
                    openSet.insert(neighbor)
                }
            }
        }
        return []
    }
}
