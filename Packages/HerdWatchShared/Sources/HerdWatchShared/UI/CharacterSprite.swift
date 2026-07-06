import SwiftUI

/// ドット絵1フレーム。行文字列で定義する（32×24固定、左向きが正）。
/// 文字: '.'=透明 / 'b'=主色 / 'w'=副色 / 'd'=濃色(顔・脚) / 'a'=アクセント(嘴・角・トサカ) / 'e'=目 / 'h'=角(淡色)
public struct SpriteFrame: Equatable, Hashable {
    public static let width = 32
    public static let height = 24
    static let legacyWidth = 24
    static let legacyHeight = 18

    public let rows: [String]
    let sourceRows: [String]

    public init(rows: [String]) {
        self.sourceRows = rows
        if Self.isLegacy(rows) {
            self.rows = Self.upscaledLegacyRows(rows)
        } else {
            self.rows = rows
        }
    }

    private static func isLegacy(_ rows: [String]) -> Bool {
        rows.count == legacyHeight && rows.allSatisfy { $0.count == legacyWidth }
    }

    private static func upscaledLegacyRows(_ rows: [String]) -> [String] {
        let source = rows.map(Array.init)
        return (0..<height).map { y in
            let sourceY = min(legacyHeight - 1, y * legacyHeight / height)
            let chars = (0..<width).map { x in
                let sourceX = min(legacyWidth - 1, x * legacyWidth / width)
                return source[sourceY][sourceX]
            }
            return String(chars)
        }
    }
}

public struct SpriteAnimation {
    public let frames: [SpriteFrame]
    public let frameDuration: TimeInterval

    public init(frames: [SpriteFrame], frameDuration: TimeInterval) {
        self.frames = frames
        self.frameDuration = frameDuration
    }

    /// 経過時間からフレームを選ぶ純関数（テスト対象）。
    public func frame(elapsed: TimeInterval) -> SpriteFrame {
        guard frames.count > 1, frameDuration > 0 else { return frames[0] }
        let index = Int(elapsed / frameDuration) % frames.count
        return frames[index]
    }
}

// MARK: - 種別ごとのスプライト定義

extension Species {
    /// 状態→アニメーション。blockedは静止フレーム（跳ねはAnimatorがオフセットで付ける）。
    public func animation(for state: AgentState) -> SpriteAnimation {
        let art = SpriteArt.art(for: self)
        switch state {
        case .idle:
            // 座って休んでいる。まばたきはループに焼き込み（末尾1フレームだけ閉眼）
            return SpriteAnimation(frames: [art.sit, art.sit, art.sit, art.sit, art.sit, art.sitBlink],
                                   frameDuration: 0.25)
        case .working:
            return SpriteAnimation(frames: [art.walk0, art.walk1, art.walk2, art.walk3],
                                   frameDuration: 0.16)
        case .blocked:
            return SpriteAnimation(frames: [art.idle], frameDuration: 1)
        case .done:
            // 立って完了。チェック表示はOverlayBadgeが担う。
            return SpriteAnimation(frames: [art.idle], frameDuration: 1)
        case .unknown:
            return SpriteAnimation(frames: [art.blink], frameDuration: 1)
        }
    }

    /// ドラッグ中（首を掴まれてぶら下がり、脚をバタバタ）。
    public var carriedAnimation: SpriteAnimation {
        let art = SpriteArt.art(for: self)
        return SpriteAnimation(frames: [art.carried0, art.carried1], frameDuration: 0.12)
    }
}

public struct SpeciesArt {
    public let idle: SpriteFrame
    public let blink: SpriteFrame
    public let sitBlink: SpriteFrame
    public let walk0: SpriteFrame
    public let walk1: SpriteFrame
    public let walk2: SpriteFrame
    public let walk3: SpriteFrame
    public let sit: SpriteFrame
    public let carried0: SpriteFrame
    public let carried1: SpriteFrame

    public init(idle: SpriteFrame, blink: SpriteFrame, sitBlink: SpriteFrame,
                walk0: SpriteFrame, walk1: SpriteFrame,
                walk2: SpriteFrame? = nil, walk3: SpriteFrame? = nil,
                sit: SpriteFrame, carried0: SpriteFrame, carried1: SpriteFrame) {
        self.idle = idle
        self.blink = blink
        self.sitBlink = sitBlink
        self.walk0 = walk0
        self.walk1 = walk1
        self.walk2 = walk2 ?? walk0
        self.walk3 = walk3 ?? walk1
        self.sit = sit
        self.carried0 = carried0
        self.carried1 = carried1
    }
}

public enum SpriteArt {
    /// 目を閉じる: 'e' → 'd'
    private static func blinkVariant(_ frame: SpriteFrame) -> SpriteFrame {
        SpriteFrame(rows: frame.sourceRows.map { $0.replacingOccurrences(of: "e", with: "d") })
    }

