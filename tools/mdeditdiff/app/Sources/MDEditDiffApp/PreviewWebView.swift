import AppKit
import WebKit

/// The rendered preview. Sends the Find menu (⌘F, ⌘G, ⇧⌘G, ⌘E) to the preview's own find bar,
/// so Find works in Read mode and in the rendered pane of Split mode.
final class PreviewWebView: WKWebView {
    /// Runs a find action by its NSTextFinder.Action tag.
    var onFind: (@MainActor (NSTextFinder.Action) -> Void)?
    /// "highlight" or "note", from the right-click menu.
    var onAnnotate: (@MainActor (String) -> Void)?

    /// Puts Highlight and Add Note at the top of the right-click menu, like Preview.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        let highlight = NSMenuItem(title: "Highlight", action: #selector(contextHighlight(_:)), keyEquivalent: "")
        highlight.target = self
        let note = NSMenuItem(title: "Add Note", action: #selector(contextNote(_:)), keyEquivalent: "")
        note.target = self
        menu.insertItem(.separator(), at: 0)
        menu.insertItem(note, at: 0)
        menu.insertItem(highlight, at: 0)
    }

    @objc private func contextHighlight(_ sender: Any?) { MainActor.assumeIsolated { onAnnotate?("highlight") } }
    @objc private func contextNote(_ sender: Any?) { MainActor.assumeIsolated { onAnnotate?("note") } }

    static let supportedFindActions: Set<NSTextFinder.Action> = [
        .showFindInterface, .nextMatch, .previousMatch, .setSearchString, .hideFindInterface,
    ]

    static func findAction(from sender: Any?) -> NSTextFinder.Action {
        let tag = (sender as? NSValidatedUserInterfaceItem)?.tag ?? NSTextFinder.Action.showFindInterface.rawValue
        return NSTextFinder.Action(rawValue: tag) ?? .showFindInterface
    }

    override func performTextFinderAction(_ sender: Any?) {
        let action = Self.findAction(from: sender)
        guard Self.supportedFindActions.contains(action) else { return NSSound.beep() }
        MainActor.assumeIsolated { onFind?(action) }
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(contextHighlight(_:)) || item.action == #selector(contextNote(_:)) { return true }
        if item.action == #selector(NSResponder.performTextFinderAction(_:)) {
            return Self.supportedFindActions.contains(NSTextFinder.Action(rawValue: item.tag) ?? .showReplaceInterface)
        }
        return super.validateUserInterfaceItem(item)
    }
}
