import AppKit
import MDEditDiffCore

/// One open Markdown file. Saving is explicit (no autosave over the original), and a save
/// with no real edits writes back the exact original bytes.
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    /// The file as last read or saved.
    private(set) var source: SourceText = .empty
    /// Text for a window that hasn't been created yet.
    private(set) var loadedText: String = ""
    /// History revision label from mdeditdiff, for example "r5", or nil if unavailable.
    var historyStatus: String? {
        didSet { MainActor.assumeIsolated { mainController?.updateSubtitle() } }
    }

    private var pendingSaveData: Data?

    override class var autosavesInPlace: Bool { false }

    var mainController: DocumentWindowController? {
        windowControllers.first as? DocumentWindowController
    }

    /// The text currently in the editor. NSDocument calls reading and writing on the main thread.
    var currentText: String {
        MainActor.assumeIsolated { mainController?.currentText } ?? loadedText
    }

    override func makeWindowControllers() {
        MainActor.assumeIsolated { addWindowController(DocumentWindowController(document: self)) }
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let s = try SourceText(data: data)
        source = s
        loadedText = s.text
        if mainController != nil {
            // Reverted or reloaded while open.
            MainActor.assumeIsolated { mainController?.reloadFromDocument() }
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        let out = source.data(for: currentText)
        pendingSaveData = out
        return out
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if error == nil, let self, let written = self.pendingSaveData, saveOperation != .autosaveElsewhereOperation {
                if let s = try? SourceText(data: written) {
                    self.source = s
                    self.loadedText = s.text
                }
                self.recordSave(at: url)
            }
            self?.pendingSaveData = nil
            completionHandler(error)
        }
    }

    /// Called by the editor on every change, so the edited dot clears when edits are undone.
    func editorTextDidChange(_ text: String) {
        if source.isEdited(text) {
            updateChangeCount(.changeDone)
        } else {
            updateChangeCount(.changeCleared)
        }
    }

    // MARK: - Shared history (mdeditdiff)

    private func recordSave(at url: URL) {
        HistoryBridge.checkpoint(url, note: "Saved in mdEditDiff") { [weak self] label in
            guard let self else { return }
            self.historyStatus = label
            // Your own save is not an unread change for you.
            MainActor.assumeIsolated { self.mainController?.refreshReview() }
        }
    }

    // MARK: - Changes made by other apps (for example an agent)

    override func presentedItemDidChange() {
        super.presentedItemDidChange()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.handleOutsideChange() }
        }
    }

    @MainActor
    private func handleOutsideChange() {
        guard let url = fileURL, let type = fileType, let data = try? Data(contentsOf: url) else { return }
        if data == source.originalData { return } // No real change (or our own save).
        if !isDocumentEdited {
            // Nothing to lose: show the new version and what changed.
            try? revert(toContentsOf: url, ofType: type)
            mainController?.outsideChangeLoaded()
            return
        }
        guard let disk = try? SourceText(data: data) else { return }
        mainController?.showConflict(diskText: disk.text) { [weak self] in
            guard let self else { return }
            try? self.revert(toContentsOf: url, ofType: type)
        }
    }
}
