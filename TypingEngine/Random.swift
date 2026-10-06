import Foundation

extension RandomNumberGenerator {
    /// Стандартное нормальное распределение N(0, 1) по методу Бокса — Мюллера.
    public mutating func nextGaussian() -> Double {
        let u1 = Double.random(in: Double.ulpOfOne..<1, using: &self)
        let u2 = Double.random(in: 0..<1, using: &self)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    /// Равномерное значение из диапазона.
    public mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }

    /// `true` с вероятностью `probability`.
    public mutating func chance(_ probability: Double) -> Bool {
        guard probability > 0 else { return false }
        return Double.random(in: 0..<1, using: &self) < probability
    }
}

/// Детерминированный генератор SplitMix64: один и тот же seed даёт один и тот же план набора.
public struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
