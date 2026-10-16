import Foundation

/// Talks to the mdeditdiff command-line tool, so the app and agents share one history.
/// Everything is optional: if mdeditdiff isn't installed, the app works normally and
/// change tracking is simply off.
enum HistoryBridge {
    /// The name this person appears under in history, both as reader and author.
    static var personName: String { NSUserName() }

    private static let queue = DispatchQueue(label: "mdeditdiff.history")

    /// Runs `mdeditdiff <args>` through the user's login shell, so it finds Node and
    /// npm-installed tools the same way Terminal does.
    private static func run(_ args: [String], completion: @escaping (Int32, String) -> Void) {
        queue.async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-ilc", "mdeditdiff \"$@\"", "mdeditdiff"] + args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            do {
                try p.run()
            } catch {
                DispatchQueue.main.async { completion(-1, "") }
                return
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            let status = p.terminationStatus
            DispatchQueue.main.async { completion(status, text) }
        }
    }

    /// Runs a command with --json and returns the parsed object, or nil if the tool is missing or failed.
    private static func runJSON(_ args: [String], completion: @escaping ([String: Any]?) -> Void) {
        run(args + ["--json"]) { status, out in
            guard status == 0, let start = out.firstIndex(of: "{"), let end = out.lastIndex(of: "}") else {
                return completion(nil)
            }
            let obj = try? JSONSerialization.jsonObject(with: Data(out[start...end].utf8))
            completion(obj as? [String: Any])
        }
    }

    /// What changed for this person since they last read the file, with the text they last read.
    /// Records the current version in history if it's new. Never moves the person's bookmark.
    static func changes(of url: URL, completion: @escaping ([String: Any]?) -> Void) {
        runJSON(["changes", url.path, "--reader", personName, "--peek", "--with-base"], completion: completion)
    }

    /// Marks the current version as read by this person.
    static func markSeen(_ url: URL, completion: @escaping ([String: Any]?) -> Void = { _ in }) {
        runJSON(["seen", url.path, "--reader", personName], completion: completion)
    }

    /// Records a save with this person's name.
    static func checkpoint(_ url: URL, note: String, completion: @escaping (String?) -> Void) {
        runJSON(["checkpoint", url.path, "--author", personName, "--note", note]) { obj in
            completion((obj?["revision"] as? [String: Any])?["revision"] as? String)
        }
    }

    /// Revisions, newest first, and where each reader last looked.
    static func history(of url: URL, completion: @escaping ([String: Any]?) -> Void) {
        runJSON(["history", url.path, "--limit", "200"], completion: completion)
    }

    /// Full text of one revision.
    static func text(of url: URL, revision: String, completion: @escaping (String?) -> Void) {
        runJSON(["show", url.path, revision]) { obj in
            completion(obj?["text"] as? String)
        }
    }
}
