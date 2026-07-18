//
//  PasteService.swift
//  Recall
//

import AppKit

enum PasteService {
    static func copyToPasteboard(_ item: ClipItem, store: ClipboardStore, monitor: ClipboardMonitor?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .image:
            let url = store.database.imageURL(hash: item.hash)
            if let data = try? Data(contentsOf: url) {
                pb.setData(data, forType: .png)
            }
        case .file:
            let urls = item.content.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            pb.writeObjects(urls as [NSURL])
        default:
            pb.setString(item.content, forType: .string)
        }
        monitor?.expectedChangeCount = pb.changeCount
    }

    static var canAutoPaste: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        // The prompt rarely surfaces for a menu-bar app, so open the pane too.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // Must run after the panel is dismissed so the original app is frontmost.
    static func sendPasteKeystroke() {
        guard canAutoPaste else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyVDown?.flags = .maskCommand
        keyVUp?.flags = .maskCommand
        keyVDown?.post(tap: .cghidEventTap)
        keyVUp?.post(tap: .cghidEventTap)
    }
}
