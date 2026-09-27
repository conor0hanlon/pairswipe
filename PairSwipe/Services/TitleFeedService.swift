import Foundation

final class TitleFeedService {
    static let shared = TitleFeedService()

    private var lastQueue: [TitleCard] = []
    private var cardCache: [String: TitleCard] = [:]
    private var detailsCache: [String: TitleDetails] = [:]
    private var typeCache: [String: String] = [:]

    // Loads a shared queue of currently streamable movies and TV shows.
    func loadQueue(pairId: String, completion: @escaping ([TitleCard]) -> Void) {
        FirestoreService.shared.fetchPair(pairId: pairId) { pair in
            guard let pair = pair else {
                self.loadTonightCards(completion: completion)
                return
            }

            FirestoreService.shared.fetchVotedTitleIDsForCurrentUser(pairId: pairId) { votedTitleIDs in
                let existingQueueIDs = pair.queueTitleIds ?? []
                if !existingQueueIDs.isEmpty {
                    self.loadCards(for: existingQueueIDs, pairId: pairId) { cards in
                        let remainingCards = cards.filter { !votedTitleIDs.contains($0.id) }
                        DispatchQueue.main.async {
                            self.lastQueue = remainingCards
                            completion(remainingCards)
                        }
                    }
                    return
                }

                self.loadTonightCards { tonightCards in
                    let queueSeedCards = Array(tonightCards.prefix(18))
                    FirestoreService.shared.ensureQueueTitleIDs(pairId: pairId, proposedCards: queueSeedCards) { queueIDs in
                        let cardsToPersist = queueSeedCards.filter { queueIDs.contains($0.id) }
                        FirestoreService.shared.saveTitles(pairId: pairId, cards: cardsToPersist) { _ in }

                        self.loadCards(for: queueIDs, pairId: pairId) { cards in
                            let remainingCards = cards.filter { !votedTitleIDs.contains($0.id) }
                            DispatchQueue.main.async {
                                self.lastQueue = remainingCards
                                completion(remainingCards)
                            }
                        }
                    }
                }
            }
        }
    }

    // Builds the next duplicate-free round for an existing room.
    func loadAdditionalRound(excluding existingIDs: Set<String>, completion: @escaping ([TitleCard]) -> Void) {
        let nextPage = max(2, (existingIDs.count / 18) + 1)

        loadTonightCards(page: nextPage) { firstPageCards in
            var newCards: [TitleCard] = []
            self.appendUniqueCards(
                from: firstPageCards.filter { !existingIDs.contains($0.id) },
                count: 18,
                to: &newCards
            )

            guard newCards.count < 18 else {
                completion(Array(newCards.prefix(18)))
                return
            }

            // A second page fills gaps caused by overlap between TMDB categories.
            self.loadTonightCards(page: nextPage + 1) { secondPageCards in
                self.appendUniqueCards(
                    from: secondPageCards.filter { !existingIDs.contains($0.id) },
                    count: 18 - newCards.count,
                    to: &newCards
                )
                completion(Array(newCards.prefix(18)))
            }
        }
    }

    // Loads a single title by id from cache, Firestore, or TMDB.
    func fetchTitle(id: String, pairId: String?, completion: @escaping (TitleCard?) -> Void) {
        if let cached = cardCache[id] {
            completion(cached)
            return
        }

        if let inQueue = lastQueue.first(where: { $0.id == id }) {
            cardCache[id] = inQueue
            completion(inQueue)
            return
        }

        if let pairId = pairId {
            FirestoreService.shared.fetchSavedTitle(pairId: pairId, titleId: id) { savedCard in
                if let savedCard = savedCard {
                    self.cardCache[id] = savedCard
                    self.typeCache[id] = savedCard.type
                    completion(savedCard)
                    return
                }
                self.fetchTitleFromTMDB(id: id, completion: completion)
            }
            return
        }

        fetchTitleFromTMDB(id: id, completion: completion)
    }

