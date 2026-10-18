import Foundation

/// What a text clip looks like, so the panel can preview and filter it smartly.
enum ClipContent: Equatable {
    case link(URL)
    case color(RGBColor)
    case email(String)
    case address(String)
    case code
    case plain

    var symbol: String {
        switch self {
        case .link: return "link"
        case .color: return "paintpalette"
        case .email: return "envelope"
        case .address: return "map"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .plain: return "text.alignleft"
        }
    }
    var label: String {
        switch self {
        case .link: return "Link"
        case .color: return "Color"
        case .email: return "Email"
        case .address: return "Address"
        case .code: return "Code"
        case .plain: return "Text"
        }
    }

    private static var cache: [String: ClipContent] = [:]
    private static let lock = NSLock()

    static func of(_ clip: Clip) -> ClipContent {
        guard clip.kind == .text else { return .plain }
        let key = clip.id.uuidString + String(clip.text.hashValue)
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let value = detect(clip.text)
        if cache.count > 4_000 { cache.removeAll() }
        cache[key] = value
        return value
    }

    static func detect(_ raw: String) -> ClipContent {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let singleLine = !text.contains(where: \.isNewline)
        if singleLine, text.count <= 40, let color = RGBColor(parsing: text) { return .color(color) }
        if singleLine, !text.contains(" "), let url = URL(string: text),
           let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil {
            return .link(url)
        }
        if singleLine, text.count <= 254, text.range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return .email(text)
        }
        if looksLikeCode(text) { return .code }
        if text.count <= 200, text.split(whereSeparator: \.isNewline).count <= 4,
           let match = addressDetector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           match.range.length >= (text as NSString).length * 3 / 4 {
            return .address(text)
        }
        return .plain
    }

    private static let addressDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)

    static func looksLikeCode(_ text: String) -> Bool {
        guard text.count >= 8, text.count <= 200_000 else { return false }
        let sample = String(text.prefix(4_000))
        var score = 0
        for token in ["{", "}", ";", "=>", "->", "==", "!=", "&&", "||", "();", "</", "/>", "#include", "#!/"] where sample.contains(token) { score += 1 }
        let keywords = ["func ", "let ", "var ", "const ", "def ", "return ", "import ", "class ", "struct ", "function ", "public ", "private ", "async ", "await ", "SELECT ", "FROM ", "if (", "for (", "elif ", "fn ", "echo ", "sudo "]
        for keyword in keywords where sample.contains(keyword) { score += 1 }
        let lines = sample.split(whereSeparator: \.isNewline)
        let indented = lines.filter { $0.hasPrefix("    ") || $0.hasPrefix("\t") }.count
        if lines.count >= 3 && indented * 3 >= lines.count { score += 2 }
        return score >= 3
    }

    /// One-time codes and password- or token-like strings, which should not linger in history.
    static func looksSecret(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil {
            // Four digits that read as a year (1900–2099) are far more likely to be a year than a code.
            if text.count == 4, let year = Int(text), (1900...2099).contains(year) { return false }
            return true
        }
        if text.range(of: #"^\d{3}[- ]\d{3}$"#, options: .regularExpression) != nil { return true }
        guard text.count >= 10, text.count <= 128, !text.contains(where: { $0.isWhitespace }) else { return false }
        if text.contains("://") || text.contains("@") && text.contains(".") || text.hasPrefix("/") || text.hasPrefix("~") { return false }
        if RGBColor(parsing: text) != nil { return false }
        var classes = 0
        if text.contains(where: \.isLowercase) { classes += 1 }
        if text.contains(where: \.isUppercase) { classes += 1 }
        if text.contains(where: \.isNumber) { classes += 1 }
        if text.contains(where: { !$0.isLetter && !$0.isNumber }) { classes += 1 }
        let digits = text.filter(\.isNumber).count
        // Passwords mix most character classes; API keys and tokens are long and mix letters with digits.
        if classes >= 3 && digits >= 1 && text.count <= 64 { return true }
        if text.count >= 24 && classes >= 2 && digits >= 3 { return true }
        return false
    }
}

struct RGBColor: Equatable {
    var red: Double, green: Double, blue: Double, alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    init?(parsing raw: String) {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("#") {
            var hex = String(text.dropFirst())
            guard [3, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard let value = UInt64(hex, radix: 16) else { return nil }
            if hex.count == 8 {
                self.init(red: Double((value >> 24) & 0xff) / 255, green: Double((value >> 16) & 0xff) / 255,
                          blue: Double((value >> 8) & 0xff) / 255, alpha: Double(value & 0xff) / 255)
            } else {
                self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
            }
            return
        }
        guard text.hasPrefix("rgb"), let open = text.firstIndex(of: "("), text.hasSuffix(")") else { return nil }
        let parts = text[text.index(after: open)..<text.index(before: text.endIndex)]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Double($0.trimmingCharacters(in: CharacterSet(charactersIn: "%"))) }
        guard parts.count == 3 || parts.count == 4, parts.prefix(3).allSatisfy({ (0...255).contains($0) }) else { return nil }
        self.init(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: parts.count == 4 ? min(1, parts[3]) : 1)
    }

    var hex: String {
        let value = String(format: "#%02X%02X%02X", Int(round(red * 255)), Int(round(green * 255)), Int(round(blue * 255)))
        return alpha < 1 ? value + String(format: "%02X", Int(round(alpha * 255))) : value
    }
    var rgb: String {
        let base = "\(Int(round(red * 255))), \(Int(round(green * 255))), \(Int(round(blue * 255)))"
        return alpha < 1 ? "rgba(\(base), \(String(format: "%.2g", alpha)))" : "rgb(\(base))"
    }
    var hsl: String {
        let maxV = max(red, green, blue), minV = min(red, green, blue)
        let light = (maxV + minV) / 2
        var hue = 0.0, sat = 0.0
        if maxV != minV {
            let d = maxV - minV
            sat = light > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
            if maxV == red { hue = (green - blue) / d + (green < blue ? 6 : 0) }
            else if maxV == green { hue = (blue - red) / d + 2 }
            else { hue = (red - green) / d + 4 }
            hue *= 60
        }
        return "hsl(\(Int(round(hue))), \(Int(round(sat * 100)))%, \(Int(round(light * 100)))%)"
    }
}
