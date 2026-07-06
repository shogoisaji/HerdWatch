import SwiftUI

public enum Facing {
    case left, right
}

/// GraphicsContextへドット絵を描く純粋な描画ルーチン。アートは左向きが正、右向きはミラー。
public enum SpriteRenderer {
    public static func cellSize(pixelSize: CGFloat) -> CGFloat {
        pixelSize * CGFloat(SpriteFrame.legacyWidth) / CGFloat(SpriteFrame.width)
    }

    public static func draw(frame: SpriteFrame,
                     palette: CharacterPalette,
                     in context: GraphicsContext,
                     at origin: CGPoint,
                     pixelSize: CGFloat,
                     facing: Facing) {
        // 隣接ドット間のアンチエイリアス継ぎ目を消すため、わずかに重ねて塗る
        let cellSize = Self.cellSize(pixelSize: pixelSize)
        let bleed = min(0.3, cellSize * 0.15)
        forEachOpaqueCell(in: frame, cellSize: cellSize, at: origin, facing: facing) { char, rect in
            guard let color = palette.color(for: char) else { return }
            context.fill(Path(rect.insetBy(dx: -bleed, dy: -bleed)), with: .color(color))
        }
    }

    /// スプライトの見かけサイズ（ラベル・ヒットテスト共用）
    public static func spriteSize(pixelSize: CGFloat) -> CGSize {
        let cellSize = Self.cellSize(pixelSize: pixelSize)
        return CGSize(width: CGFloat(SpriteFrame.width) * cellSize,
                      height: CGFloat(SpriteFrame.height) * cellSize)
    }

    /// 不透明ピクセルをまとめた1つのPath（縁取りシャドウ用）。
    /// pixelごとに別々にfillするとシャドウ抽出時に継ぎ目が黒くにじむため、1つのPathにまとめて単一fillにする。
    public static func silhouettePath(frame: SpriteFrame, pixelSize: CGFloat,
                               at origin: CGPoint, facing: Facing) -> Path {
        var path = Path()
        let cellSize = Self.cellSize(pixelSize: pixelSize)
        forEachOpaqueCell(in: frame, cellSize: cellSize, at: origin, facing: facing) { _, rect in
            path.addRect(rect)
        }
        return path
    }

    /// draw/silhouettePath共通のピクセル走査。'.'（透明）以外のセルをfacing反転込みの描画矩形で列挙する。
    private static func forEachOpaqueCell(in frame: SpriteFrame, cellSize: CGFloat,
                                          at origin: CGPoint, facing: Facing,
                                          _ body: (Character, CGRect) -> Void) {
        for (y, row) in frame.rows.enumerated() {
            for (x, char) in row.enumerated() {
                guard char != "." else { continue }
                let drawX = facing == .left ? x : (SpriteFrame.width - 1 - x)
                let rect = CGRect(x: origin.x + CGFloat(drawX) * cellSize,
                                  y: origin.y + CGFloat(y) * cellSize,
                                  width: cellSize, height: cellSize)
                body(char, rect)
            }
        }
    }
}

/// キャラクタースプライト画像をフレーム単位でキャッシュする。
///
/// 通常描画はセルごとにPathを作って塗るため、キャラ数が増えると毎フレームのCPU負荷が高くなる。
/// 見た目は frame + species + palette + facing + pixelSize だけで決まるので、オフスクリーンで1回だけ
/// 描いた画像を以後 `context.draw(image, in:)` で貼り付ける。
public enum SpriteImageCache {
    public static func padding(for pixelSize: CGFloat) -> CGFloat {
        let cellSize = SpriteRenderer.cellSize(pixelSize: pixelSize)
        return min(0.3, cellSize * 0.15)
    }

    public static func imageSize(spriteSize: CGSize, pixelSize: CGFloat) -> CGSize {
        let pad = padding(for: pixelSize)
        return CGSize(width: spriteSize.width + pad * 2,
                      height: spriteSize.height + pad * 2)
    }

    public static func drawOffset(origin: CGPoint, pixelSize: CGFloat) -> CGPoint {
        let pad = padding(for: pixelSize)
        return CGPoint(x: origin.x - pad, y: origin.y - pad)
    }

    public struct Key: Hashable {
        public let frame: SpriteFrame
        public let species: Species
        public let paletteIndex: Int
        public let facing: Facing
        public let pixelSize: CGFloat

        public init(frame: SpriteFrame, species: Species, paletteIndex: Int,
                    facing: Facing, pixelSize: CGFloat) {
            self.frame = frame
            self.species = species
            self.paletteIndex = Self.normalizedPaletteIndex(paletteIndex)
            self.facing = facing
            self.pixelSize = pixelSize
        }

        private static func normalizedPaletteIndex(_ index: Int) -> Int {
            let n = CharacterAssignmentStore.palettesPerSpecies
            return ((index % n) + n) % n
        }
    }

    @MainActor
    public static func render(frame: SpriteFrame, species: Species, paletteIndex: Int,
                              facing: Facing, pixelSize: CGFloat) -> Image {
        let key = Key(frame: frame, species: species, paletteIndex: paletteIndex,
                      facing: facing, pixelSize: pixelSize)
        let palette = CharacterPalette.palette(for: key.species, index: key.paletteIndex)
        let spriteSize = SpriteRenderer.spriteSize(pixelSize: pixelSize)
        let pad = padding(for: pixelSize)
        let totalSize = imageSize(spriteSize: spriteSize, pixelSize: pixelSize)
        let view = Canvas { context, _ in
            SpriteRenderer.draw(frame: key.frame,
                                palette: palette,
                                in: context,
                                at: CGPoint(x: pad, y: pad),
                                pixelSize: pixelSize,
                                facing: key.facing)
        }
        .frame(width: totalSize.width, height: totalSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        #if os(macOS)
        return Image(nsImage: renderer.nsImage ?? NSImage(size: totalSize))
        #else
        return Image(uiImage: renderer.uiImage ?? UIImage())
        #endif
    }
}

/// frame + species + palette + facing + pixelSize ごとにキャラクター画像をキャッシュするストア。
public final class SpriteImageStore {
    private var cache: [SpriteImageCache.Key: Image] = [:]

    public init() {}

    @MainActor
    public func image(for frame: SpriteFrame, species: Species, paletteIndex: Int,
                      facing: Facing, pixelSize: CGFloat) -> Image {
        let key = SpriteImageCache.Key(frame: frame,
                                       species: species,
                                       paletteIndex: paletteIndex,
                                       facing: facing,
                                       pixelSize: pixelSize)
        if let cached = cache[key] { return cached }
        let image = SpriteImageCache.render(frame: frame,
                                            species: species,
                                            paletteIndex: paletteIndex,
                                            facing: facing,
                                            pixelSize: pixelSize)
        cache[key] = image
        return image
    }

    public var count: Int { cache.count }
}
