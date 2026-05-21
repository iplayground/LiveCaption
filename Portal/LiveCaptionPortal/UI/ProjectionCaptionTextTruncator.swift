import AppKit

enum ProjectionCaptionTextTruncator {
    static func visibleText(
        of text: String,
        fitting size: CGSize,
        font: NSFont,
        lineSpacing: CGFloat,
        verticalPlacement: ProjectionCaptionVerticalPlacement
    ) -> String {
        switch verticalPlacement {
        case .top:
            return visiblePrefix(of: text, fitting: size, font: font, lineSpacing: lineSpacing)
        case .bottom:
            return visibleSuffix(of: text, fitting: size, font: font, lineSpacing: lineSpacing)
        }
    }

    static func visibleSuffix(
        of text: String,
        fitting size: CGSize,
        font: NSFont,
        lineSpacing: CGFloat
    ) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty, size.width > 0, size.height > 0 else {
            return trimmedText
        }

        let tokens = wrappingTokens(in: trimmedText)

        if let wrappedText = wrappedText(tokens: tokens, fitting: size, font: font, lineSpacing: lineSpacing) {
            return wrappedText
        }

        for startIndex in tokens.indices.dropFirst() {
            guard tokens[startIndex] != " ", tokens[startIndex] != "\n" else {
                continue
            }

            let candidateTokens = Array(tokens[startIndex...])

            if let wrappedText = wrappedText(
                tokens: candidateTokens,
                fitting: size,
                font: font,
                lineSpacing: lineSpacing
            ) {
                return wrappedText
            }
        }

