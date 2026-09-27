import SwiftUI

struct TitleCardView: View {
    let card: TitleCard
    let onMoreInfo: (() -> Void)?
    let posterHeight: CGFloat
    let showsOverview: Bool
    let onDragChanged: ((CGSize) -> Void)?
    let onDragEnded: ((CGSize) -> Void)?

    init(
        card: TitleCard,
        posterHeight: CGFloat = 320,
        showsOverview: Bool = true,
        onMoreInfo: (() -> Void)? = nil,
        onDragChanged: ((CGSize) -> Void)? = nil,
        onDragEnded: ((CGSize) -> Void)? = nil
    ) {
        self.card = card
        self.posterHeight = posterHeight
        self.showsOverview = showsOverview
        self.onMoreInfo = onMoreInfo
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            posterArea

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.title)
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 7) {
                        GlassTag(card.type == "tv" ? "Series" : "Movie", tint: AppTheme.secondaryText)

                        if !card.year.isEmpty {
                            GlassTag(card.year, tint: AppTheme.secondaryText)
                        }

                        if let runtime = card.runtimeMinutes {
                            GlassTag("\(runtime) min", tint: AppTheme.teal)
                        }
                    }
                }

                metricsRow

                if showsOverview {
                    Text(card.overview.isEmpty ? "Details are still loading for this title." : card.overview)
                        .font(.subheadline)
                        .lineLimit(4)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !card.genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(card.genres.prefix(5), id: \.self) { genre in
                                GlassTag(genre, tint: AppTheme.secondaryText)
                            }
                        }
                    }
                }

                providerPreview

                if let onMoreInfo {
                    Button(action: onMoreInfo) {
                        Label("Ratings and watch options", systemImage: "info.circle.fill")
                    }
                    .buttonStyle(GlassButtonStyle(tint: AppTheme.charcoal))
                    .accessibilityHint("Shows ratings and where this title is available")
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: AppTheme.surfaceShadow, radius: 24, x: 0, y: 16)
    }

    private var posterArea: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(AppTheme.ink.opacity(0.18))
                .frame(height: posterHeight)

            if let url = URL(string: imageUrl), !imageUrl.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallbackPoster
                    default:
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: posterHeight)
                .clipped()
            } else {
                fallbackPoster
            }

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    GlassTag(card.type == "tv" ? "Series" : "Movie", tint: Color.white)
                    Spacer()
                    if let score = card.tmdbScore {
                        Label(String(format: "%.1f", score), systemImage: "star.fill")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.black.opacity(0.50), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }

                Text("Tonight candidate")
                    .font(.caption.weight(.black))
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.amber)
            }
            .padding(14)
        }
        .frame(height: posterHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    onDragChanged?(value.translation)
                }
                .onEnded { value in
                    onDragEnded?(value.translation)
                }
        )
    }

    private var metricsRow: some View {
        HStack(spacing: 8) {
            if let score = card.tmdbScore {
                metric("TMDB", value: String(format: "%.1f", score), color: AppTheme.amber)
            }

            if let rotten = card.rottenTomatoesScore {
                metric("RT", value: rotten, color: AppTheme.green)
            }

            if !card.streamProviders.isEmpty {
                metric("On", value: card.streamProviders.prefix(2).joined(separator: ", "), color: AppTheme.teal)
            }
        }
    }

    @ViewBuilder
    private var providerPreview: some View {
        if !card.streamProviders.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "play.tv.fill")
                    .foregroundStyle(AppTheme.teal)
                Text(card.streamProviders.prefix(3).joined(separator: " • "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.screen, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func metric(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.black))
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var imageUrl: String {
        card.backdropUrl.isEmpty ? card.posterUrl : card.backdropUrl
    }

    private var fallbackPoster: some View {
        ZStack {
            LinearGradient(colors: [AppTheme.charcoal, AppTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: card.type == "tv" ? "tv.fill" : "film.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity)
        .frame(height: posterHeight)
    }
}
