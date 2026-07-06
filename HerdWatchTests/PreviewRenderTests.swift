import SwiftUI
import XCTest
import HerdWatchShared
@testable import HerdWatch

/// 全種×全状態のスプライトをオフスクリーン描画してPNGに落とす目視検証補助。
/// 描画がクラッシュしないことのassertに加え、成果物PNGを人間/AIがレビューする。
@MainActor
final class PreviewRenderTests: XCTestCase {
    func testRenderSpeciesStateMatrix() throws {
        let view = SpriteMatrixView()
            .frame(width: 6 * 150 + 140, height: CGFloat(Species.allCases.count) * 130 + 40)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        let image = try XCTUnwrap(renderer.nsImage, "matrix render should produce an image")
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
            .representation(using: .png, properties: [:]))
        let out = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("herdwatch-sprite-matrix.png")
        try png.write(to: out)
        print("sprite matrix written to: \(out.path)")
    }
}

extension PreviewRenderTests {
    /// 実際のPastureView（2段ラベル・影・バッジ込み）をfakeデータで描画して確認する。
    func testRenderPastureScene() async throws {
        let fake = FakeTransport(panes: [
            ("wA:p1", "idle"), ("wA:p2", "working"), ("wB:p1", "blocked"),
            ("wB:p3", "done"), ("wC:p1", "unknown"),
        ])
        var config = HerdrClient.Config()
        config.pollInterval = nil
        config.resubscribeDebounce = .milliseconds(0)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("herdwatch-scene-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = PastureStore(client: HerdrClient(transport: fake, config: config),
                                 assignments: CharacterAssignmentStore(directory: tempDir))
        store.start()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(store.agentsByID.count, 5)

        let view = PastureView(store: store, interactive: false, showWorkingElapsed: true)
            .frame(width: 760, height: 480)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?
            .representation(using: .png, properties: [:]))
        let out = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("herdwatch-pasture-scene.png")
        try png.write(to: out)
        print("pasture scene written to: \(out.path)")
        store.stop()
    }
}

/// 種×状態のマトリクス（行=種、列=状態+carried）。パレットは行内で巡回。
private struct SpriteMatrixView: View {
    private let pixelSize: CGFloat = 4
    private let states: [AgentState] = [.idle, .working, .blocked, .done, .unknown]

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(red: 0.43, green: 0.60, blue: 0.33)))
            let spriteSize = SpriteRenderer.spriteSize(pixelSize: pixelSize)

            for (row, species) in Species.allCases.enumerated() {
                let y = 30 + CGFloat(row) * 130
                let name = context.resolve(Text(species.rawValue)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white))
                context.draw(name, at: CGPoint(x: 60, y: y + spriteSize.height / 2))

                for (col, state) in states.enumerated() {
                    let origin = CGPoint(x: 140 + CGFloat(col) * 150, y: y)
                    let rect = CGRect(origin: origin, size: spriteSize)
                    let palette = CharacterPalette.palette(
                        for: species, index: col % CharacterAssignmentStore.palettesPerSpecies)
                    let animation = species.animation(for: state)
                    // 歩行は2フレーム目、まばたきはblinkフレームが見えるよう位相を選ぶ
                    let frame = state == .working ? animation.frames[1] : animation.frames.last!
                    let facing: Facing = col % 2 == 0 ? .left : .right
                    SpriteRenderer.draw(frame: frame, palette: palette,
                                        in: context, at: origin,
                                        pixelSize: pixelSize, facing: facing)
                    OverlayBadge.draw(state: state, in: context, above: rect,
                                      time: 0.2, facing: facing,
                                      showElapsed: state == .working,
                                      elapsed: state == .working ? 19 * 60 : nil)
                    let label = context.resolve(Text(state.rawValue)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9)))
                    context.draw(label, at: CGPoint(x: rect.midX, y: rect.maxY + 12))
                }

                // carried（ドラッグ中）列
                let origin = CGPoint(x: 140 + CGFloat(states.count) * 150, y: y)
                let rect = CGRect(origin: origin, size: spriteSize)
                SpriteRenderer.draw(frame: species.carriedAnimation.frames[0],
                                    palette: CharacterPalette.palette(for: species, index: 0),
                                    in: context, at: origin,
                                    pixelSize: pixelSize, facing: .left)
                let label = context.resolve(Text("carried")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9)))
                context.draw(label, at: CGPoint(x: rect.midX, y: rect.maxY + 12))
            }
        }
    }
}
