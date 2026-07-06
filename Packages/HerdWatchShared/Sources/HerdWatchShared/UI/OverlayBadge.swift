import SwiftUI

/// キャラ頭上の状態表示（blocked「!」/ done「✓」/ unknown「?」/ working=周回ブロック付き経過時間）。
public enum OverlayBadge {
    public static func draw(state: AgentState,
                     in context: GraphicsContext,
                     above spriteRect: CGRect,
                     time: TimeInterval = 0,
                     facing: Facing = .left,
                     showElapsed: Bool = false,
                     elapsed: TimeInterval? = nil) {
        if state == .working {
            if showElapsed {
                drawOrbitBadge(elapsed: elapsed ?? 0, in: context, above: spriteRect, time: time)
            } else {
                drawActivityBadge(in: context, above: spriteRect, time: time)
            }
            return
        }

        let symbolText: String?
        switch state {
        case .blocked: symbolText = "!"
        case .done: symbolText = "✓"
        case .unknown: symbolText = "?"
        case .idle, .working: symbolText = nil
        }
        guard let symbolText, let background = state.accentColor else { return }

        let size: CGFloat = max(14, spriteRect.width * 0.32)
        let center = CGPoint(x: spriteRect.midX, y: spriteRect.minY - size * 0.7)
        let bubble = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)

        context.fill(Path(ellipseIn: bubble), with: .color(background))
        // 吹き出しのしっぽ
        var tail = Path()
        tail.move(to: CGPoint(x: bubble.midX - size * 0.15, y: bubble.maxY - 1))
        tail.addLine(to: CGPoint(x: bubble.midX + size * 0.15, y: bubble.maxY - 1))
        tail.addLine(to: CGPoint(x: bubble.midX, y: bubble.maxY + size * 0.25))
        tail.closeSubpath()
        context.fill(tail, with: .color(background))

        let text = Text(symbolText)
            .font(.system(size: size * 0.7, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
        context.draw(text, at: center)
    }

    /// working: シンプルな時間フレームの外周を5連ブロックが時計回りに回るバッジ。
    private static func drawOrbitBadge(elapsed: TimeInterval,
                                       in context: GraphicsContext,
                                       above spriteRect: CGRect,
                                       time: TimeInterval) {
        let fontSize = max(9, spriteRect.width * 0.16)
        let px = max(1, spriteRect.width / CGFloat(SpriteFrame.width))
        let label = WorkingElapsedFormatter.format(seconds: elapsed)
        let text = Text(label)
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
        let resolved = context.resolve(text)
        let measured = resolved.measure(in: CGSize(width: 160, height: fontSize * 2))

        let padH: CGFloat = 6
        let padV: CGFloat = 3
        let bgW = measured.width + padH * 2
        let bgH = measured.height + padV * 2
        let bg = CGRect(x: spriteRect.midX - bgW / 2,
                        y: spriteRect.minY - bgH - px * 2,
                        width: bgW,
                        height: bgH)
        let orbitRect = bg.insetBy(dx: -px * 0.6, dy: -px * 0.6)

        context.fill(Path(roundedRect: bg, cornerRadius: 4),
                     with: .color(Color(red: 0.03, green: 0.08, blue: 0.12).opacity(0.86)))
        context.stroke(Path(roundedRect: bg, cornerRadius: 4),
                       with: .color(Color(red: 0.12, green: 0.55, blue: 0.90).opacity(0.9)),
                       lineWidth: 1)

        drawOrbitingBlocks(in: context, around: orbitRect, pixelSize: px, time: time)

        let shadowText = Text(label)
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.black.opacity(0.7))
        context.draw(shadowText, at: CGPoint(x: bg.midX + 1, y: bg.midY + 1))
        context.draw(resolved, at: CGPoint(x: bg.midX, y: bg.midY))
    }

    /// workingの状態だけ示す軽量バッジ。経過時間非表示時はText生成・計測を避ける。
    private static func drawActivityBadge(in context: GraphicsContext,
                                          above spriteRect: CGRect,
                                          time: TimeInterval) {
        let px = max(1, spriteRect.width / CGFloat(SpriteFrame.width))
        let size = max(14, spriteRect.width * 0.28)
        let center = CGPoint(x: spriteRect.midX, y: spriteRect.minY - size * 0.75)
        let bg = CGRect(x: center.x - size / 2,
                        y: center.y - size / 2,
                        width: size,
                        height: size)
        let orbitRect = bg.insetBy(dx: -px * 0.45, dy: -px * 0.45)

        context.fill(Path(ellipseIn: bg),
                     with: .color(Color(red: 0.03, green: 0.08, blue: 0.12).opacity(0.86)))
        context.stroke(Path(ellipseIn: bg),
                       with: .color(Color(red: 0.12, green: 0.55, blue: 0.90).opacity(0.9)),
                       lineWidth: 1)
        drawOrbitingBlocks(in: context, around: orbitRect, pixelSize: px, time: time)
    }

    private static func drawOrbitingBlocks(in context: GraphicsContext,
                                           around rect: CGRect,
                                           pixelSize px: CGFloat,
                                           time: TimeInterval) {
        let blockSize = max(3, px * 1.25)
        let cycle: CGFloat = 1.25
        let head = CGFloat(time.truncatingRemainder(dividingBy: TimeInterval(cycle))) / cycle
        let blockCount = 5
        let spacing: CGFloat = 0.035
        for i in 0..<blockCount {
            let progress = (head - CGFloat(i) * spacing).truncatingRemainder(dividingBy: 1)
            let normalized = progress < 0 ? progress + 1 : progress
            let point = pointOnRectPerimeter(normalized, rect: rect)
            let opacity = 1.0 - Double(i) * 0.10
            let color = i == 0
                ? Color(red: 0.70, green: 0.95, blue: 1.0)
                : Color(red: 0.12, green: 0.68, blue: 1.0).opacity(opacity)
            let block = CGRect(x: point.x - blockSize / 2,
                               y: point.y - blockSize / 2,
                               width: blockSize,
                               height: blockSize)
            context.fill(Path(block), with: .color(color))
        }
    }

    private static func pointOnRectPerimeter(_ progress: CGFloat, rect: CGRect) -> CGPoint {
        let w = rect.width
        let h = rect.height
        let perimeter = max(1, 2 * (w + h))
        let distance = progress * perimeter
        if distance < w {
            return CGPoint(x: rect.minX + distance, y: rect.minY)
        }
        if distance < w + h {
            return CGPoint(x: rect.maxX, y: rect.minY + distance - w)
        }
        if distance < w * 2 + h {
            return CGPoint(x: rect.maxX - (distance - w - h), y: rect.maxY)
        }
        return CGPoint(x: rect.minX, y: rect.maxY - (distance - w * 2 - h))
    }
}
