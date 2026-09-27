import Foundation

final class PairSession: ObservableObject {
    @Published var activePair: Pair? = nil

    // Sets the currently selected pair in one place.
    func openPair(_ pair: Pair) {
        activePair = pair
    }

    // Refreshes the active pair after live updates come in from Firestore.
    func updatePair(_ pair: Pair) {
        guard activePair?.id == pair.id else { return }
        activePair = pair
    }

    // Clears the current pair so the user returns to landing.
    func closePair() {
        activePair = nil
    }
}
