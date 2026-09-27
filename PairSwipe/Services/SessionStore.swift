import Foundation

#if canImport(FirebaseAuth)
import FirebaseAuth

final class SessionStore: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var userId: String? = nil

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.userId = user?.uid
            self?.isSignedIn = user != nil
        }
    }

    deinit {
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}
#else

final class SessionStore: ObservableObject {
    @Published var isSignedIn: Bool = true // Default to signed in for stub mode
    @Published var userId: String? = "local-user"
}

#endif
