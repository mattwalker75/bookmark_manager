// Touch ID (or the Mac's password) before a secret is shown, when Settings → General asks for it (Matt, Oct 29
// 2026). One passed check covers the next minute, so several secrets in a row ask once. Cancelling says nothing;
// a Mac with nothing to check against says so, so the option can be turned off again.
import Foundation
import LocalAuthentication

@MainActor
enum SecretGate {
    /// how long one passed check lasts
    static let grace: TimeInterval = 60
    private(set) static var lastPassed: Date?

    static var recentlyPassed: Bool { lastPassed.map { Date().timeIntervalSince($0) < grace } ?? false }

    /// Whether this Mac can check at all (Touch ID, or a login password).
    static var available: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    /// Asks; `done(passed, problem)` on the main thread — `problem` is a sentence when it failed for a reason worth telling (not a cancel).
    static func check(reason: String, done: @escaping @MainActor (Bool, String?) -> Void) {
        let context = LAContext()
        var why: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &why) else {
            done(false, "This Mac can't check who you are right now: \(why?.localizedDescription ?? "there is no Touch ID and no login password to check against"). Turn off “Ask for Touch ID before showing a secret” in Settings → General to show secrets without it.")
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, error in
            Task { @MainActor in
                if ok { lastPassed = Date(); done(true, nil); return }
                if let e = error as? LAError, [.userCancel, .appCancel, .systemCancel].contains(e.code) { done(false, nil); return }
                done(false, error?.localizedDescription ?? "Touch ID didn't recognize you.")
            }
        }
    }

    /// For the tests and for Settings being turned off: forget the last check.
    static func forget() { lastPassed = nil }
    /// For the tests: pretend a check passed `ago` seconds ago.
    static func pretendPassed(ago: TimeInterval) { lastPassed = Date().addingTimeInterval(-ago) }
}
