import SwiftUI

struct ClipPreview: View {
    let clip: Clip
    let markedCount: Int
    let verb: String
    let paste: () -> Void
    let actions: () -> Void
    let quickLook: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if markedCount > 1 { multiple } else { content }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().opacity(0.5).padding(.horizontal, 20)
            if markedCount <= 1 {
                metadata.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
            }
            HStack(spacing: 14) {
                KeyHint(keys: "↩", label: markedCount > 1 ? "\(verb) \(markedCount)" : verb, action: paste)
                KeyHint(keys: "⌘K", label: "Actions", action: actions)
                Spacer()
                KeyHint(keys: "⌘Y", label: "Quick Look", action: quickLook)
            }
            .padding(.horizontal, 20).padding(.top, markedCount > 1 ? 12 : 0).padding(.bottom, 14)
        }
    }

    private var multiple: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text("\(markedCount) Clips Selected").font(.system(size: 15, weight: .semibold))
            Text("Press ↩ to \(verb.lowercased()) them together, one per line.")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
    }

    @ViewBuilder private var content: some View {
        switch clip.kind {
        case .image:
            if let data = clip.data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .padding(24)
            }
        case .files:
            VStack(spacing: 12) {
                ClipIcon(clip: clip, size: 72)
                Text(clip.title).font(.system(size: 15, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
                if clip.fileURLs.count > 1 {
                    Text("and \(clip.fileURLs.count - 1) more").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        case .text:
            switch ClipContent.of(clip) {
            case .color(let color): ColorPreview(color: color)
            case .link(let url): LinkPreview(url: url)
            case .code: textView(CodeHighlighter.highlight(clip.text), monospaced: true)
            default: textView(AttributedString(clip.text), monospaced: false)
            }
        }
    }

    private func textView(_ text: AttributedString, monospaced: Bool) -> some View {
        ScrollView {
            Text(text)
                .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .lineSpacing(3)
                .modifier(SelectableUnlessHighlighted(highlighted: monospaced))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(20)
        }
    }

    private var metadata: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
            if let name = clip.snippetName {
                GridRow { label("Snippet"); Text(name).lineLimit(1) }
            }
            GridRow {
                label("From")
                HStack(spacing: 5) {
                    if let icon = AppIcons.icon(for: clip.sourceBundleID) {
                        Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                    }
                    Text(clip.source).lineLimit(1)
                }
            }
            GridRow {
                label("Copied")
                Text(clip.lastUsedAt.formatted(.relative(presentation: .named)).capitalizedFirst)
            }
            GridRow {
                label(clip.kind == .text ? ClipContent.of(clip).label : "Size")
                Text(clip.detail)
            }
            if let expires = clip.expiresAt {
                GridRow {
                    label("Deletes")
                    Text(expires, style: .relative).foregroundStyle(.orange)
                }
            }
            if clip.kind == .image, let text = clip.recognizedText, !text.isEmpty {
                GridRow { label("Text"); Text(text.replacingOccurrences(of: "\n", with: " ")).lineLimit(1) }
            }
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }
}

/// On macOS, selectable Text drops attributed colors, so highlighted code isn't selectable.
private struct SelectableUnlessHighlighted: ViewModifier {
    let highlighted: Bool
    func body(content: Content) -> some View {
        if highlighted { content } else { content.textSelection(.enabled) }
    }
}

private struct ColorPreview: View {
    let color: RGBColor
    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .frame(width: 120, height: 120)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
            VStack(spacing: 4) {
                ForEach([color.hex, color.rgb, color.hsl], id: \.self) { value in
                    Text(value).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

private struct LinkPreview: View {
    let url: URL
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "safari").font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
            Text(url.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString)
                .font(.system(size: 16, weight: .semibold)).lineLimit(1)
            Text(url.absoluteString)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(4).multilineTextAlignment(.center).textSelection(.enabled)
        }
        .padding(24)
    }
}

/// A small, dependency-free highlighter: comments, strings, numbers and common keywords.
enum CodeHighlighter {
    private static let keywords = Set("""
    func let var const def return import class struct enum protocol extension if else elif for while in of switch case default break continue \
    function async await try catch throw throws public private internal static final new this self super nil null true false None True False \
    int float double string bool void fn pub mut impl use mod match select from where insert update delete into values and or not
    """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))

    static func highlight(_ code: String) -> AttributedString {
        let text = String(code.prefix(20_000))
        var result = AttributedString(text)
        let ns = text as NSString
        func paint(_ pattern: String, _ color: Color, options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard let range = Range(match.range, in: text), let attributed = Range(range, in: result) else { continue }
                result[attributed].foregroundColor = color
            }
        }
        paint(#"\b\d+(\.\d+)?\b"#, .orange)
        if let regex = try? NSRegularExpression(pattern: #"\b[A-Za-z_]+\b"#) {
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) where keywords.contains(ns.substring(with: match.range)) {
                if let range = Range(match.range, in: text), let attributed = Range(range, in: result) { result[attributed].foregroundColor = .pink }
            }
        }
        paint(#""([^"\\\n]|\\.)*"|'([^'\\\n]|\\.)*'|`[^`]*`"#, .red)
        paint(#"//[^\n]*|#(?!include|!)[^\n]*|/\*[\s\S]*?\*/"#, .secondary)
        return result
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
