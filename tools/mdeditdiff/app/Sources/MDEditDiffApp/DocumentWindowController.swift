import AppKit
import WebKit

/// One document window: a plain-text Markdown editor, a rendered preview, and a
/// Read / Edit / Split switch.
@MainActor
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, WKNavigationDelegate, NSMenuItemValidation {
    enum Mode: Int, CaseIterable {
        case read = 0, edit = 1, split = 2
        var title: String { ["Read", "Edit", "Split"][rawValue] }
    }

    private static let defaultFontSize: CGFloat = 13
    private static let previewScale: CGFloat = 16.0 / 13.0

    private let splitView = NSSplitView()
    private let editorScroll: NSScrollView
    private let textView: NSTextView
    private let webView: WKWebView
    private let modeControl = NSSegmentedControl(labels: Mode.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let resources: PreviewResourceHandler
    private let linkHandler: LinkMessageHandler
    private var highlighter = MarkdownHighlighter(fontSize: DocumentWindowController.defaultFontSize)
    private var mode: Mode = .read
    private var previewReady = false
    private var renderWork: DispatchWorkItem?
    private var fontSize: CGFloat = DocumentWindowController.defaultFontSize
    private weak var markdownDocument: MarkdownDocument?

    var currentText: String { textView.string }

    init(document doc: MarkdownDocument) {
        markdownDocument = doc

        let scroll = NSTextView.scrollableTextView()
        editorScroll = scroll
        textView = scroll.documentView as! NSTextView

        let resourceHandler = PreviewResourceHandler()
        let links = LinkMessageHandler()
        resources = resourceHandler
        linkHandler = links
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(resourceHandler, forURLScheme: PreviewResourceHandler.scheme)
        config.userContentController.add(links, name: "link")
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
        configureModeControl(in: window)

        textView.string = doc.loadedText
        highlighter.apply(to: textView)
        setMode(doc.fileURL == nil ? .edit : .read)
        window.center()
        updateSubtitle()
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
        textView.textContainerInset = NSSize(width: 20, height: 20)
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

    private func configureModeControl(in window: NSWindow) {
        modeControl.target = self
        modeControl.action = #selector(modeControlChanged(_:))
        modeControl.segmentStyle = .automatic
        modeControl.setAccessibilityLabel("Document mode")
        for m in Mode.allCases {
            modeControl.setToolTip("\(m.title) (⌘\(m.rawValue + 1))", forSegment: m.rawValue)
        }
        modeControl.sizeToFit()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: modeControl.frame.width + 16, height: 28))
        modeControl.frame.origin = NSPoint(x: 0, y: (28 - modeControl.frame.height) / 2)
        container.addSubview(modeControl)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = container
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)
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
    }

    func updateSubtitle() {
        guard let doc = markdownDocument else { return }
        if doc.fileURL == nil {
            window?.subtitle = ""
        } else if let rev = doc.historyStatus {
            window?.subtitle = "History \(rev)"
        } else {
            window?.subtitle = "History off"
        }
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
        renderWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.renderNow() }
        renderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func renderNow() {
        renderWork?.cancel()
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
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only the bundled preview page may load. Links are handled in openLink.
        if let url = navigationAction.request.url, url.isFileURL, url.lastPathComponent == "preview.html", !previewReady {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
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

/// Forwards link clicks from the preview without retaining the window controller.
final class LinkMessageHandler: NSObject, WKScriptMessageHandler {
    var onLink: ((String) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "link", let href = message.body as? String else { return }
        onLink?(href)
    }
}
