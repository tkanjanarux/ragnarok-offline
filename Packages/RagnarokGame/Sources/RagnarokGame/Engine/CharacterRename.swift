import Foundation

struct CharacterRenameState {
    private(set) var characterID: UInt32?
    private(set) var requestedName = ""
    private(set) var awaitingList = false
    private(set) var uncertain = false
    private(set) var message: String?
    var blocked: Bool { characterID != nil || uncertain }

    mutating func begin(characterID: UInt32, credits: Int, name: String) -> Bool {
        guard !blocked, credits > 0 else { return false }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 23,
              name.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else {
            message = "Enter a name of at most 23 UTF-8 bytes without control characters."
            return false
        }
        self.characterID = characterID
        requestedName = name
        message = "Waiting for the server…"
        return true
    }

    mutating func receive(result: UInt32) {
        guard characterID != nil, !uncertain, !awaitingList else { return }
        if result == 0 {
            awaitingList = true
            message = "Refreshing character list…"
        } else {
            characterID = nil
            message = switch result {
            case 1: "No rename credit is available."
            case 4: "That name is already in use. Your credit was kept."
            case 5: "This server requires leaving your guild before renaming. Your credit was kept."
            case 6: "This server requires leaving your party before renaming. Your credit was kept."
            case 7, 8: "That name is not allowed. Your credit was kept."
            default: "The server rejected the rename. Reconnect to check your character and credit."
            }
        }
    }

    mutating func receiveCharacterList(_ names: [UInt32: String]) {
        guard awaitingList, let id = characterID, let name = names[id], !uncertain else { return }
        characterID = nil
        awaitingList = false
        message = "Character renamed to \(name)."
    }

    mutating func timeout() {
        guard characterID != nil else { return }
        uncertain = true
        message = "Rename result is unknown. Return to login to refresh before trying again."
    }
}
