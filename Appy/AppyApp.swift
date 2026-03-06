import SwiftUI
import AppKit

// MARK: Environment keys

struct PopoverDismissKey: EnvironmentKey {
    nonisolated static let defaultValue: () -> Void = {}
}

struct PopoverResizeKey: EnvironmentKey {
    nonisolated static let defaultValue: (CGSize) -> Void = { _ in }
}

extension EnvironmentValues {
    var dismissPopover: () -> Void {
        get { self[PopoverDismissKey.self] }
        set { self[PopoverDismissKey.self] = newValue }
    }
    var resizePopover: (CGSize) -> Void {
        get { self[PopoverResizeKey.self] }
        set { self[PopoverResizeKey.self] = newValue }
    }
}

// MARK: AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    let scanner = AppScannerService()
    let preferences = PreferencesManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Appy")
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Build SwiftUI content with environment
        let contentView = ContentView()
            .environment(scanner)
            .environment(preferences)
            .environment(\.dismissPopover, { [weak self] in
                self?.closePopover()
            })
            .environment(\.resizePopover, { [weak self] newSize in
                guard let self else { return }
                self.popover.contentSize = newSize
                self.preferences.popoverWidth = newSize.width
                self.preferences.popoverHeight = newSize.height
            })

        // Configure popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: preferences.popoverWidth, height: preferences.popoverHeight)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    @objc private func togglePopover() {
        // Right-click: show context menu with Quit
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quit Appy", action: #selector(quitApp), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }

        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            // Rescan apps each time the popover opens
            scanner.scan()
            popover.contentSize = NSSize(width: preferences.popoverWidth, height: preferences.popoverHeight)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            preferences.popoverVisible = true
            installMonitors()
        }
    }

    private func closePopover() {
        preferences.popoverVisible = false
        popover.performClose(nil)
        removeMonitors()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func installMonitors() {
        // Global monitor: clicks outside the app
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.closePopover()
        }
        // Local monitor: clicks on the status bar button while popover is open
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if let button = self.statusItem.button, event.window == button.window {
                self.closePopover()
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}

// MARK: App entry point

@main
struct AppyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
