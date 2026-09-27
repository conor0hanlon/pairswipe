import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SwipeDeckView: View {
    let pair: Pair

    @EnvironmentObject private var pairSession: PairSession
    @State private var queue: [TitleCard] = []
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isLoading = true
    @State private var selectedCard: TitleCard?
    @State private var livePair: Pair?
    @State private var pairListener: MatchesListener?
    @State private var bannerMessage: String?
    @State private var isSavingVote = false
    @State private var voteError: String?

    var body: some View {
        ZStack {
            AppGradientBackground()

            VStack(spacing: 10) {
                connectionBanner

                if let message = bannerMessage ?? voteError {
                    statusToast(message)
                }

                progressHeader

                if isLoading {
                    Spacer()
                    ProgressView("Loading tonight's queue...")
                        .tint(.white)
                        .foregroundStyle(.white)
                    Spacer()
                } else if currentIndex >= queue.count {
                    finishedView
                } else {
                    let card = queue[currentIndex]

                    decisionContext(for: card)

                    ScrollView(showsIndicators: false) {
                        TitleCardView(
                            card: card,
                            posterHeight: 300,
                            showsOverview: false,
                            onMoreInfo: nil,
                            onDragChanged: { translation in
                                guard !isSavingVote else { return }
                                dragOffset = translation
                            },
                            onDragEnded: { translation in
                                guard !isSavingVote else { return }
                                if translation.width > 110 {
                                    handleVote(.like)
                                } else if translation.width < -110 {
                                    handleVote(.pass)
                                } else {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        dragOffset = .zero
                                    }
                                }
                            }
                        )
                        .overlay {
                            swipeDecisionOverlay
                        }
                        .offset(dragOffset)
                        .rotationEffect(.degrees(Double(dragOffset.width / 28)))
                        .padding(.horizontal, 32)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 96)
                    }
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom) {
            if currentCard != nil {
                swipeActionBar
                    .padding(.bottom, 10)
            }
        }
        .sheet(item: $selectedCard) { card in
            TitleDetailSheetView(card: card)
        }
        .onAppear {
            loadQueue()
            pairListener = FirestoreService.shared.listenPair(pairId: pair.id) { updatedPair in
                DispatchQueue.main.async {
                    livePair = updatedPair
                    if let updatedPair = updatedPair {
                        pairSession.updatePair(updatedPair)
                    }
                }
            }
        }
        .onDisappear {
            pairListener?.remove()
            pairListener = nil
        }
        .onChange(of: livePair?.queueTitleIds?.count) { newCount in
            guard let newCount, newCount > (pair.queueTitleIds?.count ?? 0) else { return }
            loadQueue()
        }
    }

    private var activePair: Pair {
        livePair ?? pair
    }

    private var currentCard: TitleCard? {
        guard !isLoading, currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    private var shareMessage: String {
        "Join my PairSwipe pair with invite code \(activePair.inviteCode)."
    }

    private var connectionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: activePair.memberB == nil ? "person.badge.clock.fill" : "checkmark.circle.fill")
                .foregroundStyle(activePair.memberB == nil ? AppTheme.amber : AppTheme.teal)

            VStack(alignment: .leading, spacing: 2) {
                Text(activePair.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)

                Text(activePair.memberB == nil ? "Waiting on partner" : "Both voters connected")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)

                if activePair.memberB == nil {
                    Text("Invite code  \(activePair.inviteCode)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Spacer()

            if activePair.memberB == nil {
                GlassIconButton(systemName: "doc.on.doc", label: "Copy invite code", action: copyInviteCode)

                ShareLink(item: shareMessage) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline.weight(.bold))
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.line, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Share invite code")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: UIScreen.main.bounds.width - 32, alignment: .leading)
        .background(AppTheme.warmPaper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.divider, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
    }

    private func statusToast(_ message: String) -> some View {
        Label(message, systemImage: voteError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background((voteError == nil ? AppTheme.teal : AppTheme.red).opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func decisionContext(for card: TitleCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionEyebrow(text: "Now judging", icon: "slider.horizontal.3")

            Text(card.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)

            Text([card.type.uppercased(), card.year].filter { !$0.isEmpty }.joined(separator: " • "))
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))

            Text("Save only if it works tonight")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .padding(.top, 2)
        }
        .frame(width: UIScreen.main.bounds.width - 32, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private var progressHeader: some View {
        VStack(spacing: 8) {
            let total = max(queue.count, 1)
            let value = min(currentIndex, queue.count)

            ProgressView(value: Double(value), total: Double(total))
            .tint(.white)
                .padding(.horizontal, 20)

            Text("\(min(currentIndex + 1, max(queue.count, 1))) of \(max(queue.count, 1))")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.88))
        }
    }

    @ViewBuilder
    private var swipeDecisionOverlay: some View {
        if abs(dragOffset.width) > 35 {
            VStack {
                HStack {
                    if dragOffset.width > 0 { Spacer() }
                    Text(dragOffset.width > 0 ? "SAVE" : "PASS")
                        .font(.title2.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(dragOffset.width > 0 ? AppTheme.red : AppTheme.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .rotationEffect(.degrees(dragOffset.width > 0 ? 8 : -8))
                    if dragOffset.width < 0 { Spacer() }
                }
                Spacer()
            }
            .padding(28)
        }
    }

    private var swipeActionBar: some View {
        HStack(spacing: 12) {
            Button {
                handleVote(.pass)
            } label: {
                Label("Pass", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(GlassButtonStyle(tint: AppTheme.ink, emphasized: false))

            Button {
                selectedCard = currentCard
            } label: {
                Label("Details", systemImage: "info.circle.fill")
            }
            .buttonStyle(GlassButtonStyle(tint: AppTheme.charcoal, emphasized: false))

            Button {
                handleVote(.like)
            } label: {
                Label("Save", systemImage: "heart.fill")
            }
            .buttonStyle(GlassButtonStyle(tint: AppTheme.red))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.44))
        .contentShape(Rectangle())
        .disabled(isSavingVote)
        .opacity(isSavingVote ? 0.65 : 1)
    }

    private var finishedView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white)

            Text("Your picks are in")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text("When your partner finishes, anything you both saved will appear in Shortlist.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)
            Text("Open Shortlist to see shared picks, or Room when you are done with this session.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }

    // Loads the current swipe queue.
    private func loadQueue() {
        isLoading = true
        TitleFeedService.shared.loadQueue(pairId: pair.id) { titles in
            DispatchQueue.main.async {
                queue = titles
                isLoading = false
                currentIndex = 0
                dragOffset = .zero
            }
        }
    }

    // Saves title metadata and submits the vote.
    private func handleVote(_ value: VoteValue) {
        guard currentIndex < queue.count, !isSavingVote else { return }

        let card = queue[currentIndex]
        isSavingVote = true
        voteError = nil
        FirestoreService.shared.saveTitle(pairId: pair.id, card: card) { _ in }

        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: value == .like ? .medium : .light).impactOccurred()
        #endif

        withAnimation(.easeIn(duration: 0.18)) {
            dragOffset = CGSize(width: value == .like ? 650 : -650, height: 20)
        }

        FirestoreService.shared.vote(pairId: pair.id, titleId: card.id, value: value) { error in
            DispatchQueue.main.async {
                self.isSavingVote = false
                if error != nil {
                    self.voteError = "That vote didn’t save. Please try again."
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        self.dragOffset = .zero
                    }
                    return
                }

                self.currentIndex += 1
                self.dragOffset = .zero
            }
        }
    }

    // Copies the invite code to the system clipboard.
    private func copyInviteCode() {
        #if canImport(UIKit)
        UIPasteboard.general.string = activePair.inviteCode
        bannerMessage = "Invite code copied."
        #endif
    }
}

struct TitleDetailSheetView: View {
    let card: TitleCard

    @Environment(\.dismiss) private var dismiss
    @State private var details: TitleDetails?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                AppGradientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        posterSection

                        if isLoading {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Finding ratings and watch options...")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            .padding(.vertical, 20)
                        } else if let details = details {
                            detailsContent(details)
                        } else {
                            Text("Could not load details.")
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(card.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                loadDetails()
            }
        }
    }

    private var posterSection: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.gray.opacity(0.15))
                .frame(height: 220)

            let imageUrl = card.backdropUrl.isEmpty ? card.posterUrl : card.backdropUrl
            if let url = URL(string: imageUrl), !imageUrl.isEmpty {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.52)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

            Text(card.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .padding(12)
        }
    }

    @ViewBuilder
    private func detailsContent(_ details: TitleDetails) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(details.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(details.subtitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            scoreRow(details)
        }

        watchSection(details)

        if !details.genres.isEmpty {
            WrapTagsView(tags: details.genres)
        }

        if !details.overview.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Overview")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(details.overview)
                    .font(.body)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }

        if details.rottenTomatoesScore == nil {
            Text("Rotten Tomatoes score was not available for this title.")
                .font(.caption)
                .foregroundStyle(AppTheme.mutedText)
        }
    }

    @ViewBuilder
    private func scoreRow(_ details: TitleDetails) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let rottenTomatoesScore = details.rottenTomatoesScore {
                    metricBadge("RT \(rottenTomatoesScore)", icon: "checkmark.seal.fill", color: .green)
                }

                if let tmdbScoreText = details.tmdbScoreText {
                    metricBadge(tmdbScoreText, icon: "star.fill", color: .orange)
                }

                if let runtimeText = details.runtimeText {
                    metricBadge(runtimeText, icon: "clock.fill", color: .blue)
                }
            }
        }
    }

    // Displays provider availability in useful subscription, free, rent, and buy groups.
    private func watchSection(_ details: TitleDetails) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "play.tv.fill")
                    .foregroundStyle(AppTheme.coral)
                Text("Where to watch")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }

            if details.hasWatchOptions {
                providerGroup("Included with subscription", icon: "checkmark.circle.fill", providers: details.subscriptionProviders)
                providerGroup("Free or with ads", icon: "sparkles.tv.fill", providers: details.freeProviders)
                providerGroup("Rent", icon: "clock.arrow.circlepath", providers: details.rentProviders)
                providerGroup("Buy", icon: "bag.fill", providers: details.buyProviders)
            } else {
                Text("We couldn’t find streaming availability for your region.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if let streamingLink = details.streamingLink, let url = URL(string: streamingLink) {
                Link(destination: url) {
                    Label("Open all watch options", systemImage: "arrow.up.right.square.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(GlassButtonStyle(tint: AppTheme.red))
            }

            Text("Availability is provided by JustWatch through TMDB and can change by region.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
    }

    // Displays one watch-option group when providers are available.
    @ViewBuilder
    private func providerGroup(_ title: String, icon: String, providers: [String]) -> some View {
        if !providers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                WrapTagsView(tags: providers)
            }
        }
    }

    // Builds a compact rating or runtime badge.
    private func metricBadge(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .background(color.opacity(0.22), in: Capsule())
    }

    // Loads detail data from the title service.
    private func loadDetails() {
        isLoading = true
        TitleFeedService.shared.fetchTitleDetails(for: card) { loadedDetails in
            DispatchQueue.main.async {
                details = loadedDetails
                isLoading = false
            }
        }
    }
}

struct WrapTagsView: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(AppTheme.secondaryText)
                    .background(AppTheme.panelStrong, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}
