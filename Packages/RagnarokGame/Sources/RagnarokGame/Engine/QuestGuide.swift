import Foundation

enum QuestGuide {
    struct Step: Decodable {
        struct Material: Decodable {
            let id: Int
            let count: Int
        }
        let en: String
        let th: String
        let items: [Material]?

        func text(locale: Locale) -> String {
            locale.language.languageCode == .thai ? th : en
        }
    }

    static let steps: [String: Step] = load("HunterQuestSteps")
    static let locations: [String: [String]] = load("QuestLocations")

    private static func load<Value: Decodable>(_ name: String) -> [String: Value] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: Value].self, from: data) else { return [:] }
        return entries
    }
}
