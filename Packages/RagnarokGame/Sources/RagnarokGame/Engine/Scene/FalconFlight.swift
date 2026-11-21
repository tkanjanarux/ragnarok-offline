/// A Blitz Beat packet describes one strike, including all of its damage ticks.
struct FalconFlight {
    static let duration: Double = 0.72
    let start: Double
    let target: SIMD3<Float>

    func targetWeight(at time: Double) -> Float {
        let phase = max(0, min(1, (time - start) / Self.duration))
        if phase < 0.4 { return Float(phase / 0.4) }
        if phase < 0.55 { return 1 }
        return Float((1 - phase) / 0.45)
    }
}
