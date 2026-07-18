//
//  RecallApp.swift
//  Recall
//

import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
struct ClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let monitor = ClipboardMonitor()
    private let hotkey = HotkeyManager()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        _ = ClipboardStore.shared

        PanelController.shared.monitor = monitor
        monitor.start()

        // Stop polling entirely while paused.
        ClipboardStore.shared.$isPaused
            .removeDuplicates()
            .sink { [weak self] paused in
                if paused { self?.monitor.stop() } else { self?.monitor.start() }
            }
            .store(in: &cancellables)

        hotkey.onHotkey = { PanelController.shared.toggle() }
        hotkey.register()

        setUpStatusItem()
        enableLaunchAtLoginOnFirstRun()
    }

    /// Register as a login item on first launch only; respect the user's
    /// choice afterwards.
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "didConfigureLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("Recall: initial launch-at-login registration failed: \(error)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        hotkey.unregister()
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                   accessibilityDescription: "Recall")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            PanelController.shared.toggle()
            return
        }
        if event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            PanelController.shared.toggle()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        let store = ClipboardStore.shared

        let open = NSMenuItem(title: "Open Recall", action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        let pause = NSMenuItem(title: store.isPaused ? "Resume Monitoring" : "Pause Monitoring",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Recall", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // keep left-click toggling the panel
    }

    @objc private func openPanel() {
        PanelController.shared.show()
    }

    @objc private func togglePause() {
        ClipboardStore.shared.isPaused.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Recall: launch-at-login toggle failed: \(error)")
        }
    }
}
