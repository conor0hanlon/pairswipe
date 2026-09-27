import Foundation

#if canImport(MultipeerConnectivity)
import MultipeerConnectivity
#endif

#if canImport(UIKit)
import UIKit
#endif

// A lightweight nearby host record used by the join sheet.
struct NearbyPairHost: Identifiable, Equatable {
    let id: String
    let displayName: String

    #if canImport(MultipeerConnectivity)
    fileprivate let peerID: MCPeerID
    #endif

    static func == (lhs: NearbyPairHost, rhs: NearbyPairHost) -> Bool {
        lhs.id == rhs.id
    }
}

// A simple observable service that exchanges Firebase invite data over the local network.
final class NearbyPairService: NSObject, ObservableObject {
    @Published var availableHosts: [NearbyPairHost] = []
    @Published var statusText: String = ""
    @Published var errorText: String?
    @Published var hostedPair: Pair?
    @Published var hostedPairWasShared = false
    @Published var isHosting = false
    @Published var isBrowsing = false
    @Published var isConnecting = false
    @Published var pendingInviteCode: String?

    #if canImport(MultipeerConnectivity)
    private struct NearbyInvitePayload: Codable {
        let inviteCode: String
        let hostName: String
    }

    private let serviceType = "pairswipe"
    private lazy var localPeerID = MCPeerID(displayName: NearbyPairService.localPeerDisplayName())
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var hasSentHostedPair = false
    #endif

    deinit {
        stop()
    }

    // Starts advertising a newly created pair to a nearby device.
    func startHosting(pair: Pair) {
        stop()
        hostedPair = pair
        hostedPairWasShared = false
        statusText = "Waiting for someone nearby to join this pair."
        errorText = nil
        isHosting = true

        #if canImport(MultipeerConnectivity)
        let session = makeSession()
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(
            peer: localPeerID,
            discoveryInfo: ["host": localPeerID.displayName],
            serviceType: serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        #else
        errorText = "Nearby pairing is not available on this device."
        isHosting = false
        #endif
    }

    // Starts browsing for nearby hosts that already created a pair.
    func startBrowsing() {
        stop()
        availableHosts = []
        statusText = "Looking for nearby pairs."
        errorText = nil
        isBrowsing = true

        #if canImport(MultipeerConnectivity)
        let session = makeSession()
        self.session = session

        let browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        #else
        errorText = "Nearby pairing is not available on this device."
        isBrowsing = false
        #endif
    }

    // Sends an invite request to a selected nearby host.
    func connect(to host: NearbyPairHost) {
        #if canImport(MultipeerConnectivity)
        guard let browser = browser, let session = session else { return }
        isConnecting = true
        statusText = "Connecting to \(host.displayName)."
        browser.invitePeer(host.peerID, to: session, withContext: nil, timeout: 12)
        #endif
    }

    // Clears the last received invite code after the UI has consumed it.
    func clearPendingInviteCode() {
        pendingInviteCode = nil
    }

    // Stops all nearby activity and resets the service to idle.
    func stop() {
        #if canImport(MultipeerConnectivity)
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil

        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil

        session?.disconnect()
        session?.delegate = nil
        session = nil

        hasSentHostedPair = false
        #endif

        availableHosts = []
        isHosting = false
        isBrowsing = false
        isConnecting = false
        statusText = ""
        errorText = nil
    }

    #if canImport(MultipeerConnectivity)
    // Builds a fresh encrypted multipeer session.
    private func makeSession() -> MCSession {
        let session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        return session
    }

    // Sends the Firebase invite code to the nearby device once the connection is ready.
    private func sendHostedPairIfNeeded(to peerID: MCPeerID) {
        guard
            !hasSentHostedPair,
            let pair = hostedPair,
            let session = session
        else {
            return
        }

        let payload = NearbyInvitePayload(inviteCode: pair.inviteCode, hostName: localPeerID.displayName)
        do {
            let data = try JSONEncoder().encode(payload)
            try session.send(data, toPeers: [peerID], with: .reliable)
            hasSentHostedPair = true
            hostedPairWasShared = true
            statusText = "Pair sent to \(peerID.displayName). They can join now."
        } catch {
            errorText = "Could not send the nearby pair."
        }
    }

    // Creates a readable device name for nearby discovery.
    private static func localPeerDisplayName() -> String {
        #if canImport(UIKit)
        let deviceName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !deviceName.isEmpty {
            return deviceName
        }
        #endif
        return "PairSwipe Device"
    }
    #endif
}

#if canImport(MultipeerConnectivity)
extension NearbyPairService: MCNearbyServiceAdvertiserDelegate {
    // Accepts one nearby invite so we can send the Firebase pair details over the session.
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            guard self.isHosting, let session = self.session else {
                invitationHandler(false, nil)
                return
            }
            self.statusText = "Connecting to \(peerID.displayName)."
            invitationHandler(true, session)
        }
    }

    // Surfaces advertiser startup failures to the UI.
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            self.errorText = "Nearby hosting could not start."
            self.statusText = error.localizedDescription
            self.isHosting = false
        }
    }
}

