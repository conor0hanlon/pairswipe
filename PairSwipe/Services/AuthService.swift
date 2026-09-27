import Foundation

#if canImport(FirebaseAuth)
import FirebaseAuth

final class AuthService: NSObject {
    static let shared = AuthService()

    // Creates a private anonymous account and reports whether it succeeded.
    func signInAnonymously(completion: @escaping (Error?) -> Void) {
        Auth.auth().signInAnonymously { _, error in
            DispatchQueue.main.async {
                completion(error)
            }
        }
    }
}
#else

final class AuthService: NSObject {
    static let shared = AuthService()

    // Completes immediately when Firebase is unavailable in local stub builds.
    func signInAnonymously(completion: @escaping (Error?) -> Void) {
        // No-op stub when FirebaseAuth isn't available. Toggle a mock session if needed.
        print("[AuthService] FirebaseAuth not available; running in stub mode.")
        completion(nil)
    }
}

#endif
