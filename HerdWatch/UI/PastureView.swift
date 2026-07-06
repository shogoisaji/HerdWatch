import SwiftUI
import HerdWatchShared

struct PastureView: View {
    let store: PastureStore
    var onFocusAgent: (PastureAgent) -> Void = { _ in }
    var onRerollAgent: (PastureAgent) -> Void = { _ in }
    /// ImageRendererによるオフスクリーン描画ではNSView層が描けないため、テストでfalseにする
    var interactive: Bool = true
    var pixelSize: CGFloat = CharacterSize.medium.pixelSize
    var autoRearrangeOnResize: Bool = false
    var background: PastureBackground = .grassland
    /// working中の経過時間を炎の横に表示するか（設定トグル）。
    var showWorkingElapsed: Bool = false
    /// リロード(⌘R)・全振り直し(⇧⌘R)コマンドから直接操作できるよう、呼び出し元（HerdWatchApp）が所有する
    var animator = AgentAnimator()

    // 設定変更でビューが再生成されても、ドラッグ中の掴みを失わないよう@Stateで保持
    @State private var hitRegistry = HitRegistry()
    @State private var dragState = DragState()
    @State private var menuPresenter = CharacterMenuPresenter()
    @State private var shadowStore = ShadowSpriteStore()
    @State private var spriteStore = SpriteImageStore()
    @State private var labelStore = AgentLabelImageStore()
    @State private var groundCache = GroundImageCache()

    final class DragState {
        var identity: AgentIdentity?
        var moved = false
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                if let groundImage = groundCache.image(for: background, size: size) {
                    context.draw(groundImage, in: CGRect(origin: .zero, size: size))
                } else {
                    GroundRenderer.draw(background: background, in: context, size: size)
                }

                let spriteSize = SpriteRenderer.spriteSize(pixelSize: pixelSize)
                let items = animator.tick(agents: store.sortedAgents,
                                          bounds: CGRect(origin: .zero, size: size),
                                          spriteSize: spriteSize,
                                          time: time,
                                          autoRearrangeOnResize: autoRearrangeOnResize)
                hitRegistry.reset()

