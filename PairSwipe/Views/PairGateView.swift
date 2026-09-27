import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PairGateView: View {
    @StateObject private var pairSession = PairSession()
    @State private var selectedTab: RootTab = .home

    var body: some View {
        currentContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                RootBottomBar(selectedTab: $selectedTab, hasPair: pairSession.activePair != nil)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
            .onChange(of: pairSession.activePair?.id) { pairId in
                if pairId == nil {
                    selectedTab = .home
                } else if selectedTab == .home {
                    selectedTab = .choose
                }
            }
    }

    private var currentContent: AnyView {
        switch selectedTab {
        case .home:
            return AnyView(CreateJoinPairView().environmentObject(pairSession))
        case .choose:
            if let pair = pairSession.activePair {
                return AnyView(SwipeDeckView(pair: pair).environmentObject(pairSession))
            }
            return AnyView(LockedWorkspaceTabView(title: "Choose together", message: "Start or join a room from Home to begin choosing.", tab: .choose, selectedTab: $selectedTab))
        case .shortlist:
            if let pair = pairSession.activePair {
                return AnyView(MatchesView(pair: pair).environmentObject(pairSession))
            }
            return AnyView(LockedWorkspaceTabView(title: "Your shortlist", message: "Your shared picks will appear here after you open a room.", tab: .shortlist, selectedTab: $selectedTab))
        case .room:
            if let pair = pairSession.activePair {
                return AnyView(PairInfoView(pair: pair).environmentObject(pairSession))
            }
            return AnyView(LockedWorkspaceTabView(title: "Your room", message: "Open a saved room or create a new one from Home.", tab: .room, selectedTab: $selectedTab))
        }
    }
}

private enum RootTab: String, CaseIterable, Hashable {
    case home
    case choose
    case shortlist
    case room

    var title: String {
        switch self {
        case .home: return "Home"
        case .choose: return "Choose"
        case .shortlist: return "Shortlist"
        case .room: return "Room"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .choose: return "rectangle.stack.fill"
        case .shortlist: return "heart.fill"
        case .room: return "person.2.fill"
        }
    }
}

private struct RootBottomBar: View {
    @Binding var selectedTab: RootTab
    let hasPair: Bool

    var body: some View {
        HStack(spacing: 6) {
            RootTabButton(tab: .home, isSelected: selectedTab == .home, hasPair: hasPair) { selectedTab = .home }
            RootTabButton(tab: .choose, isSelected: selectedTab == .choose, hasPair: hasPair) { selectedTab = .choose }
            RootTabButton(tab: .shortlist, isSelected: selectedTab == .shortlist, hasPair: hasPair) { selectedTab = .shortlist }
            RootTabButton(tab: .room, isSelected: selectedTab == .room, hasPair: hasPair) { selectedTab = .room }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.26), radius: 18, x: 0, y: 8)
    }
}

private struct RootTabButton: View {
    let tab: RootTab
    let isSelected: Bool
    let hasPair: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: .bold))
                Text(tab.title)
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(isSelected ? Color.white : AppTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? AppTheme.red : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityHint(tab == .home || hasPair ? "Opens this section" : "Start or join a room from Home first")
    }
}

private struct LockedWorkspaceTabView: View {
    let title: String
    let message: String
    let tab: RootTab
    @Binding var selectedTab: RootTab

    var body: some View {
        ZStack {
            AppGradientBackground()

            VStack(spacing: 16) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(AppTheme.orange)

                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Button("Go to Home") {
                    selectedTab = .home
                }
                .buttonStyle(GlassButtonStyle(tint: AppTheme.red))
                .frame(maxWidth: 240)
            }
            .padding(24)
        }
    }
}

private enum WorkspaceTab: Hashable {
    case choose
    case shortlist
    case room
}

struct PairWorkspaceView: View {
    let pair: Pair
    @EnvironmentObject private var pairSession: PairSession
    @State private var selectedTab: WorkspaceTab = .choose

