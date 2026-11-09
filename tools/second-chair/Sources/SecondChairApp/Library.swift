import AppKit
import PDFKit
import SecondChairCore

/// Reads the formats v1 indexes: Markdown and plain text, then PDF and Word converted to text on the Mac.
enum DocumentReader {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown"]
    static let textExtensions: Set<String> = ["txt", "text"]
    static let convertedExtensions: Set<String> = ["pdf", "docx", "doc", "rtf"]
    static var supported: Set<String> { markdownExtensions.union(textExtensions).union(convertedExtensions) }

    /// The text, and whether it's Markdown. Nil when there's no text layer (a scan, an image).
    static func read(_ url: URL) -> (String, Bool)? {
        let ext = url.pathExtension.lowercased()
        var text: String?
        if markdownExtensions.contains(ext) || textExtensions.contains(ext) {
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        } else if ext == "pdf" {
            text = PDFDocument(url: url)?.string
        } else if ext == "docx", let md = docxMarkdown(url) {
            return md.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 ? (md, true) : nil
        } else {
            let type: NSAttributedString.DocumentType = ext == "docx" ? .officeOpenXML : ext == "doc" ? .docFormat : .rtf
            text = (try? NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil))?.string
        }
        guard let text, text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 else { return nil }
        return (text, markdownExtensions.contains(ext))
    }

    /// A Word file as Markdown with its headings and lists intact (falls back to plain text if this fails).
    static func docxMarkdown(_ url: URL) -> String? {
        func part(_ name: String) -> Data? {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            p.arguments = ["-p", url.path, name]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return p.terminationStatus == 0 && !data.isEmpty ? data : nil
        }
        guard let document = part("word/document.xml") else { return nil }
        return DocxMarkdown.convert(document: document, styles: part("word/styles.xml"), numbering: part("word/numbering.xml"))
    }

    /// Every file under a folder, skipping hidden folders, the Obsidian settings and Second Chair's own notes.
    static func files(in folder: String) -> [URL] {
        let root = URL(fileURLWithPath: folder)
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [URL] = []
        for case let url as URL in e {
            if url.lastPathComponent == ".obsidian" { e.skipDescendants(); continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  !url.lastPathComponent.hasPrefix("_second-chair") else { continue }
            out.append(url)
        }
        return out.sorted { $0.path < $1.path }
    }

    /// Builds an index from folders. Unreadable files are listed as skipped, never silently included.
    static func build(folders: [String], embedder: Embedder?) async -> CorpusIndex {
        var chunks: [Chunk] = []
        var skipped: [String] = []
        for folder in folders {
            for url in files(in: folder) {
                guard supported.contains(url.pathExtension.lowercased()) else {
                    if ["png", "jpg", "jpeg", "heic", "gif", "tiff"].contains(url.pathExtension.lowercased()) {
                        skipped.append(url.path)
                    }
                    continue
                }
                guard let doc = read(url) else { skipped.append(url.path); continue }
                chunks += Chunker.chunk(text: doc.0, file: url.path, folder: folder, markdown: doc.1)
            }
        }
        var index = CorpusIndex(chunks: chunks, builtAt: Date(), skipped: skipped)
        if let embedder {
            do { try await index.embed(with: embedder) } catch {
                NSLog("Second Chair: embeddings unavailable (\(error)); index is keyword-only")
            }
        }
        return index
    }
}

/// The folders you've added, the pinned prep pack, and the index built from them.
final class Library {
    static let shared = Library()

    private(set) var index = CorpusIndex(chunks: [], builtAt: .distantPast)
    private(set) var isBuilding = false
    private(set) var isStale = true
    private var builtFingerprint = ""
    var onChange: (() -> Void)?

    var folders: [String] {
        get { UserDefaults.standard.stringArray(forKey: "folders") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "folders"); markStale() }
    }

    var primaryFolder: String? {
        get { UserDefaults.standard.string(forKey: "primaryFolder") }
        set { UserDefaults.standard.set(newValue, forKey: "primaryFolder"); onChange?() }
    }

    static var supportDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Second Chair", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var indexURL: URL { Self.supportDirectory.appendingPathComponent("index.json") }

    func load() {
        if let data = try? Data(contentsOf: indexURL), let saved = try? JSONDecoder().decode(CorpusIndex.self, from: data) {
            index = saved
            builtFingerprint = UserDefaults.standard.string(forKey: "indexFingerprint") ?? ""
        }
        checkFreshness()
    }

    /// A cheap signature of the folders: file count and newest modification time.
    func fingerprint() -> String {
        var count = 0
        var newest = Date.distantPast
        for folder in folders {
            for url in DocumentReader.files(in: folder) {
                count += 1
                if let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, d > newest { newest = d }
            }
        }
        // The reader version is part of it, so a better reader rebuilds existing indexes once.
        return "reader3|\(folders.joined(separator: "|"))#\(count)#\(newest.timeIntervalSince1970)"
    }

    func checkFreshness() {
        let fp = fingerprint()
        let stale = fp != builtFingerprint || index.chunks.isEmpty && !folders.isEmpty
        if stale != isStale { isStale = stale; onChange?() }
    }

    private func markStale() {
        isStale = true
        onChange?()
    }

    func rebuild(embedder: Embedder?, completion: (() -> Void)? = nil) {
        guard !isBuilding else { return }
        isBuilding = true
        onChange?()
        let folders = self.folders
        Task.detached(priority: .userInitiated) {
            let fp = self.fingerprint()
            let built = await DocumentReader.build(folders: folders, embedder: embedder)
            if let data = try? JSONEncoder().encode(built) { try? data.write(to: self.indexURL, options: .atomic) }
            await MainActor.run {
                self.index = built
                self.builtFingerprint = fp
                UserDefaults.standard.set(fp, forKey: "indexFingerprint")
                self.isBuilding = false
                self.isStale = false
                self.onChange?()
                completion?()
            }
        }
    }

    /// "Index fresh, 214 passages, built 9:41" or "Index stale (built Tue 18:02)".
    var statusLine: String {
        if isBuilding { return "Indexing your folders…" }
        if folders.isEmpty { return "No folders added yet" }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(index.builtAt) ? "HH:mm" : "EEE HH:mm"
        let built = index.builtAt == .distantPast ? "never built" : "built \(f.string(from: index.builtAt))"
        let kind = index.embedderName == nil ? "keyword only" : "keyword + embeddings"
        return isStale ? "Index STALE (\(built))" : "Index fresh, \(index.chunks.count) passages, \(kind), \(built)"
    }
}