    // Loads richer details for one card (runtime, providers, Rotten Tomatoes score, etc.).
    func fetchTitleDetails(for card: TitleCard, completion: @escaping (TitleDetails) -> Void) {
        if let cached = detailsCache[card.id] {
            completion(cached)
            return
        }

        guard let tmdbId = Int(card.id), let apiKey = Self.tmdbApiKey, !apiKey.isEmpty, apiKey != "REPLACE_ME" else {
            let fallback = buildDetails(from: card)
            detailsCache[card.id] = fallback
            completion(fallback)
            return
        }

        fetchTMDBDetail(type: card.type, tmdbId: tmdbId, apiKey: apiKey) { payload in
            self.fetchWatchProviders(type: card.type, tmdbId: tmdbId, apiKey: apiKey) { watchAvailability in
                self.fetchRottenTomatoesScore(type: card.type, tmdbId: tmdbId, apiKey: apiKey) { rottenTomatoesScore in
                    let mergedCard = TitleCard(
                        id: card.id,
                        type: card.type,
                        title: card.title,
                        year: payload?.year ?? card.year,
                        overview: payload?.overview.isEmpty == false ? payload?.overview ?? card.overview : card.overview,
                        posterUrl: card.posterUrl,
                        backdropUrl: card.backdropUrl,
                        runtimeMinutes: payload?.runtime ?? card.runtimeMinutes,
                        genres: payload?.genres.isEmpty == false ? payload?.genres ?? card.genres : card.genres,
                        tmdbScore: payload?.voteAverage ?? card.tmdbScore,
                        rottenTomatoesScore: rottenTomatoesScore ?? card.rottenTomatoesScore,
                        streamProviders: watchAvailability.allProviders.isEmpty ? card.streamProviders : watchAvailability.allProviders,
                        streamingLink: watchAvailability.link ?? card.streamingLink
                    )

                    self.cardCache[card.id] = mergedCard
                    self.typeCache[card.id] = mergedCard.type

                    let details = self.buildDetails(from: mergedCard, availability: watchAvailability)
                    self.detailsCache[card.id] = details
                    completion(details)
                }
            }
        }
    }