    /// 指定行（脚部）を差し替えたフレームを作る。
    private static func withRows(_ frame: SpriteFrame, _ replacements: [Int: String]) -> SpriteFrame {
        var rows = frame.sourceRows
        for (index, row) in replacements {
            rows[index] = row
        }
        return SpriteFrame(rows: rows)
    }

    private static func spriteRow(_ parts: [(Int, String)]) -> String {
        row(width: SpriteFrame.width, parts)
    }

    private static func legacyRow(_ parts: [(Int, String)]) -> String {
        row(width: SpriteFrame.legacyWidth, parts)
    }

    private static func row(width: Int, _ parts: [(Int, String)]) -> String {
        var chars = Array(repeating: Character("."), count: width)
        for (start, text) in parts {
            for (offset, char) in text.enumerated() where start + offset < chars.count {
                chars[start + offset] = char
            }
        }
        return String(chars)
    }

    /// 網羅switch: 種を追加してアート未定義ならコンパイルエラーになる（辞書引き+`!`のクラッシュを避ける）。
    public static func art(for species: Species) -> SpeciesArt {
        switch species {
        case .sheep: sheep
        case .cow: cow
        case .chicken: chicken
        case .pig: pig
        case .deer: deer
        case .duck: duck
        case .elephant: elephant
        }
    }

    // MARK: 羊（もこもこの輪郭・濃色の顔と耳・短い尻尾）

    public static let sheep: SpeciesArt = {
        let idle = SpriteFrame(rows: [
            "........................",
            ".......www..www.........",
            "......wbbbwwbbbww.......",
            ".....wbbbbbbbbbbbww.....",
            "..dd.wbbbbbbbbbbbbbw....",
            ".dddwbbbbbbbbbbbbbbbw...",
            ".deedbbbbbbbbbbbbbbbww..",
            ".ddddbbbbbbbbbbbbbbbbw..",
            ".dddwbbbbbbbbbbbbbbbww..",
            "..ddwbbbbbbbbbbbbbbww...",
            "...wbbbbbbbbbbbbbbbw....",
            "....wbbbbbbbbbbbbbw.....",
            ".....wbbbbbbbbbbw.......",
            "......dd..dd..dd.dd.....",
            "......dd..dd..dd.dd.....",
            "......dd..dd..dd.dd.....",
            "........................",
            "........................",
        ])
        let sit = SpriteFrame(rows: [
            "........................",
            "........................",
            "........................",
            ".......www..www.........",
            "......wbbbwwbbbww.......",
            ".....wbbbbbbbbbbbww.....",
            "..dd.wbbbbbbbbbbbbbw....",
            ".dddwbbbbbbbbbbbbbbbw...",
            ".deedbbbbbbbbbbbbbbbww..",
            ".ddddbbbbbbbbbbbbbbbbw..",
            ".dddwbbbbbbbbbbbbbbbww..",
            "..ddwbbbbbbbbbbbbbbww...",
            "...wbbbbbbbbbbbbbbbw....",
            "....wbbbbbbbbbbbbbw.....",
            "...ddd.wbbbbbbw.ddd.....",
            "........................",
            "........................",
            "........................",
        ])
        return SpeciesArt(
            idle: idle, blink: blinkVariant(idle), sitBlink: blinkVariant(sit),
            walk0: withRows(idle, [
                13: ".....dd..dd....dd..dd...",
                14: ".....dd..dd....dd..dd...",
                15: "....dd....dd..dd....dd..",
            ]),
            walk1: withRows(idle, [
                13: ".......dd..dd.dd..dd....",
                14: ".......dd..dd.dd..dd....",
                15: "........dd.dd..dd.dd....",
            ]),
            walk2: withRows(idle, [
                13: legacyRow([(6, "dd"), (11, "dd"), (15, "dd"), (20, "dd")]),
                14: legacyRow([(6, "dd"), (11, "dd"), (15, "dd"), (20, "dd")]),
                15: legacyRow([(5, "dd"), (12, "dd"), (16, "dd"), (21, "dd")]),
            ]),
            walk3: withRows(idle, [
                13: legacyRow([(6, "dd"), (10, "dd"), (16, "dd"), (20, "dd")]),
                14: legacyRow([(7, "dd"), (10, "dd"), (17, "dd"), (20, "dd")]),
                15: legacyRow([(7, "dd"), (11, "dd"), (16, "dd"), (20, "dd")]),
            ]),
            sit: sit,
            carried0: withRows(idle, [
                13: ".....dd...dd...dd...dd..",
                14: "....dd.....dd.dd.....dd.",
                15: "...dd......dd.dd......dd",
            ]),
            carried1: withRows(idle, [
                13: ".......dd.dd...dd.dd....",
                14: ".......dd..dd.dd..dd....",
                15: "......dd....ddd....dd...",
            ]))
    }()

    // MARK: 牛（正面向きの顔・淡色の角・左右の耳・ぶち模様・鼻の穴つきのピンクのマズル）

