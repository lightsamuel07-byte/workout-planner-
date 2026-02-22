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
