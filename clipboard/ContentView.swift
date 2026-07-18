//
//  ContentView.swift
//  Recall
//

import AppKit
import SwiftUI

// MARK: - Design tokens

enum UI {
    static let panelSize = CGSize(width: 800, height: 520)
    static let cornerRadius: CGFloat = 22

    /// Follows the accent colour from System Settings → Appearance.
    static var accent: Color { Color(nsColor: .controlAccentColor) }

    static func tint(for kind: ClipKind) -> Color {
        switch kind {
        case .text: return Color(nsColor: .systemGray)
        case .link: return Color(nsColor: .systemBlue)
        case .code: return Color(nsColor: .systemPurple)
        case .color: return Color(nsColor: .systemOrange)
        case .image: return Color(nsColor: .systemGreen)
        case .file: return Color(nsColor: .systemYellow)
        }
    }
}

/// Cached source-app icons for the rows.
@MainActor
enum AppIconProvider {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache.object(forKey: bundleID as NSString) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        cache.setObject(icon, forKey: bundleID as NSString)
        return icon
    }
}

// MARK: - Root

struct ContentView: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(store: store)
            FilterRow(store: store)
            Divider().opacity(0.35)
            if store.visible.isEmpty {
                EmptyState(query: store.query)
            } else {
                HSplitLayout(store: store)
            }
            Divider().opacity(0.35)
            FooterBar(store: store)
        }
        .frame(width: UI.panelSize.width, height: UI.panelSize.height)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: UI.cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: UI.cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.40))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: UI.cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.30), .white.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: UI.cornerRadius, style: .continuous))
    }
}

