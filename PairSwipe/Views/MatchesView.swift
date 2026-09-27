import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MatchesView: View {
    let pair: Pair

    @EnvironmentObject private var pairSession: PairSession
    @State private var matches: [Match] = []
    @State private var listener: MatchesListener?
    @State private var cardsById: [String: TitleCard] = [:]
    @State private var selectedCard: TitleCard?
    @State private var pendingTitleId: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppGradientBackground()

                if matches.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            shortlistHeader

                            ForEach(matches) { match in
                                Button {
                                    openMatch(match)
                                } label: {
                                    ShortlistRowView(card: cardsById[match.titleId], matchedAt: match.matchedAt)
                                }
                                .buttonStyle(.plain)
                                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 112)
                    }
                }
            }
            .navigationTitle("Shortlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $selectedCard) { card in
                TitleDetailSheetView(card: card)
            }
            .onAppear {
                startListening()
            }
            .onDisappear {
                listener?.remove()
                listener = nil
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: pair.memberB == nil ? "person.badge.clock.fill" : "heart.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(pair.memberB == nil ? AppTheme.amber : AppTheme.red)

            Text(pair.memberB == nil ? "Waiting for your partner" : "No shared picks yet")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            Text(pair.memberB == nil
                 ? "Share the invite code from the Room tab. You can start choosing now."
                : "Keep deciding. Anything you both save will appear here automatically.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)

            if pair.memberB == nil {
                Text("Open the Room tab to copy or share your invite code.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .glassSurface(cornerRadius: 8, padding: 22, material: .regularMaterial)
        .padding(16)
    }

    private var shortlistHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activePair.displayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.teal)
                    Text("You both picked")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(matches.count) shared \(matches.count == 1 ? "pick" : "picks") ready for tonight")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                Image(systemName: "heart.fill")
                    .font(.title2)
                .foregroundStyle(AppTheme.red)
            }

            Button(action: pickForUs) {
                Label("Choose for tonight", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(GlassButtonStyle(tint: AppTheme.red))
            .disabled(loadedCards.isEmpty)
        }
        .padding(16)
        .glassSurface(cornerRadius: 8, padding: 16, material: .regularMaterial)
    }

    private var loadedCards: [TitleCard] {
        matches.compactMap { cardsById[$0.titleId] }
    }

    private var activePair: Pair {
        pairSession.activePair ?? pair
    }

    // Starts listening to live match updates.
    private func startListening() {
        listener?.remove()
        listener = FirestoreService.shared.listenMatches(pairId: pair.id) { newMatches in
            DispatchQueue.main.async {
                self.matches = newMatches
                self.loadCards(for: newMatches)
            }
        }
    }

    // Loads card metadata for each matched title id.
    private func loadCards(for matches: [Match]) {
        for match in matches where cardsById[match.titleId] == nil {
            TitleFeedService.shared.fetchTitle(id: match.titleId, pairId: pair.id) { card in
                guard let card = card else { return }
                DispatchQueue.main.async {
                    self.cardsById[match.titleId] = card
                    if pendingTitleId == match.titleId {
                        pendingTitleId = nil
                        selectedCard = card
                    }
                }
            }
        }
    }

    // Opens a shortlist item immediately when loaded, or queues the request while metadata loads.
    private func openMatch(_ match: Match) {
        if let card = cardsById[match.titleId] {
            selectedCard = card
        } else {
            pendingTitleId = match.titleId
        }
    }

    // Selects one shared title at random when the pair wants a quick decision.
    private func pickForUs() {
        guard let card = loadedCards.randomElement() else { return }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        selectedCard = card
    }
}

struct ShortlistRowView: View {
    let card: TitleCard?
    let matchedAt: Date

    private let primaryText = Color.white
    private let secondaryText = AppTheme.secondaryText

    var body: some View {
        HStack(spacing: 12) {
            poster

            VStack(alignment: .leading, spacing: 6) {
                Text(card?.title ?? "Loading title...")
                    .font(.headline)
                    .foregroundStyle(primaryText)
                    .lineLimit(2)

                if let card = card {
                    Text([card.type.uppercased(), card.year].filter { !$0.isEmpty }.joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(secondaryText)

                    watchSummary(for: card)

                    HStack(spacing: 8) {
                        if let score = card.tmdbScore {
                            Text(String(format: "TMDB %.1f", score))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .foregroundStyle(.white)
                                .background(Color.orange.opacity(0.22), in: Capsule())
                        }

                        if let rottenTomatoesScore = card.rottenTomatoesScore {
                            Text("RT \(rottenTomatoesScore)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .foregroundStyle(.white)
                                .background(Color.green.opacity(0.22), in: Capsule())
                        }
                    }
                }

                Text("Matched \(matchedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(secondaryText)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(secondaryText)
        }
        .padding(14)
        .glassSurface(cornerRadius: 8, padding: 14, material: .regularMaterial)
    }

    private var poster: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 70, height: 100)

            if let posterUrl = card?.posterUrl,
               let url = URL(string: posterUrl),
               !posterUrl.isEmpty {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 70, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "film")
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
    }

    @ViewBuilder
    private func watchSummary(for card: TitleCard) -> some View {
        if !card.streamProviders.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "play.tv.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.teal)

                Text(card.streamProviders.prefix(3).joined(separator: ", "))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
            }
        } else {
            Text("Tap for ratings and watch options")
                .font(.caption.weight(.medium))
                .foregroundStyle(secondaryText)
        }
    }
}

struct MatchDetailView: View {
    let pair: Pair
    let titleId: String
    let matchedAt: Date

    @State private var card: TitleCard?
    @State private var isLoading = true
    @State private var showDetailSheet = false

    var body: some View {
        ZStack {
            AppGradientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let card = card {
                        TitleCardView(card: card, onMoreInfo: {
                            showDetailSheet = true
                        })
                    } else if isLoading {
                        ProgressView("Loading title...")
                            .tint(.white)
                            .foregroundStyle(.white)
                            .padding(.top, 20)
                    } else {
                        Text("Could not load title details.")
                            .foregroundStyle(.white)
                    }

                    Text("Matched on \(matchedAt.formatted(date: .complete, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
        }
        .navigationTitle("Tonight Pick")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadCard()
        }
        .sheet(isPresented: $showDetailSheet) {
            if let card = card {
                TitleDetailSheetView(card: card)
            }
        }
    }

    // Loads one saved card for the selected match.
    private func loadCard() {
        isLoading = true
        TitleFeedService.shared.fetchTitle(id: titleId, pairId: pair.id) { loadedCard in
            DispatchQueue.main.async {
                self.card = loadedCard
                self.isLoading = false
            }
        }
    }
}