    // Reads the TMDB API key from Info.plist.
    private static var tmdbApiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "TMDBApiKey") as? String
    }

    // Reads the optional OMDb key from Info.plist.
    private static var omdbApiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "OMDbApiKey") as? String
    }

    // Loads a varied set of current, relevant titles that are available to stream.
    private func loadTonightCards(page: Int = 1, completion: @escaping ([TitleCard]) -> Void) {
        guard let apiKey = Self.tmdbApiKey, !apiKey.isEmpty, apiKey != "REPLACE_ME" else {
            completion(Self.sampleTitles())
            return
        }

        let group = DispatchGroup()
        var trendingMovies: [TitleCard] = []
        var trendingShows: [TitleCard] = []
        var recentMovies: [TitleCard] = []
        var recentShows: [TitleCard] = []
        var currentShows: [TitleCard] = []
        var evergreenMovies: [TitleCard] = []
        var evergreenShows: [TitleCard] = []

        group.enter()
        fetchWeeklyTrendingCards(type: "movie", apiKey: apiKey, page: page) { cards in
            trendingMovies = cards
            group.leave()
        }

        group.enter()
        fetchWeeklyTrendingCards(type: "tv", apiKey: apiKey, page: page) { cards in
            trendingShows = cards
            group.leave()
        }

        group.enter()
        fetchRecentCards(type: "movie", apiKey: apiKey, page: page) { cards in
            recentMovies = cards
            group.leave()
        }

        group.enter()
        fetchRecentCards(type: "tv", apiKey: apiKey, page: page) { cards in
            recentShows = cards
            group.leave()
        }

        group.enter()
        fetchCurrentTVShows(apiKey: apiKey, page: page) { cards in
            currentShows = cards
            group.leave()
        }

        group.enter()
        fetchEvergreenCards(type: "movie", apiKey: apiKey, page: page) { cards in
            evergreenMovies = cards
            group.leave()
        }

        group.enter()
        fetchEvergreenCards(type: "tv", apiKey: apiKey, page: page) { cards in
            evergreenShows = cards
            group.leave()
        }

        group.notify(queue: .main) {
            let trendingCandidates = self.interleave(trendingMovies, trendingShows)

            // TMDB's trending endpoint has no streaming filter, so verify its
            // candidates against the current device region before using them.
            self.filterStreamableCards(trendingCandidates, apiKey: apiKey) { streamableTrending in
                let recentCandidates = self.interleave(recentMovies, recentShows)
                let evergreenCandidates = self.interleave(evergreenMovies, evergreenShows)

                var mixed: [TitleCard] = []
                self.appendUniqueCards(from: streamableTrending, count: 6, to: &mixed)
                self.appendUniqueCards(from: recentCandidates, count: 6, to: &mixed)
                self.appendUniqueCards(from: currentShows, count: 4, to: &mixed)
                self.appendUniqueCards(from: evergreenCandidates, count: 2, to: &mixed)

                // Fill any gaps caused by duplicates or a temporarily sparse feed.
                let backupCandidates = streamableTrending
                    + recentCandidates
                    + currentShows
                    + evergreenCandidates
                self.appendUniqueCards(from: backupCandidates, count: 18 - mixed.count, to: &mixed)

                guard mixed.count >= 10 else {
                    self.loadTrendingCards(completion: completion)
                    return
                }

                let finalCards = Array(mixed.prefix(18))
                self.cache(cards: finalCards)
                completion(finalCards)
            }
        }
    }

    // Fetches one TMDB result page and converts it into PairSwipe cards.
    private func fetchCards(url: URL?, type: String, completion: @escaping ([TitleCard]) -> Void) {
        guard let url else {
            completion([])
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, _ in
            guard
                let httpResponse = response as? HTTPURLResponse,
                (200...299).contains(httpResponse.statusCode),
                let data = data,
                let decoded = try? JSONDecoder().decode(TMDBTrendingResponse.self, from: data)
            else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let cards = decoded.results.compactMap { self.mapMedia($0, type: type) }
                .filter { ($0.tmdbScore ?? 0) >= 5.8 }

            DispatchQueue.main.async { completion(cards) }
        }.resume()
    }

    // Loads movies or shows that are trending on TMDB this week.
    private func fetchWeeklyTrendingCards(type: String, apiKey: String, page: Int, completion: @escaping ([TitleCard]) -> Void) {
        var components = URLComponents(string: "https://api.themoviedb.org/3/trending/\(type)/week")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "page", value: String(page))
        ]
        fetchCards(url: components?.url, type: type, completion: completion)
    }

    // Loads popular streaming titles released during the last two years.
    private func fetchRecentCards(type: String, apiKey: String, page: Int, completion: @escaping ([TitleCard]) -> Void) {
        let lowerDateField = type == "movie" ? "primary_release_date.gte" : "first_air_date.gte"
        let upperDateField = type == "movie" ? "primary_release_date.lte" : "first_air_date.lte"
        let extraItems = [
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "vote_count.gte", value: type == "movie" ? "150" : "75"),
            URLQueryItem(name: lowerDateField, value: Self.dateString(monthsFromToday: -24)),
            URLQueryItem(name: upperDateField, value: Self.dateString())
        ]
        fetchCards(url: discoverURL(type: type, apiKey: apiKey, page: page, extraItems: extraItems), type: type, completion: completion)
    }

    // Loads shows with episodes airing recently or during the coming week.
    private func fetchCurrentTVShows(apiKey: String, page: Int, completion: @escaping ([TitleCard]) -> Void) {
        let extraItems = [
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "vote_count.gte", value: "75"),
            URLQueryItem(name: "air_date.gte", value: Self.dateString(daysFromToday: -45)),
            URLQueryItem(name: "air_date.lte", value: Self.dateString(daysFromToday: 7))
        ]
        fetchCards(url: discoverURL(type: "tv", apiKey: apiKey, page: page, extraItems: extraItems), type: "tv", completion: completion)
    }

    // Loads highly rated older titles while still requiring streaming access.
    private func fetchEvergreenCards(type: String, apiKey: String, page: Int, completion: @escaping ([TitleCard]) -> Void) {
        let dateField = type == "movie" ? "primary_release_date.lte" : "first_air_date.lte"
        let extraItems = [
            URLQueryItem(name: "sort_by", value: "vote_average.desc"),
            URLQueryItem(name: "vote_count.gte", value: type == "movie" ? "1000" : "500"),
            URLQueryItem(name: dateField, value: Self.dateString(monthsFromToday: -24))
        ]
        fetchCards(url: discoverURL(type: type, apiKey: apiKey, page: page, extraItems: extraItems), type: type, completion: completion)
    }

    // Builds a discover request with the shared regional streaming filters.
    private func discoverURL(type: String, apiKey: String, page: Int, extraItems: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: "https://api.themoviedb.org/3/discover/\(type)")
        let sharedItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "watch_region", value: Self.watchRegion),
            URLQueryItem(name: "with_watch_monetization_types", value: "flatrate|free|ads"),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "include_video", value: "false"),
            URLQueryItem(name: "page", value: String(page))
        ]
        components?.queryItems = sharedItems + extraItems
        return components?.url
    }

    // Formats a date for TMDB query parameters.
    private static func dateString(monthsFromToday: Int = 0, daysFromToday: Int = 0) -> String {
        let calendar = Calendar.current
        let monthDate = calendar.date(byAdding: .month, value: monthsFromToday, to: Date()) ?? Date()
        let finalDate = calendar.date(byAdding: .day, value: daysFromToday, to: monthDate) ?? monthDate
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: finalDate)
    }

    // Alternates movies and TV shows so the deck does not feel repetitive.
    private func interleave(_ movies: [TitleCard], _ shows: [TitleCard]) -> [TitleCard] {
        var result: [TitleCard] = []
        let count = max(movies.count, shows.count)
        for index in 0..<count {
            if index < movies.count { result.append(movies[index]) }
            if index < shows.count { result.append(shows[index]) }
        }
        return result
    }

    // Adds a limited number of cards without repeating the same movie or show.
    private func appendUniqueCards(from candidates: [TitleCard], count: Int, to result: inout [TitleCard]) {
        guard count > 0 else { return }

        var addedCount = 0
        for card in candidates {
            // Queue IDs in existing rooms are numeric TMDB IDs. Treat a movie
            // and show with the same number as a duplicate to avoid overwriting
            // the saved title document used by those older rooms.
            let alreadyIncluded = result.contains { $0.id == card.id }
            guard !alreadyIncluded else { continue }

            result.append(card)
            addedCount += 1
            if addedCount == count {
                return
            }
        }
    }

    // Verifies that trending titles have subscription, free, or ad-supported
    // availability in the current region before adding them to the deck.
    private func filterStreamableCards(_ cards: [TitleCard], apiKey: String, completion: @escaping ([TitleCard]) -> Void) {
        let candidates = Array(cards.prefix(24))
        guard !candidates.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        var streamableByKey: [String: TitleCard] = [:]

        for card in candidates {
            guard let tmdbId = Int(card.id) else { continue }
            group.enter()
            fetchWatchProviders(type: card.type, tmdbId: tmdbId, apiKey: apiKey) { availability in
                defer { group.leave() }
                guard !availability.subscription.isEmpty || !availability.free.isEmpty else { return }

                let updatedCard = TitleCard(
                    id: card.id,
                    type: card.type,
                    title: card.title,
                    year: card.year,
                    overview: card.overview,
                    posterUrl: card.posterUrl,
                    backdropUrl: card.backdropUrl,
                    runtimeMinutes: card.runtimeMinutes,
                    genres: card.genres,
                    tmdbScore: card.tmdbScore,
                    rottenTomatoesScore: card.rottenTomatoesScore,
                    streamProviders: availability.subscription + availability.free,
                    streamingLink: availability.link
                )
                streamableByKey["\(card.type)-\(card.id)"] = updatedCard
            }
        }

        group.notify(queue: .main) {
            let ordered = candidates.compactMap { card in
                streamableByKey["\(card.type)-\(card.id)"]
            }
            completion(ordered)
        }
    }

    // Maps a TMDB result into the small card model used throughout the app.
    private func mapMedia(_ media: TMDBMedia, type: String) -> TitleCard? {
        let title = media.title ?? media.name ?? ""
        let date = media.release_date ?? media.first_air_date ?? ""
        guard !title.isEmpty, let posterPath = media.poster_path, !(media.overview ?? "").isEmpty else {
            return nil
        }

        return TitleCard(
            id: String(media.id),
            type: type,
            title: title,
            year: date.split(separator: "-").first.map(String.init) ?? "",
            overview: media.overview ?? "",
            posterUrl: "https://image.tmdb.org/t/p/w500\(posterPath)",
            backdropUrl: media.backdrop_path.map { "https://image.tmdb.org/t/p/w780\($0)" } ?? "",
            runtimeMinutes: nil,
            genres: [],
            tmdbScore: media.vote_average,
            rottenTomatoesScore: nil,
            streamProviders: [],
            streamingLink: nil
        )
    }

    // Stores cards in memory for quick navigation between tabs.
    private func cache(cards: [TitleCard]) {
        lastQueue = cards
        cards.forEach { card in
            cardCache[card.id] = card
            typeCache[card.id] = card.type
        }
    }

    // Uses the device region for provider availability, with US as a safe fallback.
    private static var watchRegion: String {
        Locale.current.region?.identifier ?? "US"
    }

    // Loads the trending feed used to seed new pair queues.
    private func loadTrendingCards(completion: @escaping ([TitleCard]) -> Void) {
        guard let apiKey = Self.tmdbApiKey, !apiKey.isEmpty, apiKey != "REPLACE_ME" else {
            let sampleCards = Self.sampleTitles()
            lastQueue = sampleCards
            completion(sampleCards)
            return
        }

        let urlString = "https://api.themoviedb.org/3/trending/all/day?api_key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            let sampleCards = Self.sampleTitles()
            lastQueue = sampleCards
            completion(sampleCards)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async {
                    let sampleCards = Self.sampleTitles()
                    self.lastQueue = sampleCards
                    completion(sampleCards)
                }
                return
            }

            do {
                let decoded = try JSONDecoder().decode(TMDBTrendingResponse.self, from: data)
                let mapped = decoded.results.compactMap { media -> TitleCard? in
                    let type = media.media_type ?? ""
                    guard type == "movie" || type == "tv" else { return nil }
                    return self.mapMedia(media, type: type)
                }

                DispatchQueue.main.async {
                    self.cache(cards: mapped)
                    completion(mapped)
                }
            } catch {
                DispatchQueue.main.async {
                    let sampleCards = Self.sampleTitles()
                    self.lastQueue = sampleCards
                    completion(sampleCards)
                }
            }
        }.resume()
    }

    // Loads cards in a stable order from queue ids.
    private func loadCards(for ids: [String], pairId: String, completion: @escaping ([TitleCard]) -> Void) {
        if ids.isEmpty {
            completion([])
            return
        }

        let group = DispatchGroup()
        var cardsByID: [String: TitleCard] = [:]

        ids.forEach { id in
            group.enter()
            fetchTitle(id: id, pairId: pairId) { card in
                if let card = card {
                    cardsByID[id] = card
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let orderedCards = ids.compactMap { cardsByID[$0] }
            orderedCards.forEach { card in
                self.cardCache[card.id] = card
                self.typeCache[card.id] = card.type
            }
            completion(orderedCards)
        }
    }

    // Builds easy-to-display text used by the detail sheet.
    private func buildDetails(from card: TitleCard, availability: WatchAvailability? = nil) -> TitleDetails {
        let subtitleParts = [card.type.uppercased(), card.year].filter { !$0.isEmpty }
        let subtitle = subtitleParts.joined(separator: " • ")
        let runtimeText = card.runtimeMinutes.map { "\($0) min" }
        let tmdbScoreText = card.tmdbScore.map { String(format: "%.1f / 10", $0) }

        return TitleDetails(
            title: card.title,
            subtitle: subtitle,
            overview: card.overview,
            genres: card.genres,
            runtimeText: runtimeText,
            tmdbScoreText: tmdbScoreText,
            rottenTomatoesScore: card.rottenTomatoesScore,
            subscriptionProviders: availability?.subscription ?? card.streamProviders,
            freeProviders: availability?.free ?? [],
            rentProviders: availability?.rent ?? [],
            buyProviders: availability?.buy ?? [],
            streamingLink: card.streamingLink
        )
    }

    // Loads a title directly from TMDB when it was not found in cache or Firestore.
    private func fetchTitleFromTMDB(id: String, completion: @escaping (TitleCard?) -> Void) {
        guard let tmdbId = Int(id), let apiKey = Self.tmdbApiKey, !apiKey.isEmpty, apiKey != "REPLACE_ME" else {
            completion(nil)
            return
        }

        if let knownType = typeCache[id] {
            fetchTMDBCard(type: knownType, tmdbId: tmdbId, apiKey: apiKey, completion: completion)
            return
        }

        fetchTMDBCard(type: "movie", tmdbId: tmdbId, apiKey: apiKey) { movieCard in
            if let movieCard = movieCard {
                completion(movieCard)
                return
            }

            self.fetchTMDBCard(type: "tv", tmdbId: tmdbId, apiKey: apiKey) { tvCard in
                completion(tvCard)
            }
        }
    }

    // Loads a single movie or TV card from TMDB detail endpoints.
    private func fetchTMDBCard(type: String, tmdbId: Int, apiKey: String, completion: @escaping (TitleCard?) -> Void) {
        guard let url = URL(string: "https://api.themoviedb.org/3/\(type)/\(tmdbId)?api_key=\(apiKey)") else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            if type == "movie", let movie = try? JSONDecoder().decode(TMDBMovieDetailResponse.self, from: data) {
                let card = TitleCard(
                    id: String(movie.id),
                    type: "movie",
                    title: movie.title ?? "Untitled",
                    year: movie.release_date?.split(separator: "-").first.map(String.init) ?? "",
                    overview: movie.overview ?? "",
                    posterUrl: movie.poster_path.map { "https://image.tmdb.org/t/p/w500\($0)" } ?? "",
                    backdropUrl: movie.backdrop_path.map { "https://image.tmdb.org/t/p/w780\($0)" } ?? "",
                    runtimeMinutes: movie.runtime,
                    genres: movie.genres?.map(\.name) ?? [],
                    tmdbScore: movie.vote_average,
                    rottenTomatoesScore: nil,
                    streamProviders: [],
                    streamingLink: nil
                )
                DispatchQueue.main.async {
                    self.cardCache[card.id] = card
                    self.typeCache[card.id] = card.type
                    completion(card)
                }
                return
            }

            if type == "tv", let tv = try? JSONDecoder().decode(TMDBTVDetailResponse.self, from: data) {
                let runtime = tv.episode_run_time?.first
                let card = TitleCard(
                    id: String(tv.id),
                    type: "tv",
                    title: tv.name ?? "Untitled",
                    year: tv.first_air_date?.split(separator: "-").first.map(String.init) ?? "",
                    overview: tv.overview ?? "",
                    posterUrl: tv.poster_path.map { "https://image.tmdb.org/t/p/w500\($0)" } ?? "",
                    backdropUrl: tv.backdrop_path.map { "https://image.tmdb.org/t/p/w780\($0)" } ?? "",
                    runtimeMinutes: runtime,
                    genres: tv.genres?.map(\.name) ?? [],
                    tmdbScore: tv.vote_average,
                    rottenTomatoesScore: nil,
                    streamProviders: [],
                    streamingLink: nil
                )
                DispatchQueue.main.async {
                    self.cardCache[card.id] = card
                    self.typeCache[card.id] = card.type
                    completion(card)
                }
                return
            }

            DispatchQueue.main.async { completion(nil) }
        }.resume()
    }

    // Loads core detail fields (runtime, genres, score) from TMDB.
    private func fetchTMDBDetail(type: String, tmdbId: Int, apiKey: String, completion: @escaping (TMDBDetailPayload?) -> Void) {
        guard let url = URL(string: "https://api.themoviedb.org/3/\(type)/\(tmdbId)?api_key=\(apiKey)") else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            if type == "movie", let movie = try? JSONDecoder().decode(TMDBMovieDetailResponse.self, from: data) {
                let payload = TMDBDetailPayload(
                    year: movie.release_date?.split(separator: "-").first.map(String.init) ?? "",
                    overview: movie.overview ?? "",
                    genres: movie.genres?.map(\.name) ?? [],
                    runtime: movie.runtime,
                    voteAverage: movie.vote_average
                )
                DispatchQueue.main.async { completion(payload) }
                return
            }

            if type == "tv", let tv = try? JSONDecoder().decode(TMDBTVDetailResponse.self, from: data) {
                let payload = TMDBDetailPayload(
                    year: tv.first_air_date?.split(separator: "-").first.map(String.init) ?? "",
                    overview: tv.overview ?? "",
                    genres: tv.genres?.map(\.name) ?? [],
                    runtime: tv.episode_run_time?.first,
                    voteAverage: tv.vote_average
                )
                DispatchQueue.main.async { completion(payload) }
                return
            }

            DispatchQueue.main.async { completion(nil) }
        }.resume()
    }

    // Loads streaming providers from TMDB's watch-provider endpoint.
    private func fetchWatchProviders(type: String, tmdbId: Int, apiKey: String, completion: @escaping (WatchAvailability) -> Void) {
        guard let url = URL(string: "https://api.themoviedb.org/3/\(type)/\(tmdbId)/watch/providers?api_key=\(apiKey)") else {
            completion(.empty)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let decoded = try? JSONDecoder().decode(TMDBWatchProvidersResponse.self, from: data) else {
                DispatchQueue.main.async { completion(.empty) }
                return
            }

            let regionData = decoded.results[Self.watchRegion] ?? decoded.results["US"]
            let subscription = Self.uniqueProviderNames(regionData?.flatrate ?? [])
            let free = Self.uniqueProviderNames((regionData?.free ?? []) + (regionData?.ads ?? []))
            let rent = Self.uniqueProviderNames(regionData?.rent ?? [])
            let buy = Self.uniqueProviderNames(regionData?.buy ?? [])
            let availability = WatchAvailability(
                subscription: subscription,
                free: free,
                rent: rent,
                buy: buy,
                link: regionData?.link
            )

            DispatchQueue.main.async {
                completion(availability)
            }
        }.resume()
    }

    // Removes duplicate provider names while preserving TMDB's display order.
    private static func uniqueProviderNames(_ providers: [TMDBWatchProvider]) -> [String] {
        var names: [String] = []
        providers.forEach { provider in
            if !names.contains(provider.provider_name) {
                names.append(provider.provider_name)
            }
        }
        return Array(names.prefix(8))
    }

    // Loads Rotten Tomatoes score through OMDb using TMDB external IDs.
    private func fetchRottenTomatoesScore(type: String, tmdbId: Int, apiKey: String, completion: @escaping (String?) -> Void) {
        guard let omdbKey = Self.omdbApiKey, !omdbKey.isEmpty, omdbKey != "REPLACE_ME" else {
            completion(nil)
            return
        }

        guard let externalURL = URL(string: "https://api.themoviedb.org/3/\(type)/\(tmdbId)/external_ids?api_key=\(apiKey)") else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: externalURL) { data, _, _ in
            guard let data = data,
                  let externalIds = try? JSONDecoder().decode(TMDBExternalIDsResponse.self, from: data),
                  let imdbId = externalIds.imdb_id,
                  !imdbId.isEmpty,
                  let omdbURL = URL(string: "https://www.omdbapi.com/?i=\(imdbId)&apikey=\(omdbKey)") else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            URLSession.shared.dataTask(with: omdbURL) { omdbData, _, _ in
                guard let omdbData = omdbData,
                      let omdb = try? JSONDecoder().decode(OMDbResponse.self, from: omdbData) else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                let score = omdb.Ratings.first(where: { $0.Source == "Rotten Tomatoes" })?.Value
                DispatchQueue.main.async { completion(score) }
            }.resume()
        }.resume()
    }

    // Provides local sample cards when API keys are missing.
    private static func sampleTitles() -> [TitleCard] {
        return [
            TitleCard(id: "tt0111161", type: "movie", title: "The Shawshank Redemption", year: "1994",
                      overview: "Two imprisoned men bond over a number of years, finding solace and eventual redemption.",
                      posterUrl: "", backdropUrl: "", runtimeMinutes: 142, genres: ["Drama"],
                      tmdbScore: 8.7, rottenTomatoesScore: "89%", streamProviders: [], streamingLink: nil),
            TitleCard(id: "tt0109830", type: "movie", title: "Forrest Gump", year: "1994",
                      overview: "The story of Forrest, a man with a low IQ who achieves great things.",
                      posterUrl: "", backdropUrl: "", runtimeMinutes: 142, genres: ["Drama", "Romance"],
                      tmdbScore: 8.5, rottenTomatoesScore: "71%", streamProviders: [], streamingLink: nil),
            TitleCard(id: "tt1375666", type: "movie", title: "Inception", year: "2010",
                      overview: "A thief who steals corporate secrets through dream-sharing technology.",
                      posterUrl: "", backdropUrl: "", runtimeMinutes: 148, genres: ["Sci-Fi", "Action"],
                      tmdbScore: 8.4, rottenTomatoesScore: "87%", streamProviders: [], streamingLink: nil)
        ]
    }
}