    public static let cow: SpeciesArt = {
        let idle = SpriteFrame(rows: [
            ".hh...hh................",
            "..h...h.................",
            ".bbbbbbb................",
            "dbbbbbbbdbbbbbbbbbbbb...",
            "dbwwbbbbdbbbwwwbbbbbbb..",
            ".bebbbebbbbwwwwwbbbbbb..",
            ".aaaaaaabbbwwwwwbbbwwb..",
            ".adaaadabbbbwwwbbbwwwwb.",
            "..aaaaabbbbbbbbbbbwwwwb.",
            "...bbbbbwwbbbbbbbbwwwb..",
            "...bbbbwwwwbbbbbbbbbbb..",
            "...bbbbwwwwbbbbbbbbbb...",
            "....bbbwwbbbbbbbbbbbb...",
            "....dd...dd....dd...dd..",
            "....dd...dd....dd...dd..",
            "....dd...dd....dd...dd..",
            "........................",
            "........................",
        ])
        let sit = SpriteFrame(rows: [
            "........................",
            "........................",
            ".hh...hh................",
            "..h...h.................",
            ".bbbbbbb................",
            "dbbbbbbbdbbbbbbbbbbbb...",
            "dbwwbbbbdbbbwwwbbbbbbb..",
            ".bebbbebbbbwwwwwbbbbbb..",
            ".aaaaaaabbbwwwwwbbbwwb..",
            ".adaaadabbbbwwwbbbwwwwb.",
            "..aaaaabbbbbbbbbbbwwwwb.",
            "...bbbbbwwbbbbbbbbwwwb..",
            "...bbbbwwwwbbbbbbbbbbb..",
            "...bbbbwwwwbbbbbbbbbb...",
            "..ddd..bbbbbbbbbb..ddd..",
            "........................",
            "........................",
            "........................",
        ])
        return SpeciesArt(
            idle: idle, blink: blinkVariant(idle), sitBlink: blinkVariant(sit),
            walk0: withRows(idle, [
                13: "...dd...dd......dd...dd.",
                14: "...dd...dd......dd...dd.",
                15: "..dd.....dd....dd.....dd",
            ]),
            walk1: withRows(idle, [
                13: ".....dd...dd..dd...dd...",
                14: ".....dd...dd..dd...dd...",
                15: "......dd...dddd...dd....",
            ]),
            walk2: withRows(idle, [
                13: legacyRow([(4, "dd"), (9, "dd"), (13, "dd"), (18, "dd")]),
                14: legacyRow([(4, "dd"), (9, "dd"), (13, "dd"), (18, "dd")]),
                15: legacyRow([(3, "dd"), (10, "dd"), (14, "dd"), (19, "dd")]),
            ]),
            walk3: withRows(idle, [
                13: legacyRow([(5, "dd"), (8, "dd"), (15, "dd"), (18, "dd")]),
                14: legacyRow([(5, "dd"), (8, "dd"), (15, "dd"), (18, "dd")]),
                15: legacyRow([(6, "dd"), (9, "dd"), (14, "dd"), (17, "dd")]),
            ]),
            sit: sit,
            carried0: withRows(idle, [
                13: "...dd....dd....dd....dd.",
                14: "..dd......dd..dd......dd",
                15: ".dd.......dd..dd.......d",
            ]),
            carried1: withRows(idle, [
                13: ".....dd..dd....dd..dd...",
                14: ".....dd...dd..dd...dd...",
                15: "....dd.....dddd.....dd..",
            ]))
    }()

    // MARK: 鶏（トサカ・肉垂れ・翼・尾羽・細い脚）

    public static let chicken: SpeciesArt = {
        let idle = SpriteFrame(rows: [
            "......aa................",
            ".....aaaa...............",
            "......aaa...............",
            "....bbbbbb..............",
            "..aabebbbb..............",
            "....abbbbbb......w......",
            "....abbbbbb.....ww......",
            "....bbbbbbbbbbbwww......",
            "...bbbbbbbbbbbbwww......",
            "...bbbbbbbbbbbbww.......",
            "...bbwwwwwbbbbbww.......",
            "...bbwwwwwwbbbbb........",
            "....bbwwwwbbbbb.........",
            "....bbbbbbbbbb..........",
            ".........a...a..........",
            ".........a...a..........",
            "........aa...aa.........",
            "........................",
        ])
        let sit = SpriteFrame(rows: [
            "........................",
            "........................",
            "......aa................",
            ".....aaaa...............",
            "......aaa...............",
            "....bbbbbb..............",
            "..aabebbbb..............",
            "....abbbbbb......w......",
            "....abbbbbb.....ww......",
            "....bbbbbbbbbbbwww......",
            "...bbbbbbbbbbbbwww......",
            "...bbbbbbbbbbbbww.......",
            "...bbwwwwwbbbbbww.......",
            "...bbwwwwwwbbbbb........",
            "....bbwwwwbbbbb.........",
            ".....bbbbbbbbb..........",
            "........................",
            "........................",
        ])
        return SpeciesArt(
            idle: idle, blink: blinkVariant(idle), sitBlink: blinkVariant(sit),
            // 接地(大股)→後ろ足上げ→接地(揃い)→前足上げ の歩行サイクル
            walk0: withRows(idle, [
                14: "......a....a............",
                15: "......a....a............",
                16: ".....aa...aa............",
            ]),
            walk1: withRows(idle, [
                14: ".......a..a.............",
                15: ".......a.aa.............",
                16: "......aa................",
            ]),
            walk2: withRows(idle, [
                14: "........a.a.............",
                15: "........a.a.............",
                16: ".......aa.aa............",
            ]),
            walk3: withRows(idle, [
                14: "........a..a............",
                15: ".......aa..a............",
                16: "..........aa............",
            ]),
            sit: sit,
            carried0: withRows(idle, [
                14: "........a.....a.........",
                15: ".......a.......a........",
                16: "......aa.......aa.......",
            ]),
            carried1: withRows(idle, [
                14: "..........a..a..........",
                15: "..........a..a..........",
                16: ".........aa..aa.........",
            ]))
    }()

