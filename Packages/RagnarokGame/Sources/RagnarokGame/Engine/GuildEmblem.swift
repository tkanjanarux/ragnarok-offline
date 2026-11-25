import Foundation
import RagnarokPackets
import zlib

extension PlaySession {
    func uploadGuildEmblem(_ bitmap: Data) {
        guard guild.master, guild.id != nil, guild.pending == nil else { return }
        guard GuildBitmap.isValid(bitmap) else { guild.message = "Choose a 24 × 24 BMP emblem (8-bit or 24-bit, up to 1782 bytes)."; return }
        var length = uLongf(compressBound(uLong(bitmap.count)))
        var compressed = [UInt8](repeating: 0, count: Int(length))
        let result = bitmap.withUnsafeBytes { source in
            compressed.withUnsafeMutableBytes { destination in
                compress2(destination.bindMemory(to: UInt8.self).baseAddress, &length,
                          source.bindMemory(to: UInt8.self).baseAddress, uLong(bitmap.count), Z_BEST_COMPRESSION)
            }
        }
        guard result == Z_OK, length <= 2048 else { guild.message = "This emblem could not be loaded."; return }
        compressed.removeLast(compressed.count - Int(length))
        guild.submittedEmblem = Array(bitmap); waitForGuild(.emblem)
        sendFoundationPacket(GuildRequest.uploadEmblem(compressed))
    }
    func receiveGuildEmblem(_ packet: GuildEmblemPacket) {
        guard packet.guildID == guild.id, packet.version >= guild.emblemVersion else { return }
        var bitmap = [UInt8](repeating: 0, count: 1800)
        var length = uLongf(bitmap.count)
        let result = packet.compressed.withUnsafeBytes { source in
            bitmap.withUnsafeMutableBytes { destination in
                uncompress(destination.bindMemory(to: UInt8.self).baseAddress, &length,
                           source.bindMemory(to: UInt8.self).baseAddress, uLong(packet.compressed.count))
            }
        }
        guard result == Z_OK else { guild.message = "The guild emblem could not be loaded."; return }
        bitmap.removeLast(bitmap.count - Int(length))
        guard GuildBitmap.isValid(Data(bitmap)) else { return }
        let newer = packet.version > guild.emblemVersion
        guild.emblemVersion = packet.version; guild.emblemBitmap = Data(bitmap)
        if newer, guild.pending == .emblem, guild.submittedEmblem == bitmap {
            guild.submittedEmblem = nil; guild.finish(.emblem, message: "Guild emblem updated.")
        }
    }
}
