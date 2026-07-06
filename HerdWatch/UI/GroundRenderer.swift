import SwiftUI

/// 地面描画を PastureView から切り出した純粋描画ルーチン。
/// 地面は完全に静的（背景種 + サイズが同じなら結果不変）なので、
/// GroundImageCache で Image 化してキャッシュする前提。
enum GroundRenderer {
    static let grass = Color(red: 0.43, green: 0.60, blue: 0.33)
    static let grassShade = Color(red: 0.38, green: 0.55, blue: 0.29)
    static let sand = Color(red: 0.71, green: 0.61, blue: 0.44)
    static let stone = Color(red: 0.57, green: 0.54, blue: 0.50)
    static let stoneDark = Color(red: 0.44, green: 0.41, blue: 0.38)
    // キャラの視認性を優先し、レンガは低彩度・低コントラストに抑える
    static let mortar = Color(red: 0.60, green: 0.47, blue: 0.41)
    static let brickRed = Color(red: 0.55, green: 0.39, blue: 0.33)
    static let brickDark = Color(red: 0.51, green: 0.36, blue: 0.30)

    static func draw(background: PastureBackground, in context: GraphicsContext, size: CGSize) {
        switch background {
        case .grassland: drawGrassland(in: context, size: size)
        case .wasteland: drawWasteland(in: context, size: size)
        case .brick: drawBrick(in: context, size: size)
        }
    }

    static func drawGrassland(in context: GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(grass))
        // 単調さを避ける固定パターンの草地の濃淡（動かない・主張しない）
        let patch = CGSize(width: 56, height: 40)
        var y: CGFloat = 0
        var rowIndex = 0
        while y < size.height {
            var x: CGFloat = (rowIndex % 2 == 0) ? 0 : patch.width / 2
            while x < size.width {
                if (Int(x / patch.width) + rowIndex) % 3 == 0 {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 10, height: 4)),
                                 with: .color(grassShade))
                }
                x += patch.width
            }
            y += patch.height
            rowIndex += 1
        }
    }

    /// 砂地に大小の石を散らす。草地と同じく固定パターン（動かない・主張しない）
    static func drawWasteland(in context: GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(sand))
        let patch = CGSize(width: 64, height: 48)
        var y: CGFloat = 0
        var rowIndex = 0
        while y < size.height {
            var x: CGFloat = (rowIndex % 2 == 0) ? 0 : patch.width / 2
            var colIndex = 0
            while x < size.width {
                switch (colIndex * 7 + rowIndex * 13) % 6 {
                case 0:
                    // 大きめの岩: 影を1ptずらして立体感を出す
                    let rock = CGRect(x: x + 10, y: y + 12, width: 11, height: 8)
                    context.fill(Path(ellipseIn: rock.offsetBy(dx: 1, dy: 1)),
                                 with: .color(stoneDark))
                    context.fill(Path(ellipseIn: rock), with: .color(stone))
                case 3:
                    context.fill(Path(ellipseIn: CGRect(x: x + 36, y: y + 30, width: 5, height: 4)),
                                 with: .color(stoneDark))
                default:
                    break
                }
                x += patch.width
                colIndex += 1
            }
            y += patch.height
            rowIndex += 1
        }
    }

    /// レンガ積み: 目地の上に半個ずらしの段積み。色を2種混ぜて単調さを避ける
    static func drawBrick(in context: GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(mortar))
        let brick = CGSize(width: 46, height: 20)
        let gap: CGFloat = 3
        var y: CGFloat = 0
        var rowIndex = 0
        while y < size.height {
            var x: CGFloat = (rowIndex % 2 == 0) ? 0 : -(brick.width + gap) / 2
            var colIndex = 0
            while x < size.width {
                let color = (colIndex + rowIndex * 3) % 4 == 0 ? brickDark : brickRed
                context.fill(Path(roundedRect: CGRect(x: x, y: y, width: brick.width,
                                                      height: brick.height),
                                  cornerRadius: 2),
                             with: .color(color))
                x += brick.width + gap
                colIndex += 1
            }
            y += brick.height + gap
            rowIndex += 1
        }
    }
}

/// 背景種 + サイズごとに地面画像をキャッシュする。
/// PastureView が @State で保持し、Canvas クロージャ内で呼ぶ。
/// サイズが変わるか背景が切り替わるまで同じ Image を使い回す。
final class GroundImageCache {
    private var image: Image?
    private var key: Key?

    struct Key: Equatable {
        let background: PastureBackground
        let size: CGSize
    }

    @MainActor
    func image(for background: PastureBackground, size: CGSize) -> Image? {
        guard size.width > 0, size.height > 0 else { return nil }
        let key = Key(background: background, size: size)
        if key == self.key, let image { return image }
        let view = Canvas { context, s in
            GroundRenderer.draw(background: background, in: context, size: s)
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let nsImage = renderer.nsImage else { return nil }
        let newImage = Image(nsImage: nsImage)
        self.key = key
        self.image = newImage
        return newImage
    }
}
