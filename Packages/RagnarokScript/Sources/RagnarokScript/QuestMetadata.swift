import Foundation
import RagnarokCore
import RagnarokLua
import RagnarokResources

/// Client resource descriptions, not server-authoritative rewards or quest state.
public struct QuestMetadata: Sendable {
    public struct Reward: Sendable {
        public var itemID: Int
        public var count: Int
    }
    public var title = ""
    public var summary = ""
    public var description = ""
    public var icon = "ico_nq.bmp"
    public var npcMap = ""
    public var npcX = 0
    public var npcY = 0
    public var rewardEXP: Int?
    public var rewardJobEXP: Int?
    public var rewards: [Reward] = []
    public init() {}
}

struct QuestMetadataDecoder {
    static func lua(_ data: Data) throws -> [UInt32: QuestMetadata] {
        let context = LuaContext()
        try context.load(data)
        guard let table = context["QuestInfoList"].tableValue else { return [:] }
        var result: [UInt32: QuestMetadata] = [:]
        func text(_ value: LuaValue?) -> String {
            value?.string(using: .utf8) ?? value?.string(using: .dosKorean) ?? value?.stringValue ?? ""
        }
        for (key, entry) in table {
            guard let integer = key.intValue, let id = UInt32(exactly: integer) else { continue }
            var info = QuestMetadata()
            info.title = text(entry["Title"])
            info.summary = text(entry["Summary"])
            info.description = (entry["Description"]?.arrayValue ?? []).map { text($0) }.joined(separator: "\n")
            if info.description.isEmpty { info.description = text(entry["Description"]) }
            let icon = text(entry["IconName"])
            if !icon.isEmpty { info.icon = icon }
            info.npcMap = text(entry["NpcNavi"])
            info.npcX = entry["NpcPosX"]?.intValue ?? 0
            info.npcY = entry["NpcPosY"]?.intValue ?? 0
            info.rewardEXP = entry["RewardEXP"]?.intValue
            info.rewardJobEXP = entry["RewardJEXP"]?.intValue
            info.rewards = (entry["RewardItemList"]?.arrayValue ?? []).compactMap {
                guard let item = $0["ItemID"]?.intValue, let count = $0["ItemNum"]?.intValue else { return nil }
                return .init(itemID: item, count: count)
            }
            result[id] = info
        }
        return result
    }

    // questid2display.txt: ID#Title#Group#Image#Description#Summary#
    static func text(_ source: String) -> [UInt32: QuestMetadata] {
        let uncommented = source.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        let fields = uncommented.components(separatedBy: "#")
        var result: [UInt32: QuestMetadata] = [:]
        for offset in stride(from: 0, to: max(0, fields.count - 5), by: 6) {
            guard let id = UInt32(fields[offset].trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
            var info = QuestMetadata()
            info.title = fields[offset + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            info.description = fields[offset + 4].trimmingCharacters(in: .whitespacesAndNewlines)
            info.summary = fields[offset + 5].trimmingCharacters(in: .whitespacesAndNewlines)
            result[id] = info
        }
        return result
    }
}

extension ResourceManager {
    public func questMetadata() async -> [UInt32: QuestMetadata] {
        // Same paths and Lua 5.1 decoder used by the client's other resource tables.
        for directory in [["System"], ["system"], ["data", "System"], ["data", "system"]] {
            for ext in ["lub", "lua"] {
                let path = ResourcePath(components: directory + ["OngoingQuestInfoList.\(ext)"])
                if let data = try? await contentsOfResource(at: path),
                   let table = try? QuestMetadataDecoder.lua(data), !table.isEmpty { return table }
            }
        }
        guard let data = try? await contentsOfResource(at: ["data", "questid2display.txt"]),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .dosKorean) else { return [:] }
        return QuestMetadataDecoder.text(text)
    }
}
