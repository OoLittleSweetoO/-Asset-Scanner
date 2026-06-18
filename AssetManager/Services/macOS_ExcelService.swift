import Foundation
import UniformTypeIdentifiers
import CoreFoundation

/// Excel 文件服务 - macOS 版本
final class ExcelService {

    func readExcel(from url: URL) async throws -> [[String: String]] {
        print("📖 开始读取 Excel/CSV 文件")
        let ext = url.pathExtension.lowercased()
        if ext == "csv" {
            return try await readCSV(from: url)
        } else if ext == "xlsx" {
            return try await readXLSX(from: url)
        } else {
            throw NSError(domain: "ExcelError", code: 1, userInfo: [NSLocalizedDescriptionKey: "不支持的格式"])
        }
    }

    private func readCSV(from url: URL) async throws -> [[String: String]] {
        print("📄 读取 CSV 文件: \(url.lastPathComponent)")

        if let attrs = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let size = attrs.fileSize, size > 100 * 1024 * 1024 {
            throw NSError(domain: "ExcelError", code: 2, userInfo: [NSLocalizedDescriptionKey: "文件过大（\(size) 字节），最大支持 100MB"])
        }

        let content = try readCSVContent(from: url)
        let rows = CSVService.parse(content)
        let nonEmptyRows = rows.filter { row in
            !row.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        guard nonEmptyRows.count >= 2 else {
            throw NSError(domain: "ExcelError", code: 3, userInfo: [NSLocalizedDescriptionKey: "文件至少需要包含表头和一行数据"])
        }

        let headers = nonEmptyRows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var parsedRows: [[String: String]] = []

        for values in nonEmptyRows.dropFirst() {
            var row: [String: String] = [:]
            for (index, header) in headers.enumerated() where !header.isEmpty {
                row[header] = index < values.count ? values[index] : ""
            }
            parsedRows.append(row)
        }

        return parsedRows
    }

    private func readCSVContent(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )

        let candidateEncodings: [String.Encoding] = [
            .utf8,
            .unicode,
            .utf16LittleEndian,
            .utf16BigEndian,
            gb18030
        ]

        for encoding in candidateEncodings {
            if let content = String(data: data, encoding: encoding) {
                return content
            }
        }

        throw NSError(
            domain: "ExcelError",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "CSV 编码无法识别，请尝试 UTF-8 或 UTF-16 编码后重新导入"]
        )
    }

    private func readXLSX(from url: URL) async throws -> [[String: String]] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssetManagerExcel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try unzipWorkbook(url, to: folder)
        let workbookRoot = folder.appendingPathComponent("xl", isDirectory: true)
        let sharedStrings = try parseSharedStrings(at: workbookRoot.appendingPathComponent("sharedStrings.xml"))
        let worksheetURL = try firstWorksheetURL(in: workbookRoot)
        let rows = try parseWorksheet(at: worksheetURL, sharedStrings: sharedStrings)
            .filter { row in
                !row.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }

        guard rows.count >= 2 else {
            throw NSError(
                domain: "ExcelError",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "文件至少需要包含表头和一行数据"]
            )
        }

        let headers = rows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var result: [[String: String]] = []

        for values in rows.dropFirst() {
            var row: [String: String] = [:]
            for (index, header) in headers.enumerated() where !header.isEmpty {
                row[header] = index < values.count ? values[index] : ""
            }
            result.append(row)
        }

        return result
    }

    private func unzipWorkbook(_ url: URL, to folder: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", "-o", url.path, "-d", folder.path]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "unzip exit \(process.terminationStatus)"
            throw NSError(
                domain: "ExcelError",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "Excel 解压失败: \(message)"]
            )
        }
    }

    private func firstWorksheetURL(in workbookRoot: URL) throws -> URL {
        let workbookURL = workbookRoot.appendingPathComponent("workbook.xml")
        let relsURL = workbookRoot.appendingPathComponent("_rels/workbook.xml.rels")

        guard FileManager.default.fileExists(atPath: workbookURL.path),
              FileManager.default.fileExists(atPath: relsURL.path) else {
            let fallback = workbookRoot.appendingPathComponent("worksheets/sheet1.xml")
            guard FileManager.default.fileExists(atPath: fallback.path) else {
                throw NSError(domain: "ExcelError", code: 10, userInfo: [NSLocalizedDescriptionKey: "没有找到可读取的工作表"])
            }
            return fallback
        }

        let workbookParser = WorkbookSheetParser()
        try parseXML(workbookURL, delegate: workbookParser)
        let relParser = WorkbookRelationshipParser()
        try parseXML(relsURL, delegate: relParser)

        if let firstSheetId = workbookParser.firstSheetRelationshipId,
           let target = relParser.worksheetTargets[firstSheetId] {
            let normalizedTarget = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/\(target)"
            let worksheetURL = workbookRoot.deletingLastPathComponent().appendingPathComponent(normalizedTarget)
            if FileManager.default.fileExists(atPath: worksheetURL.path) {
                return worksheetURL
            }
        }

        let fallback = workbookRoot.appendingPathComponent("worksheets/sheet1.xml")
        guard FileManager.default.fileExists(atPath: fallback.path) else {
            throw NSError(domain: "ExcelError", code: 11, userInfo: [NSLocalizedDescriptionKey: "没有找到可读取的工作表"])
        }
        return fallback
    }

    private func parseSharedStrings(at url: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let parser = SharedStringParser()
        try parseXML(url, delegate: parser)
        return parser.values
    }

    private func parseWorksheet(at url: URL, sharedStrings: [String]) throws -> [[String]] {
        let parser = WorksheetValueParser(sharedStrings: sharedStrings)
        try parseXML(url, delegate: parser)
        return parser.rows
    }

    private func parseXML(_ url: URL, delegate: XMLParserDelegate) throws {
        guard let parser = XMLParser(contentsOf: url) else {
            throw NSError(domain: "ExcelError", code: 12, userInfo: [NSLocalizedDescriptionKey: "无法读取 \(url.lastPathComponent)"])
        }
        parser.delegate = delegate
        guard parser.parse() else {
            throw NSError(
                domain: "ExcelError",
                code: 13,
                userInfo: [NSLocalizedDescriptionKey: parser.parserError?.localizedDescription ?? "解析 \(url.lastPathComponent) 失败"]
            )
        }
    }

    func exportAssets(_ assets: [macOS_Asset], to url: URL) async throws {
        let rows = [
            ["外编号", "名称", "型号", "品牌", "一级状态", "内编号", "一级存放地", "采购日期", "备注"]
        ] + assets.map { asset in
            [
                asset.id, asset.assetName, asset.modelName, asset.brand,
                asset.status.rawValue, asset.internalCode, asset.location,
                asset.purchaseDate?.toString() ?? "", asset.note ?? ""
            ]
        }
        let csv = CSVService.encode(rows: rows)
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    func exportRecords(_ records: [macOS_OperationRecord], to url: URL) async throws {
        let rows = [
            ["id", "外编号", "名称", "类型", "操作人", "时间", "备注", "预计归还时间"]
        ] + records.map { record in
            [
                record.id.uuidString, record.assetId, record.assetName,
                record.type.rawValue, record.operatorName,
                record.timestamp.toString(), record.note ?? "",
                record.estimatedReturnDate?.toString() ?? ""
            ]
        }
        let csv = CSVService.encode(rows: rows)
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }
}

