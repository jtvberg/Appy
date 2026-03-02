//
//  AppyApp.swift
//  Appy
//
//  Created by Joel Vandenberg on 3/1/26.
//

import SwiftUI
import AppKit

// MARK: - Environment key for popover dismiss

struct PopoverDismissKey: EnvironmentKey {
    nonisolated static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var dismissPopover: () -> Void {
        get { self[PopoverDismissKey.self] }
        set { self[PopoverDismissKey.self] = newValue }
    }
}

// MARK: - AppDelegate

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
        }

        // Build SwiftUI content with environment
        let contentView = ContentView()
            .environment(scanner)
            .environment(preferences)
            .environment(\.dismissPopover, { [weak self] in
                self?.closePopover()
            })

        // Configure popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: preferences.popoverWidth, height: preferences.popoverHeight)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            // Rescan apps each time the popover opens
            scanner.scan()
            popover.contentSize = NSSize(width: preferences.popoverWidth, height: preferences.popoverHeight)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            installMonitors()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        removeMonitors()
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
            // If the click is on the status item button, close and swallow
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

// MARK: - App entry point

@main
struct AppyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