    // MARK: 豚（正面向きの顔・中央の大きな鼻の穴つき鼻・左右の立ち耳・巻き尻尾）

    public static let pig: SpeciesArt = {
        let idle = SpriteFrame(rows: [
            "..bb...bb...............",
            ".bdb...bdb..............",
            ".bbbbbbbbb..............",
            "bbbbbbbbbb..............",
            "bbbbbbbbbbbbbbbbbbb.....",
            "bebbbbbbebbbbbbbbbbbb...",
            "baaaaaaaabbbbbbbbbbbb...",
            "baddaaddabbbbbbbbbbbbbaa",
            "baaaaaaaabbbbbbbbbbbbb.a",
            "bbbbbbbbbbwwwbbbbbbbb.aa",
            ".bbbbbbbwwwwwbbbbbbbb...",
            ".bbbbbbbwwwwwbbbbbbb....",
            "..bbbbbbbwwwbbbbbbbb....",
            "....dd...dd...dd...dd...",
            "....dd...dd...dd...dd...",
            "........................",
            "........................",
            "........................",
        ])
        let sit = SpriteFrame(rows: [
            "........................",
            "........................",
            "..bb...bb...............",
            ".bdb...bdb..............",
            ".bbbbbbbbb..............",
            "bbbbbbbbbb..............",
            "bbbbbbbbbbbbbbbbbbb.....",
            "bebbbbbbebbbbbbbbbbbb...",
            "baaaaaaaabbbbbbbbbbbb...",
            "baddaaddabbbbbbbbbbbbbaa",
            "baaaaaaaabbbbbbbbbbbbb.a",
            "bbbbbbbbbbwwwbbbbbbbb.aa",
            ".bbbbbbbwwwwwbbbbbbbb...",
            "..ddd.bbbwwwbbbb.ddd....",
            "........................",
            "........................",
            "........................",
            "........................",
        ])
        return SpeciesArt(
            idle: idle, blink: blinkVariant(idle), sitBlink: blinkVariant(sit),
            walk0: withRows(idle, [
                13: "...dd...dd.....dd...dd..",
                14: "...dd...dd.....dd...dd..",
            ]),
            walk1: withRows(idle, [
                13: ".....dd...dd.dd...dd....",
                14: ".....dd...dd.dd...dd....",
            ]),
            walk2: withRows(idle, [
                13: legacyRow([(4, "dd"), (9, "dd"), (14, "dd"), (19, "dd")]),
                14: legacyRow([(4, "dd"), (9, "dd"), (14, "dd"), (19, "dd")]),
            ]),
            walk3: withRows(idle, [
                13: legacyRow([(5, "dd"), (8, "dd"), (15, "dd"), (18, "dd")]),
                14: legacyRow([(6, "dd"), (9, "dd"), (14, "dd"), (17, "dd")]),
            ]),
            sit: sit,
            carried0: withRows(idle, [
                13: "...dd....dd...dd....dd..",
                14: "..dd......dd.dd......dd.",
            ]),
            carried1: withRows(idle, [
                13: ".....dd..dd...dd..dd....",
                14: "......dd..dd.dd..dd.....",
            ]))
    }()

    // MARK: 鹿（枝角・黒い鼻先と白いマズル・濃色の耳先・白い胸元と尻の斑）