                let plans = items.map { item in
                    DrawPlan(item: item,
                            origin: CGPoint(x: item.position.x.rounded(),
                                            y: (item.position.y + item.bobOffset).rounded()),
                            frame: (item.isCarried
                                ? item.agent.character.species.carriedAnimation
                                : item.agent.character.species.animation(for: item.agent.state))
                                .frame(elapsed: time))
                }
                drawSilhouetteShadows(plans, context: context)
                for plan in plans {
                    draw(plan, spriteSize: spriteSize, time: time, context: context)
                }
                drawConnectionState(context: context, size: size)
            }
        }
        .gesture(ExclusiveGesture(
            // ⌥+クリック = キャラ振り直し / ダブルクリック = paneへフォーカス
            SpatialTapGesture().modifiers(.option).onEnded { tap in
                if let identity = hitRegistry.hit(at: tap.location),
                   let agent = store.agentsByID[identity] {
                    onRerollAgent(agent)
                }
            },
            SpatialTapGesture(count: 2).onEnded { tap in
                if let identity = hitRegistry.hit(at: tap.location),
                   let agent = store.agentsByID[identity] {
                    // フォーカス指示を受けた合図に小さく跳ねる
                    animator.triggerHop(identity, at: Date.timeIntervalSinceReferenceDate)
                    onFocusAgent(agent)
                }
            }
        ))
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if dragState.identity == nil, !dragState.moved {
                        dragState.identity = hitRegistry.hit(at: value.startLocation)
                        dragState.moved = true
                        if let id = dragState.identity {
                            animator.beginCarry(id, at: value.location)
                        }
                    }
                    if let id = dragState.identity {
                        animator.updateCarry(id, to: value.location)
                    }
                }
                .onEnded { _ in
                    if let id = dragState.identity {
                        animator.endCarry(id)
                    }
                    dragState.identity = nil
                    dragState.moved = false
                }
        )
        .overlay {
            if interactive {
                RightClickCatcher { point, nsView in
                    guard let identity = hitRegistry.hit(at: point),
                          let agent = store.agentsByID[identity] else { return }
                    menuPresenter.show(
                        for: agent, at: point, in: nsView,
                        onSelectSpecies: { store.setCharacter(identity, species: $0,
                                                              paletteIndex: agent.character.paletteIndex) },
                        onSelectPalette: { store.setCharacter(identity, species: agent.character.species,
                                                              paletteIndex: $0) },
                        onReroll: { store.reroll(identity) })
                }
            }
        }
        .overlay(alignment: .top) {
            // 旧タイトルバー領域のグラデーション（信号機ボタンの視認性確保）
            LinearGradient(colors: [.black.opacity(0.5), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 32)
                .allowsHitTesting(false)
        }
        .overlay {
            if isConnectingToHerdr {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    if case .reconnecting(let attempt) = store.connectionState {
                        Text(Self.reconnectingHint(attempt: attempt))
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.6))
                            .padding(.horizontal, 24)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("放牧場")
    }

    /// 描画1体分の下ごしらえ（位置スナップ・フレーム選択をまとめて先に済ませる）。
    /// シルエットの一括シャドウ化と本体描画の両方が同じorigin/frameを参照するため必要。
    private struct DrawPlan {
        let item: AnimatedCharacter
        let origin: CGPoint  // 小数座標だとドット間にアンチエイリアスの継ぎ目が出るため、整数ptへスナップ済み
        let frame: SpriteFrame
    }

    /// 重なったキャラを見分けやすいよう、外形に薄い縁取り状のシャドウを入れる。
    /// シャドウの形は frame + facing + pixelSize にのみ依存するため、各キャラのシャドウ画像を
    /// `shadowStore` でキャッシュし、毎フレームの `drawLayer` + shadowフィルタ（オフスクリーンブラー）
    /// を回避して `context.draw(image, in:)` の1回の貼り付けで済ませる。
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

        // 接地感のための影（跳ねても影は地面に残る。持ち上げ中は影を出さない）
        if !item.isCarried {
            let shadow = CGRect(x: item.position.x + spriteSize.width * 0.15,
                                y: item.position.y + spriteSize.height * 0.88,
                                width: spriteSize.width * 0.7,
                                height: spriteSize.height * 0.14)
            context.fill(Path(ellipseIn: shadow), with: .color(.black.opacity(0.14)))
        }

        let image = spriteStore.image(for: plan.frame,
                                      species: agent.character.species,
                                      paletteIndex: agent.character.paletteIndex,
                                      facing: item.facing,
                                      pixelSize: pixelSize)
        let imageSize = SpriteImageCache.imageSize(spriteSize: spriteSize, pixelSize: pixelSize)
        let imageOrigin = SpriteImageCache.drawOffset(origin: origin, pixelSize: pixelSize)
        context.draw(image, in: CGRect(origin: imageOrigin, size: imageSize))
        if !item.isCarried {
            let elapsed = agent.workingStartedAt.map { time - $0.timeIntervalSinceReferenceDate }
            OverlayBadge.draw(state: agent.state, in: context, above: rect,
                              time: time, facing: item.facing,
                              showElapsed: showWorkingElapsed, elapsed: elapsed)
        }
        drawLabel(primary: agent.primaryLabel, secondary: agent.secondaryLabel,
                  state: agent.state, below: rect, context: context)

        hitRegistry.register(agent.identity, rect: rect)
    }

    static let defaultLabelFontSize: CGFloat = 11

    /// 極小サイズは他より一段小さいフォントに、大サイズは一段大きいフォントにして
    /// キャラとのバランスを保つ
    static func labelFontSize(pixelSize: CGFloat) -> CGFloat {
        if pixelSize <= CharacterSize.tiny.pixelSize {
            return defaultLabelFontSize - 2
        } else if pixelSize >= CharacterSize.large.pixelSize {
            return defaultLabelFontSize + 2
        } else {
            return defaultLabelFontSize
        }
    }

    /// 2段ラベル: 上段=workspace名（強調）、下段=agent名+pane番号（控えめ）。
    /// idle以外はaccentで状態色の枠線を付け、遠目にも状態が伝わるようにする。
    private func drawLabel(primary: String, secondary: String,
                           state: AgentState, below rect: CGRect, context: GraphicsContext) {
        let fontSize = Self.labelFontSize(pixelSize: pixelSize)
        let label = labelStore.image(primary: primary,
                                     secondary: secondary,
                                     state: state,
                                     fontSize: fontSize)
        let origin = AgentLabelImageCache.drawOrigin(labelSize: label.size, below: rect)
        context.draw(label.image, in: CGRect(origin: origin, size: label.size))
    }

    /// herdrに未接続の間、Canvas側の状態表示は出さない（代わりにローディングインディケーターのみ表示）
    private func drawConnectionState(context: GraphicsContext, size: CGSize) {
        guard case .live = store.connectionState, store.agentsByID.isEmpty else { return }
        let text = "エージェントがいません（herdrでpaneを開くと現れます）"
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

    private var isConnectingToHerdr: Bool {
        switch store.connectionState {
        case .live: false
        case .connecting, .reconnecting: true
        }
    }

    static func reconnectingHint(attempt: Int) -> String {
        "herdrへ再接続中(\(attempt)回目)… herdrが起動しているか確認してください"
    }
}
