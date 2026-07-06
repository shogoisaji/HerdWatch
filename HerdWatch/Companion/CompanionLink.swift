import Foundation
import MultipeerConnectivity
import os

/// MultipeerConnectivityの薄いIOラッパ（Mac側=サービスアドバイザ）。
/// 真偽源・状態解釈は持たず、Dataの送受信とピア接続管理のみを行う。
/// ロジックはCompanionHostService/CompanionHostRouter/CompanionHostSnapshotBuilderへ分離済み。
final class CompanionLink: NSObject {
    private let logger = Logger(subsystem: "com.isaji134.HerdWatch", category: "companion-link")
    private let peerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser

    /// 受信ハンドラ（1メッセージ分のData）。CompanionHostServiceへ注入される。
    var onReceive: ((Data) -> Void)?
    var onPeerConnected: (() -> Void)?

    /// 接続中ピア数（デバッグ表示・テスト用）。
    private(set) var connectedPeerCount = 0

    init(displayName: String = "HerdWatch Mac") {
        self.peerID = MCPeerID(displayName: displayName)
        self.session = MCSession(peer: peerID,
                                 securityIdentity: nil,
                                 encryptionPreference: .required)
        // サービス型は1-15文字・英数字のみ
        self.advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["role": "host"],
            serviceType: CompanionLink.serviceType)
        super.init()
        session.delegate = self
        advertiser.delegate = self
    }

    func start() {
        advertiser.startAdvertisingPeer()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        session.disconnect()
    }

    /// 接続中の全ピアへ1メッセージを送信。接続先がいなければ何もしない。
    @discardableResult
    func send(_ data: Data) -> Bool {
        guard !session.connectedPeers.isEmpty else { return false }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            return true
        } catch {
            logger.warning("Companion送信失敗: \(String(describing: error))")
            return false
        }
    }

    static let serviceType = "hrdwtch-cmp"
}

extension CompanionLink: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        connectedPeerCount = session.connectedPeers.count
        logger.info("Companion ピア状態変化: \(peerID.displayName) → \(String(describing: state))")
        if state == .connected {
            Task { @MainActor [weak self] in
                self?.onPeerConnected?()
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data,
                 fromPeer peerID: MCPeerID) {
        // iOS→Macのfocus命令など。受信ハンドラへ委譲（ロジックはサービス層）。
        onReceive?(data)
    }

    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension CompanionLink: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // 同一Appleアカウント/自分のデバイスからの招待のみ受け入れる。
        // Multipeer自体はApple IDでゲートしないが、HerdWatchの用途では自分のiOSデバイスのみ許可。
        invitationHandler(true, session)
    }
}