    public static let deer: SpeciesArt = {
        let idle = SpriteFrame(rows: [
            ".a...a..................",
            ".a.a.a.a................",
            "..aa.aa.................",
            "...bbbb.bd..............",
            "..wbebbbb...............",
            ".dwbbbbb.bbbbbbbbbb.....",
            "..dbbbbbbbbbbbbbbbbbw...",
            "...dbbbbbbbbbbbbbbbbww..",
            "...dbbbbbbbbbbbbbbbbww..",
            "....bbbbbbbbbbbbbbbww...",
            "....bbwwbbbbbbbbbbbw....",
            "....bbwwwbbbbbbbbbb.....",
            ".....bwwbbbbbbbbbbb.....",
            ".....dd..dd....dd..dd...",
            ".....dd..dd....dd..dd...",
            ".....dd..dd....dd..dd...",
            "........................",
            "........................",
        ])
        let sit = SpriteFrame(rows: [
            "........................",
            "........................",
            ".a...a..................",
            ".a.a.a.a................",
            "..aa.aa.................",
            "...bbbb.bd..............",
            "..wbebbbb...............",
            ".dwbbbbb.bbbbbbbbbb.....",
            "..dbbbbbbbbbbbbbbbbbw...",
            "...dbbbbbbbbbbbbbbbbww..",
            "...dbbbbbbbbbbbbbbbbww..",
            "....bbbbbbbbbbbbbbbww...",
            "....bbwwbbbbbbbbbbbw....",
            ".....bwwbbbbbbbbbbb.....",
            "...ddd.bbbbbbbb.ddd.....",
            "........................",
            "........................",
            "........................",
        ])
        return SpeciesArt(
            idle: idle, blink: blinkVariant(idle), sitBlink: blinkVariant(sit),
            walk0: withRows(idle, [
                13: "....dd..dd......dd..dd..",
                14: "....dd..dd......dd..dd..",
                15: "...dd....dd....dd....dd.",
            ]),
            walk1: withRows(idle, [
                13: "......dd..dd..dd..dd....",
                14: "......dd..dd..dd..dd....",
                15: ".......dd..dddd..dd.....",
            ]),
            walk2: withRows(idle, [
                13: legacyRow([(5, "dd"), (10, "dd"), (15, "dd"), (20, "dd")]),
                14: legacyRow([(5, "dd"), (10, "dd"), (15, "dd"), (20, "dd")]),
                15: legacyRow([(4, "dd"), (11, "dd"), (16, "dd"), (21, "dd")]),
            ]),
            walk3: withRows(idle, [
                13: legacyRow([(6, "dd"), (9, "dd"), (16, "dd"), (19, "dd")]),
                14: legacyRow([(6, "dd"), (9, "dd"), (16, "dd"), (19, "dd")]),
                15: legacyRow([(7, "dd"), (10, "dd"), (15, "dd"), (18, "dd")]),
            ]),
            sit: sit,
            carried0: withRows(idle, [
                13: "....dd...dd....dd...dd..",
                14: "...dd.....dd..dd.....dd.",
                15: "..dd......dd..dd......dd",
            ]),
            carried1: withRows(idle, [
                13: "......dd.dd....dd.dd....",
                14: "......dd..dd..dd..dd....",
                15: ".....dd....dddd....dd...",
            ]))
    }()

    // MARK: アヒル（長い首・平たい嘴・翼・水かき）

    public static let duck: SpeciesArt = {
        let idle = SpriteFrame(rows: [
            "........................",
            "....bbbb................",
            "...bbbbbb...............",
            "aaabebbbb...............",
            "aaa.bbbbb...............",
            "....bbbb................",
            "....bbbb................",
            "....bbbbbbbbbbbbbb......",
            "...bbbbbbbbbbbbbbbbb....",
            "...bbbbwwwwwwbbbbbbbb...",
            "...bbbwwwwwwwwbbbbbbb...",
            "...bbbbwwwwwwbbbbbbb....",
            "....bbbbwwwwbbbbbbb.....",
            ".....bbbbbbbbbbbbb......",
            ".......a......a.........",
            ".......a......a.........",
            "......aaa....aaa........",
            "........................",
        ])
        let sit = SpriteFrame(rows: [
            "........................",
            "........................",
            "........................",
            ".....bbbb...............",
            "....bbbbbb..............",
            ".aaabebbbb..............",
            ".aaa.bbbbb..............",
            ".....bbbb...............",
            ".....bbbb...............",
            ".....bbbbbbbbbbbbbb.....",
            "....bbbbbbbbbbbbbbbbb...",
            "....bbbbwwwwwwbbbbbbbb..",
            "....bbbwwwwwwwwbbbbbb...",
            "....bbbbwwwwwwbbbbbb....",
            ".....bbbbbbbbbbbbbb.....",
            "........................",
            "........................",
            "........................",
        ])
        // 鶏と同じ配置: idleから両脚を左右対称に±1pxだけ開閉させる（振れ幅は毎フレーム同じにする）。
        return SpeciesArt(
            idle: idle, blink: blinkVariant(idle), sitBlink: blinkVariant(sit),
            walk0: withRows(idle, [
                14: "......a........a........",
                15: "......a........a........",
                16: ".....aaa......aaa.......",
            ]),
            walk1: withRows(idle, [
                14: "........a....a..........",
                15: "........a....a..........",
                16: ".......aaa..aaa.........",
            ]),
            walk2: withRows(idle, [
                14: legacyRow([(7, "a"), (16, "a")]),
                15: legacyRow([(7, "a"), (16, "a")]),
                16: legacyRow([(6, "aaa"), (15, "aaa")]),
            ]),
            walk3: withRows(idle, [
                14: legacyRow([(9, "a"), (14, "a")]),
                15: legacyRow([(9, "a"), (14, "a")]),
                16: legacyRow([(8, "aaa"), (13, "aaa")]),
            ]),
            sit: sit,
            carried0: withRows(idle, [
                14: "......a.........a.......",
                15: ".....a...........a......",
                16: "....aaa.........aaa.....",
            ]),
            carried1: withRows(idle, [
                14: ".........a...a..........",
                15: ".........a...a..........",
                16: "........aaa..aaa........",
            ]))
    }()

