//
//  ItemInfoTable.swift
//  RagnarokLocalization
//
//  Created by Leon Li on 2024/5/28.
//

import Foundation

struct ItemInfo: Decodable {
    var unidentifiedItemName: String?
    var unidentifiedItemDescription: String?
    var identifiedItemName: String?
    var identifiedItemDescription: String?
}

final public class ItemInfoTable {
    let itemInfosByID: [Int : ItemInfo]

    public convenience init() {
        let language = Bundle.main.preferredLocalizations.first
        self.init(locale: language.map { Locale(identifier: $0) } ?? .current)
    }

    public init(locale: Locale) {
        let resources = Bundle.module
        let available = resources.localizations
        // Prefer the actual .lproj, including its on-disk capitalization.
        let identifiers = [locale.identifier.replacingOccurrences(of: "_", with: "-"),
                           locale.language.languageCode?.identifier].compactMap { $0 }
        let language = identifiers.lazy.compactMap { tag in
            available.first { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }.first ?? Bundle.preferredLocalizations(from: available, forPreferences: [locale.identifier]).first
        guard let language,
              let directory = resources.url(forResource: language, withExtension: "lproj"),
              let url = Bundle(url: directory)?.url(forResource: "ItemInfo", withExtension: "json") else {
            self.itemInfosByID = [:]
            return
        }

        do {
            let decoder = JSONDecoder()
            let data = try Data(contentsOf: url)
            self.itemInfosByID = try decoder.decode([Int : ItemInfo].self, from: data)
        } catch {
            self.itemInfosByID = [:]
        }
    }

    public func localizedIdentifiedItemName(forItemID itemID: Int) -> String? {
        itemInfosByID[itemID]?.identifiedItemName
    }

    public func localizedUnidentifiedItemName(forItemID itemID: Int) -> String? {
        itemInfosByID[itemID]?.unidentifiedItemName
    }

    public func localizedUnidentifiedItemDescription(forItemID itemID: Int) -> String? {
        itemInfosByID[itemID]?.unidentifiedItemDescription
    }

    public func localizedIdentifiedItemDescription(forItemID itemID: Int) -> String? {
        itemInfosByID[itemID]?.identifiedItemDescription
    }
}
