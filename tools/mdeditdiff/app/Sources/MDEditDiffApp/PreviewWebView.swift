import AppKit
import WebKit

/// The rendered preview. Sends the Find menu (⌘F, ⌘G, ⇧⌘G, ⌘E) to the preview's own find bar,
/// so Find works in Read mode and in the rendered pane of Split mode.
final class PreviewWebView: WKWebView {
    /// Runs a find action by its NSTextFinder.Action tag.
    var onFind: (@MainActor (NSTextFinder.Action) -> Void)?

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
        if item.action == #selector(NSResponder.performTextFinderAction(_:)) {
            return Self.supportedFindActions.contains(NSTextFinder.Action(rawValue: item.tag) ?? .showReplaceInterface)
        }
        return super.validateUserInterfaceItem(item)
    }
}
