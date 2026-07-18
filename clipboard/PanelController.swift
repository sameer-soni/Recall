//
//  PanelController.swift
//  Recall
//
//  A non-activating floating panel. It never activates our app, so the app
//  you were working in keeps focus and paste lands back where you left it.
//

import AppKit
import SwiftUI

final class ClipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()

    private var panel: ClipPanel?
    private var keyMonitor: Any?
    /// Guards the fade-out against a show() racing in mid-fade.
    private var presentGeneration = 0
    var monitor: ClipboardMonitor?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let panel = ensurePanel()
        presentGeneration += 1
        ClipboardStore.shared.resetForPresentation()
        positionPanel(panel)

        // Fade in while rising slightly.
        let target = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: target.x, y: target.y - 12))
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(target)
        }
        installKeyMonitor()
    }

    func hide(animated: Bool = true) {
        removeKeyMonitor()
        guard let panel, panel.isVisible else { return }
        // The paste path dismisses without animation so the panel has resigned
        // key before the synthesized ⌘V reaches the previous app.
        guard animated else {
            panel.orderOut(nil)
            return
        }
        let generation = presentGeneration
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard self?.presentGeneration == generation else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - Setup

    private func ensurePanel() -> ClipPanel {
        if let panel { return panel }
        let size = NSSize(width: UI.panelSize.width, height: UI.panelSize.height)
        let panel = ClipPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .utilityWindow

        let host = NSHostingView(rootView: ContentView(store: ClipboardStore.shared))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + (frame.height - size.height) * 0.58
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        let store = ClipboardStore.shared
        let cmd = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case 53: // esc
            hide()
            return true
        case 125: // down
            store.moveSelection(by: 1)
            return true
        case 126: // up
            store.moveSelection(by: -1)
            return true
        case 36, 76: // return / keypad enter
            if let item = store.selectedItem { pasteAndDismiss(item) }
            return true
        case 48: // tab
            store.cycleFilter(forward: !event.modifierFlags.contains(.shift))
            return true
        case 51 where cmd: // cmd+delete
            if let item = store.selectedItem { store.delete(item) }
            return true
        default:
            break
        }

        if cmd, let chars = event.charactersIgnoringModifiers {
            switch chars {
            case "p":
                if let item = store.selectedItem { store.togglePin(item) }
                return true
            case "c":
                if let item = store.selectedItem {
                    PasteService.copyToPasteboard(item, store: store, monitor: monitor)
                    hide()
                }
                return true
            case "1", "2", "3", "4", "5", "6", "7", "8", "9":
                let index = Int(chars)! - 1
                if index < store.visible.count {
                    pasteAndDismiss(store.visible[index])
                }
                return true
            default:
                break
            }
        }
        return false
    }

    func pasteAndDismiss(_ item: ClipItem) {
        let store = ClipboardStore.shared
        PasteService.copyToPasteboard(item, store: store, monitor: monitor)
        hide(animated: false)
        if store.autoPaste, PasteService.canAutoPaste {
            // Give the previous app a moment to regain focus before ⌘V.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                PasteService.sendPasteKeystroke()
            }
        }
    }
}
