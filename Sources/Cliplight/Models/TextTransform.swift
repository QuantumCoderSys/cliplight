import Foundation

/// Quick fixes that can be applied to a text clip before pasting.
enum TextTransform: String, CaseIterable, Identifiable {
    case uppercase, lowercase, titleCase, trimWhitespace, formatJSON, minifyJSON, cleanLink
    var id: String { rawValue }
    var title: String {
        switch self {
        case .uppercase: return "Paste as UPPERCASE"
        case .lowercase: return "Paste as lowercase"
        case .titleCase: return "Paste as Title Case"
        case .trimWhitespace: return "Paste Trimmed"
        case .formatJSON: return "Paste Formatted JSON"
        case .minifyJSON: return "Paste Minified JSON"
        case .cleanLink: return "Paste Link Without Tracking"
        }
    }
    var symbol: String {
        switch self {
        case .uppercase: return "textformat.size.larger"
        case .lowercase: return "textformat.size.smaller"
        case .titleCase: return "textformat"
        case .trimWhitespace: return "scissors"
        case .formatJSON: return "curlybraces"
        case .minifyJSON: return "arrow.down.right.and.arrow.up.left"
        case .cleanLink: return "link.badge.plus"
        }
    }

    /// The transformed text, or nil when the transform doesn't apply or changes nothing.
    func apply(_ text: String) -> String? {
        let result: String?
        switch self {
        case .uppercase: result = text.uppercased()
        case .lowercase: result = text.lowercased()
        case .titleCase: result = text.capitalized
        case .trimWhitespace:
            result = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .formatJSON: result = Self.json(text, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        case .minifyJSON: result = Self.json(text, options: [.withoutEscapingSlashes])
        case .cleanLink: result = Self.cleanLink(text)
        }
        guard let result, result != text, !result.isEmpty else { return nil }
        return result
    }

    private static func json(_ text: String, options: JSONSerialization.WritingOptions) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              object is [Any] || object is [String: Any],
              let out = try? JSONSerialization.data(withJSONObject: object, options: options) else { return nil }
        return String(data: out, encoding: .utf8)
    }

    static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "mc_cid", "mc_eid", "igshid", "igsh",
        "si", "ref_src", "ref_url", "_hsenc", "_hsmi", "mkt_tok", "yclid", "twclid", "spm", "s_cid", "trk"
    ]
    static func cleanLink(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .link = ClipContent.detect(trimmed), var parts = URLComponents(string: trimmed),
              let items = parts.queryItems, !items.isEmpty else { return nil }
        let kept = items.filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_") && !trackingParameters.contains(name)
        }
        guard kept.count != items.count else { return nil }
        parts.queryItems = kept.isEmpty ? nil : kept
        return parts.string
    }
}
