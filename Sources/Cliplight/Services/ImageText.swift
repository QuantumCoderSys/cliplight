import AppKit
import Vision

/// Finds text in copied images on this Mac, so a screenshot can be found by the words in it.
enum ImageText {
    @MainActor
    static func recognize(_ clip: Clip, in store: ClipboardStore) {
        guard clip.kind == .image, let data = clip.data else { return }
        let id = clip.id
        DispatchQueue.global(qos: .utility).async {
            guard let text = recognize(data), !text.isEmpty else { return }
            DispatchQueue.main.async { store.attach(recognizedText: text, to: id) }
        }
    }

    static func recognize(_ data: Data) -> String? {
        guard let image = NSImage(data: data), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do { try VNImageRequestHandler(cgImage: cgImage).perform([request]) } catch { return nil }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return String(lines.joined(separator: "\n").prefix(20_000))
    }
}
