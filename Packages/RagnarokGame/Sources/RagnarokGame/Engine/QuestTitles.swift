import Foundation

// Snapshot of this server's quest_db.yml. Unknown IDs retain a numeric fallback.
let questTitles: [UInt32: String] = {
    guard let url = Bundle.module.url(forResource: "QuestTitles", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let names = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
    return Dictionary(uniqueKeysWithValues: names.compactMap { key, value in
        UInt32(key).map { ($0, value) }
    })
}()
