import SwiftUI

/// シルエットシャドウ画像をフレーム単位でキャッシュする。
///
/// 従来は毎フレーム全キャラのシルエットを1つのPathにまとめ、`drawLayer` + shadowフィルタで
/// オフスクリーンブラーを1回走らせていた。このキャッシュは各 (frame, facing, pixelSize) ごとに
/// シャドウ付きシルエット画像を1回だけ生成し、以降は `context.draw(image, in:)` で貼る。
/// シャドウの形は frame + facing + pixelSize にのみ依存し、キャラの位置には依存しないため
/// 位置が変わっても画像を使い回せる。
public enum ShadowSpriteCache {
    /// シャドウのブラー半径（SpriteRenderer.drawSilhouetteShadows と同じ値）。
    static let blurRadiusFactor: CGFloat = 0.5

    /// シャドウ画像の余白（blur radius の2倍。両側に効く）。
    public static func padding(for pixelSize: CGFloat) -> CGFloat {
        pixelSize * blurRadiusFactor * 2
    }

    /// シャドウ画像の全体サイズ。
    public static func imageSize(spriteSize: CGSize, pixelSize: CGFloat) -> CGSize {
        let pad = padding(for: pixelSize)
        return CGSize(width: spriteSize.width + pad * 2,
                      height: spriteSize.height + pad * 2)
    }

    /// シャドウ画像を描く先の origin に対するオフセット（画像左上 = origin - padding）。
    public static func drawOffset(origin: CGPoint, pixelSize: CGFloat) -> CGPoint {
        let pad = padding(for: pixelSize)
        return CGPoint(x: origin.x - pad, y: origin.y - pad)
    }

    /// キャッシュキー。
    public struct Key: Hashable {
        public let frame: SpriteFrame
        public let facing: Facing
        public let pixelSize: CGFloat

        public init(frame: SpriteFrame, facing: Facing, pixelSize: CGFloat) {
            self.frame = frame
            self.facing = facing
            self.pixelSize = pixelSize
        }
    }

    /// シャドウ付きシルエット1枚をオフスクリーン描画して Image を生成する。
    /// ImageRenderer はメインスレッド必須のため @MainActor。
    @MainActor
    public static func render(frame: SpriteFrame, facing: Facing, pixelSize: CGFloat) -> Image {
        let spriteSize = SpriteRenderer.spriteSize(pixelSize: pixelSize)
        let pad = padding(for: pixelSize)
        let totalSize = imageSize(spriteSize: spriteSize, pixelSize: pixelSize)
        let view = Canvas { context, _ in
            let path = SpriteRenderer.silhouettePath(
                frame: frame, pixelSize: pixelSize,
                at: CGPoint(x: pad, y: pad), facing: facing)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.35), radius: pixelSize * blurRadiusFactor))
                layer.fill(path, with: .color(.black))
            }
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

/// frame + facing + pixelSize ごとにシャドウ画像をキャッシュするストア。
/// PastureView / CompanionPastureView が @State で保持し、Canvas クロージャ内で呼ぶ。
///
/// Canvas描画中に @State の値型をmutateするとSwiftUI側の更新対象になりやすく、
/// キャッシュ生成そのものが次フレームの再描画を誘発する。参照型の内部状態として保持し、
/// キャッシュヒット時はSwiftUIのView状態を変更しない。
public final class ShadowSpriteStore {
    private var cache: [ShadowSpriteCache.Key: Image] = [:]

    public init() {}

    @MainActor
    public func image(for frame: SpriteFrame, facing: Facing, pixelSize: CGFloat) -> Image {
        let key = ShadowSpriteCache.Key(frame: frame, facing: facing, pixelSize: pixelSize)
        if let cached = cache[key] { return cached }
        let image = ShadowSpriteCache.render(frame: frame, facing: facing, pixelSize: pixelSize)
        cache[key] = image
        return image
    }

    public var count: Int { cache.count }
}
