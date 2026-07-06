import Foundation

public enum Species: String, Codable, CaseIterable, Sendable {
    case sheep, cow, chicken, pig, deer, duck, elephant
}

public struct CharacterAssignment: Codable, Equatable, Sendable {
    public let species: Species
    public let paletteIndex: Int

    public init(species: Species, paletteIndex: Int) {
        self.species = species
        self.paletteIndex = paletteIndex
    }
}

/// identity→キャラの永続割当。状態は一切持たない（永続化するのは割当のみ: ADR-0001）。
final public class CharacterAssignmentStore: @unchecked Sendable {
    public static let palettesPerSpecies = 5

    private let fileURL: URL
    private let lock = NSLock()
    private var assignments: [String: CharacterAssignment]
    private var random: AnyRNG

    /// - Parameters:
    ///   - directory: 保存先（既定はApplication Support/HerdWatch。テストはtempを注入）
    ///   - random: シード可能な乱数（テスト用に注入可能）
    public init(directory: URL? = nil, random: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HerdWatch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("character-assignments.json")
        self.random = AnyRNG(base: random)
        // 壊れた/存在しないファイルは空から開始（クラッシュさせない）。
        // 種の廃止・改名で残った未知種エントリは、そのキャラだけ捨てて再割当（全消失させない）
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([String: TolerantAssignment].self, from: data) {
            self.assignments = loaded.compactMapValues(\.value)
        } else {
            self.assignments = [:]
        }
    }

    private struct TolerantAssignment: Decodable {
        let value: CharacterAssignment?
        init(from decoder: Decoder) throws {
            value = try? CharacterAssignment(from: decoder)
        }
    }

    /// 既存の割当を返す。無ければランダムに割り当てて永続化する。
    public func assignment(for identity: AgentIdentity) -> CharacterAssignment {
        lock.lock(); defer { lock.unlock() }
        if let existing = assignments[identity.key] { return existing }
        let fresh = randomAssignment(avoiding: nil)
        assignments[identity.key] = fresh
        persist()
        return fresh
    }

    /// 明示的な指定（右クリックメニューからの種類・カラー選択）。
    public func set(_ assignment: CharacterAssignment, for identity: AgentIdentity) {
        lock.lock(); defer { lock.unlock() }
        assignments[identity.key] = assignment
        persist()
    }

    /// 振り直し。必ず現在と異なる組合せを返す。
    @discardableResult
    public func reroll(for identity: AgentIdentity) -> CharacterAssignment {
        lock.lock(); defer { lock.unlock() }
        let current = assignments[identity.key]
        let fresh = randomAssignment(avoiding: current)
        assignments[identity.key] = fresh
        persist()
        return fresh
    }

    private func randomAssignment(avoiding current: CharacterAssignment?) -> CharacterAssignment {
        while true {
            let species = Species.allCases.randomElement(using: &random)!
            let palette = Int.random(in: 0..<Self.palettesPerSpecies, using: &random)
            let candidate = CharacterAssignment(species: species, paletteIndex: palette)
            if candidate != current { return candidate }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(assignments) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
