import SwiftUI

struct TVShortlistView: View {
    @EnvironmentObject private var session: TVShortlistSession
    @State private var inviteCode = ""
    @State private var selectedTitle: TVShortlistTitle?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.05, blue: 0.10), Color(red: 0.12, green: 0.04, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if session.isSigningIn {
                ProgressView("Connecting to PairSwipe…")
            } else if session.pairID == nil {
                connectView
            } else {
                shortlistView
            }
        }
        .foregroundStyle(.white)
        .alert("PairSwipe", isPresented: errorIsPresented) {
            Button("OK") { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
        .sheet(item: $selectedTitle) { title in
            TVTitleDetailView(title: title)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )
    }

    private var connectView: some View {
        VStack(spacing: 34) {
            Image(systemName: "heart.rectangle.fill")
                .font(.system(size: 90, weight: .bold))
                .foregroundStyle(.pink)

            VStack(spacing: 12) {
                Text("PairSwipe Shortlist")
                    .font(.system(size: 54, weight: .black, design: .rounded))
                Text("Enter the room code shown in PairSwipe on your iPhone.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.72))
            }

            HStack(spacing: 22) {
                TextField("Room code", text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .frame(width: 360)
                    .onChange(of: inviteCode) { newValue in
                        inviteCode = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                    }

                Button(session.isConnecting ? "Connecting…" : "Show Shortlist") {
                    session.connect(inviteCode: inviteCode)
                }
                .disabled(session.isConnecting)
            }
        }
        .padding(80)
    }

    private var shortlistView: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.roomName)
                        .font(.system(size: 52, weight: .black, design: .rounded))
                    Text("Your shared shortlist")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.68))
                }

                Spacer()

                Button("Change Room") {
                    session.disconnect()
                }
            }

            if session.titles.isEmpty {
                emptyShortlist
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 34) {
                        ForEach(session.titles) { title in
                            Button {
                                selectedTitle = title
                            } label: {
                                TVPosterCard(title: title)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.vertical, 22)
                }
            }
        }
        .padding(.horizontal, 70)
        .padding(.vertical, 54)
    }

    private var emptyShortlist: some View {
        VStack(spacing: 18) {
            Image(systemName: "heart.slash")
                .font(.system(size: 68))
                .foregroundStyle(.pink.opacity(0.75))
            Text("No shared picks yet")
                .font(.title.bold())
            Text("When both people save the same title on iPhone, it will appear here automatically.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TVPosterCard: View {
    let title: TVShortlistTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AsyncImage(url: title.posterURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "film.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            .frame(width: 260, height: 390)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(title.title)
                .font(.title3.bold())
                .lineLimit(2)
            Text(title.subtitle)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(width: 260, alignment: .leading)
    }
}

private struct TVTitleDetailView: View {
    let title: TVShortlistTitle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AsyncImage(url: title.backdropURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color(red: 0.04, green: 0.05, blue: 0.09)
                }
            }
            .ignoresSafeArea()

            LinearGradient(colors: [.black.opacity(0.18), .black.opacity(0.94)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                Spacer()
                Text(title.subtitle.uppercased())
                    .font(.headline.weight(.black))
                    .foregroundStyle(.pink)
                Text(title.title)
                    .font(.system(size: 62, weight: .black, design: .rounded))

                if let score = title.score {
                    Label(String(format: "TMDB %.1f", score), systemImage: "star.fill")
                        .font(.title3.bold())
                }

                Text(title.overview.isEmpty ? "No description is available yet." : title.overview)
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(5)
                    .frame(maxWidth: 950, alignment: .leading)

                if !title.providers.isEmpty {
                    Text("Watch on: \(title.providers.prefix(4).joined(separator: " • "))")
                        .font(.title3.bold())
                }

                Button("Back to Shortlist") { dismiss() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(76)
        }
        .foregroundStyle(.white)
    }
}
