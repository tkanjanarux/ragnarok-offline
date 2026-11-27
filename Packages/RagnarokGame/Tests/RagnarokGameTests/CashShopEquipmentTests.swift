import Testing
@testable import RagnarokGame

@Suite struct CashShopEquipmentTests {
    @Test func nativeHunterAndRebirthRules() throws {
        let suit = try #require(CashShopEquipment.forItem(2367))
        #expect(suit.eligibility(job: 11, level: 99) == .job)
        #expect(suit.eligibility(job: 4012, level: 49) == .level(50))
        #expect(suit.eligibility(job: 4012, level: 50) == .eligible)
        #expect(suit.eligibility(job: 4056, level: 99) == .eligible)
        #expect(suit.eligibility(job: 4010, level: 99) == .job)
        let boots = try #require(CashShopEquipment.forItem(2433))
        #expect(boots.eligibility(job: 4003, level: 99) == .job)
        #expect(boots.eligibility(job: 4010, level: 99) == .eligible)
    }

    @Test func levelBoundaryAndUnknownIdentity() throws {
        let variant = try #require(CashShopEquipment.forItem(2423))
        #expect(variant.eligibility(job: 4012, level: 84) == .level(85))
        #expect(variant.eligibility(job: 4012, level: 85) == .eligible)
        #expect(variant.eligibility(job: nil, level: 99) == .unknown)
        #expect(variant.eligibility(job: 9999, level: 99) == .unknown)
        #expect(variant.eligibility(job: 4012, level: 0) == .unknown)
        #expect(CashShopEquipment.forItem(2000010) == nil)
    }

    @Test func normalJobRestrictionsAndEntireRequestedList() throws {
        let binoculars = try #require(CashShopEquipment.forItem(2296))
        #expect(binoculars.eligibility(job: 3, level: 50) == .eligible)
        #expect(binoculars.eligibility(job: 19, level: 50) == .eligible)
        #expect(binoculars.eligibility(job: 1, level: 50) == .job)
        let rideword = try #require(CashShopEquipment.forItem(5208))
        #expect(rideword.eligibility(job: 0, level: 99) == .job)
        #expect(rideword.eligibility(job: 23, level: 99) == .job)
        let requested: [UInt32] = [5208,5325,5123,2296,2703,2677,2518,2648,2649,2115,2367,2365,2374,2423,2433,2537,2399,2553,2524]
        for id in requested {
            let item = try #require(CashShopEquipment.forItem(id))
            #expect(item.eligibility(job: 4012, level: 99) == .eligible)
        }
    }
}
