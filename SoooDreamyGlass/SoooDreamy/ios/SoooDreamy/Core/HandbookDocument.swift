import Foundation

struct HandbookSection: Identifiable, Equatable {
    let id: String
    let markdown: String
}

enum HandbookDocument {
    private static let markerPrefix = "<!-- anchor:"
    private static let markerSuffix = "-->"

    static let requiredAnchors = ["setup", "home", "chat", "play", "us", "settings"]

    static func parse(_ markdown: String) -> [HandbookSection] {
        var sections: [HandbookSection] = []
        var currentID: String?
        var currentLines: [String] = []

        func appendCurrent() {
            guard let currentID else { return }
            let content = currentLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(HandbookSection(id: currentID, markdown: content))
        }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(markerPrefix), trimmed.hasSuffix(markerSuffix) {
                appendCurrent()
                let start = trimmed.index(trimmed.startIndex, offsetBy: markerPrefix.count)
                let end = trimmed.index(trimmed.endIndex, offsetBy: -markerSuffix.count)
                currentID = String(trimmed[start..<end])
                    .trimmingCharacters(in: .whitespaces)
                currentLines = []
            } else if currentID != nil {
                currentLines.append(line)
            }
        }
        appendCurrent()
        return sections
    }
}
