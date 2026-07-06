import SwiftUI

/// 足元ラベルを画像としてキャッシュする。
///
/// ラベルの内容と状態色は位置や時刻に依存しないため、毎フレーム Text の resolve/measure を
/// 繰り返さず、内容が変わったときだけオフスクリーン描画する。
public enum AgentLabelImageCache {
    public struct Key: Hashable {
        public let primary: String
        public let secondary: String
        public let state: AgentState
        public let fontSize: CGFloat

        public init(primary: String, secondary: String, state: AgentState, fontSize: CGFloat) {
            self.primary = primary
            self.secondary = secondary
            self.state = state
            self.fontSize = fontSize
        }
    }

    public struct RenderedLabel {
        public let image: Image
        public let size: CGSize
    }

    public static func drawOrigin(labelSize: CGSize, below rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX - labelSize.width / 2,
                y: rect.maxY + 3)
    }

    @MainActor
    public static func render(primary: String, secondary: String,
                              state: AgentState, fontSize: CGFloat) -> RenderedLabel {
        let primaryText = Text(primary)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
        let secondaryText = Text(secondary)
            .font(.system(size: fontSize, weight: .regular, design: .monospaced))
            .foregroundStyle(.white.opacity(0.72))
        let resolvedSizes = measure(primary: primaryText, secondary: secondaryText)
        let layout = layout(primarySize: resolvedSizes.primary,
                            secondarySize: resolvedSizes.secondary,
                            hasAccent: state.accentColor != nil)
        let view = Canvas { context, _ in
            let primaryResolved = context.resolve(primaryText)
            let secondaryResolved = context.resolve(secondaryText)
            draw(primaryText: primaryResolved,
                 secondaryText: secondaryResolved,
                 layout: layout,
                 state: state,
                 in: &context)
        }
        .frame(width: layout.totalSize.width, height: layout.totalSize.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        #if os(macOS)
        let image = Image(nsImage: renderer.nsImage ?? NSImage(size: layout.totalSize))
        #else
        let image = Image(uiImage: renderer.uiImage ?? UIImage())
        #endif
        return RenderedLabel(image: image, size: layout.totalSize)
    }

    @MainActor
    private static func measure(primary: Text, secondary: Text) -> (primary: CGSize, secondary: CGSize) {
        var primarySize = CGSize(width: 1, height: 1)
        var secondarySize = CGSize(width: 1, height: 1)
        let view = Canvas { context, _ in
            let bound = CGSize(width: 320, height: 24)
            primarySize = context.resolve(primary).measure(in: bound)
            secondarySize = context.resolve(secondary).measure(in: bound)
        }
        .frame(width: 1, height: 1)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        #if os(macOS)
        _ = renderer.nsImage
        #else
        _ = renderer.uiImage
        #endif
        return (primarySize, secondarySize)
    }

    private struct Layout {
        let totalSize: CGSize
        let background: CGRect
        let primaryCenter: CGPoint
        let secondaryCenter: CGPoint
    }

    private static func layout(primarySize: CGSize, secondarySize: CGSize,
                               hasAccent: Bool) -> Layout {
        let lineGap: CGFloat = 1
        let padH: CGFloat = 7
        let padV: CGFloat = 3
        let strokePad: CGFloat = hasAccent ? 1.25 : 0
        let contentWidth = max(primarySize.width, secondarySize.width)
        let contentHeight = primarySize.height + lineGap + secondarySize.height
        let background = CGRect(x: strokePad,
                                y: strokePad,
                                width: contentWidth + padH * 2,
                                height: contentHeight + padV * 2)
        return Layout(
            totalSize: CGSize(width: background.width + strokePad * 2,
                              height: background.height + strokePad * 2),
            background: background,
            primaryCenter: CGPoint(x: background.midX,
                                   y: background.minY + padV + primarySize.height / 2),
            secondaryCenter: CGPoint(x: background.midX,
                                     y: background.minY + padV + primarySize.height
                                        + lineGap + secondarySize.height / 2))
    }

    private static func draw(primaryText: GraphicsContext.ResolvedText,
                             secondaryText: GraphicsContext.ResolvedText,
                             layout: Layout,
                             state: AgentState,
                             in context: inout GraphicsContext) {
        let shape = Path(roundedRect: layout.background, cornerRadius: 6)
        let fillOpacity: Double = state.accentColor != nil ? 1.0 : 0.42
        context.fill(shape, with: .color(.black.opacity(fillOpacity)))
        if let accent = state.accentColor {
            context.stroke(shape, with: .color(accent), lineWidth: 2.5)
        }
        context.draw(primaryText, at: layout.primaryCenter)
        context.draw(secondaryText, at: layout.secondaryCenter)
    }
}

public final class AgentLabelImageStore {
    private var cache: [AgentLabelImageCache.Key: AgentLabelImageCache.RenderedLabel] = [:]

    public init() {}

    @MainActor
    public func image(primary: String, secondary: String,
                      state: AgentState, fontSize: CGFloat) -> AgentLabelImageCache.RenderedLabel {
        let key = AgentLabelImageCache.Key(primary: primary,
                                           secondary: secondary,
                                           state: state,
                                           fontSize: fontSize)
        if let cached = cache[key] { return cached }
        let image = AgentLabelImageCache.render(primary: primary,
                                                secondary: secondary,
                                                state: state,
                                                fontSize: fontSize)
        cache[key] = image
        return image
    }

    public var count: Int { cache.count }
}
