import SwiftUI
import UniformTypeIdentifiers

struct ClipRow: View {
    let clip: Clip
    let selected: Bool
    let marked: Bool
    let choose: () -> Void
    let toggleMark: () -> Void
    let paste: () -> Void
    let pin: () -> Void
    let remove: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            ClipIcon(clip: clip, size: 20)
            Text(clip.title)
                .font(.system(size: 13))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 6)
            trailing
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: paste)
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) { toggleMark() } else { choose() }
        }
        .onDrag { itemProvider }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(clip.title), \(clip.source)\(clip.isPinned ? ", pinned" : "")\(marked ? ", selected" : "")")
        .accessibilityAddTraits(selected || marked ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: "Paste", paste)
        .contextMenu {
            Button("Paste", action: paste)
            Button(clip.isPinned ? "Unpin" : "Pin", action: pin)
            Divider()
            Button("Delete", role: .destructive, action: remove)
        }
    }

    private var background: Color {
        if selected { return .accentColor }
        if marked { return Color.accentColor.opacity(0.22) }
        return .clear
    }

    @ViewBuilder private var trailing: some View {
        if marked && !selected {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Color.accentColor)
        } else if let expires = clip.expiresAt {
            HStack(spacing: 3) {
                Image(systemName: "timer").font(.system(size: 9))
                Text(expires, style: .timer).monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.orange)
            .help("One-time code or password. Deleted automatically.")
        } else {
            if clip.isPinned && !selected {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Text(ShortTime.string(clip.lastUsedAt))
                .font(.system(size: 11))
                .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
        }
    }

    /// Lets a clip be dragged straight into another app.
    private var itemProvider: NSItemProvider {
        switch clip.kind {
        case .text:
            return NSItemProvider(object: clip.text as NSString)
        case .image:
            let provider = NSItemProvider()
            if let data = clip.data {
                provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                    completion(data, nil); return nil
                }
                provider.suggestedName = "Image"
            }
            return provider
        case .files:
            return clip.fileURLs.first.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider()
        }
    }
}
