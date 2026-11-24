import Foundation
import RagnarokCore
import RagnarokLua
import RagnarokResources

/// Client navigation metadata only. Monster rows identify spawn maps, not live entities.
public struct NavigationDestination: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable { case map = "Map", npc = "NPC", monster = "Monster", point = "Point" }
    public var id: String
    public var kind: Kind
    public var name: String
    public var map: String
    public var position: SIMD2<Int>?
    public init(id: String, kind: Kind, name: String, map: String, position: SIMD2<Int>? = nil) {
        self.id = id; self.kind = kind; self.name = name
        self.map = NavigationData.mapKey(map); self.position = position
    }
}

public struct NavigationPortal: Equatable, Sendable {
    public var id: String
    public var map: String
    public var position: SIMD2<Int>
    public var destinationMap: String
    public var destination: SIMD2<Int>
    public init(id: String, map: String, position: SIMD2<Int>, destinationMap: String, destination: SIMD2<Int>) {
        self.id = id; self.map = NavigationData.mapKey(map); self.position = position
        self.destinationMap = NavigationData.mapKey(destinationMap); self.destination = destination
    }
}

public struct NavigationData: Sendable {
    public var destinations: [NavigationDestination] = []
    public var portals: [NavigationPortal] = []
    public var sources: [String] = []
    public init() {}
    public static func mapKey(_ name: String) -> String {
        let value = name.lowercased()
        return value.hasSuffix(".gat") || value.hasSuffix(".rsw") ? String(value.dropLast(4)) : value
    }
    public func search(_ query: String, kind: NavigationDestination.Kind? = nil, currentMap: String) -> [NavigationDestination] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return destinations.filter {
            (kind == nil || $0.kind == kind) && (needle.isEmpty ? $0.map == Self.mapKey(currentMap) :
                $0.name.localizedCaseInsensitiveContains(needle) || $0.map.localizedCaseInsensitiveContains(needle))
        }.sorted { ($0.name, $0.map, $0.id) < ($1.name, $1.map, $1.id) }
    }

    /// Navi_Map/Npc/Mob/Link column contracts match roBrowserLegacy 2f9a9d6.
    /// Missing/invalid coordinates stay missing; service links 201...205 are excluded.
    public mutating func decode(_ bytes: Data, table: String) throws {
        let context = LuaContext()
        try context.load(bytes)
        let rows = context[table].arrayValue ?? context[table].tableValue?.values.map { $0 } ?? []
        func text(_ value: LuaValue) -> String {
            value.string(using: .utf8) ?? value.string(using: .dosKorean) ?? value.stringValue ?? ""
        }
        func position(_ row: [LuaValue], _ index: Int) -> SIMD2<Int>? {
            guard row.count > index + 1, let x = row[index].intValue, let y = row[index + 1].intValue,
                  (0...1023).contains(x), (0...1023).contains(y) else { return nil }
            return SIMD2(x, y)
        }
        for value in rows {
            guard let row = value.arrayValue, row.count >= 2 else { continue }
            let map = Self.mapKey(text(row[0]))
            guard !map.isEmpty, map.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { continue }
            switch table {
            case "Navi_Map":
                let name = text(row[1])
                destinations.append(.init(id: "map:\(map)", kind: .map, name: name.isEmpty ? map : name, map: map))
            case "Navi_Npc":
                guard row.count >= 8, let point = position(row, 6) else { continue }
                destinations.append(.init(id: "npc:\(map):\(row[1].intValue ?? -1):\(point.x):\(point.y)",
                    kind: .npc, name: text(row[4]), map: map, position: point))
            case "Navi_Mob":
                guard row.count >= 8 else { continue }
                destinations.append(.init(id: "mob:\(map):\(row[1].intValue ?? -1)", kind: .monster, name: text(row[4]), map: map))
            case "Navi_Link":
                guard row.count >= 11, row[2].intValue == 200,
                      let point = position(row, 6), let landing = position(row, 9) else { continue }
                let target = Self.mapKey(text(row[8]))
                guard !target.isEmpty, target.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { continue }
                portals.append(.init(id: "\(map):\(row[1].intValue ?? -1)", map: map,
                    position: point, destinationMap: target, destination: landing))
            default: break
            }
        }
        var ids = Set<String>()
        destinations = destinations.filter { !$0.name.isEmpty && ids.insert($0.id).inserted }
        ids = []
        portals = portals.filter { ids.insert($0.id).inserted }
    }
}

extension ResourceManager {
    public func navigationData() async -> NavigationData {
        var result = NavigationData()
        // Use one edition consistently. Do not combine conflicting portal graphs.
        for edition in ["krpri", "krsak"] {
            var candidate = NavigationData()
            for (file, table) in [("map", "Navi_Map"), ("npc", "Navi_Npc"), ("mob", "Navi_Mob"), ("link", "Navi_Link")] {
                for ext in ["lub", "lua"] {
                    if Task.isCancelled { return result }
                    let name = "navi_\(file)_\(edition).\(ext)"
                    let path = ResourcePath.scriptDirectory.appending(["navigation", name])
                    guard let bytes = try? await contentsOfResource(at: path) else { continue }
                    do {
                        try candidate.decode(bytes, table: table)
                        candidate.sources.append(path.description)
                        break
                    } catch { continue }
                }
            }
            if !candidate.destinations.isEmpty || !candidate.portals.isEmpty { result = candidate; break }
        }
        return result
    }
}
