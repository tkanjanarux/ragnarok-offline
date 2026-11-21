import Foundation
import Testing
@testable import RagnarokGame

@Test func hunterRoutesUseCurrentStage() throws {
    for id in 4000...4013 { #expect(QuestGuide.steps[String(id)] != nil) }
    let palace = try #require(QuestGuide.steps["4009"])
    let guild = try #require(QuestGuide.steps["4010"])
    #expect(palace.text(locale: Locale(identifier: "th_TH")).contains("วัง Payon"))
    #expect(guild.text(locale: Locale(identifier: "en")).contains("Archer Guild"))
    #expect(QuestGuide.locations["4009"] == ["Hunter · payon_in03 (131, 7)"])
    #expect(QuestGuide.locations["4010"] == ["Hunter · payon_in02 (21, 31)"])
    #expect(QuestGuide.steps["4008"]?.items?.map(\.count) == [2, 1, 1])
    #expect(QuestGuide.steps["4294967295"] == nil)
}
