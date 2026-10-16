import AppKit

/// Builds the menu bar in code (the app has no nib or storyboard).
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = helpMenu()
        main.addItem(submenu(help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0, target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.tag = tag
        if let target { i.target = target }
        return i
    }

    private static func appMenu() -> NSMenu {
        let m = NSMenu(title: "mdEditDiff")
        m.addItem(item("About mdEditDiff", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        m.addItem(.separator())
        let services = NSMenu(title: "Services")
        NSApp.servicesMenu = services
        let s = item("Services", nil)
        s.submenu = services
        m.addItem(s)
        m.addItem(.separator())
        m.addItem(item("Hide mdEditDiff", #selector(NSApplication.hide(_:)), "h"))
        m.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        m.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        m.addItem(.separator())
        m.addItem(item("Quit mdEditDiff", #selector(NSApplication.terminate(_:)), "q"))
        return m
    }

    private static func fileMenu() -> NSMenu {
        let m = NSMenu(title: "File")
        m.addItem(item("New", #selector(NSDocumentController.newDocument(_:)), "n"))
        m.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))
        m.addItem(.separator())
        m.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        m.addItem(item("Save", #selector(NSDocument.save(_:)), "s"))
        m.addItem(item("Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]))
        m.addItem(item("Revert to Saved", #selector(NSDocument.revertToSaved(_:))))
        return m
    }

    private static func editMenu() -> NSMenu {
        let m = NSMenu(title: "Edit")
        m.addItem(item("Undo", Selector(("undo:")), "z"))
        m.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        m.addItem(.separator())
        m.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        m.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        m.addItem(item("Paste", #selector(NSTextView.pasteAsPlainText(_:)), "v"))
        m.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        m.addItem(.separator())
        let find = NSMenu(title: "Find")
        let finder = #selector(NSResponder.performTextFinderAction(_:))
        find.addItem(item("Find…", finder, "f", tag: NSTextFinder.Action.showFindInterface.rawValue))
        find.addItem(item("Find and Replace…", finder, "f", [.command, .option], tag: NSTextFinder.Action.showReplaceInterface.rawValue))
        find.addItem(item("Find Next", finder, "g", tag: NSTextFinder.Action.nextMatch.rawValue))
        find.addItem(item("Find Previous", finder, "g", [.command, .shift], tag: NSTextFinder.Action.previousMatch.rawValue))
        find.addItem(item("Use Selection for Find", finder, "e", tag: NSTextFinder.Action.setSearchString.rawValue))
        let f = item("Find", nil)
        f.submenu = find
        m.addItem(f)
        m.addItem(.separator())
        m.addItem(item("Highlight", #selector(DocumentWindowController.highlightSelection(_:)), "h", [.command, .control]))
        m.addItem(item("Add Note", #selector(DocumentWindowController.addNoteToSelection(_:)), "n", [.command, .control]))
        m.addItem(item("Remove Highlight", #selector(DocumentWindowController.removeHighlight(_:))))
        return m
    }

    private static func viewMenu() -> NSMenu {
        let m = NSMenu(title: "View")
        m.addItem(item("Read", #selector(DocumentWindowController.showRead(_:)), "1"))
        m.addItem(item("Edit", #selector(DocumentWindowController.showEdit(_:)), "2"))
        m.addItem(item("Split", #selector(DocumentWindowController.showSplit(_:)), "3"))
        m.addItem(item("Next Mode", #selector(DocumentWindowController.cycleMode(_:)), "m", [.command, .shift]))
        m.addItem(.separator())
        m.addItem(item("Next Change", #selector(DocumentWindowController.nextChange(_:)), "]"))
        m.addItem(item("Previous Change", #selector(DocumentWindowController.previousChange(_:)), "["))
        m.addItem(item("Mark as Read", #selector(DocumentWindowController.markAsRead(_:)), "k", [.command, .shift]))
        m.addItem(item("Version History…", #selector(DocumentWindowController.showHistory(_:)), "h", [.command, .shift]))
        m.addItem(.separator())
        m.addItem(item("Pages", #selector(DocumentWindowController.showPages(_:))))
        m.addItem(item("Continuous Scroll", #selector(DocumentWindowController.showContinuous(_:))))
        m.addItem(item("Single Page", #selector(DocumentWindowController.singlePage(_:)), "1", [.command, .control]))
        m.addItem(item("Two Pages", #selector(DocumentWindowController.twoPages(_:)), "2", [.command, .control]))
        m.addItem(item("Page Thumbnails", #selector(DocumentWindowController.toggleThumbnails(_:)), "2", [.command, .option]))
        m.addItem(item("Notes and Highlights", #selector(DocumentWindowController.showNotesSidebar(_:)), "3", [.command, .option]))
        let sizes = NSMenu(title: "Page Size")
        sizes.addItem(item("US Letter", #selector(DocumentWindowController.useLetterPages(_:))))
        sizes.addItem(item("A4", #selector(DocumentWindowController.useA4Pages(_:))))
        let sizeItem = item("Page Size", nil)
        sizeItem.submenu = sizes
        m.addItem(sizeItem)
        let up = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        let down = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        m.addItem(item("Next Page", #selector(DocumentWindowController.nextPage(_:)), down, [.command, .option]))
        m.addItem(item("Previous Page", #selector(DocumentWindowController.previousPage(_:)), up, [.command, .option]))
        m.addItem(item("Go to Page…", #selector(DocumentWindowController.goToPage(_:)), "g", [.command, .option]))
        m.addItem(.separator())
        m.addItem(item("Bigger Text", #selector(DocumentWindowController.biggerText(_:)), "+"))
        m.addItem(item("Smaller Text", #selector(DocumentWindowController.smallerText(_:)), "-"))
        m.addItem(item("Actual Size", #selector(DocumentWindowController.actualSizeText(_:)), "0"))
        m.addItem(item("Zoom to Fit", #selector(DocumentWindowController.zoomToFit(_:)), "9"))
        m.addItem(item("Fit Width", #selector(DocumentWindowController.fitWidth(_:))))
        m.addItem(.separator())
        m.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return m
    }

    private static func windowMenu() -> NSMenu {
        let m = NSMenu(title: "Window")
        m.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        m.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        m.addItem(.separator())
        m.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return m
    }

    private static func helpMenu() -> NSMenu {
        let m = NSMenu(title: "Help")
        m.addItem(item("mdEditDiff on GitHub", #selector(AppDelegate.openProjectPage(_:))))
        m.addItem(item("Report an Issue", #selector(AppDelegate.reportIssue(_:))))
        return m
    }
}
