//
//  ClipboardStore.swift
//  Recall
//

import AppKit
import Combine
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

enum FilterTab: Hashable, CaseIterable {
    case all, pinned, text, links, code, images

    var label: String {
        switch self {
        case .all: return "All"
        case .pinned: return "Pinned"
        case .text: return "Text"
        case .links: return "Links"
        case .code: return "Code"
        case .images: return "Images"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .pinned: return "pin"
        case .text: return "text.alignleft"
        case .links: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .images: return "photo"
        }
    }
}

struct ImageMeta: Sendable {
    let width: Int
    let height: Int
    let byteSize: Int
}

final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    /// Full history, newest first. Deliberately not @Published: copies land
    /// while the panel is hidden, and we don't want to re-render nothing.
    private(set) var items: [ClipItem] = []

    @Published var query: String = "" {
        didSet { rebuildVisible(resetSelection: true) }
    }
    @Published var filter: FilterTab = .all {
        didSet { rebuildVisible(resetSelection: true) }
    }
    @Published private(set) var visible: [ClipItem] = []
    @Published var selectedID: Int64?
    @Published var isPaused: Bool = false
    /// Bumped on every panel presentation so the search field re-focuses.
    @Published var focusToken: Int = 0

    @AppStorage("autoPaste") var autoPaste: Bool = true
    @AppStorage("historyLimit") var historyLimit: Int = 500

    let database = Database()
    private let thumbnailCache = NSCache<NSString, NSImage>()

    private init() {
        thumbnailCache.totalCostLimit = 48 * 1024 * 1024
        items = database.loadAll()
    }

    // MARK: - Ingest from pasteboard

    func ingest(text: String, appName: String?, appBundleID: String?) {
        let hash = Self.sha(of: Data(text.utf8))
        if bumpExisting(hash: hash, appName: appName, appBundleID: appBundleID) { return }

        let kind = Classifier.classify(text)
        guard let id = database.insert(kind: kind, content: text, hash: hash, date: Date(),
                                       appName: appName, appBundleID: appBundleID,
                                       byteSize: text.utf8.count, width: 0, height: 0) else { return }
        let item = ClipItem(id: id, kind: kind, content: text, hash: hash, copyCount: 1,
                            isPinned: false, firstCopied: Date(), lastCopied: Date(),
                            appName: appName, appBundleID: appBundleID,
                            byteSize: text.utf8.count, pixelWidth: 0, pixelHeight: 0)
        items.insert(item, at: 0)
        pruneIfNeeded()
        rebuildVisible(resetSelection: true)
    }

    func ingest(fileURLs: [URL], appName: String?, appBundleID: String?) {
        let joined = fileURLs.map(\.path).joined(separator: "\n")
        let hash = Self.sha(of: Data(joined.utf8))
        if bumpExisting(hash: hash, appName: appName, appBundleID: appBundleID) { return }
        guard let id = database.insert(kind: .file, content: joined, hash: hash, date: Date(),
                                       appName: appName, appBundleID: appBundleID,
                                       byteSize: 0, width: 0, height: 0) else { return }
        let item = ClipItem(id: id, kind: .file, content: joined, hash: hash, copyCount: 1,
                            isPinned: false, firstCopied: Date(), lastCopied: Date(),
                            appName: appName, appBundleID: appBundleID,
                            byteSize: 0, pixelWidth: 0, pixelHeight: 0)
        items.insert(item, at: 0)
        pruneIfNeeded()
        rebuildVisible(resetSelection: true)
    }

    /// Decoding, PNG encoding, thumbnailing and disk writes happen off the
    /// main thread; only the bookkeeping hops back.
    func ingest(imageData: Data, appName: String?, appBundleID: String?) {
        let imagesDir = database.imagesDir
        Task.detached(priority: .utility) {
            let hash = sha256Hex(imageData)

            let isDuplicate = await MainActor.run {
                ClipboardStore.shared.bumpExisting(hash: hash, appName: appName, appBundleID: appBundleID)
            }
            if isDuplicate { return }

            let fileURL = imagesDir.appendingPathComponent("\(hash).png")
            let thumbURL = imagesDir.appendingPathComponent("\(hash)_thumb.png")
            guard let meta = processImage(imageData, fileURL: fileURL, thumbURL: thumbURL) else { return }

            await MainActor.run {
                ClipboardStore.shared.insertImageRecord(hash: hash, meta: meta,
                                                        appName: appName, appBundleID: appBundleID)
            }
        }
    }

    private func insertImageRecord(hash: String, meta: ImageMeta, appName: String?, appBundleID: String?) {
        guard let id = database.insert(kind: .image, content: "\(hash).png", hash: hash, date: Date(),
                                       appName: appName, appBundleID: appBundleID,
                                       byteSize: meta.byteSize, width: meta.width, height: meta.height) else { return }
        let item = ClipItem(id: id, kind: .image, content: "\(hash).png", hash: hash, copyCount: 1,
                            isPinned: false, firstCopied: Date(), lastCopied: Date(),
                            appName: appName, appBundleID: appBundleID,
                            byteSize: meta.byteSize, pixelWidth: meta.width, pixelHeight: meta.height)
        items.insert(item, at: 0)
        pruneIfNeeded()
        rebuildVisible(resetSelection: true)
    }

    private func bumpExisting(hash: String, appName: String?, appBundleID: String?) -> Bool {
        guard let index = items.firstIndex(where: { $0.hash == hash }) else { return false }
        var item = items[index]
        item.copyCount += 1
        item.lastCopied = Date()
        item.appName = appName
        item.appBundleID = appBundleID
        items.remove(at: index)
        items.insert(item, at: 0)
        database.touch(id: item.id, date: item.lastCopied, appName: appName, appBundleID: appBundleID)
        rebuildVisible(resetSelection: true)
        return true
    }

    private func pruneIfNeeded() {
        let unpinned = items.lazy.filter { !$0.isPinned }.count
        guard unpinned > historyLimit else { return }
        let doomedHashes = database.prune(limit: historyLimit)
        for hash in doomedHashes { database.removeImageFiles(hash: hash) }
        var kept = 0
        items.removeAll { item in
            if item.isPinned { return false }
            kept += 1
            return kept > historyLimit
        }
    }

    // MARK: - Actions

    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        database.setPinned(id: item.id, items[index].isPinned)
        rebuildVisible(resetSelection: false)
    }

    func delete(_ item: ClipItem) {
        let wasIndex = visible.firstIndex(where: { $0.id == item.id })
        database.delete(id: item.id)
        if item.kind == .image { database.removeImageFiles(hash: item.hash) }
        thumbnailCache.removeObject(forKey: item.hash as NSString)
        items.removeAll { $0.id == item.id }
        rebuildVisible(resetSelection: false)
        if let wasIndex, !visible.isEmpty {
            selectedID = visible[min(wasIndex, visible.count - 1)].id
        } else {
            selectedID = visible.first?.id
        }
    }

    func clearUnpinned() {
        for item in items where !item.isPinned && item.kind == .image {
            database.removeImageFiles(hash: item.hash)
        }
        database.deleteUnpinned()
        items.removeAll { !$0.isPinned }
        rebuildVisible(resetSelection: true)
    }

    // MARK: - Visible list / selection

    /// Recompute the filtered list. Skipped while the panel is hidden;
    /// `resetForPresentation` forces one right before it appears.
    private func rebuildVisible(resetSelection: Bool, force: Bool = false) {
        guard force || PanelController.shared.isVisible else { return }

        var result = items
        switch filter {
        case .all: break
        case .pinned: result = result.filter(\.isPinned)
        case .text: result = result.filter { $0.kind == .text || $0.kind == .color }
        case .links: result = result.filter { $0.kind == .link }
        case .code: result = result.filter { $0.kind == .code }
        case .images: result = result.filter { $0.kind == .image }
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            result = result.filter {
                $0.content.localizedCaseInsensitiveContains(trimmed)
                    || ($0.appName?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
        }
        // Pinned items float to the top within the current view.
        let pinned = result.filter(\.isPinned)
        let rest = result.filter { !$0.isPinned }
        visible = pinned + rest

        if resetSelection || !visible.contains(where: { $0.id == selectedID }) {
            selectedID = visible.first?.id
        }
    }

    var selectedItem: ClipItem? {
        visible.first { $0.id == selectedID }
    }

    func moveSelection(by delta: Int) {
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + delta, 0), visible.count - 1)
        selectedID = visible[next].id
    }

    func cycleFilter(forward: Bool) {
        let all = FilterTab.allCases
        guard let index = all.firstIndex(of: filter) else { return }
        let next = (index + (forward ? 1 : all.count - 1)) % all.count
        filter = all[next]
    }

    func resetForPresentation() {
        query = ""
        filter = .all
        rebuildVisible(resetSelection: true, force: true)
        focusToken &+= 1
    }

    // MARK: - Thumbnails

    func thumbnail(for item: ClipItem) -> NSImage? {
        if let cached = thumbnailCache.object(forKey: item.hash as NSString) { return cached }
        let url = database.thumbnailURL(hash: item.hash)
        let fallback = database.imageURL(hash: item.hash)
        guard let image = NSImage(contentsOf: url) ?? NSImage(contentsOf: fallback) else { return nil }
        let cost = Int(image.size.width * image.size.height * 4)
        thumbnailCache.setObject(image, forKey: item.hash as NSString, cost: cost)
        return image
    }

    private static func sha(of data: Data) -> String {
        sha256Hex(data)
    }
}

// MARK: - Background image pipeline

private nonisolated func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// Persists the original as PNG and writes a ≤640px thumbnail alongside it.
private nonisolated func processImage(_ data: Data, fileURL: URL, thumbURL: URL) -> ImageMeta? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = props[kCGImagePropertyPixelWidth] as? Int,
          let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }

    do {
        if CGImageSourceGetType(source) as String? == UTType.png.identifier {
            try data.write(to: fileURL)
        } else if let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
            try png.write(to: fileURL)
        } else {
            return nil
        }
    } catch {
        NSLog("clipboard: failed to persist image: \(error)")
        return nil
    }

    let thumbOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: 640,
        kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) {
        let rep = NSBitmapImageRep(cgImage: thumb)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: thumbURL)
        }
    }

    let byteSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int).flatMap { $0 } ?? data.count
    return ImageMeta(width: width, height: height, byteSize: byteSize)
}
