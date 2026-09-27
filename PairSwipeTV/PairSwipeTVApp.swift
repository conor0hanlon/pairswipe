import SwiftUI
import FirebaseCore

@main
struct PairSwipeTVApp: App {
    @StateObject private var session: TVShortlistSession

    init() {
        // PairSwipe uses the same Firebase project on iPhone and Apple TV.
        // A separate tvOS Firebase app can replace this plist later if needed.
        FirebaseApp.configure()
        _session = StateObject(wrappedValue: TVShortlistSession())
    }

    var body: some Scene {
        WindowGroup {
            TVShortlistView()
                .environmentObject(session)
        }
    }
}
