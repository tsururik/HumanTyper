import AppKit
import SwiftUI

@main
struct HumanTyperApp: App {
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var permission: AccessibilityPermission
    @StateObject private var controller: TypingController

    init() {
        AppDefaults.register()
        let permission = AccessibilityPermission()
        _permission = StateObject(wrappedValue: permission)
        _controller = StateObject(wrappedValue: TypingController(permission: permission))
    }

    var body: some Scene {
        Window("HumanTyper", id: Self.mainWindowID) {
            MainWindowView()
                .environmentObject(controller)
                .environmentObject(permission)
        }
        .defaultSize(width: 1000, height: 660)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(controller)
                .environmentObject(permission)
        } label: {
            MenuBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppTheme.current.apply()
        // Приложение живёт в строке меню (LSUIElement), поэтому окно нужно вывести вперёд явно.
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }
}
