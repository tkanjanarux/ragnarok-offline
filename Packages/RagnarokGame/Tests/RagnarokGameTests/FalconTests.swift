import RagnarokModels
import Testing
@testable import RagnarokGame

@Test func falconMapOptionsCanCoexistWithOtherFlags() {
    #expect(MapEffectOptions(rawValue: 0x18).contains(.falcon))
    #expect(MapEffectOptions(rawValue: 0x14).contains(.cloak))
    #expect(!MapEffectOptions(rawValue: 8).contains(.falcon))
    #expect(!MapEffectOptions(rawValue: 0).contains(.falcon))
}

@Test func blitzFlightReachesTargetAndReturns() {
    let flight = FalconFlight(start: 10, target: [4, 3, 0])
    #expect(flight.targetWeight(at: 10) == 0)
    #expect(flight.targetWeight(at: 10.35) == 1)
    #expect(flight.targetWeight(at: 10.6) < 0.5)
    #expect(flight.targetWeight(at: 11) == 0)
}
