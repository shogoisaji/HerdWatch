import Foundation
import MultipeerConnectivity
import os

/// MultipeerConnectivityの薄いIOラッパ（iOS側=ブラウザ）。
/// MacのCompanionLink(アドバイザ)を発見し接続。Dataの送受信のみを行う。
/// 状態解釈・描画はCompanionStore/CompanionPastureViewへ分離済み。
final class CompanionClient: NSObject {
    private let logger = Logger(subsystem: "com.isaji.HerdWatchIos", category: "companion-client")
    private let peerID: MCPeerID
    private let session: MCSession
    private let browser: MCNearbyServiceBrowser

    /// 受信ハンドラ（Macからのスナップショット）。CompanionStoreへ注入される。
    var onReceive: ((Data) -> Void)?
    /// 接続状態変化の通知。
    var onStateChange: ((Bool) -> Void)?

    private(set) var isConnected = false

    init(displayName: String = "HerdWatch Companion") {
        self.peerID = MCPeerID(displayName: displayName)
        self.session = MCSession(peer: peerID,
                                 securityIdentity: nil,
                                 encryptionPreference: .required)
        self.browser = MCNearbyServiceBrowser(peer: peerID,
                                              serviceType: CompanionLinkServiceType)
        super.init()
        session.delegate = self
        browser.delegate = self
    }

    func start() {
        browser.startBrowsingForPeers()
    }

    func stop() {
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    /// 接続中のMacへ1メッセージを送信。未接続なら何もしない。
    func send(_ data: Data) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            logger.warning("Companion送信失敗: \(String(describing: error))")
        }
    }
}

extension CompanionClient: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        let connected = (state == .connected)
        isConnected = connected
        logger.info("Companion接続状態: \(peerID.displayName) → \(String(describing: state))")
        Task { @MainActor [weak self] in
            self?.onStateChange?(connected)
        }
    }

    func session(_ session: MCSession, didReceive data: Data,
                 fromPeer peerID: MCPeerID) {
        onReceive?(data)
    }

    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension CompanionClient: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        // 自分のMacホストのみに接続（role=hostを提示しているピア）。
        guard info?["role"] == "host" else { return }
        logger.info("Companion: ホスト発見 \(peerID.displayName) — 招待を送信")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser,
                 lostPeer peerID: MCPeerID) {
        logger.info("Companion: ホスト喪失 \(peerID.displayName)")
    }
}

/// Mac側CompanionLink.serviceTypeと同じ値。文字列定数を共有するためここに置く。
let CompanionLinkServiceType = "hrdwtch-cmp"
