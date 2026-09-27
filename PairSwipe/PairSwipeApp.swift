import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif

@main
struct PairSwipeApp: App {
    init() {
        #if canImport(FirebaseCore)
        // Add GoogleService-Info.plist to the Xcode project and ensure it's in the app target.
        FirebaseApp.configure()
        #else
        // FirebaseCore not available in this build; skipping configuration.
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