    // MARK: 象（大きな耳・垂れ下がる鼻・牙・ずんぐりむっくりな体）

    public static let elephant: SpeciesArt = {
        // 左向き。頭頂ドーム→首のくぼみ→背中、顔の前から鼻がS字に垂れ下がり、
        // 大きな丸い耳(w)・牙(a)・尻尾の房(d)でシルエットを作る。
        let idle = SpriteFrame(rows: [
            spriteRow([]),
            spriteRow([]),
            spriteRow([]),
            spriteRow([(4, "bbbbbb"), (14, "bbbbbbbbbbbb")]),
            spriteRow([(3, "bbbbbbbb"), (12, "bbbbbbbbbbbbbbb")]),
            spriteRow([(2, "bbbbbbbbb"), (12, "bbbbbbbbbbbbbbbb"), (9, "wwwww")]),
            spriteRow([(2, "bbbbbbbbbbbbbbbbbbbbbbbbbbb"), (8, "wwwwwww")]),
            spriteRow([(2, "bbbbbbbbbbbbbbbbbbbbbbbbbbb"), (7, "wwwwwwwww")]),
            spriteRow([(2, "bbbbbbbbbbbbbbbbbbbbbbbbbbb"), (4, "e"), (7, "wwwwwwwww")]),
            spriteRow([(2, "bbbbbbbbbbbbbbbbbbbbbbbbbbbb"), (7, "wwwwwwwww")]),
            spriteRow([(2, "bbbbbbbbbbbbbbbbbbbbbbbbbbbb"), (7, "wwwwwwwww")]),
            spriteRow([(2, "bbbbbbbbbbbbbbbbbbbbbbbbbbb"), (8, "wwwwwww"), (29, "b")]),
            spriteRow([(2, "bbb"), (5, "aa"), (8, "bbbbbbbbbbbbbbbbbbbbb"), (9, "wwwww"), (29, "b")]),
            spriteRow([(2, "bbb"), (5, "aa"), (9, "bbbbbbbbbbbbbbbbbbbb"), (10, "www"), (29, "b")]),
            spriteRow([(1, "bbb"), (5, "a"), (9, "bbbbbbbbbbbbbbbbbbbb"), (29, "d")]),
            spriteRow([(1, "bbb"), (9, "bbbbbbbbbbbbbbbbbbbb")]),
            spriteRow([(1, "bbb"), (9, "bbbbbbbbbbbbbbbbbbbb")]),
            spriteRow([(1, "bbb"), (9, "bbbbbbbbbbbbbbbbbbbb")]),
            spriteRow([(2, "bbbb"), (10, "bbbbbbbbbbbbbbbbbb")]),
            spriteRow([(10, "bbbb"), (15, "bbbb"), (20, "bbbb"), (25, "bbbb")]),
            spriteRow([(10, "bbbb"), (15, "bbbb"), (20, "bbbb"), (25, "bbbb")]),
            spriteRow([(10, "bbbb"), (15, "bbbb"), (20, "bbbb"), (25, "bbbb")]),
            spriteRow([]),
            spriteRow([]),
        ])
        let sit = withRows(idle, [
            17: spriteRow([(1, "bbb"), (9, "bbbbbbbbbbbbbbbbbbbb")]),
            18: spriteRow([(1, "bbb"), (9, "bbbbbbbbbbbbbbbbbbbb")]),
            19: spriteRow([(2, "bbbb"), (9, "bbbbbbbbbbbbbbbbbbbb")]),
            20: spriteRow([(8, "bbbbbbbbbbbbbbbbbbbbb")]),
            21: spriteRow([(9, "bbbbb"), (23, "bbbbb")]),
        ])
        return SpeciesArt(
            idle: idle, blink: blinkVariant(idle), sitBlink: blinkVariant(sit),
            walk0: withRows(idle, [
                19: spriteRow([(10, "bbbb"), (15, "bbbb"), (20, "bbbb"), (25, "bbbb")]),
                20: spriteRow([(10, "bbbb"), (15, "bbbb"), (20, "bbbb"), (25, "bbbb")]),
                21: spriteRow([(10, "bbbb"), (15, "bbbb"), (20, "bbbb"), (25, "bbbb")]),
            ]),
            walk1: withRows(idle, [
                19: spriteRow([(10, "bbbb"), (15, "bbbb"), (20, "bbbb"), (25, "bbbb")]),
                20: spriteRow([(9, "bbbb"), (16, "bbbb"), (19, "bbbb"), (26, "bbbb")]),
                21: spriteRow([(9, "bbbb"), (16, "bbbb"), (19, "bbbb"), (26, "bbbb")]),
            ]),
            walk2: withRows(idle, [
                19: spriteRow([(11, "bbbb"), (14, "bbbb"), (21, "bbbb"), (24, "bbbb")]),
                20: spriteRow([(11, "bbbb"), (14, "bbbb"), (21, "bbbb"), (24, "bbbb")]),
                21: spriteRow([(11, "bbbb"), (14, "bbbb"), (21, "bbbb"), (24, "bbbb")]),
            ]),
            walk3: withRows(idle, [
                19: spriteRow([(10, "bbbb"), (15, "bbbb"), (20, "bbbb"), (25, "bbbb")]),
                20: spriteRow([(11, "bbbb"), (14, "bbbb"), (21, "bbbb"), (24, "bbbb")]),
                21: spriteRow([(11, "bbbb"), (14, "bbbb"), (21, "bbbb"), (24, "bbbb")]),
            ]),
            sit: sit,
            carried0: withRows(idle, [
                19: spriteRow([(10, "bbb"), (16, "bbb"), (20, "bbb"), (26, "bbb")]),
                20: spriteRow([(9, "bbb"), (16, "bbb"), (19, "bbb"), (27, "bbb")]),
                21: spriteRow([(9, "bbb"), (17, "bbb"), (19, "bbb"), (27, "bbb")]),
            ]),
            carried1: withRows(idle, [
                19: spriteRow([(11, "bbb"), (14, "bbb"), (21, "bbb"), (24, "bbb")]),
                20: spriteRow([(11, "bbb"), (14, "bbb"), (22, "bbb"), (24, "bbb")]),
                21: spriteRow([(12, "bbb"), (14, "bbb"), (22, "bbb"), (24, "bbb")]),
            ]))
    }()
}

