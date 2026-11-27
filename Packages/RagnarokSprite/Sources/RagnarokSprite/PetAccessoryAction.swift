// SPDX-License-Identifier: GPL-3.0
// Resource path metadata adapted from roBrowserLegacy DB/Pets/PetAction.js,
// Vincent Thibault et al., commit2f9a9d6cf5b04a8ac7a44077080772046e15bcb7.
// Local GRF files only; no artwork is bundled. Pet accessories replace ACT,
// retaining the species' original SPR, as in Engine/MapEngine/Pet.js.
import RagnarokCore
import RagnarokResources

enum PetAccessoryAction {
    static func path(for accessory: Int) -> ResourcePath? {
        let name: String
        switch accessory {
        case 10002: name = "몬스터/chocho_방독면"
        case 10007: name = "몬스터/lunatic_리본"
        case 10012: name = "몬스터/picky_알껍질"
        case 10013: name = "몬스터/poring_책가방"
        case 10017: name = "몬스터/spore_원주민치마"
        default: return nil
        }
        return ResourcePath.spriteDirectory.appending(K2L(name))
    }
}
