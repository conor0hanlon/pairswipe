import Foundation

struct TitleCard: Identifiable, Codable, Hashable {
    let id: String
    let type: String
    let title: String
    let year: String
    let overview: String
    let posterUrl: String
    let backdropUrl: String
    let runtimeMinutes: Int?
    let genres: [String]
    let tmdbScore: Double?
    let rottenTomatoesScore: String?
    let streamProviders: [String]
    let streamingLink: String?
}

enum VoteValue: String, Codable {
    case like
    case pass
}

struct Pair: Identifiable, Codable {
    let id: String
    let createdAt: Date
    let memberA: String
    let memberB: String?
    let inviteCode: String
    let queueTitleIds: [String]?
    let name: String?

    // Uses a friendly fallback for rooms created before naming was added.
    var displayName: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? "Tonight room" : trimmedName
    }

    // Each saved queue round contains up to 18 titles.
    var queueRound: Int {
        max(1, Int(ceil(Double(queueTitleIds?.count ?? 0) / 18.0)))
    }
}

struct Match: Identifiable, Codable {
    let id: String
    let titleId: String
    let matchedAt: Date
    let likedBy: [String]
}

struct PairLandingSnapshot: Identifiable {
    let id: String
    let pair: Pair
    let shortlistPreview: [TitleCard]
    let matchCount: Int
    let isPairReady: Bool
    let remainingSwipeCount: Int
    let totalSwipeCount: Int
}

struct TitleDetails: Hashable {
    let title: String
    let subtitle: String
    let overview: String
    let genres: [String]
    let runtimeText: String?
    let tmdbScoreText: String?
    let rottenTomatoesScore: String?
    let subscriptionProviders: [String]
    let freeProviders: [String]
    let rentProviders: [String]
    let buyProviders: [String]
    let streamingLink: String?

    var hasWatchOptions: Bool {
        !subscriptionProviders.isEmpty
            || !freeProviders.isEmpty
            || !rentProviders.isEmpty
            || !buyProviders.isEmpty
    }
}
