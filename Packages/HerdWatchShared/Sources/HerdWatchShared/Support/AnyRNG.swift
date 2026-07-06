import Foundation

/// existentialな`any RandomNumberGenerator`は`using:`に渡せないため、具体型に包む共通ラッパー。
public struct AnyRNG: RandomNumberGenerator {
    public var base: any RandomNumberGenerator
    public mutating func next() -> UInt64 { base.next() }

    public init(base: any RandomNumberGenerator) {
        self.base = base
    }
}
