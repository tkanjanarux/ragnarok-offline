import Foundation
import RagnarokPackets

struct EquipmentSwitchState {
    var entries: [Int: UInt32] = [:]
    var visible = false
    var compareIndex: Int?
    var message: String?
    struct Pending {
        var token = UUID()
        var index: Int?
        var removing = false
    }
    var pending: Pending?
    mutating func receive(_ packet: EquipmentSwitchResult) {
        let index = Int(packet.index)
        if packet.result == 0 {
            if packet.type == 0xa98 { entries[index] = packet.position }
            else if packet.type == 0xa9a { entries.removeValue(forKey: index) }
        }
        if pending?.index == index && pending?.removing == (packet.type == 0xa9a) {
            pending = nil
            message = packet.result == 0 ? "Equipment switch list updated." : "The server rejected this equipment."
        }
    }
}

extension PlaySession {
    func changeSwitchEquipment(index: Int, remove: Bool) {
        guard !rodex.busy, !trade.active, trade.waiting == nil, equipmentSwitch.pending == nil, cart.pending == nil, itemSelection.pending == nil, refine.pending == nil,
              let item = inventory.items[index], let wireIndex = UInt16(exactly: index),
              item.isIdentified, item.isEquippable else { return }
        if remove {
            guard equipmentSwitch.entries[index] != nil else { return }
            sendFoundationPacket(EquipmentSwitchRequest.remove(index: wireIndex))
        } else {
            guard !item.location.isEmpty, !item.isEquipped, let location = UInt32(exactly: item.location.rawValue) else { return }
            sendFoundationPacket(EquipmentSwitchRequest.add(index: wireIndex, position: location))
        }
        equipmentSwitch.pending = .init(index: index, removing: remove)
        scheduleSwitchTimeout()
    }
    func requestEquipmentSwitch() {
        guard !rodex.busy, !trade.active, trade.waiting == nil, equipmentSwitch.pending == nil, !equipmentSwitch.entries.isEmpty,
              cart.pending == nil, itemSelection.pending == nil, refine.pending == nil else { return }
        equipmentSwitch.pending = .init(index: nil)
        sendFoundationPacket(EquipmentSwitchRequest.swap)
        scheduleSwitchTimeout()
    }
    private func scheduleSwitchTimeout() {
        equipmentSwitch.message = "Waiting for the server…"
        let token = equipmentSwitch.pending?.token
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, let token, self.equipmentSwitch.pending?.token == token else { return }
            self.equipmentSwitch.message = "No server reply. Reconnect before trying again."
        }
    }
}
