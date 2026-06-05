import Foundation

enum CSVService {
    nonisolated static func parse(_ content: String) -> [[String]] {
        let normalizedContent = normalizeLineEndings(in: content)
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var isInsideQuotes = false

        var index = normalizedContent.startIndex
        while index < normalizedContent.endIndex {
            let character = normalizedContent[index]

            if isInsideQuotes {
                if character == "\"" {
                    let nextIndex = normalizedContent.index(after: index)
                    if nextIndex < normalizedContent.endIndex, normalizedContent[nextIndex] == "\"" {
                        currentField.append("\"")
                        index = nextIndex
                    } else {
                        isInsideQuotes = false
                    }
                } else {
                    currentField.append(character)
                }
            } else {
                switch character {
                case "\"":
                    isInsideQuotes = true
                case ",":
                    currentRow.append(currentField)
                    currentField = ""
                case "\n":
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                default:
                    currentField.append(character)
                }
            }

            index = normalizedContent.index(after: index)
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows
    }

    nonisolated static func encodeRow(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    nonisolated static func encode(rows: [[String]]) -> String {
        rows.map(encodeRow).joined(separator: "\n") + "\n"
    }

    nonisolated private static func escape(_ field: String) -> String {
        let needsQuotes = field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r")
        guard needsQuotes else { return field }

        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    nonisolated private static func normalizeLineEndings(in content: String) -> String {
        let withoutBOM: String
        if content.hasPrefix("\u{FEFF}") {
            withoutBOM = String(content.dropFirst())
        } else {
            withoutBOM = content
        }

        let normalizedCRLF = withoutBOM.replacingOccurrences(of: "\r\n", with: "\n")
        return normalizedCRLF.replacingOccurrences(of: "\r", with: "\n")
    }
}
