import SwiftUI

struct PetView: View {
    @Environment(PlaySession.self) private var session
    @Environment(GameContext.self) private var context
    @State private var name = ""
    @State private var evolution: PetEvolutionRecipe?
    @State private var action: UInt8?
    var body: some View {
        GeometryReader { bounds in
            ClassicGamePanel(title: "Pet", width: min(410, bounds.size.width - 24), height: min(510, bounds.size.height - 24), onClose: { session.pets.visible = false }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if session.pets.captureReady {
                            Text("Select the monster you want to tame in the scene.")
                            Button("Capture selected monster") { session.captureSelectedMonster() }.frame(minHeight: 44)
                            Button("Cancel capture") { session.captureSelectedMonster(cancel: true) }.frame(minHeight: 44)
                        }
                        ForEach(session.pets.eggs, id: \.self) { index in
                            if let item = session.inventory.items[index] {
                                Button { session.hatchPet(index) } label: {
                                    HStack { InventoryItemView(item: item); Text(context.itemInfoTable.localizedIdentifiedItemName(forItemID: item.itemID) ?? "Pet egg") }
                                }.frame(minHeight: 44).disabled(session.pets.pending != nil)
                            }
                        }
                        if let pet = session.pets.info {
                            Text("\(pet.szName) · Lv. \(pet.nLevel)").fontWeight(.bold)
                            Text("Hunger: \(pet.nFullness) / 100")
                            ProgressView(value: Double(pet.nFullness), total: 100)
                            Text("Intimacy: \(pet.nRelationship)")
                            HStack {
                                Button("Feed") { action = 1 }
                                Button("Perform") { session.petCommand(2) }
                            }.frame(minHeight: 44).disabled(session.pets.pending != nil)
                            Button("Return to egg") { action = 3 }.frame(minHeight: 44).disabled(session.pets.pending != nil)
                            if pet.ITID != 0 { Button("Unequip accessory") { session.petCommand(4) }.frame(minHeight: 44) }
                            Button(session.pets.autoFeed == true ? "Disable auto feed" : "Enable auto feed") { session.setPetAutoFeed(session.pets.autoFeed != true) }
                                .frame(minHeight: 44).disabled(session.pets.pending != nil)
                            DisclosureGroup("Evolution") {
                                let recipes = PetEvolutionRecipe.all.filter { $0.base == Int(pet.job) }
                                if recipes.isEmpty { Text("No evolution recipe is available for this pet.") }
                                ForEach(recipes) { recipe in
                                    Text(context.itemInfoTable.localizedIdentifiedItemName(forItemID: recipe.egg) ?? "Pet egg \(recipe.egg)")
                                    ForEach(recipe.materials,id: \.id) { material in
                                        Text("\(context.itemInfoTable.localizedIdentifiedItemName(forItemID: material.id) ?? "Item \(material.id)") ×\(material.amount)")
                                    }
                                    Button("Evolve") { evolution = recipe }.frame(minHeight: 44).disabled(pet.nRelationship < 1000 || session.pets.pending != nil)
                                }
                                Text("Requires 1000 intimacy. Materials are consumed on evolution.")
                            }
                            if pet.bModified == 0 {
                                TextField("Pet name", text: $name).textFieldStyle(.roundedBorder)
                                Button("Rename") { session.renamePet(name) }.frame(minHeight: 44).disabled(name.isEmpty || session.pets.pending != nil)
                            }
                        } else if session.pets.eggs.isEmpty && !session.pets.captureReady {
                            Text("No active pet information. Use a pet incubator to hatch an egg, or a taming item to capture a monster.")
                        }
                        if let message = session.pets.message { Text(message) }
                    }.padding(12)
                }.font(.game(size: 13)).buttonStyle(.game)
            }
        }
        .confirmationDialog("Evolve this pet and consume the listed materials?", isPresented: Binding(get: { evolution != nil },set: { if !$0 { evolution = nil } })) {
            Button("Evolve") { if let recipe = evolution { session.evolvePet(recipe) }; evolution = nil }
            Button("Cancel",role: .cancel) { evolution = nil }
        }
        .confirmationDialog(action == 1 ? "Feed your pet? Overfeeding can reduce intimacy." : "Return this pet to its egg?", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } })) {
            Button("Confirm") { if let value = action { session.petCommand(value) }; action = nil }
            Button("Cancel", role: .cancel) { action = nil }
        }
    }
}
