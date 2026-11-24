import Foundation
import RagnarokPackets

struct PetState {
    enum Operation { case evolve, feed, hatch, capture, rename, returnEgg, autoFeed }
    var visible = false
    var actorID: UInt32?
    var info: PACKET_ZC_PROPERTY_PET?
    var eggs: [Int] = []
    var captureReady = false
    var requestedName: String?
    var autoFeed: Bool?
    var pending: Operation?
    var token: UUID?
    var message: String?
    mutating func finish(_ operation: Operation, message: String? = nil) {
        guard pending == operation else { return }
        pending = nil; token = nil; self.message = message
    }
    mutating func receive(_ p: PACKET_ZC_PROPERTY_PET) {
        info = p; eggs = []
        finish(.hatch)
        if pending == .rename {
            finish(.rename, message: p.szName == requestedName ? "Pet renamed." : "The server rejected this name.")
            requestedName = nil
        }
    }
    mutating func receive(_ p: PACKET_ZC_CHANGESTATE_PET) {
        let id = UInt32(bitPattern: p.GID)
        if p.type == 0 { actorID = id; return }
        guard actorID == id else { return }
        if p.type == 1 { info?.nRelationship = Int16(clamping: p.data) }
        if p.type == 2 { info?.nFullness = Int16(clamping: p.data) }
        if p.type == 3 { info?.ITID = Int16(clamping: p.data) }
    }
    mutating func vanished(_ id: UInt32) {
        guard actorID == id else { return }
        info = nil; actorID = nil; autoFeed = nil; finish(.returnEgg, message: "Pet returned to its egg.")
    }
}

extension PlaySession {
    func evolvePet(_ recipe: PetEvolutionRecipe) {
        guard let pet = pets.info, Int(pet.job) == recipe.base, pet.nRelationship >= 1000, pets.pending == nil,
              !trade.active, !rodex.busy, !buyingStore.busy, !vending.active, vending.purchase == nil,
              recipe.materials.allSatisfy({ material in inventory.items.values.filter { $0.itemID == material.id }.reduce(0) { $0 + $1.amount } >= material.amount }) else { return }
        waitForPet(.evolve); sendFoundationPacket(PetRequest.evolve(UInt32(recipe.egg)))
    }
    func petCommand(_ command: UInt8) {
        guard pets.info != nil, pets.pending == nil, !trade.active, bank.pending == nil else { return }
        if command == 1 { waitForPet(.feed) }
        if command == 3 { waitForPet(.returnEgg) }
        sendFoundationPacket(PetRequest.command(command))
    }
    func hatchPet(_ index: Int) {
        guard pets.pending == nil, pets.eggs.contains(index), inventory.items[index] != nil, let value = UInt16(exactly: index), !trade.active else { return }
        waitForPet(.hatch); sendFoundationPacket(PetRequest.hatch(value))
    }
    func captureSelectedMonster(cancel: Bool = false) {
        guard pets.captureReady, pets.pending == nil else { return }
        let target = mapScene?.selectedTarget
        guard cancel || target?.type == .monster else { pets.message = "Select a monster in the scene first."; return }
        pets.captureReady = false; waitForPet(.capture)
        sendFoundationPacket(PetRequest.capture(cancel ? 0 : target!.objectID))
    }
    func renamePet(_ name: String) {
        guard pets.info?.bModified == 0, pets.pending == nil, !name.isEmpty, name.utf8.count <= 23, !name.contains("\0") else { return }
        pets.requestedName = name
        waitForPet(.rename); sendFoundationPacket(PetRequest.rename(name))
    }
    func setPetAutoFeed(_ enabled: Bool) {
        guard pets.info != nil, pets.pending == nil else { return }
        waitForPet(.autoFeed); sendFoundationPacket(PetRequest.autoFeed(enabled))
    }
    private func waitForPet(_ operation: PetState.Operation) {
        let token = UUID(); pets.pending = operation; pets.token = token; pets.message = "Waiting for the server…"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.pets.token == token else { return }
            self.pets.message = "No server result. Reconnect to refresh your pet."
        }
    }
}
