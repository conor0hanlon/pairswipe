import Foundation

// A simple protocol so views don't need Firebase types directly.
protocol MatchesListener {
    func remove()
}

#if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
import FirebaseFirestore
import FirebaseAuth

final class FirestoreService: ObservableObject {
    static let shared = FirestoreService()
    private let db = Firestore.firestore()

    private struct FirestoreMatchesListener: MatchesListener {
        let registration: ListenerRegistration
        func remove() { registration.remove() }
    }

    // Starts a live listener for one pair document.
    func listenPair(pairId: String, onUpdate: @escaping (Pair?) -> Void) -> MatchesListener {
        let registration = db.collection("pairs").document(pairId)
            .addSnapshotListener { snapshot, _ in
                guard let snapshot = snapshot, let data = snapshot.data() else {
                    onUpdate(nil)
                    return
                }
                onUpdate(self.mapPair(documentId: snapshot.documentID, data: data))
            }
        return FirestoreMatchesListener(registration: registration)
    }

    // Creates a new pair and stores the creator as member A.
    func createPair(completion: @escaping (Result<Pair, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        createPairWithUniqueInvite(createdBy: uid, attempt: 0, completion: completion)
    }

    // Joins an existing pair using an invite code.
    func joinPair(inviteCode: String, completion: @escaping (Result<Pair, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let inviteRef = db.collection("invites").document(inviteCode)

        db.runTransaction({ transaction, errorPointer in
            do {
                let inviteSnapshot = try transaction.getDocument(inviteRef)
                guard let inviteData = inviteSnapshot.data(),
                      let pairId = inviteData["pairId"] as? String,
                      !pairId.isEmpty
                else {
                    errorPointer?.pointee = Self.pairError(code: 404, message: "Invite code not found.")
                    return nil
                }

                let pairRef = self.db.collection("pairs").document(pairId)
                let pairSnapshot = try transaction.getDocument(pairRef)
                guard let pairData = pairSnapshot.data() else {
                    errorPointer?.pointee = Self.pairError(code: 404, message: "Pair not found.")
                    return nil
                }

                let memberA = pairData["memberA"] as? String ?? ""
                let existingMemberB = Self.parseOptionalString(pairData["memberB"])

                if memberA == uid {
                    errorPointer?.pointee = Self.pairError(code: 412, message: "Use a different device to join this pair.")
                    return nil
                }

                if existingMemberB != nil {
                    errorPointer?.pointee = Self.pairError(code: 409, message: "This pair is already full.")
                    return nil
                }

                transaction.updateData(["memberB": uid], forDocument: pairRef)

                let pair = Pair(
                    id: pairId,
                    createdAt: (pairData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    memberA: memberA,
                    memberB: uid,
                    inviteCode: inviteCode,
                    queueTitleIds: pairData["queueTitleIds"] as? [String],
                    name: Self.parseOptionalString(pairData["name"])
                )
                return pair
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
        }) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let pair = result as? Pair {
                completion(.success(pair))
            } else {
                completion(.failure(Self.pairNSError(code: 500, message: "Could not join pair.")))
            }
        }
    }

    // Writes a swipe vote for the current user.
    func vote(pairId: String, titleId: String, value: VoteValue, completion: @escaping (Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let voteId = "\(titleId)_\(uid)"
        let data: [String: Any] = [
            "titleId": titleId,
            "uid": uid,
            "value": value.rawValue,
            "votedAt": FieldValue.serverTimestamp()
        ]
        db.collection("pairs").document(pairId).collection("votes").document(voteId).setData(data) { error in
            if error == nil, value == .like {
                // Fallback match creation in case Cloud Functions are unavailable.
                self.tryCreateMatchIfMutualLike(pairId: pairId, titleId: titleId)
            }
            completion(error)
        }
    }

    // Creates a match document if both pair members have liked the title.
    private func tryCreateMatchIfMutualLike(pairId: String, titleId: String) {
        let pairRef = db.collection("pairs").document(pairId)
        pairRef.getDocument { snapshot, _ in
            guard
                let snapshot = snapshot,
                let pairData = snapshot.data(),
                let memberA = pairData["memberA"] as? String,
                let memberB = pairData["memberB"] as? String,
                !memberA.isEmpty,
                !memberB.isEmpty
            else {
                return
            }

            let votesRef = pairRef.collection("votes")
            let voteARef = votesRef.document("\(titleId)_\(memberA)")
            let voteBRef = votesRef.document("\(titleId)_\(memberB)")

            let group = DispatchGroup()
            var likeA = false
            var likeB = false

            group.enter()
            voteARef.getDocument { voteSnapshot, _ in
                if voteSnapshot?.data()?["value"] as? String == VoteValue.like.rawValue {
                    likeA = true
                }
                group.leave()
            }

            group.enter()
            voteBRef.getDocument { voteSnapshot, _ in
                if voteSnapshot?.data()?["value"] as? String == VoteValue.like.rawValue {
                    likeB = true
                }
                group.leave()
            }

            group.notify(queue: .main) {
                guard likeA && likeB else { return }

                pairRef.collection("matches").document(titleId).setData(
                    [
                        "titleId": titleId,
                        "matchedAt": FieldValue.serverTimestamp(),
                        "likedBy": [memberA, memberB]
                    ],
                    merge: true
                )
            }
        }
    }

    // Saves title metadata so matches can be shown later even after app restarts.
    func saveTitle(pairId: String, card: TitleCard, completion: @escaping (Error?) -> Void) {
        let data = titleCardData(from: card)
        db.collection("pairs")
            .document(pairId)
            .collection("titles")
            .document(card.id)
            .setData(data, merge: true) { error in
                completion(error)
            }
    }

    // Saves a batch of title cards for later lookup.
    func saveTitles(pairId: String, cards: [TitleCard], completion: @escaping (Error?) -> Void) {
        let batch = db.batch()

        cards.forEach { card in
            let ref = db.collection("pairs").document(pairId).collection("titles").document(card.id)
            batch.setData(titleCardData(from: card), forDocument: ref, merge: true)
        }

        batch.commit { error in
            completion(error)
        }
    }

    // Starts a live listener for matches in a pair.
    func listenMatches(pairId: String, onUpdate: @escaping ([Match]) -> Void) -> MatchesListener {
        let registration = db.collection("pairs").document(pairId).collection("matches")
            .order(by: "matchedAt", descending: true)
            .addSnapshotListener { snapshot, _ in
                let matches = snapshot?.documents.compactMap(self.mapMatch(document:)) ?? []
                onUpdate(matches)
            }
        return FirestoreMatchesListener(registration: registration)
    }

    // Loads the latest matches once, useful for landing-page previews.
    func fetchRecentMatches(pairId: String, limit: Int = 10, completion: @escaping ([Match]) -> Void) {
        db.collection("pairs")
            .document(pairId)
            .collection("matches")
            .order(by: "matchedAt", descending: true)
            .limit(to: limit)
            .getDocuments { snapshot, _ in
                let matches = snapshot?.documents.compactMap(self.mapMatch(document:)) ?? []
                completion(matches)
            }
    }

    // Loads the pair document once.
    func fetchPair(pairId: String, completion: @escaping (Pair?) -> Void) {
        db.collection("pairs").document(pairId).getDocument { snapshot, _ in
            guard let snapshot = snapshot, let data = snapshot.data() else {
                completion(nil)
                return
            }
            completion(self.mapPair(documentId: snapshot.documentID, data: data))
        }
    }

    // Loads the current user's voted title ids for a pair.
    func fetchVotedTitleIDsForCurrentUser(pairId: String, completion: @escaping (Set<String>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion([])
            return
        }

        db.collection("pairs")
            .document(pairId)
            .collection("votes")
            .whereField("uid", isEqualTo: uid)
            .getDocuments { snapshot, _ in
                let titleIDs = Set(snapshot?.documents.compactMap { $0.data()["titleId"] as? String } ?? [])
                completion(titleIDs)
            }
    }

    // Watches every vote in a room so the UI knows when both people finish a round.
    func listenVotedTitleIDsByMember(pairId: String, onUpdate: @escaping ([String: Set<String>]) -> Void) -> MatchesListener {
        let registration = db.collection("pairs")
            .document(pairId)
            .collection("votes")
            .addSnapshotListener { snapshot, _ in
                var votedIDsByMember: [String: Set<String>] = [:]

                snapshot?.documents.forEach { document in
                    let data = document.data()
                    guard
                        let uid = data["uid"] as? String,
                        let titleID = data["titleId"] as? String
                    else {
                        return
                    }
                    votedIDsByMember[uid, default: []].insert(titleID)
                }

                onUpdate(votedIDsByMember)
            }
        return FirestoreMatchesListener(registration: registration)
    }

    // Saves a stable queue for a pair exactly once.
    func ensureQueueTitleIDs(pairId: String, proposedCards: [TitleCard], completion: @escaping ([String]) -> Void) {
        let pairRef = db.collection("pairs").document(pairId)
        let proposedIDs = Array(proposedCards.prefix(18)).map(\.id)

        db.runTransaction({ transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(pairRef)
                guard let data = snapshot.data() else {
                    errorPointer?.pointee = Self.pairError(code: 404, message: "Pair not found.")
                    return nil
                }

                let existingIDs = data["queueTitleIds"] as? [String] ?? []
                if !existingIDs.isEmpty {
                    return existingIDs
                }

                transaction.updateData(["queueTitleIds": proposedIDs], forDocument: pairRef)
                return proposedIDs
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
        }) { result, _ in
            completion(result as? [String] ?? [])
        }
    }

    // Appends one new 18-title round only if the queue has not changed since loading.
    // Saving the cards and extending the queue happen in the same transaction.
    func appendQueueCards(pairId: String,
                          expectedQueueCount: Int,
                          proposedCards: [TitleCard],
                          completion: @escaping (Result<[String], Error>) -> Void) {
        let pairRef = db.collection("pairs").document(pairId)

        db.runTransaction({ transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(pairRef)
                guard let data = snapshot.data() else {
                    errorPointer?.pointee = Self.pairError(code: 404, message: "Pair not found.")
                    return nil
                }

                let existingIDs = data["queueTitleIds"] as? [String] ?? []
                guard existingIDs.count == expectedQueueCount else {
                    return [] as [String]
                }

                var seenIDs = Set(existingIDs)
                let newCards = proposedCards.filter { card in
                    guard !seenIDs.contains(card.id) else { return false }
                    seenIDs.insert(card.id)
                    return true
                }
                .prefix(18)

                let cardsToAppend = Array(newCards)
                let addedIDs = cardsToAppend.map(\.id)
                guard !addedIDs.isEmpty else {
                    return [] as [String]
                }

                transaction.updateData(
                    ["queueTitleIds": existingIDs + addedIDs],
                    forDocument: pairRef
                )

                cardsToAppend.forEach { card in
                    let titleRef = pairRef.collection("titles").document(card.id)
                    transaction.setData(self.titleCardData(from: card), forDocument: titleRef, merge: true)
                }

                return addedIDs
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
        }) { result, error in
            if let error {
                completion(.failure(error))
                return
            }
            completion(.success(result as? [String] ?? []))
        }
    }

    // Changes the shared room name. An empty name restores the default label.
    func updatePairName(pairId: String, name: String, completion: @escaping (Error?) -> Void) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = String(trimmedName.prefix(40))
        let value: Any = safeName.isEmpty ? FieldValue.delete() : safeName

        db.collection("pairs")
            .document(pairId)
            .updateData(["name": value]) { error in
                completion(error)
            }
    }

    // Loads a previously saved title card from Firestore.
    func fetchSavedTitle(pairId: String, titleId: String, completion: @escaping (TitleCard?) -> Void) {
        db.collection("pairs")
            .document(pairId)
            .collection("titles")
            .document(titleId)
            .getDocument { snapshot, _ in
                guard let data = snapshot?.data() else {
                    completion(nil)
                    return
                }
                completion(self.mapTitleCard(data: data, titleId: titleId))
            }
    }

    // Loads all pairs for the current user so we can render a persistent landing page.
    func loadPairsForCurrentUser(completion: @escaping ([Pair]) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion([])
            return
        }

        let group = DispatchGroup()
        var documentsById: [String: QueryDocumentSnapshot] = [:]

        group.enter()
        db.collection("pairs")
            .whereField("memberA", isEqualTo: uid)
            .getDocuments { snapshot, _ in
                snapshot?.documents.forEach { documentsById[$0.documentID] = $0 }
                group.leave()
            }

        group.enter()
        db.collection("pairs")
            .whereField("memberB", isEqualTo: uid)
            .getDocuments { snapshot, _ in
                snapshot?.documents.forEach { documentsById[$0.documentID] = $0 }
                group.leave()
            }

        group.notify(queue: .main) {
            let pairs = documentsById.values
                .filter { document in
                    let hiddenFor = document.data()["hiddenFor"] as? [String] ?? []
                    return !hiddenFor.contains(uid)
                }
                .map(self.mapPair(document:))
                .sorted { $0.createdAt > $1.createdAt }
            completion(pairs)
        }
    }

    // Removes a room from only the current user's saved-room list.
    // The shared Firestore room stays intact for the other member.
    func removeSavedPair(pairId: String, completion: @escaping (Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(Self.pairNSError(code: 401, message: "You must be signed in to remove a room."))
            return
        }

        db.collection("pairs")
            .document(pairId)
            .updateData(["hiddenFor": FieldValue.arrayUnion([uid])]) { error in
                completion(error)
            }
    }

    // Converts a Firestore pair document into a strongly typed model.
    private func mapPair(document: QueryDocumentSnapshot) -> Pair {
        mapPair(documentId: document.documentID, data: document.data())
    }

    // Converts pair data into a strongly typed model.
    private func mapPair(documentId: String, data: [String: Any]) -> Pair {
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
        let memberBRaw = data["memberB"]
        let memberB: String?
        if memberBRaw is NSNull {
            memberB = nil
        } else {
            memberB = memberBRaw as? String
        }

        return Pair(
            id: documentId,
            createdAt: createdAt,
            memberA: data["memberA"] as? String ?? "",
            memberB: memberB,
            inviteCode: data["inviteCode"] as? String ?? "------",
            queueTitleIds: data["queueTitleIds"] as? [String],
            name: Self.parseOptionalString(data["name"])
        )
    }

    // Converts a Firestore match document into a strongly typed model.
    private func mapMatch(document: QueryDocumentSnapshot) -> Match? {
        let data = document.data()
        guard
            let titleId = data["titleId"] as? String,
            let likedBy = data["likedBy"] as? [String]
        else {
            return nil
        }
        let matchedAt = (data["matchedAt"] as? Timestamp)?.dateValue() ?? Date()
        return Match(id: document.documentID, titleId: titleId, matchedAt: matchedAt, likedBy: likedBy)
    }

    // Converts Firestore title data back into a TitleCard.
    private func mapTitleCard(data: [String: Any], titleId: String) -> TitleCard? {
        guard let title = data["title"] as? String else {
            return nil
        }

        return TitleCard(
            id: titleId,
            type: data["type"] as? String ?? "movie",
            title: title,
            year: data["year"] as? String ?? "",
            overview: data["overview"] as? String ?? "",
            posterUrl: data["posterUrl"] as? String ?? "",
            backdropUrl: data["backdropUrl"] as? String ?? "",
            runtimeMinutes: Self.parseInt(data["runtimeMinutes"]),
            genres: data["genres"] as? [String] ?? [],
            tmdbScore: Self.parseDouble(data["tmdbScore"]),
            rottenTomatoesScore: data["rottenTomatoesScore"] as? String,
            streamProviders: data["streamProviders"] as? [String] ?? [],
            streamingLink: data["streamingLink"] as? String
        )
    }

    // Converts a TitleCard into a Firestore dictionary.
    private func titleCardData(from card: TitleCard) -> [String: Any] {
        var data: [String: Any] = [
            "id": card.id,
            "type": card.type,
            "title": card.title,
            "year": card.year,
            "overview": card.overview,
            "posterUrl": card.posterUrl,
            "backdropUrl": card.backdropUrl,
            "genres": card.genres,
            "streamProviders": card.streamProviders
        ]

        if let runtimeMinutes = card.runtimeMinutes {
            data["runtimeMinutes"] = runtimeMinutes
        }
        if let tmdbScore = card.tmdbScore {
            data["tmdbScore"] = tmdbScore
        }
        if let rottenTomatoesScore = card.rottenTomatoesScore {
            data["rottenTomatoesScore"] = rottenTomatoesScore
        }
        if let streamingLink = card.streamingLink {
            data["streamingLink"] = streamingLink
        }

        return data
    }

    // Converts unknown number values from Firestore to Int.
    private static func parseInt(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    // Converts unknown number values from Firestore to Double.
    private static func parseDouble(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? Int64 { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    // Converts an unknown Firestore value into an optional string.
    private static func parseOptionalString(_ value: Any?) -> String? {
        if value is NSNull { return nil }
        if let value = value as? String, !value.isEmpty { return value }
        return nil
    }

    // Generates a localized NSError for pair flow failures.
    private static func pairNSError(code: Int, message: String) -> NSError {
        NSError(domain: "Pair", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // Bridges NSError into the pointer type used by Firestore transactions.
    private static func pairError(code: Int, message: String) -> NSError {
        pairNSError(code: code, message: message)
    }

    // Creates a pair plus its invite code document.
    private func createPairWithUniqueInvite(createdBy uid: String,
                                            attempt: Int,
                                            completion: @escaping (Result<Pair, Error>) -> Void) {
        if attempt >= 8 {
            completion(.failure(Self.pairNSError(code: 500, message: "Could not generate an invite code.")))
            return
        }

        let inviteCode = Self.randomInviteCode()
        let inviteRef = db.collection("invites").document(inviteCode)

        inviteRef.getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if snapshot?.exists == true {
                self.createPairWithUniqueInvite(createdBy: uid, attempt: attempt + 1, completion: completion)
                return
            }

            let pairRef = self.db.collection("pairs").document()
            let batch = self.db.batch()

            batch.setData(
                [
                    "createdAt": FieldValue.serverTimestamp(),
                    "memberA": uid,
                    "memberB": NSNull(),
                    "inviteCode": inviteCode,
                    "queueTitleIds": []
                ],
                forDocument: pairRef
            )

            batch.setData(
                [
                    "code": inviteCode,
                    "pairId": pairRef.documentID,
                    "createdBy": uid,
                    "createdAt": FieldValue.serverTimestamp()
                ],
                forDocument: inviteRef
            )

            batch.commit { error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                completion(
                    .success(
                        Pair(
                            id: pairRef.documentID,
                            createdAt: Date(),
                            memberA: uid,
                            memberB: nil,
                            inviteCode: inviteCode,
                            queueTitleIds: [],
                            name: nil
                        )
                    )
                )
            }
        }
    }

    // Creates invite codes that avoid ambiguous characters.
    private static func randomInviteCode(length: Int = 6) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}
#else

// Fallback stub implementation to allow the project to build without Firebase.
final class FirestoreService: ObservableObject {
    static let shared = FirestoreService()
    private var localPairs: [Pair] = []
    private var localTitlesByPair: [String: [String: TitleCard]] = [:]
    private var localMatchesByPair: [String: [Match]] = [:]
    private var localVotedTitleIDsByPairAndUser: [String: Set<String>] = [:]

    private struct NoopListener: MatchesListener {
        func remove() {}
    }

    // Simulates pair creation when Firebase is unavailable.
    func createPair(completion: @escaping (Result<Pair, Error>) -> Void) {
        let pair = Pair(id: UUID().uuidString,
                        createdAt: Date(),
                        memberA: "local-user",
                        memberB: nil,
                        inviteCode: "LOCAL01",
                        queueTitleIds: [],
                        name: nil)
        localPairs.append(pair)
        completion(.success(pair))
    }

    // Simulates joining a pair when Firebase is unavailable.
    func joinPair(inviteCode: String, completion: @escaping (Result<Pair, Error>) -> Void) {
        if let existingIndex = localPairs.firstIndex(where: { $0.inviteCode == inviteCode && $0.memberB == nil }) {
            let existingPair = localPairs[existingIndex]
            let joinedPair = Pair(id: existingPair.id,
                                  createdAt: existingPair.createdAt,
                                  memberA: existingPair.memberA,
                                  memberB: "local-user-B",
                                  inviteCode: inviteCode,
                                  queueTitleIds: existingPair.queueTitleIds,
                                  name: existingPair.name)
            localPairs[existingIndex] = joinedPair
            completion(.success(joinedPair))
        } else {
            completion(.failure(NSError(domain: "Pair", code: 404)))
        }
    }

    // No-op vote in local stub mode.
    func vote(pairId: String, titleId: String, value: VoteValue, completion: @escaping (Error?) -> Void) {
        let currentUser = "local-user"
        let voteKey = "\(pairId)_\(currentUser)"
        var voted = localVotedTitleIDsByPairAndUser[voteKey] ?? []
        voted.insert(titleId)
        localVotedTitleIDsByPairAndUser[voteKey] = voted

        if value == .like {
            var pairMatches = localMatchesByPair[pairId] ?? []
            if !pairMatches.contains(where: { $0.titleId == titleId }) {
                pairMatches.insert(
                    Match(id: titleId, titleId: titleId, matchedAt: Date(), likedBy: [currentUser]),
                    at: 0
                )
                localMatchesByPair[pairId] = pairMatches
            }
        }
        completion(nil)
    }

    // Saves title metadata locally in stub mode.
    func saveTitle(pairId: String, card: TitleCard, completion: @escaping (Error?) -> Void) {
        var titles = localTitlesByPair[pairId] ?? [:]
        titles[card.id] = card
        localTitlesByPair[pairId] = titles
        completion(nil)
    }

    // Returns a no-op listener with local sample matches in stub mode.
    func listenMatches(pairId: String, onUpdate: @escaping ([Match]) -> Void) -> MatchesListener {
        onUpdate(localMatchesByPair[pairId] ?? [])
        return NoopListener()
    }

    // Returns a no-op pair listener in stub mode.
    func listenPair(pairId: String, onUpdate: @escaping (Pair?) -> Void) -> MatchesListener {
        onUpdate(localPairs.first(where: { $0.id == pairId }))
        return NoopListener()
    }

    // Loads local matches once in stub mode.
    func fetchRecentMatches(pairId: String, limit: Int = 10, completion: @escaping ([Match]) -> Void) {
        let matches = Array((localMatchesByPair[pairId] ?? []).prefix(limit))
        completion(matches)
    }

    // Loads one local pair in stub mode.
    func fetchPair(pairId: String, completion: @escaping (Pair?) -> Void) {
        completion(localPairs.first(where: { $0.id == pairId }))
    }

    // Loads voted title ids in stub mode.
    func fetchVotedTitleIDsForCurrentUser(pairId: String, completion: @escaping (Set<String>) -> Void) {
        completion(localVotedTitleIDsByPairAndUser["\(pairId)_local-user"] ?? [])
    }

    // Returns local vote progress in fallback mode.
    func listenVotedTitleIDsByMember(pairId: String, onUpdate: @escaping ([String: Set<String>]) -> Void) -> MatchesListener {
        let votes = localVotedTitleIDsByPairAndUser["\(pairId)_local-user"] ?? []
        onUpdate(["local-user": votes])
        return NoopListener()
    }

    // Saves queue ids once in stub mode.
    func ensureQueueTitleIDs(pairId: String, proposedCards: [TitleCard], completion: @escaping ([String]) -> Void) {
        guard let pairIndex = localPairs.firstIndex(where: { $0.id == pairId }) else {
            completion([])
            return
        }

        let existingIDs = localPairs[pairIndex].queueTitleIds ?? []
        if !existingIDs.isEmpty {
            completion(existingIDs)
            return
        }

        let ids = Array(proposedCards.prefix(18)).map(\.id)
        let pair = localPairs[pairIndex]
        localPairs[pairIndex] = Pair(id: pair.id,
                                     createdAt: pair.createdAt,
                                     memberA: pair.memberA,
                                     memberB: pair.memberB,
                                     inviteCode: pair.inviteCode,
                                     queueTitleIds: ids,
                                     name: pair.name)
        completion(ids)
    }

    // Appends a new round in local fallback mode.
    func appendQueueCards(pairId: String,
                          expectedQueueCount: Int,
                          proposedCards: [TitleCard],
                          completion: @escaping (Result<[String], Error>) -> Void) {
        guard let pairIndex = localPairs.firstIndex(where: { $0.id == pairId }) else {
            completion(.failure(NSError(domain: "Pair", code: 404)))
            return
        }

        let pair = localPairs[pairIndex]
        let existingIDs = pair.queueTitleIds ?? []
        guard existingIDs.count == expectedQueueCount else {
            completion(.success([]))
            return
        }

        var seenIDs = Set(existingIDs)
        let cardsToAppend = Array(proposedCards.filter { card in
            guard !seenIDs.contains(card.id) else { return false }
            seenIDs.insert(card.id)
            return true
        }.prefix(18))
        let addedIDs = cardsToAppend.map(\.id)

        var titles = localTitlesByPair[pairId] ?? [:]
        cardsToAppend.forEach { titles[$0.id] = $0 }
        localTitlesByPair[pairId] = titles
        localPairs[pairIndex] = Pair(
            id: pair.id,
            createdAt: pair.createdAt,
            memberA: pair.memberA,
            memberB: pair.memberB,
            inviteCode: pair.inviteCode,
            queueTitleIds: existingIDs + addedIDs,
            name: pair.name
        )
        completion(.success(addedIDs))
    }

    // Changes the shared room name in local fallback mode.
    func updatePairName(pairId: String, name: String, completion: @escaping (Error?) -> Void) {
        guard let pairIndex = localPairs.firstIndex(where: { $0.id == pairId }) else {
            completion(NSError(domain: "Pair", code: 404))
            return
        }

        let pair = localPairs[pairIndex]
        let trimmedName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        localPairs[pairIndex] = Pair(
            id: pair.id,
            createdAt: pair.createdAt,
            memberA: pair.memberA,
            memberB: pair.memberB,
            inviteCode: pair.inviteCode,
            queueTitleIds: pair.queueTitleIds,
            name: trimmedName.isEmpty ? nil : trimmedName
        )
        completion(nil)
    }

    // Loads a saved local title in stub mode.
    func fetchSavedTitle(pairId: String, titleId: String, completion: @escaping (TitleCard?) -> Void) {
        completion(localTitlesByPair[pairId]?[titleId])
    }

    // Saves local title batches in stub mode.
    func saveTitles(pairId: String, cards: [TitleCard], completion: @escaping (Error?) -> Void) {
        var titles = localTitlesByPair[pairId] ?? [:]
        cards.forEach { titles[$0.id] = $0 }
        localTitlesByPair[pairId] = titles
        completion(nil)
    }

    // Loads local pairs in stub mode.
    func loadPairsForCurrentUser(completion: @escaping ([Pair]) -> Void) {
        completion(localPairs.sorted { $0.createdAt > $1.createdAt })
    }

    // Removes one saved room in local fallback mode.
    func removeSavedPair(pairId: String, completion: @escaping (Error?) -> Void) {
        localPairs.removeAll { $0.id == pairId }
        completion(nil)
    }
}

#endif
