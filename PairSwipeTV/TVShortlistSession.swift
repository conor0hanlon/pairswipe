import Foundation
import FirebaseAuth
@preconcurrency import FirebaseFirestore

// The small data model used by the Apple TV app.
struct TVShortlistTitle: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let overview: String
    let posterURL: URL?
    let backdropURL: URL?
    let providers: [String]
    let score: Double?
}

// Owns sign-in, room connection, and the live shortlist listener.
// Keeping this work in one object makes the SwiftUI screen easy to understand.
@MainActor
final class TVShortlistSession: ObservableObject {
    @Published private(set) var isSigningIn = true
    @Published private(set) var isConnecting = false
    @Published private(set) var roomName = "PairSwipe"
    @Published private(set) var pairID: String?
    @Published private(set) var titles: [TVShortlistTitle] = []
    @Published var errorMessage: String?

    private let database = Firestore.firestore()
    private var matchesListener: ListenerRegistration?
    private var titleListeners: [String: ListenerRegistration] = [:]
    private var orderedTitleIDs: [String] = []
    private var titlesByID: [String: TVShortlistTitle] = [:]

    init() {
        signInAndRestoreRoom()
    }

    deinit {
        matchesListener?.remove()
        titleListeners.values.forEach { $0.remove() }
    }

    // Uses Firebase anonymous authentication, matching the iPhone app.
    private func signInAndRestoreRoom() {
        if Auth.auth().currentUser != nil {
            finishSignIn()
            return
        }

        Auth.auth().signInAnonymously { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.isSigningIn = false
                    self?.errorMessage = "Could not sign in: \(error.localizedDescription)"
                    return
                }
                self?.finishSignIn()
            }
        }
    }

    // Restores the last room so the television normally opens straight to the shortlist.
    private func finishSignIn() {
        isSigningIn = false
        guard let savedPairID = UserDefaults.standard.string(forKey: "tvPairID") else {
            return
        }

        pairID = savedPairID
        roomName = UserDefaults.standard.string(forKey: "tvRoomName") ?? "PairSwipe"
        startListening(pairID: savedPairID)
    }

    // Exchanges the six-character iPhone invite code for read-only shortlist access.
    func connect(inviteCode: String) {
        let code = inviteCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard code.count == 6 else {
            errorMessage = "Enter the six-character room code from the iPhone app."
            return
        }
        guard let userID = Auth.auth().currentUser?.uid else {
            errorMessage = "Apple TV is still signing in. Please try again."
            return
        }

        isConnecting = true
        errorMessage = nil
        let database = database

        database.collection("invites").document(code).getDocument { [weak self] invite, error in
            guard let self else { return }
            guard error == nil,
                  let pairID = invite?.data()?["pairId"] as? String,
                  !pairID.isEmpty else {
                Task { @MainActor in
                    self.isConnecting = false
                    self.errorMessage = "That room code was not found."
                }
                return
            }

            let pairReference = database.collection("pairs").document(pairID)
            pairReference.updateData([
                "viewerIds": FieldValue.arrayUnion([userID])
            ]) { updateError in
                guard updateError == nil else {
                    Task { @MainActor in
                        self.isConnecting = false
                        self.errorMessage = "Could not connect this Apple TV: \(updateError!.localizedDescription)"
                    }
                    return
                }

                pairReference.getDocument { pair, _ in
                    let name = (pair?.data()?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { @MainActor in
                        self.isConnecting = false
                        self.pairID = pairID
                        self.roomName = (name?.isEmpty == false) ? name! : "Tonight room"
                        UserDefaults.standard.set(pairID, forKey: "tvPairID")
                        UserDefaults.standard.set(self.roomName, forKey: "tvRoomName")
                        self.startListening(pairID: pairID)
                    }
                }
            }
        }
    }

    // Forgets the room on this television without changing the shared iPhone room.
    func disconnect() {
        matchesListener?.remove()
        matchesListener = nil
        titleListeners.values.forEach { $0.remove() }
        titleListeners = [:]
        orderedTitleIDs = []
        titlesByID = [:]
        titles = []
        pairID = nil
        roomName = "PairSwipe"
        UserDefaults.standard.removeObject(forKey: "tvPairID")
        UserDefaults.standard.removeObject(forKey: "tvRoomName")
    }

    // Watches matches so new shared picks appear on the television automatically.
    private func startListening(pairID: String) {
        matchesListener?.remove()
        matchesListener = database.collection("pairs")
            .document(pairID)
            .collection("matches")
            .order(by: "matchedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = "Could not load the shortlist: \(error.localizedDescription)"
                        return
                    }

                    self.orderedTitleIDs = snapshot?.documents.compactMap {
                        $0.data()["titleId"] as? String
                    } ?? []
                    self.removeUnusedTitleListeners()
                    self.listenForTitles(pairID: pairID)
                    self.publishTitles()
                }
            }
    }

    // Starts one lightweight listener for each title on the shortlist.
    private func listenForTitles(pairID: String) {
        for titleID in orderedTitleIDs where titleListeners[titleID] == nil {
            titleListeners[titleID] = database.collection("pairs")
                .document(pairID)
                .collection("titles")
                .document(titleID)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let data = snapshot?.data() else { return }
                    let title = Self.makeTitle(id: titleID, data: data)
                    Task { @MainActor in
                        self?.titlesByID[titleID] = title
                        self?.publishTitles()
                    }
                }
        }
    }

    // Stops listeners for titles that are no longer part of the shortlist.
    private func removeUnusedTitleListeners() {
        let activeIDs = Set(orderedTitleIDs)
        for (titleID, listener) in titleListeners where !activeIDs.contains(titleID) {
            listener.remove()
            titleListeners[titleID] = nil
            titlesByID[titleID] = nil
        }
    }

    // Keeps the cards in the same newest-first order as the match documents.
    private func publishTitles() {
        titles = orderedTitleIDs.compactMap { titlesByID[$0] }
    }

    // Converts a Firestore title document into the simple display model above.
    private static func makeTitle(id: String, data: [String: Any]) -> TVShortlistTitle {
        let kind = (data["type"] as? String) == "tv" ? "Series" : "Movie"
        let year = data["year"] as? String ?? ""
        let subtitle = [kind, year].filter { !$0.isEmpty }.joined(separator: " • ")

        return TVShortlistTitle(
            id: id,
            title: data["title"] as? String ?? "Untitled",
            subtitle: subtitle,
            overview: data["overview"] as? String ?? "",
            posterURL: URL(string: data["posterUrl"] as? String ?? ""),
            backdropURL: URL(string: data["backdropUrl"] as? String ?? ""),
            providers: data["streamProviders"] as? [String] ?? [],
            score: (data["tmdbScore"] as? NSNumber)?.doubleValue
        )
    }
}
