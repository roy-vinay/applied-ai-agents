import CryptoKit
import Foundation

/// Personal highlights and notes, kept in the app's own storage and never next to the document:
/// `~/Library/Application Support/mdEditDiff/Annotations/<SHA-256 of the file's path>.json`.
/// Separate from revision history, so clearing history never deletes them. The format is
/// documented in docs/ANNOTATIONS.md.
enum AnnotationStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("mdEditDiff", isDirectory: true).appendingPathComponent("Annotations", isDirectory: true)
    }

    /// The same file reached through a symlink (for example /var vs /private/var) gets the same key.
    static func key(for url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func storeURL(for url: URL) -> URL {
        directory.appendingPathComponent(key(for: url) + ".json")
    }

    static func load(for url: URL) -> String? {
        try? String(contentsOf: storeURL(for: url), encoding: .utf8)
    }

    /// Writes atomically, so a crash never leaves half a file. Returns false if it couldn't.
    @discardableResult
    static func save(_ json: String, for url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: storeURL(for: url), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// The document was moved or renamed in Finder: its annotations go with it.
    static func move(from old: URL, to new: URL) {
        let from = storeURL(for: old), to = storeURL(for: new)
        guard from != to, FileManager.default.fileExists(atPath: from.path),
              !FileManager.default.fileExists(atPath: to.path) else { return }
        try? FileManager.default.moveItem(at: from, to: to)
    }

    /// How many highlights and notes a saved JSON snapshot holds.
    static func count(in json: String?) -> Int {
        guard let json, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [Any] else { return 0 }
        return items.count
    }
}
