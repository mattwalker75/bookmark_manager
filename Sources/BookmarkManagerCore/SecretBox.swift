// The secrets, encrypted on disk (Matt's decision, as in App Starter: not the Keychain — an ad-hoc-signed app
// would be asked for every item again after each rebuild). The texts are sealed with AES-GCM (256-bit) into
// secrets.enc; the key is a random file, secret.key, readable by you only. That keeps them out of library.json,
// out of exports (unless you tick the box) and out of backups of that file — but anyone who can read your files
// as you can read the key too: it protects against a file being copied or shown, not against someone using
// your account.
import Foundation
import CryptoKit

public final class SecretBox: @unchecked Sendable {
    public let folder: URL
    public var dataURL: URL { folder.appendingPathComponent("secrets.enc") }
    public var keyURL: URL { folder.appendingPathComponent("secret.key") }

    public init(folder: URL) { self.folder = folder }

    /// The key, made the first time it is needed.
    func key(create: Bool) throws -> SymmetricKey? {
        if let d = try? Data(contentsOf: keyURL), d.count == 32 { return SymmetricKey(data: d) }
        if FileManager.default.fileExists(atPath: keyURL.path) {
            throw BMError("The secrets key \(keyURL.path) is damaged, so the secrets can't be read.")
        }
        guard create else { return nil }
        let k = SymmetricKey(size: .bits256)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let d = k.withUnsafeBytes { Data($0) }
        guard FileManager.default.createFile(atPath: keyURL.path, contents: d, attributes: [.posixPermissions: 0o600]) else {
            throw BMError("The secrets key could not be written in \(folder.path).")
        }
        return k
    }

    /// bookmark id → secret text
    public func load() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: dataURL.path) else { return [:] }
        guard let k = try key(create: false) else {
            throw BMError("The secrets (\(dataURL.path)) can't be read: their key, secret.key, is missing.")
        }
        do {
            let box = try AES.GCM.SealedBox(combined: Data(contentsOf: dataURL))
            return try JSONDecoder().decode([String: String].self, from: AES.GCM.open(box, using: k))
        } catch {
            throw BMError("The secrets (\(dataURL.path)) can't be read with this key.")
        }
    }

    public func save(_ values: [String: String]) throws {
        if values.isEmpty, !FileManager.default.fileExists(atPath: dataURL.path) { return }
        guard let k = try key(create: true) else { return }
        let sealed = try AES.GCM.seal(JSONEncoder().encode(values), using: k)
        guard let combined = sealed.combined else { throw BMError("The secrets could not be encrypted.") }
        try combined.write(to: dataURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dataURL.path)
    }
}
