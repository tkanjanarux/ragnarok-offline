import Foundation
import Testing
@testable import RagnarokScript

@Test func questMetadataParsesClientLua() throws {
    let source = """
    QuestInfoList = {[11118] = {Title="Spore Hunting", Summary="Hunt", Description={"First line", "Second line"}, IconName="ico_nq.bmp", RewardEXP=250, RewardItemList={{ItemID=501, ItemNum=3}}, NpcNavi="moc_para01", NpcPosX=32, NpcPosY=30}}
    """
    let info = try QuestMetadataDecoder.lua(Data(source.utf8))[11118]
    #expect(info?.description == "First line\nSecond line")
    #expect(info?.rewardEXP == 250)
    #expect(info?.rewardJobEXP == nil)
    #expect(info?.rewards.first?.itemID == 501)
    #expect(info?.npcMap == "moc_para01")
}

@Test func questMetadataTextFallbackPreservesMultilineDescription() {
    let info = QuestMetadataDecoder.text("// ignored\n11118#Spore Hunting#1#image#First line\nSecond line#Hunt#\n11119#Other#1#image#Description#Summary#")
    #expect(info[11118]?.description == "First line\nSecond line")
    #expect(info[11119]?.title == "Other")
    #expect(info[11118]?.rewardEXP == nil)
}
