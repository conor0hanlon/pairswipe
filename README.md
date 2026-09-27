# PairSwipe (iOS, tvOS + Firebase)

This repo contains a lightweight SwiftUI app skeleton and Firebase backend scaffolding for the pair-based swipe/match product spec.

## Draft v2 features
- Interactive swipe cards with a **More Info** sheet.
- Title detail sheet with:
  - TMDB score
  - Rotten Tomatoes score (when available via OMDb)
  - Runtime + genres
  - "Where to Stream" providers (TMDB watch providers)
- Landing page with persistent saved pairs and shortlist previews.
- Upgraded visual style and in-app logo branding.
- Apple TV shortlist viewer with room-code pairing and live updates.

## Structure
- `PairSwipe.xcodeproj`: Xcode project (SwiftUI + Firebase SPM)
- `PairSwipe`: iOS app source + assets + Info.plist
- `PairSwipeTV`: tvOS shortlist app source + Info.plist
- `firebase/functions`: Cloud Functions (match creation)
- `firebase/firestore.rules`: Firestore rules draft

## Next steps
1. Open `/Users/conorohanlon/Documents/New project/PairSwipe.xcodeproj` in Xcode.
2. Copy `PairSwipe/GoogleService-Info.example.plist` to `PairSwipe/GoogleService-Info.plist`, then replace its placeholders with your Firebase Apple-app config.
3. Enable Anonymous auth in Firebase (Authentication > Sign-in method > Anonymous).
4. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and add your TMDB API key.
5. Add your OMDb key to that same local secrets file for Rotten Tomatoes scores.
6. Deploy `firebase/functions` and `firebase/firestore.rules`.
7. Select the `PairSwipeTV` scheme to run the Apple TV app in the tvOS simulator.

## Apple TV setup

1. Open the PairSwipe iPhone app and create or open a room.
2. Open PairSwipe on Apple TV and enter the six-character room code.
3. The television is added as a read-only viewer. Shared matches appear automatically.

The tvOS target currently shares the iPhone Firebase configuration and bundle identifier.
Before App Store submission, add the required tvOS app-icon artwork in Xcode.

Notes:
- The app is currently set to Anonymous sign-in so it works without a paid Apple Developer account.
- The swipe feed pulls from TMDB Trending (movie + TV). If `TMDBApiKey` is missing, it falls back to a sample list.
- TMDB requires attribution in your app UI (logo + text). The text is now shown as a footer; add a `tmdb-logo` asset if you want to show the logo elsewhere.
