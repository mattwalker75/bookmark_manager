import XCTest
import CryptoKit
@testable import BookmarkManagerCore

/// Review 2 (Oct 30 2026) of Backup / PassphraseWrap / BackupStore: the reviewer's cases, asserting the fixed behaviour.
final class BackupReviewTests: XCTestCase {
    private func perms(_ u: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.posixPermissions] as? Int) ?? -1 }

    func testCraftedOrTinyRoundsAreRefusedNotCrashedOn() throws {
        let key = SymmetricKey(size: .bits256)
        XCTAssertThrowsBM(try PassphraseWrap.make(key: key, passphrase: "sierra nevada 1987", rounds: 1), containing: "out of range")
        XCTAssertThrowsBM(try PassphraseWrap.make(key: key, passphrase: "sierra nevada 1987", rounds: 99_999), containing: "out of range")
        var wrap = try PassphraseWrap.make(key: key, passphrase: "sierra nevada 1987", rounds: PassphraseWrap.fewestRounds)
        XCTAssertEqual(try wrap.unwrap(passphrase: "sierra nevada 1987"), key)
        for bad in [-1, 0, 1, 9_999, 5_000_000_000] {
            wrap.rounds = bad
            XCTAssertThrowsBM(try wrap.unwrap(passphrase: "sierra nevada 1987"), containing: "damaged")
        }
        wrap.rounds = PassphraseWrap.fewestRounds; wrap.salt = Data([1, 2, 3])
        XCTAssertThrowsBM(try wrap.unwrap(passphrase: "sierra nevada 1987"), containing: "damaged")
        // the same words with a differently composed accent are the same passphrase
        let w2 = try PassphraseWrap.make(key: key, passphrase: "caf\u{65}\u{301} au lait!", rounds: PassphraseWrap.fewestRounds)
        XCTAssertEqual(try w2.unwrap(passphrase: "caf\u{E9} au lait!"), key)
        // the wrap knows which key it holds
        XCTAssertTrue(w2.matches(key)); XCTAssertFalse(w2.matches(SymmetricKey(size: .bits256)))
        var old = w2; old.keyFingerprint = nil
        XCTAssertTrue(old.matches(SymmetricKey(size: .bits256)), "a wrap from before the fingerprint is given the benefit of the doubt")
    }

    func testKeepKeepsTheFileMode() throws {
        let s = Scratch()
        let bs = BackupStore(folder: s.url.appendingPathComponent("Backups"))
        let u = try bs.write(try Backup.make(Sample.library(), key: SymmetricKey(size: .bits256), passphrase: nil, reason: .manual), at: Date())
        XCTAssertEqual(perms(u), 0o600)
        try bs.setKept(u, kept: true, note: "x")
        XCTAssertEqual(perms(u), 0o600)
    }

    func testPruneOrderWithEqualCreatedAtAndClimbingSuffixes() throws {
        let s = Scratch()
        let bs = BackupStore(folder: s.url.appendingPathComponent("Backups"))
        let key = SymmetricKey(size: .bits256)
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        var urls: [URL] = []
        for _ in 0..<3 {
            urls.append(try bs.write(try Backup.make(Sample.library(), key: key, passphrase: nil, reason: .daily, now: t), at: t))
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertTrue(urls[2].lastPathComponent.hasSuffix(" (3).bmbackup"))
        XCTAssertEqual(bs.list().map(\.url), urls.reversed(), "same second: the one written last is listed first")
        XCTAssertEqual(bs.prune(keep: 2), [urls[0]], "the one written first goes")
    }
}
