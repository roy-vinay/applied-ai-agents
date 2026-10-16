import AppKit
import WebKit

/// One document window: a plain-text Markdown editor, a rendered preview, and a
/// Read / Edit / Split switch.
@MainActor
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, WKNavigationDelegate, NSMenuItemValidation, NSToolbarDelegate {
    enum Mode: Int, CaseIterable {
        case read = 0, edit = 1, split = 2
        var title: String { ["Read", "Edit", "Split"][rawValue] }
        /// SF Symbols for the toolbar switch.
        var symbol: String { ["book", "square.and.pencil", "rectangle.split.2x1"][rawValue] }
    }

    private static let defaultFontSize: CGFloat = 13
    private static let previewScale: CGFloat = 16.0 / 13.0

    private let splitView = NSSplitView()
    private let editorScroll: NSScrollView
    private let textView: NSTextView
    private let webView: WKWebView
    private let modeControl = NSSegmentedControl(labels: Mode.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let changesButton = NSButton(title: "Up to date", target: nil, action: nil)

    private enum ToolbarID {
        static let mode = NSToolbarItem.Identifier("mdeditdiff.mode")
        static let changes = NSToolbarItem.Identifier("mdeditdiff.changes")
        static let history = NSToolbarItem.Identifier("mdeditdiff.history")
    }
    private let resources: PreviewResourceHandler
    private let linkHandler: LinkMessageHandler
    private let reviewHandler: LinkMessageHandler
    private var highlighter = MarkdownHighlighter(fontSize: DocumentWindowController.defaultFontSize)
    private var mode: Mode = .read
    private var previewReady = false
    private var fontSize: CGFloat = DocumentWindowController.defaultFontSize
    private weak var markdownDocument: MarkdownDocument?

    /// What the preview compares against, if anything.
    private enum Review {
        case none
        /// Changes since this person last read the file.
        case unread(base: String, revisions: [[String: Any]])
        /// Changes since an earlier revision the person picked in History.
        case compare(base: String, title: String)
        /// The person's unsaved edits compared with a newer version on disk.
        case conflict(disk: String)
    }
    private var review: Review = .none
    private var unreadCount = 0
    private var lastHistory: [[String: Any]] = []
    private var conflictAlertShowing = false

    /// Mark changes as read when the window closes (default on).
    private static var markReadOnClose: Bool {
        UserDefaults.standard.object(forKey: "MarkReadOnClose") as? Bool ?? true
    }

    var currentText: String { textView.string }

    /// Mode for opening existing files: Read unless the "DefaultMode" setting says otherwise
    /// (for example `defaults write io.github.roy-vinay.mdeditdiff DefaultMode split`).
    static var defaultModeForFiles: Mode {
        switch UserDefaults.standard.string(forKey: "DefaultMode")?.lowercased() {
        case "edit": return .edit
        case "split": return .split
        default: return .read
        }
    }

    init(document doc: MarkdownDocument) {
        markdownDocument = doc

        let scroll = NSTextView.scrollableTextView()
        editorScroll = scroll
        textView = scroll.documentView as! NSTextView

        let resourceHandler = PreviewResourceHandler()
        let links = LinkMessageHandler()
        let reviews = LinkMessageHandler()
        resources = resourceHandler
        linkHandler = links
        reviewHandler = reviews
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(resourceHandler, forURLScheme: PreviewResourceHandler.scheme)
        config.userContentController.add(links, name: "link")
        config.userContentController.add(reviews, name: "review")
        webView = WKWebView(frame: .zero, configuration: config)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 480, height: 320)
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true

        configureEditor()
        configurePreview()
        configureLayout(in: window)
        configureToolbar(in: window)

        textView.string = doc.loadedText
        highlighter.apply(to: textView)
        setMode(doc.fileURL == nil ? .edit : Self.defaultModeForFiles)
        window.center()
        updateSubtitle()
        refreshReview()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Setup

    private func configureEditor() {
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 36, height: 28)
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor
        textView.font = highlighter.baseFont
        textView.typingAttributes = highlighter.baseAttributes
        textView.setAccessibilityLabel("Markdown source")
        editorScroll.hasVerticalScroller = true
        editorScroll.borderType = .noBorder
    }

    private func configurePreview() {
        webView.navigationDelegate = self
        webView.setAccessibilityLabel("Rendered preview")
        webView.allowsMagnification = false
        resources.baseDirectory = { [weak self] in
            self?.markdownDocument?.fileURL?.deletingLastPathComponent()
        }
        linkHandler.onLink = { [weak self] href in self?.openLink(href) }
        reviewHandler.onMessage = { [weak self] body in self?.handleReviewMessage(body) }
        if let dir = PreviewResourceHandler.previewDirectory {
            let page = dir.appendingPathComponent("preview.html")
            webView.loadFileURL(page, allowingReadAccessTo: dir)
        }
    }

    private func configureLayout(in window: NSWindow) {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(editorScroll)
        splitView.addArrangedSubview(webView)
        window.contentView = splitView
    }

    private func configureToolbar(in window: NSWindow) {
        modeControl.target = self
        modeControl.action = #selector(modeControlChanged(_:))
        modeControl.segmentStyle = .automatic
        modeControl.setAccessibilityLabel("Document mode")
        for m in Mode.allCases {
            if let image = NSImage(systemSymbolName: m.symbol, accessibilityDescription: m.title) {
                modeControl.setImage(image, forSegment: m.rawValue)
                modeControl.setImageScaling(.scaleProportionallyDown, forSegment: m.rawValue)
            }
            modeControl.setToolTip("\(m.title) (⌘\(m.rawValue + 1))", forSegment: m.rawValue)
        }
        modeControl.sizeToFit()

        changesButton.target = self
        changesButton.action = #selector(nextChange(_:))
        changesButton.bezelStyle = .texturedRounded
        changesButton.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
        changesButton.imagePosition = .imageLeading
        changesButton.isEnabled = false
        changesButton.toolTip = "Go to the next change (⌘])"

        let toolbar = NSToolbar(identifier: "mdeditdiff.document")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [ToolbarID.mode]
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, ToolbarID.mode, .flexibleSpace, ToolbarID.changes, ToolbarID.history]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
        case ToolbarID.mode:
            item.view = modeControl
            item.label = "Mode"
        case ToolbarID.changes:
            item.view = changesButton
            item.label = "Changes"
        case ToolbarID.history:
            item.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Version history")
            item.label = "History"
            item.toolTip = "Version history (⇧⌘H)"
            item.target = self
            item.action = #selector(showHistory(_:))
            item.isBordered = true
        default:
            return nil
        }
        return item
    }

    private func updateChangesButton() {
        var count = 0
        if case .unread = review { count = unreadCount }
        if count > 0 {
            changesButton.title = count == 1 ? "1 change" : "\(count) changes"
            changesButton.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 7, weight: .bold))
            changesButton.contentTintColor = .controlAccentColor
            changesButton.isEnabled = true
            changesButton.setAccessibilityLabel("\(count) unread changes. Go to the next change.")
        } else {
            changesButton.title = "Up to date"
            changesButton.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
            changesButton.contentTintColor = .secondaryLabelColor
            changesButton.isEnabled = false
            changesButton.setAccessibilityLabel("No unread changes")
        }
        changesButton.sizeToFit()
    }

    // MARK: - Document sync

    func reloadFromDocument() {
        guard let doc = markdownDocument else { return }
        let selection = textView.selectedRange()
        textView.string = doc.loadedText
        highlighter.apply(to: textView)
        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        textView.undoManager?.removeAllActions()
        renderNow()
        refreshReview()
    }

    func updateSubtitle() {
        guard let doc = markdownDocument else { return }
        var parts: [String] = []
        if case .unread = review, unreadCount > 0 {
            parts.append(unreadCount == 1 ? "1 unread change" : "\(unreadCount) unread changes")
        }
        if doc.fileURL == nil {
            // New, unsaved document.
        } else if let rev = doc.historyStatus {
            parts.append("History \(rev)")
        } else {
            parts.append("History off")
        }
        window?.subtitle = parts.joined(separator: " · ")
        updateChangesButton()
    }

    func textDidChange(_ notification: Notification) {
        highlighter.apply(to: textView)
        markdownDocument?.editorTextDidChange(textView.string)
        scheduleRender()
    }

    // MARK: - Modes

    private func setMode(_ newMode: Mode) {
        mode = newMode
        modeControl.selectedSegment = newMode.rawValue
        editorScroll.isHidden = newMode == .read
        webView.isHidden = newMode == .edit
        splitView.adjustSubviews()
        if newMode == .split {
            splitView.setPosition(splitView.bounds.width / 2, ofDividerAt: 0)
        }
        if newMode == .read {
            renderNow()
            window?.makeFirstResponder(webView)
        } else {
            window?.makeFirstResponder(textView)
            if newMode == .split { renderNow() }
        }
    }

    @objc private func modeControlChanged(_ sender: NSSegmentedControl) {
        setMode(Mode(rawValue: sender.selectedSegment) ?? .read)
    }

    @objc func showRead(_ sender: Any?) { setMode(.read) }
    @objc func showEdit(_ sender: Any?) { setMode(.edit) }
    @objc func showSplit(_ sender: Any?) { setMode(.split) }
    @objc func cycleMode(_ sender: Any?) { setMode(Mode(rawValue: (mode.rawValue + 1) % 3) ?? .read) }

    @objc func biggerText(_ sender: Any?) { setFontSize(fontSize + 1) }
    @objc func smallerText(_ sender: Any?) { setFontSize(fontSize - 1) }
    @objc func actualSizeText(_ sender: Any?) { setFontSize(Self.defaultFontSize) }

    private func setFontSize(_ size: CGFloat) {
        fontSize = min(max(size, 9), 32)
        highlighter = MarkdownHighlighter(fontSize: fontSize)
        textView.font = highlighter.baseFont
        textView.typingAttributes = highlighter.baseAttributes
        highlighter.apply(to: textView)
        applyPreviewFontSize()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(nextChange(_:)), #selector(previousChange(_:)):
            if case .none = review { return false }
            return true
        case #selector(markAsRead(_:)):
            if case .unread = review { return unreadCount > 0 }
            return false
        case #selector(showHistory(_:)):
            return markdownDocument?.fileURL != nil && markdownDocument?.historyStatus != nil
        case #selector(showRead(_:)): menuItem.state = mode == .read ? .on : .off
        case #selector(showEdit(_:)): menuItem.state = mode == .edit ? .on : .off
        case #selector(showSplit(_:)): menuItem.state = mode == .split ? .on : .off
        default: break
        }
        return true
    }

    // MARK: - Preview

    private func scheduleRender() {
        guard mode != .edit else { return }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(renderFromTimer), object: nil)
        perform(#selector(renderFromTimer), with: nil, afterDelay: 0.2)
    }

    @objc private func renderFromTimer() { renderNow() }

    private func renderNow() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(renderFromTimer), object: nil)
        guard previewReady else { return }
        guard let data = try? JSONEncoder().encode(textView.string), let literal = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.mdRender(\(literal))", completionHandler: nil)
    }

    private func applyPreviewFontSize() {
        guard previewReady else { return }
        let px = Int((fontSize * Self.previewScale).rounded())
        webView.evaluateJavaScript("window.mdSetFontSize(\(px))", completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        previewReady = true
        applyPreviewFontSize()
        renderNow()
        pushReviewToPreview()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only the bundled preview page may load. Links are handled in openLink.
        if let url = navigationAction.request.url, url.isFileURL, url.lastPathComponent == "preview.html", !previewReady {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    // MARK: - Review: changes since you last read, history, restore

    /// Asks the shared history what changed for this person, and shows it in the preview.
    func refreshReview() {
        guard let url = markdownDocument?.fileURL else { return }
        // Keep a comparison the person chose until they press Done.
        if case .compare = review { return }
        if case .conflict = review { return }
        HistoryBridge.changes(of: url) { [weak self] result in
            guard let self else { return }
            guard let result, let status = result["status"] as? String else {
                // mdeditdiff isn't installed or failed: no change tracking.
                self.markdownDocument?.historyStatus = nil
                self.setReview(.none)
                return
            }
            if let to = result["to"] as? [String: Any], let rev = to["revision"] as? String {
                self.markdownDocument?.historyStatus = rev
            }
            switch status {
            case "first_look":
                // First time this person opens the file: what they see now is their starting point.
                HistoryBridge.markSeen(url)
                self.setReview(.none)
            default:
                if let base = result["base_text"] as? String {
                    self.setReview(.unread(base: base, revisions: result["revisions"] as? [[String: Any]] ?? []))
                } else {
                    self.setReview(.none)
                }
            }
        }
    }

    private func setReview(_ newReview: Review) {
        review = newReview
        if case .unread = newReview {} else { unreadCount = 0 }
        pushReviewToPreview()
        updateSubtitle()
    }

    private func pushReviewToPreview() {
        guard previewReady else { return }
        var payload: [String: Any]?
        switch review {
        case .none: payload = nil
        case let .unread(base, revisions): payload = ["mode": "unread", "baseText": base, "revisions": revisions]
        case let .compare(base, title): payload = ["mode": "compare", "baseText": base, "title": title]
        case let .conflict(disk): payload = ["mode": "conflict", "baseText": disk]
        }
        guard let payload else {
            webView.evaluateJavaScript("window.mdSetReview(null)", completionHandler: nil)
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.mdSetReview(\(json))", completionHandler: nil)
    }

    private func handleReviewMessage(_ body: [String: Any]) {
        guard let action = body["action"] as? String else { return }
        switch action {
        case "count":
            if case .unread = review { unreadCount = body["n"] as? Int ?? 0 }
            updateSubtitle()
        case "markRead":
            markAsRead(nil)
        case "history":
            showHistory(nil)
        case "endCompare":
            setReview(.none)
            refreshReview()
        case "restoreBlock":
            guard let text = body["text"] as? String else { return }
            restoreBlock(text, beforeLine: body["beforeLine"] as? Int ?? 0, kind: body["kind"] as? String ?? "paragraph")
        case "compare":
            guard let rev = body["revision"] as? String, let url = markdownDocument?.fileURL else { return }
            HistoryBridge.text(of: url, revision: rev) { [weak self] text in
                guard let self, let text else { return NSSound.beep() }
                self.setReview(.compare(base: text, title: self.describe(revision: rev)))
                if self.mode == .edit { self.setMode(.read) }
            }
        case "restoreVersion":
            guard let rev = body["revision"] as? String, let url = markdownDocument?.fileURL else { return }
            HistoryBridge.text(of: url, revision: rev) { [weak self] text in
                guard let self, let text else { return NSSound.beep() }
                let all = NSRange(location: 0, length: (self.textView.string as NSString).length)
                self.replaceText(in: all, with: text, actionName: "Restore \(rev)")
                self.webView.evaluateJavaScript("window.mdHideHistory()", completionHandler: nil)
            }
        default:
            break
        }
    }

    private func describe(revision: String) -> String {
        guard let entry = lastHistory.first(where: { $0["revision"] as? String == revision }) else { return revision }
        if let author = entry["author"] as? String { return "\(revision) (\(author))" }
        return revision
    }

    /// Puts a removed block back where it was, as an undoable, unsaved edit.
    private func restoreBlock(_ block: String, beforeLine: Int, kind: String) {
        let ns = textView.string as NSString
        let tight = kind == "list-item" || kind == "table-row"
        var location = ns.length
        if beforeLine > 0 {
            var line = 1
            var index = 0
            while line < beforeLine && index < ns.length {
                let r = ns.lineRange(for: NSRange(location: index, length: 0))
                index = NSMaxRange(r)
                line += 1
            }
            location = min(index, ns.length)
        }
        let insertion: String
        if location >= ns.length {
            let needsNewline = ns.length > 0 && !textView.string.hasSuffix("\n")
            insertion = (needsNewline ? "\n" : "") + (tight || ns.length == 0 ? "" : "\n") + block + "\n"
        } else {
            insertion = block + (tight ? "\n" : "\n\n")
        }
        replaceText(in: NSRange(location: location, length: 0), with: insertion, actionName: "Restore Passage")
        textView.setSelectedRange(NSRange(location: location, length: (block as NSString).length))
    }

    /// Replaces text through the text view so it can be undone and marks the document edited.
    private func replaceText(in range: NSRange, with string: String, actionName: String) {
        guard textView.shouldChangeText(in: range, replacementString: string) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: string)
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
    }

    @objc func nextChange(_ sender: Any?) {
        if mode == .edit { setMode(.read) }
        webView.evaluateJavaScript("window.mdNav(1)", completionHandler: nil)
    }

    @objc func previousChange(_ sender: Any?) {
        if mode == .edit { setMode(.read) }
        webView.evaluateJavaScript("window.mdNav(-1)", completionHandler: nil)
    }

    @objc func markAsRead(_ sender: Any?) {
        guard let url = markdownDocument?.fileURL else { return }
        HistoryBridge.markSeen(url) { [weak self] _ in self?.refreshReview() }
    }

    @objc func showHistory(_ sender: Any?) {
        guard let url = markdownDocument?.fileURL else { return }
        if mode == .edit { setMode(.split) }
        HistoryBridge.history(of: url) { [weak self] result in
            guard let self, let result else { return NSSound.beep() }
            let revisions = result["revisions"] as? [[String: Any]] ?? []
            self.lastHistory = revisions
            let readerAt = (result["readers"] as? [String: Any])?[HistoryBridge.personName] as? String
            guard let data = try? JSONSerialization.data(withJSONObject: revisions), let json = String(data: data, encoding: .utf8) else { return }
            let at = readerAt.map { "\"\($0)\"" } ?? "null"
            self.webView.evaluateJavaScript("window.mdShowHistory(\(json), \(at))", completionHandler: nil)
        }
    }

    /// The file changed on disk and was reloaded (no unsaved edits): show what's new.
    func outsideChangeLoaded() {
        refreshReview()
    }

    /// The file changed on disk while the person has unsaved edits. Nothing is replaced
    /// until they choose.
    func showConflict(diskText: String, keepTheirs: @escaping () -> Void) {
        guard let window, !conflictAlertShowing else { return }
        conflictAlertShowing = true
        if let url = markdownDocument?.fileURL { HistoryBridge.changes(of: url) { _ in } } // record the outside version
        let alert = NSAlert()
        alert.messageText = "This file changed in another app"
        alert.informativeText = "Your unsaved edits are still here, and nothing has been replaced. Compare the two versions, keep your edits, or load the other version (your unsaved edits will be discarded)."
        alert.addButton(withTitle: "Compare")
        alert.addButton(withTitle: "Keep My Edits")
        alert.addButton(withTitle: "Load Other Version")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.conflictAlertShowing = false
            switch response {
            case .alertFirstButtonReturn:
                self.setReview(.conflict(disk: diskText))
                if self.mode == .edit { self.setMode(.split) }
            case .alertThirdButtonReturn:
                keepTheirs()
            default:
                break
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        if Self.markReadOnClose, case .unread = review, unreadCount > 0, let url = markdownDocument?.fileURL {
            HistoryBridge.markSeen(url)
        }
    }

    private func openLink(_ href: String) {
        if let url = URL(string: href), let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https", "mailto":
                NSWorkspace.shared.open(url)
            case "file":
                openLocal(url)
            default:
                NSSound.beep() // Other schemes are blocked.
            }
            return
        }
        guard let base = markdownDocument?.fileURL?.deletingLastPathComponent() else { return }
        let pathPart = String(href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let decoded = pathPart.removingPercentEncoding ?? pathPart
        guard !decoded.isEmpty else { return }
        openLocal(URL(fileURLWithPath: decoded, relativeTo: base).standardizedFileURL)
    }

    private func openLocal(_ url: URL) {
        let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdx"]
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        if markdownExtensions.contains(url.pathExtension.lowercased()) {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        } else {
            // Never launch other files from a document; show them in Finder instead.
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

/// Forwards messages from the preview (link clicks and review actions) without retaining
/// the window controller.
final class LinkMessageHandler: NSObject, WKScriptMessageHandler {
    var onLink: (@MainActor (String) -> Void)?
    var onMessage: (@MainActor ([String: Any]) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "link", let href = message.body as? String {
            MainActor.assumeIsolated { onLink?(href) }
        } else if message.name == "review", let body = message.body as? [String: Any] {
            MainActor.assumeIsolated { onMessage?(body) }
        }
    }
}
