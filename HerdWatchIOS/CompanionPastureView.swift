import SwiftUI
import HerdWatchShared

/// iOS版放牧場ビュー。Mac版PastureViewの描画ロジック（SpriteRenderer/AgentAnimator/OverlayBadge）を再利用する。
struct CompanionPastureView: View {
    let store: CompanionStore
    var onFocus: (PastureAgent) -> Void = { _ in }
    var onReload: () -> Void = {}
    var pixelSize: CGFloat = 3.0

    @State private var hitRegistry = HitRegistry()
    @State private var animator = AgentAnimator()
    @State private var dragState = DragState()
    @State private var shadowStore = ShadowSpriteStore()
    @State private var spriteStore = SpriteImageStore()
    @State private var labelStore = AgentLabelImageStore()

    final class DragState {
        var identity: AgentIdentity?
        var moved = false
    }

    private static let grass = Color(red: 0.43, green: 0.60, blue: 0.33)
    private static let grassShade = Color(red: 0.38, green: 0.55, blue: 0.29)

    var body: some View {
        ZStack {
            Canvas { context, size in
                drawGround(context: context, size: size)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            GeometryReader { proxy in
                TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
                    Canvas { context, size in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let spriteSize = SpriteRenderer.spriteSize(pixelSize: pixelSize)
                        let bounds = safeBounds(size: size, insets: proxy.safeAreaInsets)
                        let movementArea = AgentAnimator.spriteOriginArea(in: bounds, spriteSize: spriteSize)
                        let items = animator.tick(
                            agents: store.sortedAgents,
                            bounds: bounds,
                            spriteSize: spriteSize,
                            time: time,
                            autoRearrangeOnResize: true,
                            movementArea: movementArea)
                        hitRegistry.reset()

                        let plans = items.map { item in
                            DrawPlan(item: item,
                                     origin: CGPoint(x: item.position.x.rounded(),
                                                     y: (item.position.y + item.bobOffset).rounded()),
                                     frame: item.agent.character.species
                                        .animation(for: item.agent.state)
                                        .frame(elapsed: time))
                        }
                        drawSilhouetteShadows(plans, context: context)
                        for plan in plans {
                            draw(plan, spriteSize: spriteSize, time: time, context: context)
                        }
                        drawStatusHints(context: context, size: size)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(count: 2).onEnded { tap in
                        if let identity = hitRegistry.hit(at: tap.location),
                           let agent = store.agents.first(where: { $0.identity == identity }) {
                            animator.triggerHop(identity, at: Date.timeIntervalSinceReferenceDate)
                            onFocus(agent)
                        }
                    }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            let spriteSize = SpriteRenderer.spriteSize(pixelSize: pixelSize)
                            let bounds = safeBounds(size: proxy.size, insets: proxy.safeAreaInsets)
                            let movementArea = AgentAnimator.spriteOriginArea(in: bounds, spriteSize: spriteSize)
                            let grabPoint = AgentAnimator.clampedGrabPoint(value.location,
                                                                           spriteSize: spriteSize,
                                                                           movementArea: movementArea)
                            if dragState.identity == nil, !dragState.moved {
                                dragState.identity = hitRegistry.hit(at: value.startLocation)
                                dragState.moved = true
                                if let identity = dragState.identity {
                                    animator.beginCarry(identity, at: grabPoint)
                                }
                            }
                            if let identity = dragState.identity {
                                animator.updateCarry(identity, to: grabPoint)
                            }
                        }
                        .onEnded { value in
                            let spriteSize = SpriteRenderer.spriteSize(pixelSize: pixelSize)
                            let bounds = safeBounds(size: proxy.size, insets: proxy.safeAreaInsets)
                            let movementArea = AgentAnimator.spriteOriginArea(in: bounds, spriteSize: spriteSize)
                            let grabPoint = AgentAnimator.clampedGrabPoint(value.location,
                                                                           spriteSize: spriteSize,
                                                                           movementArea: movementArea)
                            if let identity = dragState.identity {
                                animator.updateCarry(identity, to: grabPoint)
                                animator.endCarry(identity, spriteSize: spriteSize, movementArea: movementArea)
                            }
                            dragState.identity = nil
                            dragState.moved = false
                        }
                )
                .overlay(alignment: .top) {
                    if !store.isConnectedToHost { connectingHint }
                }
                .overlay(alignment: .topTrailing) {
                    reloadButton
                }
            }
        }
        .accessibilityLabel("放牧場")
    }

    private func safeBounds(size: CGSize, insets: EdgeInsets) -> CGRect {
        CGRect(x: insets.leading,
               y: insets.top,
               width: max(0, size.width - insets.leading - insets.trailing),
               height: max(0, size.height - insets.top - insets.bottom))
    }