extension NearbyPairService: MCNearbyServiceBrowserDelegate {
    // Adds a discovered nearby host to the join list.
    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String : String]?) {
        DispatchQueue.main.async {
            let displayName = info?["host"] ?? peerID.displayName
            let host = NearbyPairHost(id: peerID.displayName, displayName: displayName, peerID: peerID)
            if !self.availableHosts.contains(host) {
                self.availableHosts.append(host)
                self.availableHosts.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            }
            if self.availableHosts.count == 1 && !self.isConnecting {
                self.statusText = "Choose a nearby pair to join."
            }
        }
    }

    // Removes a host when it is no longer visible on the network.
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.availableHosts.removeAll { $0.id == peerID.displayName }
            if self.availableHosts.isEmpty && !self.isConnecting {
                self.statusText = "Looking for nearby pairs."
            }
        }
    }

    // Surfaces browser startup failures to the UI.
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.errorText = "Nearby browsing could not start."
            self.statusText = error.localizedDescription
            self.isBrowsing = false
        }
    }
}

extension NearbyPairService: MCSessionDelegate {
    // Tracks connection progress and triggers the Firebase invite handoff.
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connecting:
                self.statusText = "Connecting to \(peerID.displayName)."
            case .connected:
                self.isConnecting = false
                if self.isHosting {
                    self.sendHostedPairIfNeeded(to: peerID)
                } else {
                    self.statusText = "Receiving pair details from \(peerID.displayName)."
                }
            case .notConnected:
                self.isConnecting = false
                if !self.hostedPairWasShared && self.isHosting {
                    self.statusText = "Waiting for someone nearby to join this pair."
                } else if self.isBrowsing {
                    self.statusText = self.availableHosts.isEmpty ? "Looking for nearby pairs." : "Choose a nearby pair to join."
                }
            @unknown default:
                self.isConnecting = false
            }
        }
    }

    // Receives the Firebase invite code that the host shared locally.
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            let payload = try JSONDecoder().decode(NearbyInvitePayload.self, from: data)
            DispatchQueue.main.async {
                self.pendingInviteCode = payload.inviteCode
                self.statusText = "Joining the pair from \(payload.hostName)."
            }
        } catch {
            DispatchQueue.main.async {
                self.errorText = "The nearby pair details were unreadable."
            }
        }
    }

    // Unused stream callback required by MCSessionDelegate.
    func session(_ session: MCSession,
                 didReceive stream: InputStream,
                 withName streamName: String,
                 fromPeer peerID: MCPeerID) {}

    // Unused resource-start callback required by MCSessionDelegate.
    func session(_ session: MCSession,
                 didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 with progress: Progress) {}

    // Unused resource-finish callback required by MCSessionDelegate.
    func session(_ session: MCSession,
                 didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 at localURL: URL?,
                 withError error: Error?) {}
}
#endif
