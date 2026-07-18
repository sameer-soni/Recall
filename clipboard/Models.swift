//
//  Models.swift
//  Recall
//

import Foundation

enum ClipKind: Int, CaseIterable, Codable {
    case text = 0
    case link = 1
    case code = 2
    case color = 3
    case image = 4
    case file = 5

    var label: String {
        switch self {
        case .text: return "Text"
        case .link: return "Links"
        case .code: return "Code"
        case .color: return "Colors"
        case .image: return "Images"
        case .file: return "Files"
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}

struct ClipItem: Identifiable, Equatable {
    let id: Int64
    var kind: ClipKind
    /// Text, URL, hex color, newline-separated file paths, or an image file name.
    var content: String
    let hash: String
    var copyCount: Int
    var isPinned: Bool
    let firstCopied: Date
    var lastCopied: Date
    var appName: String?
    var appBundleID: String?
    var byteSize: Int
    var pixelWidth: Int
    var pixelHeight: Int

    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.id == rhs.id
            && lhs.copyCount == rhs.copyCount
            && lhs.isPinned == rhs.isPinned
            && lhs.lastCopied == rhs.lastCopied
    }

    var titleLine: String {
        switch kind {
        case .image:
            return "Image \(pixelWidth)×\(pixelHeight)"
        case .file:
            let paths = content.split(separator: "\n")
            if paths.count == 1, let first = paths.first {
                return (first as NSString).lastPathComponent
            }
            return "\(paths.count) files"
        default:
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
            return String(firstLine.prefix(200))
        }
    }
}
