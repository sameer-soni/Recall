//
//  Classifier.swift
//  Recall
//

import Foundation

enum Classifier {
    static func classify(_ text: String) -> ClipKind {
        // No need to scan a huge paste in full — a prefix classifies fine.
        let sample = text.count > 16_384 ? String(text.prefix(16_384)) : text
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .text }

        if isHexColor(trimmed) { return .color }
        if isLink(trimmed) { return .link }
        if looksLikeCode(trimmed) { return .code }
        return .text
    }

    static func isHexColor(_ s: String) -> Bool {
        guard s.hasPrefix("#"), s.count == 4 || s.count == 7 || s.count == 9 else { return false }
        return s.dropFirst().allSatisfy(\.isHexDigit)
    }

    private static func isLink(_ s: String) -> Bool {
        guard !s.contains("\n"), s.count < 2048 else { return false }
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return true }
        // bare domain, e.g. example.com/path
        if !s.contains(" "), s.contains("."),
           let url = URL(string: "https://\(s)"), let host = url.host,
           host.contains("."), !host.hasSuffix(".") {
            let tld = host.split(separator: ".").last ?? ""
            return tld.count >= 2 && tld.allSatisfy(\.isLetter)
        }
        return false
    }

    private static let codeMarkers: [String] = [
        "func ", "def ", "class ", "import ", "let ", "var ", "const ", "return ",
        "public ", "private ", "static ", "void ", "fn ", "#include", "package ",
        "struct ", "enum ", "if (", "if(", "for (", "for(", "while (", "=> {",
        "});", "});", "</", "SELECT ", "select ", "INSERT ", "CREATE TABLE",
        "async ", "await ", "lambda ", "elif ", "#!/",
    ]

    private static func looksLikeCode(_ s: String) -> Bool {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        var score = 0

        for marker in codeMarkers where s.contains(marker) { score += 2 }

        let symbolSet: Set<Character> = ["{", "}", ";", "=", "(", ")", "[", "]", "<", ">"]
        let symbolCount = s.lazy.filter { symbolSet.contains($0) }.count
        if s.count > 0, Double(symbolCount) / Double(s.count) > 0.04 { score += 2 }

        let indented = lines.lazy.filter { $0.hasPrefix("    ") || $0.hasPrefix("\t") }.count
        if lines.count >= 3, Double(indented) / Double(lines.count) > 0.3 { score += 2 }

        if s.contains("://"), lines.count == 1 { score -= 2 } // probably a pasted URL with params

        return score >= 4
    }
}