    var body: some View {
        TabView(selection: $selectedTab) {
            SwipeDeckView(pair: currentPair)
                .tabItem { Label("Choose", systemImage: "rectangle.stack.fill") }
                .tag(WorkspaceTab.choose)

            MatchesView(pair: currentPair)
                .tabItem { Label("Shortlist", systemImage: "heart.fill") }
                .tag(WorkspaceTab.shortlist)

            PairInfoView(pair: currentPair)
                .tabItem { Label("Room", systemImage: "person.2.fill") }
                .tag(WorkspaceTab.room)
        }
        .tint(AppTheme.red)
        .toolbarBackground(Color.black.opacity(0.42), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
    }

    private var currentPair: Pair {
        pairSession.activePair ?? pair
    }
}

struct PairInfoView: View {
    let pair: Pair
    @EnvironmentObject private var pairSession: PairSession
    @State private var livePair: Pair?
    @State private var pairListener: MatchesListener?
    @State private var voteListener: MatchesListener?
    @State private var votedCount = 0
    @State private var votedIDsByMember: [String: Set<String>] = [:]
    @State private var isAddingRound = false
    @State private var roundMessage: String?
    @State private var showingRenameAlert = false
    @State private var proposedRoomName = ""
    @State private var isSavingName = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppGradientBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        roomHeader
                        inviteCard
                        queueCard
                        leaveRoomButton