    private struct DrawPlan {
        let item: AnimatedCharacter
        let origin: CGPoint
        let frame: SpriteFrame
    }

    private func drawSilhouetteShadows(_ plans: [DrawPlan], context: GraphicsContext) {
        let spriteSize = SpriteRenderer.spriteSize(pixelSize: pixelSize)
        let imageSize = ShadowSpriteCache.imageSize(spriteSize: spriteSize, pixelSize: pixelSize)
        for plan in plans {
            let image = shadowStore.image(for: plan.frame,
                                          facing: plan.item.facing,
                                          pixelSize: pixelSize)
            let offset = ShadowSpriteCache.drawOffset(origin: plan.origin, pixelSize: pixelSize)
            context.draw(image, in: CGRect(origin: offset, size: imageSize))
        }
    }

    private func draw(_ plan: DrawPlan, spriteSize: CGSize,
                      time: TimeInterval, context: GraphicsContext) {
        let item = plan.item
        let agent = item.agent
        let origin = plan.origin
        let rect = CGRect(origin: origin, size: spriteSize)

        let shadow = CGRect(x: item.position.x + spriteSize.width * 0.15,
                            y: item.position.y + spriteSize.height * 0.88,
                            width: spriteSize.width * 0.7,
                            height: spriteSize.height * 0.14)
        context.fill(Path(ellipseIn: shadow), with: .color(.black.opacity(0.14)))

        let image = spriteStore.image(for: plan.frame,
                                      species: agent.character.species,
                                      paletteIndex: agent.character.paletteIndex,
                                      facing: item.facing,
                                      pixelSize: pixelSize)
        let imageSize = SpriteImageCache.imageSize(spriteSize: spriteSize, pixelSize: pixelSize)
        let imageOrigin = SpriteImageCache.drawOffset(origin: origin, pixelSize: pixelSize)
        context.draw(image, in: CGRect(origin: imageOrigin, size: imageSize))
        let elapsed = agent.workingStartedAt.map { time - $0.timeIntervalSinceReferenceDate }
        OverlayBadge.draw(state: agent.state, in: context, above: rect,
                          time: time, facing: item.facing,
                          showElapsed: true, elapsed: elapsed)
        drawLabel(primary: agent.primaryLabel, secondary: agent.secondaryLabel,
                  state: agent.state, below: rect, context: context)

        hitRegistry.register(agent.identity, rect: rect)
    }

    private func drawLabel(primary: String, secondary: String,
                           state: AgentState, below rect: CGRect, context: GraphicsContext) {
        let fontSize: CGFloat = pixelSize <= 1.5 ? 9 : 11
        let label = labelStore.image(primary: primary,
                                     secondary: secondary,
                                     state: state,
                                     fontSize: fontSize)
        let origin = AgentLabelImageCache.drawOrigin(labelSize: label.size, below: rect)
        context.draw(label.image, in: CGRect(origin: origin, size: label.size))
    }

    private func drawGround(context: GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.grass))
        let patch = CGSize(width: 56, height: 40)
        var y: CGFloat = 0
        var rowIndex = 0
        while y < size.height {
            var x: CGFloat = (rowIndex % 2 == 0) ? 0 : patch.width / 2
            while x < size.width {
                if (Int(x / patch.width) + rowIndex) % 3 == 0 {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 10, height: 4)),
                                 with: .color(Self.grassShade))
                }
                x += patch.width
            }
            y += patch.height
            rowIndex += 1
        }
    }

    /// herdr未接続 or ホスト未接続時のヒント。
    private func drawStatusHints(context: GraphicsContext, size: CGSize) {
        guard store.isConnectedToHost, store.agents.isEmpty,
              hostConnectionStateIsLive else { return }
        let text = "エージェントがいません（Macでpaneを開くと現れます）"
        let label = context.resolve(Text(text).font(.system(size: 12)).foregroundStyle(Color.white))
        let textSize = label.measure(in: CGSize(width: size.width - 32, height: 60))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let background = CGRect(x: center.x - textSize.width / 2 - 12,
                                y: center.y - textSize.height / 2 - 8,
                                width: textSize.width + 24, height: textSize.height + 16)
        context.fill(Path(roundedRect: background, cornerRadius: 8),
                     with: .color(.black.opacity(0.45)))
        context.draw(label, at: center)
    }

    private var hostConnectionStateIsLive: Bool { store.hostConnectionState == "live" }

    private var reloadButton: some View {
        Button(action: onReload) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.42), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .padding(.trailing, 12)
        .accessibilityLabel("状態をリロード")
    }

    private var connectingHint: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.large).tint(.white)
            Text("MacのHerdWatchを探しています…\n同じWi-FiネットワークでHerdWatchを起動してください")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.6))
                .padding(.horizontal, 24)
        }
        .allowsHitTesting(false)
    }
}
