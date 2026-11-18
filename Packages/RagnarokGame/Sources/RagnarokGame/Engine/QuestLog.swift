import Foundation
import RagnarokPackets

struct QuestObjective: Identifiable {
    var id: UInt32
    var name: String
    var current: Int
    var required: Int
}
struct QuestEntry: Identifiable {
    var id: UInt32
    var state: UInt8
    var expires: UInt32
    var objectives: [QuestObjective]
}
private struct QuestReader {
    let bytes: [UInt8]
    var offset = 2
    mutating func number(_ count: Int) throws -> UInt32 {
        guard offset + count <= bytes.count else { throw CocoaError(.fileReadCorruptFile) }
        defer { offset += count }
        return (0..<count).reduce(0) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }
    mutating func name() throws -> String {
        guard offset + 24 <= bytes.count else { throw CocoaError(.fileReadCorruptFile) }
        defer { offset += 24 }
        return String(decoding: bytes[offset..<offset+24].prefix { $0 != 0 }, as: UTF8.self)
    }
    mutating func entry(adding: Bool) throws -> QuestEntry {
        let id = try number(4), state = try number(1)
        _ = try number(4)
        let expires = try number(4), count = try number(2)
        guard count <= 100 else { throw CocoaError(.fileReadCorruptFile) }
        var objectives: [QuestObjective] = []
        for _ in 0..<count {
            let hunt = try number(4)
            _ = try number(4); _ = try number(4)
            _ = try number(2); _ = try number(2)
            let current = try number(2)
            let required = adding ? 0 : try number(2)
            let label = try name()
            objectives.append(.init(id: hunt, name: label, current: Int(current), required: Int(required)))
        }
        return .init(id: id, state: UInt8(state), expires: expires, objectives: objectives)
    }
}
enum QuestLogDecoder {
    static func applying(_ packet: QuestWirePacket, to quests: [UInt32: QuestEntry]) -> [UInt32: QuestEntry] {
        // Parse into a copy: malformed packets must not partially alter the log.
        var next = quests
        var reader = QuestReader(bytes: packet.bytes)
        do {
            switch packet.type {
            case 0x9f8:
                _ = try reader.number(2)
                let count = try reader.number(4)
                guard count <= 10000 else { return quests }
                next = [:]
                for _ in 0..<count {
                    let quest = try reader.entry(adding: false)
                    next[quest.id] = quest
                }
            case 0x9f9:
                let quest = try reader.entry(adding: true)
                next[quest.id] = quest
            case 0x2b4:
                next.removeValue(forKey: try reader.number(4))
            case 0x2b7:
                let id = try reader.number(4)
                next[id]?.state = UInt8(try reader.number(1))
            case 0x9fa, 0x8fe:
                let length = try reader.number(2)
                let count = packet.type == 0x9fa ? try reader.number(2) : (length - 4) / 12
                guard count <= 10000 else { return quests }
                for _ in 0..<count {
                    let first = try reader.number(4), second = try reader.number(4)
                    let required = try reader.number(2), current = try reader.number(2)
                    let id = packet.type == 0x9fa ? first : first / 1000
                    let hunt = packet.type == 0x9fa ? second : first
                    if let i = next[id]?.objectives.firstIndex(where: { $0.id == hunt }) {
                        next[id]?.objectives[i].required = Int(required)
                        next[id]?.objectives[i].current = Int(current)
                    }
                }
            default: return quests
            }
            return next
        } catch { return quests }
    }
}

extension PlaySession {
    func applyQuestPacket(_ packet: QuestWirePacket) {
        quests = QuestLogDecoder.applying(packet, to: quests)
    }
}