                        Text("Titles and watch availability come from TMDB. Availability is provided by JustWatch and can vary by region.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.horizontal, 4)
                    }
                    .padding(16)
                    .padding(.bottom, 112)
                }
            }
            .navigationTitle("Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                loadProgress()
                pairListener = FirestoreService.shared.listenPair(pairId: pair.id) { updatedPair in
                    DispatchQueue.main.async {
                        livePair = updatedPair
                        if let updatedPair {
                            pairSession.updatePair(updatedPair)
                        }
                    }
                }
                voteListener = FirestoreService.shared.listenVotedTitleIDsByMember(pairId: pair.id) { voteProgress in
                    DispatchQueue.main.async {
                        votedIDsByMember = voteProgress
                        loadProgress()
                    }
                }
            }
            .onDisappear {
                pairListener?.remove()
                pairListener = nil
                voteListener?.remove()
                voteListener = nil
            }
            .alert("Name this room", isPresented: $showingRenameAlert) {
                TextField("Room name", text: $proposedRoomName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    saveRoomName()
                }
            } message: {
                Text("Both people will see this name. Leave it blank to use Tonight room.")
            }
        }
    }

    private var roomHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(activePair.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Spacer()

                Button {
                    proposedRoomName = activePair.name ?? ""
                    showingRenameAlert = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.headline.weight(.bold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .disabled(isSavingName)
                .accessibilityLabel("Rename room")
            }

            SectionEyebrow(text: isConnected ? "Both voters connected" : "Waiting on partner", icon: isConnected ? "checkmark.circle.fill" : "person.badge.clock.fill")
                .foregroundStyle(isConnected ? AppTheme.teal : AppTheme.amber)

            Text(isConnected ? "Both of you are choosing from the same queue." : "Start deciding now, or share the code so your partner can join.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 8, padding: 18, material: .regularMaterial)
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Invite code")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            Text(activePair.inviteCode)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .tracking(4)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            HStack(spacing: 10) {
                Button(action: copyInviteCode) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(GlassButtonStyle(tint: AppTheme.teal))

                ShareLink(item: shareMessage) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(GlassButtonStyle(tint: AppTheme.charcoal, emphasized: false))
            }
        }
        .glassSurface(cornerRadius: 8, padding: 18, material: .regularMaterial)
    }

    private var queueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Decision progress")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Round \(activePair.queueRound)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Text("\(min(votedCount, totalQueueCount))/\(totalQueueCount)")
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
            }

            ProgressView(value: Double(min(votedCount, totalQueueCount)), total: Double(max(totalQueueCount, 1)))
                .tint(AppTheme.red)

            Text(isConnected ? "Shared picks appear in Shortlist as soon as both people save the same title." : "Your partner will see this same queue after joining.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)

            if let roundMessage {
                Text(roundMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(roundMessage.hasPrefix("Could not") ? AppTheme.red : AppTheme.teal)
            }

            if isConnected {
                Button(action: addAnotherRound) {
                    if isAddingRound {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Add 18 more", systemImage: "plus.rectangle.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(GlassButtonStyle(tint: AppTheme.teal))
                .disabled(!bothMembersFinished || isAddingRound)

                if !bothMembersFinished {
                    Text("This unlocks when both people finish the current queue.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .glassSurface(cornerRadius: 8, padding: 18, material: .regularMaterial)
    }

    private var leaveRoomButton: some View {
        Button {
            pairSession.closePair()
        } label: {
            Label("Leave room", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .buttonStyle(GlassButtonStyle(tint: AppTheme.red, emphasized: false))
    }

    private var activePair: Pair {
        livePair ?? pairSession.activePair ?? pair
    }

    private var isConnected: Bool {
        activePair.memberB != nil
    }

    private var totalQueueCount: Int {
        max(activePair.queueTitleIds?.count ?? 0, 1)
    }

    private var shareMessage: String {
        "Join my PairSwipe room \"\(activePair.displayName)\" with invite code \(activePair.inviteCode)."
    }

    private var bothMembersFinished: Bool {
        guard
            let memberB = activePair.memberB,
            let queueIDs = activePair.queueTitleIds,
            !queueIDs.isEmpty
        else {
            return false
        }

        let requiredIDs = Set(queueIDs)
        let memberAIsDone = requiredIDs.isSubset(of: votedIDsByMember[activePair.memberA] ?? [])
        let memberBIsDone = requiredIDs.isSubset(of: votedIDsByMember[memberB] ?? [])
        return memberAIsDone && memberBIsDone
    }

    private func loadProgress() {
        FirestoreService.shared.fetchVotedTitleIDsForCurrentUser(pairId: pair.id) { votedIDs in
            DispatchQueue.main.async {
                votedCount = votedIDs.count
            }
        }
    }

    // Generates and atomically appends the next mixed 18-title round.
    private func addAnotherRound() {
        guard bothMembersFinished, !isAddingRound else { return }

        let existingIDs = activePair.queueTitleIds ?? []
        let nextRoundNumber = activePair.queueRound + 1
        isAddingRound = true
        roundMessage = nil

        TitleFeedService.shared.loadAdditionalRound(excluding: Set(existingIDs)) { cards in
            guard cards.count == 18 else {
                DispatchQueue.main.async {
                    isAddingRound = false
                    roundMessage = "Could not find 18 fresh streamable titles. Please try again."
                }
                return
            }

            FirestoreService.shared.appendQueueCards(
                pairId: activePair.id,
                expectedQueueCount: existingIDs.count,
                proposedCards: cards
            ) { result in
                DispatchQueue.main.async {
                    isAddingRound = false
                    switch result {
                    case .success(let addedIDs) where addedIDs.count == 18:
                        roundMessage = "Round \(nextRoundNumber) is ready."
                    case .success:
                        roundMessage = "Another phone already added the next round."
                    case .failure:
                        roundMessage = "Could not add another round. Please try again."
                    }
                }
            }
        }
    }

    // Saves a shared nickname for this room.
    private func saveRoomName() {
        guard !isSavingName else { return }
        isSavingName = true

        FirestoreService.shared.updatePairName(pairId: activePair.id, name: proposedRoomName) { error in
            DispatchQueue.main.async {
                isSavingName = false
                if error != nil {
                    roundMessage = "Could not rename the room. Please try again."
                }
            }
        }
    }

    private func copyInviteCode() {
        #if canImport(UIKit)
        UIPasteboard.general.string = activePair.inviteCode
        #endif
    }
}