        return characterTrimmedSuffix(
            of: trimmedText,
            fitting: size,
            font: font,
            lineSpacing: lineSpacing
        )
    }

    private static func visiblePrefix(
        of text: String,
        fitting size: CGSize,
        font: NSFont,
        lineSpacing: CGFloat
    ) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty, size.width > 0, size.height > 0 else {
            return trimmedText
        }

        let tokens = wrappingTokens(in: trimmedText)

        if let wrappedText = wrappedText(tokens: tokens, fitting: size, font: font, lineSpacing: lineSpacing) {
            return wrappedText
        }

        for endIndex in tokens.indices.dropLast().reversed() {
            let candidateTokens = Array(tokens[...endIndex])
            guard candidateTokens.last != " ", candidateTokens.last != "\n" else {
                continue
            }

            if let wrappedText = wrappedText(
                tokens: candidateTokens,
                fitting: size,
                font: font,
                lineSpacing: lineSpacing
            ) {
                return wrappedText
            }
        }

        return characterTrimmedPrefix(
            of: trimmedText,
            fitting: size,
            font: font,
            lineSpacing: lineSpacing
        )
    }

    private static func characterTrimmedSuffix(
        of text: String,
        fitting size: CGSize,
        font: NSFont,
        lineSpacing: CGFloat
    ) -> String {
        let characterStartIndices = text.indices.dropFirst()

        for index in characterStartIndices {
            let candidate = String(text[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = wrappingTokens(in: candidate)

            if let wrappedText = wrappedText(tokens: tokens, fitting: size, font: font, lineSpacing: lineSpacing) {
                return wrappedText
            }
        }

        return ""
    }

    private static func characterTrimmedPrefix(
        of text: String,
        fitting size: CGSize,
        font: NSFont,
        lineSpacing: CGFloat
    ) -> String {
        let characterEndIndices = text.indices.dropLast().reversed()

        for index in characterEndIndices {
            let candidate = String(text[...index]).trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = wrappingTokens(in: candidate)

            if let wrappedText = wrappedText(tokens: tokens, fitting: size, font: font, lineSpacing: lineSpacing) {
                return wrappedText
            }
        }

        return ""
    }

    private static func wrappedText(
        tokens: [String],
        fitting size: CGSize,
        font: NSFont,
        lineSpacing: CGFloat
    ) -> String? {
        let lines = wrappedLines(tokens: tokens, width: size.width, font: font)
        let height = measuredHeight(lineCount: lines.count, font: font, lineSpacing: lineSpacing)

        guard height <= size.height else {
            return nil
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func wrappedLines(
        tokens: [String],
        width: CGFloat,
        font: NSFont
    ) -> [String] {
        var lines: [String] = []
        var currentLine = ""

        for token in tokens {
            if token == "\n" {
                appendLine(currentLine, to: &lines)
                currentLine = ""
                continue
            }

            if token == " " {
                guard !currentLine.isEmpty else {
                    continue
                }

                let candidate = currentLine + token

                if measuredWidth(of: candidate, font: font) <= width {
                    currentLine = candidate
                } else {
                    appendLine(currentLine, to: &lines)
                    currentLine = ""
                }

                continue
            }

            if currentLine.isEmpty {
                appendToken(token, width: width, font: font, currentLine: &currentLine, lines: &lines)
                continue
            }

            let candidate = currentLine + token

            if measuredWidth(of: candidate, font: font) <= width {
                currentLine = candidate
            } else {
                appendLine(currentLine, to: &lines)
                currentLine = ""
                appendToken(token, width: width, font: font, currentLine: &currentLine, lines: &lines)
            }
        }

        appendLine(currentLine, to: &lines)
        return lines.isEmpty ? [""] : lines
    }

    private static func appendToken(
        _ token: String,
        width: CGFloat,
        font: NSFont,
        currentLine: inout String,
        lines: inout [String]
    ) {
        guard measuredWidth(of: token, font: font) > width else {
            currentLine = token
            return
        }

        for character in token {
            let fragment = String(character)

            if currentLine.isEmpty {
                currentLine = fragment
                continue
            }

            let candidate = currentLine + fragment

            if measuredWidth(of: candidate, font: font) <= width {
                currentLine = candidate
            } else {
                appendLine(currentLine, to: &lines)
                currentLine = fragment
            }
        }
    }

    private static func appendLine(_ line: String, to lines: inout [String]) {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        if !trimmedLine.isEmpty {
            lines.append(trimmedLine)
        }
    }

    private static func wrappingTokens(in text: String) -> [String] {
        var tokens: [String] = []
        var wordBuffer = ""
        var previousWasWhitespace = false

        func flushWordBuffer() {
            guard !wordBuffer.isEmpty else {
                return
            }

            tokens.append(wordBuffer)
            wordBuffer = ""
        }

        for character in text {
            if character.isNewline {
                flushWordBuffer()
                tokens.append("\n")
                previousWasWhitespace = false
                continue
            }

            if character.isWhitespace {
                flushWordBuffer()

                if !previousWasWhitespace {
                    tokens.append(" ")
                }

                previousWasWhitespace = true
                continue
            }

            previousWasWhitespace = false

            if character.isCJKWrappingCharacter {
                flushWordBuffer()
                tokens.append(String(character))
            } else {
                wordBuffer.append(character)
            }
        }

        flushWordBuffer()
        return tokens
    }

    private static func measuredWidth(of text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func measuredHeight(lineCount: Int, font: NSFont, lineSpacing: CGFloat) -> CGFloat {
        guard lineCount > 0 else {
            return 0
        }

        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        return (lineHeight * CGFloat(lineCount)) + (lineSpacing * CGFloat(max(0, lineCount - 1)))
    }
}

private extension Character {
    var isWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) }
    }

    var isNewline: Bool {
        unicodeScalars.allSatisfy { CharacterSet.newlines.contains($0) }
    }

    var isCJKWrappingCharacter: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x2EFF,
                 0x3000...0x303F,
                 0x3040...0x30FF,
                 0x3100...0x312F,
                 0x3130...0x318F,
                 0x31A0...0x31BF,
                 0x31C0...0x31EF,
                 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xAC00...0xD7AF,
                 0xF900...0xFAFF,
                 0xFF00...0xFFEF:
                return true
            default:
                return false
            }
        }
    }
}
