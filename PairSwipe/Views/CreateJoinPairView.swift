import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CreateJoinPairView: View {
    @EnvironmentObject private var pairSession: PairSession
    @StateObject private var nearbyPairService = NearbyPairService()
    @State private var inviteCode: String = ""
    @State private var statusText: String? = nil
    @State private var isBusy = false
    @State private var landingSnapshots: [PairLandingSnapshot] = []
    @State private var isLoadingPairs = false
    @State private var nearbyHostPair: Pair?
    @State private var showingNearbyHostSheet = false
    @State private var showingNearbyBrowseSheet = false
    @State private var roomPendingRemoval: Pair?
    @State private var removingRoomIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack {
                AppGradientBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        landingHeader
                        roomActionsCard
                        shortlistSection
                    }
                    .padding(16)
                    .padding(.bottom, 112)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarHidden(true)
            .onAppear {
                loadLandingData()
            }
            .onChange(of: nearbyPairService.pendingInviteCode) { inviteCode in
                guard let inviteCode else { return }
                finishNearbyJoin(inviteCode: inviteCode)
            }
            .sheet(isPresented: $showingNearbyHostSheet, onDismiss: closeNearbyFlow) {
                nearbyHostSheet
            }
            .sheet(isPresented: $showingNearbyBrowseSheet, onDismiss: closeNearbyFlow) {
                nearbyBrowseSheet
            }
            .alert("Remove saved room?", isPresented: removalAlertIsPresented) {
                Button("Cancel", role: .cancel) {
                    roomPendingRemoval = nil
                }
                Button("Remove", role: .destructive) {
                    guard let pair = roomPendingRemoval else { return }
                    roomPendingRemoval = nil
                    removeSavedPair(pair)
                }
            } message: {
                Text("This removes the room from your Home list. It does not delete the room for the other person.")
            }
        }
    }

    private var removalAlertIsPresented: Binding<Bool> {
        Binding(
            get: { roomPendingRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    roomPendingRemoval = nil
                }
            }
        )
    }

    private var landingHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            PairSwipeLogoView(size: 58)

            VStack(alignment: .leading, spacing: 4) {
                SectionEyebrow(text: "Tonight's watch room", icon: "sofa.fill")

                Text("PairSwipe")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("Decide what to watch tonight.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
            }

            Spacer()
        }
        .padding(.top, 8)
    }

    private var roomActionsCard: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Make one shared choice")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("Start a private room, share it with your partner, and move from maybe to tonight's pick.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: createPair) {
                Label("Start a room", systemImage: "play.fill")
            }
            .buttonStyle(GlassButtonStyle(tint: AppTheme.red))
            .disabled(isBusy)

            VStack(alignment: .leading, spacing: 9) {
                Text("Join a room")
                    .font(.headline)
                    .foregroundStyle(.white)

                HStack(spacing: 10) {
                    TextField("", text: $inviteCode, prompt: Text("Invite code").foregroundColor(AppTheme.mutedText))
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .tint(AppTheme.red)
                        .frame(minHeight: 52)
                        .padding(.horizontal, 14)
                        .background(AppTheme.screen, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppTheme.line, lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button("Join") {
                        guard canJoinPair else { return }
                        joinPair()
                    }
                    .frame(minWidth: 76)
                    .buttonStyle(GlassButtonStyle(tint: canJoinPair ? AppTheme.charcoal : AppTheme.ink, emphasized: canJoinPair))
                    .disabled(!canJoinPair)
                }
            }
            .padding(12)
            .background(AppTheme.screen, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(AppTheme.teal)
                    Text("Nearby")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button(action: startNearbyHost) {
                        Label("Start", systemImage: "iphone.radiowaves.left.and.right")
                    }
                    .buttonStyle(GlassButtonStyle(tint: AppTheme.teal, emphasized: false))

                    Button(action: startNearbyBrowse) {
                        Label("Find", systemImage: "wifi")
                    }
                    .buttonStyle(GlassButtonStyle(tint: AppTheme.charcoal, emphasized: false))
                }
            }
            .padding(12)
            .background(AppTheme.screen, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(isBusy)

            if let statusText = statusText {
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 8, padding: 0, material: .regularMaterial)
    }

    private var shortlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume a room")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Saved decision sessions")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer()

                if isLoadingPairs {
                    ProgressView()
                        .tint(.white)
                } else {
                    GlassIconButton(systemName: "arrow.clockwise", label: "Refresh saved pairs", action: loadLandingData)
                }
            }

            if landingSnapshots.isEmpty && !isLoadingPairs {
                VStack(alignment: .leading, spacing: 5) {
                    Text("No saved rooms yet")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Start a room when you are ready to decide together.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(cornerRadius: 8, padding: 16, material: .regularMaterial)
            }

            ForEach(landingSnapshots) { snapshot in
                pairSnapshotCard(snapshot)
            }
        }
    }

    private func pairSnapshotCard(_ snapshot: PairLandingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.pair.name == nil && !snapshot.isPairReady ? "Invite pending" : snapshot.pair.displayName)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(snapshot.pair.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                Text(statusText(for: snapshot))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusForeground(for: snapshot))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusBackground(for: snapshot), in: Capsule())

                Button {
                    roomPendingRemoval = snapshot.pair
                } label: {
                    if removingRoomIDs.contains(snapshot.id) {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "trash")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .disabled(removingRoomIDs.contains(snapshot.id))
                .accessibilityLabel("Remove saved room")
            }

            HStack(spacing: 10) {
                Button(resumeTitle(for: snapshot)) {
                    pairSession.openPair(snapshot.pair)
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(GlassButtonStyle(tint: AppTheme.charcoal))

                if !snapshot.isPairReady {
                    Button {
                        copyInviteCode(snapshot.pair.inviteCode)
                    } label: {
                        Label("Copy Code", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle(tint: AppTheme.charcoal, emphasized: false))
                }
            }


            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(progressText(for: snapshot))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(snapshot.matchCount) shared \(snapshot.matchCount == 1 ? "pick" : "picks")")
                        .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.red)
                }

                ProgressView(value: progressValue(for: snapshot), total: 1)
                    .tint(snapshot.matchCount > 0 ? AppTheme.red : AppTheme.teal)
            }

            Text(detailText(for: snapshot))
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)

            if snapshot.shortlistPreview.isEmpty {
                Text(snapshot.isPairReady ? "No matches yet for this pair." : "Open this pair to copy or share the invite code.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(snapshot.shortlistPreview, id: \.id) { card in
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(AppTheme.ink.opacity(0.12))
                                        .frame(width: 88, height: 128)

                                    if let url = URL(string: card.posterUrl), !card.posterUrl.isEmpty {
                                        AsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            ProgressView()
                                        }
                                        .frame(width: 88, height: 128)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    } else {
                                        Image(systemName: "film")
                                            .foregroundStyle(AppTheme.secondaryText)
                                    }
                                }

                                Text(card.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .frame(width: 88, alignment: .leading)
                            }
                        }
                    }
                        .padding(.vertical, 2)
                }
            }
        }
        .glassSurface(cornerRadius: 8, padding: 14, material: .regularMaterial)
    }

    // Creates a pair and immediately opens it.
    private func createPair() {
        isBusy = true
        statusText = nil
        FirestoreService.shared.createPair { result in
            DispatchQueue.main.async {
                self.isBusy = false
                switch result {
                case .success(let pair):
                    self.pairSession.openPair(pair)
                case .failure:
                    self.statusText = "Could not create pair."
                }
            }
        }
    }

    // Creates a pair, then starts advertising it to a nearby device.
    private func startNearbyHost() {
        isBusy = true
        statusText = nil
        FirestoreService.shared.createPair { result in
            DispatchQueue.main.async {
                self.isBusy = false
                switch result {
                case .success(let pair):
                    self.nearbyHostPair = pair
                    self.nearbyPairService.startHosting(pair: pair)
                    self.showingNearbyHostSheet = true
                case .failure:
                    self.statusText = "Could not start a nearby pair."
                }
            }
        }
    }

    // Starts browsing for a nearby host that already created a pair.
    private func startNearbyBrowse() {
        statusText = nil
        nearbyPairService.startBrowsing()
        showingNearbyBrowseSheet = true
    }

    // Joins a pair by invite code and immediately opens it.
    private func joinPair() {
        isBusy = true
        statusText = nil
        let normalizedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        FirestoreService.shared.joinPair(inviteCode: normalizedCode) { result in
            DispatchQueue.main.async {
                self.isBusy = false
                switch result {
                case .success(let pair):
                    self.pairSession.openPair(pair)
                case .failure(let error):
                    let nsError = error as NSError
                    if nsError.domain == "Pair", nsError.code == 404 {
                        self.statusText = "Invite code not found."
                    } else if nsError.domain == "Pair", nsError.code == 409 {
                        self.statusText = "This pair is already full."
                    } else {
                        self.statusText = "Could not join pair. Please try again."
                    }
                }
            }
        }
    }

    // Completes the Firebase join after a nearby host shared an invite locally.
    private func finishNearbyJoin(inviteCode: String) {
        guard !isBusy else { return }
        isBusy = true
        statusText = nil

        FirestoreService.shared.joinPair(inviteCode: inviteCode) { result in
            DispatchQueue.main.async {
                self.isBusy = false
                self.nearbyPairService.clearPendingInviteCode()
                switch result {
                case .success(let pair):
                    self.showingNearbyBrowseSheet = false
                    self.nearbyPairService.stop()
                    self.pairSession.openPair(pair)
                case .failure(let error):
                    let nsError = error as NSError
                    if nsError.domain == "Pair", nsError.code == 409 {
                        self.statusText = "That nearby pair is already full."
                    } else {
                        self.statusText = "Could not join the nearby pair."
                    }
                    self.nearbyPairService.stop()
                    self.showingNearbyBrowseSheet = false
                }
            }
        }
    }

    // Loads landing data: all user pairs plus a shortlist preview for each pair.
    private func loadLandingData() {
        isLoadingPairs = true
        FirestoreService.shared.loadPairsForCurrentUser { pairs in
            if pairs.isEmpty {
                DispatchQueue.main.async {
                    self.landingSnapshots = []
                    self.isLoadingPairs = false
                }
                return
            }

            var previewsByPairId: [String: [TitleCard]] = [:]
            var matchCountsByPairId: [String: Int] = [:]
            var remainingByPairId: [String: Int] = [:]
            let group = DispatchGroup()

            for pair in pairs {
                group.enter()
                let nestedGroup = DispatchGroup()

                nestedGroup.enter()
                loadShortlistPreview(for: pair) { previewCards, matchCount in
                    previewsByPairId[pair.id] = previewCards
                    matchCountsByPairId[pair.id] = matchCount
                    nestedGroup.leave()
                }

                nestedGroup.enter()
                FirestoreService.shared.fetchVotedTitleIDsForCurrentUser(pairId: pair.id) { votedIDs in
                    let totalQueueCount = pair.queueTitleIds?.count ?? 0
                    remainingByPairId[pair.id] = max(totalQueueCount - votedIDs.count, 0)
                    nestedGroup.leave()
                }

                nestedGroup.notify(queue: .main) {
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.landingSnapshots = pairs.map { pair in
                    let totalQueueCount = pair.queueTitleIds?.count ?? 0
                    return PairLandingSnapshot(
                        id: pair.id,
                        pair: pair,
                        shortlistPreview: previewsByPairId[pair.id] ?? [],
                        matchCount: matchCountsByPairId[pair.id] ?? 0,
                        isPairReady: pair.memberB != nil,
                        remainingSwipeCount: remainingByPairId[pair.id] ?? 0,
                        totalSwipeCount: totalQueueCount
                    )
                }
                self.isLoadingPairs = false
            }
        }
    }

    // Loads the latest matches and returns three cards for the landing-page preview.
    private func loadShortlistPreview(for pair: Pair, completion: @escaping ([TitleCard], Int) -> Void) {
        FirestoreService.shared.fetchRecentMatches(pairId: pair.id, limit: 100) { matches in
            if matches.isEmpty {
                completion([], 0)
                return
            }

            let previewMatches = Array(matches.prefix(3))
            var cardsById: [String: TitleCard] = [:]
            let group = DispatchGroup()

            for match in previewMatches {
                group.enter()
                TitleFeedService.shared.fetchTitle(id: match.titleId, pairId: pair.id) { card in
                    if let card = card {
                        cardsById[match.titleId] = card
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                let ordered = previewMatches.compactMap { cardsById[$0.titleId] }
                completion(ordered, matches.count)
            }
        }
    }

    private func statusText(for snapshot: PairLandingSnapshot) -> String {
        if !snapshot.isPairReady {
            return "Share code"
        }
        if snapshot.remainingSwipeCount > 0 {
            return "\(snapshot.remainingSwipeCount) left"
        }
        return "Done swiping"
    }

    private func progressText(for snapshot: PairLandingSnapshot) -> String {
        guard snapshot.totalSwipeCount > 0 else {
            return snapshot.isPairReady ? "Queue is being prepared" : "Room ready to share"
        }

        let completedCount = max(snapshot.totalSwipeCount - snapshot.remainingSwipeCount, 0)
        return "\(completedCount) of \(snapshot.totalSwipeCount) reviewed"
    }

    private func progressValue(for snapshot: PairLandingSnapshot) -> Double {
        guard snapshot.totalSwipeCount > 0 else {
            return snapshot.isPairReady ? 0.08 : 0
        }

        let completedCount = max(snapshot.totalSwipeCount - snapshot.remainingSwipeCount, 0)
        return min(Double(completedCount) / Double(snapshot.totalSwipeCount), 1)
    }

    private func resumeTitle(for snapshot: PairLandingSnapshot) -> String {
        if snapshot.matchCount > 0 {
            return "Open shortlist"
        }
        if snapshot.remainingSwipeCount > 0 || snapshot.totalSwipeCount == 0 {
            return "Continue choosing"
        }
        return "Review room"
    }

    private func statusBackground(for snapshot: PairLandingSnapshot) -> Color {
        if !snapshot.isPairReady {
            return Color.orange.opacity(0.20)
        }
        if snapshot.remainingSwipeCount > 0 {
            return Color.blue.opacity(0.16)
        }
        return Color.green.opacity(0.16)
    }

    private func statusForeground(for snapshot: PairLandingSnapshot) -> Color {
        if !snapshot.isPairReady {
            return AppTheme.orange
        }
        if snapshot.remainingSwipeCount > 0 {
            return Color(red: 0.50, green: 0.76, blue: 1.0)
        }
        return Color(red: 0.42, green: 0.90, blue: 0.62)
    }

    private func detailText(for snapshot: PairLandingSnapshot) -> String {
        if !snapshot.isPairReady {
            return "Share code \(snapshot.pair.inviteCode) so both of you can choose from the same list."
        }
        if snapshot.remainingSwipeCount > 0 {
            return "You still have \(snapshot.remainingSwipeCount) titles left before your side is done."
        }
        if snapshot.shortlistPreview.isEmpty {
            return "Your side is done. Shared picks appear as soon as both people save the same title."
        }
        return "A shared shortlist is ready. Open it and pick something."
    }

    // Copies an invite code from the landing page.
    private func copyInviteCode(_ code: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = code
        statusText = "Invite code copied."
        #endif
    }

    // Removes a room from this user's saved-room list after confirmation.
    private func removeSavedPair(_ pair: Pair) {
        removingRoomIDs.insert(pair.id)
        statusText = nil

        FirestoreService.shared.removeSavedPair(pairId: pair.id) { error in
            DispatchQueue.main.async {
                self.removingRoomIDs.remove(pair.id)

                if error != nil {
                    self.statusText = "Could not remove the room. Please try again."
                    return
                }

                self.landingSnapshots.removeAll { $0.id == pair.id }
                if self.pairSession.activePair?.id == pair.id {
                    self.pairSession.closePair()
                }
                self.statusText = "Room removed from your saved list."
            }
        }
    }

    // Stops the nearby service when the host or browser sheet closes.
    private func closeNearbyFlow() {
        nearbyPairService.stop()
    }

    private var canJoinPair: Bool {
        !isBusy && !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var nearbyHostSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Nearby room")
                    .font(.title2.weight(.bold))

                Text(nearbyPairService.hostedPairWasShared
                     ? "Room details were shared with the nearby device. You can open the room now."
                     : "Keep this screen open while your partner taps Find nearby on their phone.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                if let pair = nearbyHostPair {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Invite code \(pair.inviteCode)", systemImage: "number.square")
                        Label("Waiting for your partner's phone", systemImage: "iphone.radiowaves.left.and.right")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.11, green: 0.17, blue: 0.29))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.95, green: 0.97, blue: 0.99), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if !nearbyPairService.statusText.isEmpty {
                    Text(nearbyPairService.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let errorText = nearbyPairService.errorText {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

                Spacer()

                VStack(spacing: 10) {
                    if let pair = nearbyHostPair, nearbyPairService.hostedPairWasShared {
                        Button {
                            showingNearbyHostSheet = false
                            nearbyPairService.stop()
                            pairSession.openPair(pair)
                        } label: {
                            Label("Open room", systemImage: "rectangle.stack.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(GlassButtonStyle(tint: AppTheme.red))
                    }

                    Button("Stop nearby pairing") {
                        showingNearbyHostSheet = false
                    }
                    .buttonStyle(GlassButtonStyle(tint: AppTheme.charcoal, emphasized: false))
                }
            }
            .padding(20)
            .navigationTitle("Nearby")
            .navigationBarTitleDisplayMode(.inline)
        }
        .background(AppGradientBackground().ignoresSafeArea())
        .presentationDetents([.medium])
    }

    private var nearbyBrowseSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Find a nearby room")
                    .font(.title2.weight(.bold))

                Text(nearbyPairService.statusText.isEmpty ? "Choose one of the nearby devices below." : nearbyPairService.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let errorText = nearbyPairService.errorText {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

                if nearbyPairService.availableHosts.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Searching for nearby pairs...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(nearbyPairService.availableHosts) { host in
                        Button {
                            nearbyPairService.connect(to: host)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(host.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.white)

                                    Text("Tap to request this room")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if nearbyPairService.isConnecting {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(nearbyPairService.isConnecting)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.paper)
                }
            }
            .padding(20)
            .navigationTitle("Nearby")
            .navigationBarTitleDisplayMode(.inline)
        }
        .background(AppGradientBackground().ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}