private struct HSplitLayout: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        HStack(spacing: 0) {
            ItemList(store: store)
                .frame(width: 340)
            Divider().opacity(0.35)
            DetailPane(store: store)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Search bar

private struct SearchBar: View {
    @ObservedObject var store: ClipboardStore
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(UI.accent)
            TextField("Search clipboard history…", text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($focused)
                .onAppear { focused = true }
                // The hosting view persists, so re-focus on every open.
                .onChange(of: store.focusToken) { _, _ in focused = true }
            if !store.query.isEmpty {
                Button {
                    store.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            SettingsMenu(store: store)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

private struct SettingsMenu: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        Menu {
            Toggle("Paste automatically", isOn: $store.autoPaste)
            if store.autoPaste && !PasteService.canAutoPaste {
                Button("Grant Accessibility Access…") {
                    PasteService.requestAccessibility()
                }
            }
            Toggle("Pause monitoring", isOn: $store.isPaused)
            Divider()
            Button("Clear Unpinned History", role: .destructive) {
                store.clearUnpinned()
            }
            Divider()
            Button("Quit Recall") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Filter chips

private struct FilterRow: View {
    @ObservedObject var store: ClipboardStore
    @Namespace private var chipSpace

    var body: some View {
        HStack(spacing: 5) {
            ForEach(FilterTab.allCases, id: \.self) { tab in
                FilterChip(tab: tab, isOn: store.filter == tab, namespace: chipSpace) {
                    withAnimation(.snappy(duration: 0.22)) {
                        store.filter = tab
                    }
                }
            }
            Spacer()
            if store.isPaused {
                Label("Paused", systemImage: "pause.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }
}

private struct FilterChip: View {
    let tab: FilterTab
    let isOn: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(tab.label)
                    .font(.system(size: 12, weight: isOn ? .semibold : .medium))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                if isOn {
                    Capsule()
                        .fill(UI.accent)
                        .matchedGeometryEffect(id: "chip", in: namespace)
                } else {
                    Capsule()
                        .fill(Color.primary.opacity(hovering ? 0.09 : 0.045))
                }
            }
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Item list (left pane)

private struct ItemList: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(store.visible.enumerated()), id: \.element.id) { index, item in
                        ItemRow(store: store, item: item,
                                isSelected: store.selectedID == item.id,
                                shortcutIndex: index < 9 ? index + 1 : nil)
                            .id(item.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: store.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }
}

private struct ItemRow: View {
    @ObservedObject var store: ClipboardStore
    let item: ClipItem
    let isSelected: Bool
    let shortcutIndex: Int?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            leadingIcon
            VStack(alignment: .leading, spacing: 2) {
                title
                    .lineLimit(1)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    if let icon = AppIconProvider.icon(forBundleID: item.appBundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 11, height: 11)
                    }
                    Text(item.lastCopied, format: .relative(presentation: .named))
                    if item.copyCount > 1 {
                        Text("· \(item.copyCount)×")
                            .fontWeight(.semibold)
                            .foregroundStyle(UI.accent)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(UI.accent)
                    .rotationEffect(.degrees(45))
            }
            if let shortcutIndex, isSelected || hovering {
                Text("⌘\(shortcutIndex)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isSelected
                        ? UI.accent.opacity(0.18)
                        : Color.primary.opacity(hovering ? 0.055 : 0)
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if isSelected {
                PanelController.shared.pasteAndDismiss(item)
            } else {
                store.selectedID = item.id
            }
        }
        .contextMenu {
            Button("Paste") { PanelController.shared.pasteAndDismiss(item) }
            Button(item.isPinned ? "Unpin" : "Pin") { store.togglePin(item) }
            Button("Delete", role: .destructive) { store.delete(item) }
        }
    }

    @ViewBuilder private var title: some View {
        switch item.kind {
        case .image:
            Text("Image · \(item.pixelWidth)×\(item.pixelHeight)")
        case .color:
            Text(item.content.uppercased())
                .font(.system(size: 13, design: .monospaced))
        default:
            Text(item.titleLine)
        }
    }

    @ViewBuilder private var leadingIcon: some View {
        switch item.kind {
        case .color:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(hex: item.content) ?? .gray)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                )
        case .image:
            Group {
                if let thumb = store.thumbnail(for: item) {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 34, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            )
        default:
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(UI.tint(for: item.kind).opacity(0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(UI.tint(for: item.kind))
            }
        }
    }
}

// MARK: - Detail pane (right)

private struct DetailPane: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        Group {
            if let item = store.selectedItem {
                VStack(alignment: .leading, spacing: 0) {
                    DetailHeader(store: store, item: item)
                    Divider().opacity(0.3)
                    DetailContent(store: store, item: item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .id(item.id)
                .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .animation(.easeOut(duration: 0.10), value: store.selectedID)
    }
}

private struct DetailHeader: View {
    @ObservedObject var store: ClipboardStore
    let item: ClipItem

    var body: some View {
        HStack(spacing: 8) {
            // Kind badge
            HStack(spacing: 4) {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(kindLabel)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(UI.tint(for: item.kind).opacity(0.16)))
            .foregroundStyle(UI.tint(for: item.kind))

            if let icon = AppIconProvider.icon(forBundleID: item.appBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            }
            Text(metaText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            HeaderButton(symbol: item.isPinned ? "pin.slash" : "pin",
                         help: item.isPinned ? "Unpin (⌘P)" : "Pin (⌘P)") {
                store.togglePin(item)
            }
            HeaderButton(symbol: "trash", help: "Delete (⌘⌫)") {
                store.delete(item)
            }
            Button {
                PanelController.shared.pasteAndDismiss(item)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "return")
                        .font(.system(size: 9, weight: .bold))
                    Text("Paste")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(UI.accent))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var kindLabel: String {
        switch item.kind {
        case .text: return "Text"
        case .link: return "Link"
        case .code: return "Code"
        case .color: return "Color"
        case .image: return "Image"
        case .file: return "File"
        }
    }

    private var metaText: String {
        var parts: [String] = []
        if let app = item.appName { parts.append(app) }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        parts.append(formatter.localizedString(for: item.lastCopied, relativeTo: Date()))
        if item.copyCount > 1 { parts.append("copied \(item.copyCount)×") }
        if item.byteSize > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }
}

private struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.09 : 0.045)))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

private struct DetailContent: View {
    @ObservedObject var store: ClipboardStore
    let item: ClipItem

    var body: some View {
        switch item.kind {
        case .image:
            imagePreview
        case .color:
            colorPreview
        case .code:
            ScrollView {
                Text(HighlightMemo.highlight(item.content, key: item.hash))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        case .file:
            filePreview
        default:
            ScrollView {
                Text(item.content)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
    }

    private var imagePreview: some View {
        Group {
            if let image = store.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
                    .padding(16)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var colorPreview: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: item.content) ?? .gray)
                .frame(width: 120, height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: (Color(hex: item.content) ?? .clear).opacity(0.45), radius: 14, y: 4)
            Text(item.content.uppercased())
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filePreview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(item.content.split(separator: "\n"), id: \.self) { path in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: String(path)))
                            .resizable()
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((String(path) as NSString).lastPathComponent)
                                .font(.system(size: 12.5, weight: .medium))
                            Text(String(path))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Empty state

private struct EmptyState: View {
    let query: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ZStack {
                Circle()
                    .fill(UI.accent.opacity(0.13))
                    .frame(width: 64, height: 64)
                Image(systemName: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(UI.accent)
            }
            Text(query.isEmpty ? "Nothing here yet" : "No matches for “\(query)”")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            if query.isEmpty {
                Text("Copy something and it will show up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Footer

private struct FooterBar: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        HStack(spacing: 14) {
            KeyHint(keys: "↩", label: "paste")
            KeyHint(keys: "⌘P", label: "pin")
            KeyHint(keys: "⌘⌫", label: "delete")
            KeyHint(keys: "⇥", label: "filter")
            Spacer()
            Text("\(store.visible.count) item\(store.visible.count == 1 ? "" : "s")")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4.5)
                        .fill(Color.primary.opacity(0.08))
                )
            Text(label)
                .font(.system(size: 10.5))
        }
        .foregroundStyle(.tertiary)
    }
}

// MARK: - Helpers

/// Memoizes the last highlight so we don't re-run it on every keystroke.
@MainActor
private enum HighlightMemo {
    private static var key: String?
    private static var value: AttributedString?

    static func highlight(_ code: String, key itemKey: String) -> AttributedString {
        if key == itemKey, let value { return value }
        let result = CodeHighlighter.highlight(code, maxLength: 6000)
        key = itemKey
        value = result
        return result
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let v = s.count == 6 ? value : value >> 8
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
