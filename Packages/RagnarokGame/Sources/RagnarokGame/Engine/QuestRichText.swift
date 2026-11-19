import Foundation

/// RO item markup. Only positive numeric item IDs become links; no resource URL is executed.
enum QuestRichText {
    struct Segment: Equatable {
        var text: String
        var itemID: Int?
    }
    static func parse(_ source: String) -> [Segment] {
        let pattern = #"<ITEM>([^<]*)<INFO>\s*([0-9]+)\s*</INFO></ITEM>"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let sourceRange = NSRange(source.startIndex..., in: source)
        var segments: [Segment] = []
        var cursor = source.startIndex
        for match in expression.matches(in: source, range: sourceRange) {
            guard let whole = Range(match.range, in: source), let label = Range(match.range(at: 1), in: source),
                  let number = Range(match.range(at: 2), in: source) else { continue }
            if cursor < whole.lowerBound { segments.append(.init(text: plain(String(source[cursor..<whole.lowerBound])), itemID: nil)) }
            let id = Int(source[number].trimmingCharacters(in: .whitespacesAndNewlines))
            segments.append(.init(text: String(source[label]), itemID: id.flatMap { $0 > 0 ? $0 : nil }))
            cursor = whole.upperBound
        }
        if cursor < source.endIndex { segments.append(.init(text: plain(String(source[cursor...])), itemID: nil)) }
        return segments
    }
    private static func plain(_ value: String) -> String {
        value.replacingOccurrences(of: #"<INFO>.*?(?:</INFO>|$)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</?(?:ITEM|NAVI|URL|TIP)>"#, with: "", options: [.regularExpression, .caseInsensitive])
    }
}
