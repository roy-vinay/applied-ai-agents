import Foundation

/// Talks to the mdeditdiff command-line tool, so saves made here show up in the same
/// history agents use. Everything is optional: if mdeditdiff isn't installed, the app
/// works normally and the window says history is off.
enum HistoryBridge {
    /// The name this person appears under in history.
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

    /// Extracts the JSON object from the output (shell startup files may print other lines).
    private static func json(_ output: String) -> [String: Any]? {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}") else { return nil }
        let data = Data(output[start...end].utf8)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// The latest revision label, for example "r5 of 5", recording the current version if it's new.
    static func latestRevision(of url: URL, completion: @escaping (String?) -> Void) {
        run(["history", url.path, "--json", "--limit", "1"]) { status, out in
            guard status == 0, let obj = json(out),
                  let revs = obj["revisions"] as? [[String: Any]], let rev = revs.first?["revision"] as? String
            else { return completion(nil) }
            completion(rev)
        }
    }

    /// Records a save with this person's name.
    static func checkpoint(_ url: URL, note: String, completion: @escaping (String?) -> Void) {
        run(["checkpoint", url.path, "--author", personName, "--note", note, "--json"]) { status, out in
            guard status == 0, let obj = json(out),
                  let rev = obj["revision"] as? [String: Any], let label = rev["revision"] as? String
            else { return completion(nil) }
            completion(label)
        }
    }
}