// MARK: - パレット（種×4バリエーション）

public struct CharacterPalette {
    public let body: Color
    public let secondary: Color
    public let dark: Color
    public let accent: Color
    // 'h': アクセントがピンク等で角に使えない種（牛）向けの淡い角色
    public var horn: Color = Color(red: 0.84, green: 0.76, blue: 0.58)

    public init(body: Color, secondary: Color, dark: Color, accent: Color,
                horn: Color = Color(red: 0.84, green: 0.76, blue: 0.58)) {
        self.body = body
        self.secondary = secondary
        self.dark = dark
        self.accent = accent
        self.horn = horn
    }

    /// 5色/種。背景（草地）と紛れる緑系は使わない。
    public static func palette(for species: Species, index: Int) -> CharacterPalette {
        let n = CharacterAssignmentStore.palettesPerSpecies
        let i = ((index % n) + n) % n
        switch species {
        case .sheep:
            let wools: [(Color, Color)] = [
                (Color(red: 0.97, green: 0.96, blue: 0.93), Color(red: 0.82, green: 0.80, blue: 0.74)),
                (Color(red: 0.98, green: 0.68, blue: 0.80), Color(red: 0.90, green: 0.48, blue: 0.66)),
                (Color(red: 0.62, green: 0.80, blue: 0.96), Color(red: 0.42, green: 0.62, blue: 0.88)),
                (Color(red: 0.58, green: 0.40, blue: 0.28), Color(red: 0.42, green: 0.28, blue: 0.20)),
                (Color(red: 0.74, green: 0.58, blue: 0.94), Color(red: 0.58, green: 0.42, blue: 0.82)),
            ]
            return CharacterPalette(body: wools[i].0, secondary: wools[i].1,
                                    dark: Color(red: 0.25, green: 0.20, blue: 0.18),
                                    accent: Color(red: 0.9, green: 0.7, blue: 0.7))
        case .cow:
            let coats: [(Color, Color)] = [
                (Color(red: 0.96, green: 0.95, blue: 0.92), Color(red: 0.15, green: 0.13, blue: 0.12)),
                (Color(red: 0.96, green: 0.95, blue: 0.92), Color(red: 0.48, green: 0.30, blue: 0.18)),
                (Color(red: 0.62, green: 0.42, blue: 0.28), Color(red: 0.32, green: 0.20, blue: 0.14)),
                (Color(red: 0.22, green: 0.20, blue: 0.20), Color(red: 0.95, green: 0.93, blue: 0.88)),
                (Color(red: 0.82, green: 0.58, blue: 0.38), Color(red: 0.38, green: 0.18, blue: 0.12)),
            ]
            return CharacterPalette(body: coats[i].0,
                                    secondary: coats[i].1,
                                    dark: Color(red: 0.22, green: 0.18, blue: 0.16),
                                    accent: Color(red: 0.93, green: 0.72, blue: 0.70))
        case .chicken:
            // 羽(w=secondary)は完全不透明で、body色より少し暗い色にする。
            // 以前は `feathers[i].opacity(0.75)` で半透明にしていたが、
            // 羽が透けて見える問題があるため完全不透明に変更。
            let feathers: [(Double, Double, Double)] = [
                (0.97, 0.96, 0.92),
                (0.78, 0.55, 0.30),
                (0.28, 0.25, 0.24),
                (0.93, 0.84, 0.55),
                (0.87, 0.48, 0.32),
            ]
            let (r, g, b) = feathers[i]
            return CharacterPalette(body: Color(red: r, green: g, blue: b),
                                    secondary: Color(red: r * 0.82, green: g * 0.82, blue: b * 0.82),
                                    dark: Color(red: 0.25, green: 0.20, blue: 0.18),
                                    accent: Color(red: 0.88, green: 0.30, blue: 0.22))
        case .pig:
            let skins: [(Color, Color)] = [
                (Color(red: 1.00, green: 0.72, blue: 0.76), Color(red: 0.92, green: 0.50, blue: 0.58)),
                (Color(red: 0.55, green: 0.85, blue: 0.95), Color(red: 0.38, green: 0.70, blue: 0.88)),
                (Color(red: 0.97, green: 0.78, blue: 0.62), Color(red: 0.90, green: 0.62, blue: 0.48)),
                (Color(red: 0.97, green: 0.94, blue: 0.88), Color(red: 0.90, green: 0.72, blue: 0.68)),
                (Color(red: 0.55, green: 0.36, blue: 0.26), Color(red: 0.42, green: 0.26, blue: 0.18)),
            ]
            return CharacterPalette(body: skins[i].0, secondary: skins[i].1,
                                    dark: Color(red: 0.35, green: 0.24, blue: 0.24),
                                    accent: Color(red: 0.90, green: 0.55, blue: 0.55))
        case .deer:
            let coats: [Color] = [
                Color(red: 0.86, green: 0.66, blue: 0.42),
                Color(red: 0.42, green: 0.28, blue: 0.20),
                Color(red: 0.58, green: 0.58, blue: 0.62),
                Color(red: 0.97, green: 0.96, blue: 0.92),
                Color(red: 0.78, green: 0.38, blue: 0.26),
            ]
            return CharacterPalette(body: coats[i],
                                    secondary: Color(red: 0.96, green: 0.93, blue: 0.86),
                                    dark: Color(red: 0.30, green: 0.23, blue: 0.18),
                                    accent: Color(red: 0.90, green: 0.85, blue: 0.72))
        case .duck:
            let plumage: [(Color, Color)] = [
                (Color(red: 0.97, green: 0.88, blue: 0.45), Color(red: 0.90, green: 0.76, blue: 0.32)),
                (Color(red: 0.96, green: 0.95, blue: 0.92), Color(red: 0.82, green: 0.82, blue: 0.80)),
                (Color(red: 0.64, green: 0.78, blue: 0.93), Color(red: 0.50, green: 0.66, blue: 0.85)),
                (Color(red: 0.68, green: 0.52, blue: 0.38), Color(red: 0.55, green: 0.42, blue: 0.30)),
                (Color(red: 0.95, green: 0.73, blue: 0.55), Color(red: 0.88, green: 0.60, blue: 0.42)),
            ]
            return CharacterPalette(body: plumage[i].0, secondary: plumage[i].1,
                                    dark: Color(red: 0.24, green: 0.22, blue: 0.20),
                                    accent: Color(red: 0.94, green: 0.58, blue: 0.20))
        case .elephant:
            let skins: [(Color, Color)] = [
                (Color(red: 0.62, green: 0.66, blue: 0.70), Color(red: 0.50, green: 0.54, blue: 0.59)),
                (Color(red: 0.88, green: 0.84, blue: 0.78), Color(red: 0.74, green: 0.70, blue: 0.64)),
                (Color(red: 0.45, green: 0.70, blue: 0.92), Color(red: 0.30, green: 0.55, blue: 0.82)),
                (Color(red: 0.78, green: 0.58, blue: 0.86), Color(red: 0.64, green: 0.46, blue: 0.74)),
                (Color(red: 0.86, green: 0.72, blue: 0.55), Color(red: 0.70, green: 0.56, blue: 0.42)),
            ]
            return CharacterPalette(body: skins[i].0, secondary: skins[i].1,
                                    dark: Color(red: 0.22, green: 0.22, blue: 0.24),
                                    accent: Color(red: 0.96, green: 0.94, blue: 0.88),
                                    horn: Color(red: 0.95, green: 0.93, blue: 0.85))
        }
    }

    public func color(for char: Character) -> Color? {
        switch char {
        case "b": return body
        case "w": return secondary
        case "d": return dark
        case "a": return accent
        case "h": return horn
        case "e": return Color(red: 0.08, green: 0.08, blue: 0.08)
        default: return nil
        }
    }
}
