import Testing
@testable import RagnarokGame

@Test func questItemLinksPreserveLabelsAndText() {
    #expect(QuestRichText.parse("Bring <ITEM>Red Potion<INFO>501</INFO></ITEM> now.") == [
        .init(text: "Bring ", itemID: nil), .init(text: "Red Potion", itemID: 501), .init(text: " now.", itemID: nil)
    ])
    #expect(QuestRichText.parse("<item>Apple<info> 512 </info></item>").first?.itemID == 512)
}

@Test func malformedQuestLinksNeverOpenURLs() {
    for source in ["<ITEM>Bad<INFO>https://example.com</INFO></ITEM>", "<ITEM>Bad<INFO>-1</INFO></ITEM>", "<ITEM>Bad<INFO>0</INFO></ITEM>", "<ITEM>Bad<INFO>99999999999999999999999</INFO></ITEM>", "<ITEM>Bad<INFO>501"] {
        let parsed = QuestRichText.parse(source)
        #expect(parsed.allSatisfy { $0.itemID == nil })
        #expect(parsed.map(\.text).joined() == "Bad")
    }
    #expect(QuestRichText.parse("Plain text").first?.text == "Plain text")
}
