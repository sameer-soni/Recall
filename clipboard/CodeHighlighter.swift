//
//  CodeHighlighter.swift
//  Recall
//

import SwiftUI

enum CodeHighlighter {
    struct Theme {
        let keyword = Color(red: 0.99, green: 0.42, blue: 0.62)
        let string = Color(red: 0.55, green: 0.80, blue: 0.45)
        let number = Color(red: 0.95, green: 0.70, blue: 0.35)
        let comment = Color(white: 0.55)
        let plain = Color.primary.opacity(0.85)
    }

    private static let keywords: Set<String> = [
        "func", "let", "var", "if", "else", "for", "while", "return", "class",
        "struct", "enum", "import", "guard", "switch", "case", "default",
        "def", "elif", "lambda", "None", "True", "False", "self", "pass",
        "const", "function", "async", "await", "export", "new", "this",
        "public", "private", "static", "void", "int", "float", "double",
        "bool", "string", "fn", "impl", "match", "mut", "pub", "use",
        "package", "type", "interface", "extends", "implements", "try",
        "catch", "finally", "throw", "throws", "in", "of", "do", "break",
        "continue", "nil", "null", "undefined", "true", "false", "SELECT",
        "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "CREATE",
    ]

    static func highlight(_ code: String, maxLength: Int = 1200) -> AttributedString {
        let theme = Theme()
        let text = String(code.prefix(maxLength))
        var result = AttributedString()
        var buffer = ""
        var i = text.startIndex

        func flushPlain() {
            guard !buffer.isEmpty else { return }
            var run = AttributedString(buffer)
            run.foregroundColor = theme.plain
            result += run
            buffer = ""
        }

        func append(_ s: String, _ color: Color) {
            flushPlain()
            var run = AttributedString(s)
            run.foregroundColor = color
            result += run
        }

        while i < text.endIndex {
            let c = text[i]

            // line comments
            if c == "/", text.index(after: i) < text.endIndex, text[text.index(after: i)] == "/" {
                let lineEnd = text[i...].firstIndex(of: "\n") ?? text.endIndex
                append(String(text[i..<lineEnd]), theme.comment)
                i = lineEnd
                continue
            }
            if c == "#", i == text.startIndex || text[text.index(before: i)] == "\n" {
                let lineEnd = text[i...].firstIndex(of: "\n") ?? text.endIndex
                append(String(text[i..<lineEnd]), theme.comment)
                i = lineEnd
                continue
            }

            // strings
            if c == "\"" || c == "'" {
                var j = text.index(after: i)
                while j < text.endIndex, text[j] != c, text[j] != "\n" {
                    if text[j] == "\\" { j = text.index(after: j) }
                    if j < text.endIndex { j = text.index(after: j) }
                }
                if j < text.endIndex { j = text.index(after: j) }
                append(String(text[i..<j]), theme.string)
                i = j
                continue
            }

            // identifiers and keywords
            if c.isLetter || c == "_" {
                var j = i
                while j < text.endIndex, text[j].isLetter || text[j].isNumber || text[j] == "_" {
                    j = text.index(after: j)
                }
                let word = String(text[i..<j])
                if keywords.contains(word) {
                    append(word, theme.keyword)
                } else {
                    buffer += word
                }
                i = j
                continue
            }

            // numbers
            if c.isNumber {
                var j = i
                while j < text.endIndex, text[j].isNumber || text[j] == "." || text[j] == "x"
                    || text[j].isHexDigit {
                    j = text.index(after: j)
                }
                append(String(text[i..<j]), theme.number)
                i = j
                continue
            }

            buffer.append(c)
            i = text.index(after: i)
        }
        flushPlain()
        return result
    }
}