private struct TMDBTrendingResponse: Decodable {
    let results: [TMDBMedia]
}

private struct TMDBMedia: Decodable {
    let id: Int
    let media_type: String?
    let title: String?
    let name: String?
    let release_date: String?
    let first_air_date: String?
    let overview: String?
    let poster_path: String?
    let backdrop_path: String?
    let vote_average: Double?
}

private struct TMDBGenre: Decodable {
    let name: String
}

private struct TMDBMovieDetailResponse: Decodable {
    let id: Int
    let title: String?
    let release_date: String?
    let overview: String?
    let poster_path: String?
    let backdrop_path: String?
    let runtime: Int?
    let genres: [TMDBGenre]?
    let vote_average: Double?
}

private struct TMDBTVDetailResponse: Decodable {
    let id: Int
    let name: String?
    let first_air_date: String?
    let overview: String?
    let poster_path: String?
    let backdrop_path: String?
    let episode_run_time: [Int]?
    let genres: [TMDBGenre]?
    let vote_average: Double?
}

private struct TMDBWatchProvidersResponse: Decodable {
    let results: [String: TMDBWatchProviderRegion]
}

private struct TMDBWatchProviderRegion: Decodable {
    let link: String?
    let flatrate: [TMDBWatchProvider]?
    let free: [TMDBWatchProvider]?
    let ads: [TMDBWatchProvider]?
    let rent: [TMDBWatchProvider]?
    let buy: [TMDBWatchProvider]?
}

private struct TMDBWatchProvider: Decodable {
    let provider_name: String
}

private struct TMDBExternalIDsResponse: Decodable {
    let imdb_id: String?
}

private struct OMDbResponse: Decodable {
    let Ratings: [OMDbRating]
}

private struct OMDbRating: Decodable {
    let Source: String
    let Value: String
}

private struct TMDBDetailPayload {
    let year: String
    let overview: String
    let genres: [String]
    let runtime: Int?
    let voteAverage: Double?
}

private struct WatchAvailability {
    let subscription: [String]
    let free: [String]
    let rent: [String]
    let buy: [String]
    let link: String?

    static let empty = WatchAvailability(
        subscription: [],
        free: [],
        rent: [],
        buy: [],
        link: nil
    )

    var allProviders: [String] {
        var names: [String] = []
        (subscription + free + rent + buy).forEach { provider in
            if !names.contains(provider) {
                names.append(provider)
            }
        }
        return names
    }
}
