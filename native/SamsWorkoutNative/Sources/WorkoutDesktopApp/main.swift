import AppKit
import SwiftUI
import WorkoutCore
import WorkoutIntegrations
import WorkoutPersistence

final class WorkoutAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rootView = NativeWorkoutRootView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Sam's Workout App"
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unified
        window.contentView = NSHostingView(rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = WorkoutAppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate

let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)

let editMenuItem = NSMenuItem()
mainMenu.addItem(editMenuItem)
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editMenuItem.submenu = editMenu

let viewMenuItem = NSMenuItem()
mainMenu.addItem(viewMenuItem)
let viewMenu = NSMenu(title: "View")
let sidebarItem = NSMenuItem(
    title: "Toggle Sidebar",
    action: #selector(NSSplitViewController.toggleSidebar(_:)),
    keyEquivalent: "s"
)
sidebarItem.keyEquivalentModifierMask = [.control, .command]
viewMenu.addItem(sidebarItem)
viewMenuItem.submenu = viewMenu

app.mainMenu = mainMenu

let appMenu = NSMenu()
appMenu.addItem(
    withTitle: "About Sam's Workout App",
    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
    keyEquivalent: ""
)
appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(
    withTitle: "Quit Sam's Workout App",
    action: #selector(NSApplication.terminate(_:)),
    keyEquivalent: "q"
)
appMenuItem.submenu = appMenu

print("\(BuildInfo.trackName) initialized")
print("Start date: \(BuildInfo.trackStartDate)")
print(IntegrationsFacade().describeCurrentMode())

app.run()