extension Date {
    func toString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: self)
    }
}

private final class SharedStringParser: NSObject, XMLParserDelegate {
    var values: [String] = []
    private var inItem = false
    private var inText = false
    private var current = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "si" {
            inItem = true
            current = ""
        } else if inItem && elementName == "t" {
            inText = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" {
            inText = false
        } else if elementName == "si" {
            values.append(current)
            inItem = false
        }
    }
}

private final class WorksheetValueParser: NSObject, XMLParserDelegate {
    var rows: [[String]] = []

    private let sharedStrings: [String]
    private var currentRowIndex: Int?
    private var rowValues: [Int: String] = [:]
    private var currentColumnIndex: Int?
    private var currentCellType: String?
    private var currentValue = ""
    private var capturingValue = false
    private var maxColumnCount = 0

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "row" {
            currentRowIndex = Int(attributeDict["r"] ?? "")
            rowValues = [:]
        } else if elementName == "c",
                  let ref = attributeDict["r"],
                  let address = CellAddress(ref) {
            currentColumnIndex = address.column - 1
            currentCellType = attributeDict["t"]
            currentValue = ""
        } else if currentColumnIndex != nil && (elementName == "v" || elementName == "t") {
            capturingValue = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingValue { currentValue += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "v" || elementName == "t" {
            capturingValue = false
        } else if elementName == "c" {
            if let currentColumnIndex {
                rowValues[currentColumnIndex] = resolvedValue(currentValue, type: currentCellType)
            }
            currentColumnIndex = nil
            currentCellType = nil
            currentValue = ""
        } else if elementName == "row" {
            if !rowValues.isEmpty {
                let columnCount = (rowValues.keys.max() ?? -1) + 1
                maxColumnCount = max(maxColumnCount, columnCount)
                var row: [String] = []
                for index in 0..<columnCount {
                    row.append(rowValues[index] ?? "")
                }
                rows.append(row)
            }
            currentRowIndex = nil
            rowValues = [:]
        }
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        guard maxColumnCount > 0 else { return }
        for index in rows.indices {
            while rows[index].count < maxColumnCount {
                rows[index].append("")
            }
        }
    }

    private func resolvedValue(_ raw: String, type: String?) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if type == "s", let index = Int(trimmed), sharedStrings.indices.contains(index) {
            return sharedStrings[index]
        }
        if let number = Double(trimmed), number.rounded() == number {
            return String(Int(number))
        }
        return trimmed
    }
}

private final class WorkbookSheetParser: NSObject, XMLParserDelegate {
    var firstSheetRelationshipId: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "sheet", firstSheetRelationshipId == nil else { return }
        firstSheetRelationshipId = attributeDict["r:id"] ?? attributeDict["id"]
    }
}

private final class WorkbookRelationshipParser: NSObject, XMLParserDelegate {
    var worksheetTargets: [String: String] = [:]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "Relationship",
              let id = attributeDict["Id"],
              let type = attributeDict["Type"],
              let target = attributeDict["Target"],
              type.contains("/worksheet") else { return }
        worksheetTargets[id] = target
    }
}

private struct CellAddress {
    let column: Int
    let row: Int

    init?(_ ref: String) {
        let letters = ref.prefix { $0.isLetter }
        let numbers = ref.drop { $0.isLetter }
        guard !letters.isEmpty, let row = Int(numbers) else { return nil }
        self.column = letters.reduce(0) { result, char in
            let scalar = char.unicodeScalars.first?.value ?? 64
            return result * 26 + Int(scalar - 64)
        }
        self.row = row
    }
}
