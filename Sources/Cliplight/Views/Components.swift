import SwiftUI
import AppKit

/// Icons of the apps clips were copied from, cached by bundle identifier.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let image = cache[bundleID] { return image }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }
}

/// The leading icon for a clip: image thumbnail, file icon, or the source app's icon.
struct ClipIcon: View {
    let clip: Clip
    let size: CGFloat
    var body: some View {
        Group {
            if clip.kind == .image, let data = clip.data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else if clip.kind == .files, let url = clip.fileURLs.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
            } else if case .color(let color) = ClipContent.of(clip) {
                Circle()
                    .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                    .padding(size * 0.08)
            } else if clip.isSnippet {
                Image(systemName: "text.quote").font(.system(size: size * 0.6)).foregroundStyle(.secondary)
            } else if let icon = AppIcons.icon(for: clip.sourceBundleID) {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: clip.kind.symbol).font(.system(size: size * 0.6)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

enum ShortTime {
    static func string(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "Now" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if Calendar.current.isDateInToday(date) { return "\(seconds / 3_600)h" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// A small keyboard hint, e.g. "↩ Copy". Clickable so mouse users get the same actions.
struct KeyHint: View {
    let keys: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(keys)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 17)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(label).font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
