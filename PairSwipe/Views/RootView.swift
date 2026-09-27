import SwiftUI

struct RootView: View {
    @StateObject private var session = SessionStore()

    var body: some View {
        content
    }

    private var content: some View {
        Group {
            if session.isSignedIn {
                PairGateView()
                    .environmentObject(session)
            } else {
                SignInView()
                    .environmentObject(session)
            }
        }
    }
}
