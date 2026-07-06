import AppKit
import SwiftUI
import HerdWatchShared

/// 右クリックだけを拾い、それ以外のイベント（左クリック・ドラッグ）は下のCanvasへ素通しする層。
struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: (CGPoint, NSView) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onRightClick = onRightClick
    }

    final class CatcherView: NSView {
        var onRightClick: ((CGPoint, NSView) -> Void)?

        override var isFlipped: Bool { true }  // SwiftUI座標系（左上原点）に合わせる

        override func hitTest(_ point: NSPoint) -> NSView? {
            // 右クリック系のイベントのときだけ自分が受け、他は透過する
            switch NSApp.currentEvent?.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return super.hitTest(point)
            default:
                return nil
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onRightClick?(point, self)
        }
    }
}

/// 右クリックメニュー: 種類・カラーの明示選択とランダム振り直し。
@MainActor
final class CharacterMenuPresenter: NSObject {
    private var onSelectSpecies: ((Species) -> Void)?
    private var onSelectPalette: ((Int) -> Void)?
    private var onReroll: (() -> Void)?

    private static let speciesNames: [Species: String] = [
        .sheep: "羊", .cow: "牛", .chicken: "鶏", .pig: "豚", .deer: "鹿", .duck: "アヒル", .elephant: "象",
    ]

    func show(for agent: PastureAgent,
              at point: NSPoint, in view: NSView,
              onSelectSpecies: @escaping (Species) -> Void,
              onSelectPalette: @escaping (Int) -> Void,
              onReroll: @escaping () -> Void) {
        self.onSelectSpecies = onSelectSpecies
        self.onSelectPalette = onSelectPalette
        self.onReroll = onReroll

        let menu = NSMenu()
        let header = NSMenuItem(title: agent.displayLabel, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let speciesMenu = NSMenu()
        for species in Species.allCases {
            let item = NSMenuItem(title: Self.speciesNames[species] ?? species.rawValue,
                                  action: #selector(selectSpecies(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = species.rawValue
            item.state = agent.character.species == species ? .on : .off
            item.image = Self.swatch(color: CharacterPalette
                .palette(for: species, index: agent.character.paletteIndex).body)
            speciesMenu.addItem(item)
        }
        let speciesItem = NSMenuItem(title: "種類", action: nil, keyEquivalent: "")
        speciesItem.submenu = speciesMenu
        menu.addItem(speciesItem)

        let paletteMenu = NSMenu()
        for index in 0..<CharacterAssignmentStore.palettesPerSpecies {
            let item = NSMenuItem(title: "カラー \(index + 1)",
                                  action: #selector(selectPalette(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = index
            item.state = agent.character.paletteIndex == index ? .on : .off
            item.image = Self.swatch(color: CharacterPalette
                .palette(for: agent.character.species, index: index).body)
            paletteMenu.addItem(item)
        }
        let paletteItem = NSMenuItem(title: "カラー", action: nil, keyEquivalent: "")
        paletteItem.submenu = paletteMenu
        menu.addItem(paletteItem)

        menu.addItem(.separator())
        let reroll = NSMenuItem(title: "ランダムに振り直す", action: #selector(rerollAction), keyEquivalent: "")
        reroll.target = self
        menu.addItem(reroll)

        menu.popUp(positioning: nil, at: point, in: view)
    }

    @objc private func selectSpecies(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let species = Species(rawValue: raw) else { return }
        onSelectSpecies?(species)
    }

    @objc private func selectPalette(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        onSelectPalette?(index)
    }

    @objc private func rerollAction() {
        onReroll?()
    }

    private static func swatch(color: Color) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        return NSImage(size: size, flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
            return true
        }
    }
}
