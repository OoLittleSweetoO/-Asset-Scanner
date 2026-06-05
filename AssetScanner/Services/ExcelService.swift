import Foundation
import Compression
import CoreFoundation

import UniformTypeIdentifiers

/// Excel 文件服务
class ExcelService: ObservableObject {
    
    /// 读取 Excel 文件（支持 CSV 和 XLSX 格式）
    func readExcel(from url: URL) async throws -> [[String: String]] {
        let fileExtension = url.pathExtension.lowercased()
        
        if fileExtension == "csv" {
            return try await readCSV(from: url)
        } else if fileExtension == "xlsx" {
            return try await readXLSX(from: url)
        } else {
            throw ExcelError.unsupportedFormat("不支持的文件格式: \(fileExtension)")
        }
    }
    
    /// 读取 CSV 文件
    private func readCSV(from url: URL) async throws -> [[String: String]] {
        let content = try readCSVContent(from: url)
        let parsedRows = parseCSVRows(content)
            .filter { row in
                !row.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
        
        guard parsedRows.count >= 2 else {
            throw ExcelError.invalidFormat("文件至少需要包含表头和一行数据")
        }
        
        // 解析表头
        let headers = parsedRows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // 解析数据行
        var result: [[String: String]] = []
        for values in parsedRows.dropFirst() {
            var row: [String: String] = [:]
            for (index, header) in headers.enumerated() where !header.isEmpty {
                row[header] = index < values.count ? values[index] : ""
            }
            result.append(row)
        }
        
        return result
    }

    private func readCSVContent(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let encodings: [String.Encoding] = [
            .utf8,
            .unicode,
            .utf16LittleEndian,
            .utf16BigEndian
        ]

        for encoding in encodings {
            if let content = String(data: data, encoding: encoding) {
                return content
            }
        }

        let cfEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        if let content = String(data: data, encoding: String.Encoding(rawValue: cfEncoding)) {
            return content
        }

        throw ExcelError.invalidFormat("无法识别 CSV 编码，请将文件保存为 UTF-8、UTF-16 或 GB18030")
    }
    
    /// 读取 XLSX 文件 (ZIP + XML 解析)
    private func readXLSX(from url: URL) async throws -> [[String: String]] {
        let zipData = try Data(contentsOf: url)
        
        // 解压 ZIP 文件
        let files = try extractZipFiles(from: zipData)
        
        // 读取 sharedStrings.xml
        guard let sharedStringsData = files["xl/sharedStrings.xml"] else {
            throw ExcelError.unsupportedFormat("XLSX 文件缺少 sharedStrings.xml")
        }
        let sharedStrings = try extractSharedStrings(from: sharedStringsData)
        
        // 读取 sheet1.xml
        guard let sheetData = files["xl/worksheets/sheet1.xml"] else {
            throw ExcelError.unsupportedFormat("XLSX 文件缺少 sheet1.xml")
        }
        
        // 解析单元格数据
        guard let sheetXML = String(data: sheetData, encoding: .utf8) else {
            throw ExcelError.unsupportedFormat("无法解析 sheet1.xml")
        }
        let rows = try parseXLSXSheet(sheetXML, sharedStrings: sharedStrings)
        
        guard rows.count >= 2 else {
            throw ExcelError.invalidFormat("文件至少需要包含表头和一行数据")
        }
        
        let headers = rows[0]
        var result: [[String: String]] = []
        for i in 1..<rows.count {
            let values = rows[i]
            var row: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                row[header] = index < values.count ? values[index] : ""
            }
            result.append(row)
        }
        
        return result
    }
    
    // MARK: - 简易 ZIP 解压
    
    private struct ZipEntry {
        let name: String
        let compressionMethod: UInt16
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let dataOffset: UInt32
        let compressedData: Data
    }
    
    private func extractZipFiles(from zipData: Data) throws -> [String: Data] {
        var files: [String: Data] = [:]
        _ = 0
        
        // 查找中央目录
        guard let centralDirOffset = findCentralDirectory(in: zipData) else {
            throw ExcelError.unsupportedFormat("无效的 ZIP 文件")
        }
        
        // 解析中央目录条目
        var cdOffset = Int(centralDirOffset)
        while cdOffset + 46 <= zipData.count {
            let signature = zipData.readUInt32(at: cdOffset)
            guard signature == 0x02014b50 else { break }
            
            let compressionMethod = zipData.readUInt16(at: cdOffset + 10)
            let compressedSize = zipData.readUInt32(at: cdOffset + 20)
            let uncompressedSize = zipData.readUInt32(at: cdOffset + 24)
            let fileNameLength = zipData.readUInt16(at: cdOffset + 28)
            let extraFieldLength = zipData.readUInt16(at: cdOffset + 30)
            let localHeaderOffset = zipData.readUInt32(at: cdOffset + 42)
            
            let fileName = zipData.readString(at: cdOffset + 46, length: Int(fileNameLength))
            
            if !fileName.isEmpty {
                let dataStart = Int(localHeaderOffset) + 30 + Int(zipData.readUInt16(at: Int(localHeaderOffset) + 26)) + Int(zipData.readUInt16(at: Int(localHeaderOffset) + 28))
                let compressedData = zipData.subdata(in: dataStart..<dataStart + Int(compressedSize))
                
                var fileData: Data
                if compressionMethod == 0 {
                    fileData = compressedData
                } else if compressionMethod == 8 {
                    fileData = try decompressDeflate(compressedData, outputSize: Int(uncompressedSize))
                } else {
                    let commentLen = zipData.readUInt16(at: cdOffset + 32)
                    cdOffset += 46 + Int(fileNameLength) + Int(extraFieldLength) + Int(commentLen)
                    continue
                }
                
                files[fileName] = fileData
            }
            
            let commentLen = zipData.readUInt16(at: cdOffset + 32)
            cdOffset += 46 + Int(fileNameLength) + Int(extraFieldLength) + Int(commentLen)
        }
        
        return files
    }
    
    private func findCentralDirectory(in data: Data) -> UInt32? {
        let searchStart = max(0, data.count - 65536)
        for i in (searchStart..<data.count - 22).reversed() {
            if data.readUInt32(at: i) == 0x06054b50 {
                return data.readUInt32(at: i + 16)
            }
        }
        return nil
    }
    
    private func decompressDeflate(_ data: Data, outputSize: Int) throws -> Data {
        var output = Data(count: outputSize)
        let compressedSize = data.count
        
        let result = output.withUnsafeMutableBytes { outputPtr in
            data.withUnsafeBytes { inputPtr in
                compression_decode_buffer(
                    outputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    outputSize,
                    inputPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    compressedSize,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        
        guard result > 0 else {
            throw ExcelError.unsupportedFormat("解压 XLSX 数据失败")
        }
        
        output.count = result
        return output
    }
    
    private func extractSharedStrings(from data: Data) throws -> [String] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var strings: [String] = []
        
        // 提取 <si> 中的 <t> 标签内容
        let pattern = "<si>(.*?)</si>"
        let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
        
        for match in matches {
            let siRange = Range(match.range(at: 1), in: xml)!
            let siContent = String(xml[siRange])
            // 提取 <t> 标签内容
            let tPattern = "<t[^>]*>([^<]*)</t>"
            let tRegex = try NSRegularExpression(pattern: tPattern)
            let tMatches = tRegex.matches(in: siContent, range: NSRange(siContent.startIndex..., in: siContent))
            var siText = ""
            for tMatch in tMatches {
                let tRange = Range(tMatch.range(at: 1), in: siContent)!
                siText += String(siContent[tRange])
            }
            strings.append(siText)
        }
        
        return strings
    }
    
    private func parseXLSXSheet(_ xml: String, sharedStrings: [String]) throws -> [[String]] {
        var rows: [[String]] = []
        var maxCols = 0
        
        // 提取所有 <row> 标签
        let rowPattern = "<row[^>]*>(.*?)</row>"
        let rowRegex = try NSRegularExpression(pattern: rowPattern, options: .dotMatchesLineSeparators)
        let rowMatches = rowRegex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
        
        for rowMatch in rowMatches {
            let rowRange = Range(rowMatch.range(at: 1), in: xml)!
            let rowContent = String(xml[rowRange])
            
            // 提取所有 <c> 标签
            let cellPattern = "(<c[^>]*r=\"([A-Z]+\\d+)\"[^>]*>(.*?)</c>)"
            let cellRegex = try NSRegularExpression(pattern: cellPattern, options: .dotMatchesLineSeparators)
            let cellMatches = cellRegex.matches(in: rowContent, range: NSRange(rowContent.startIndex..., in: rowContent))
            
            var cells: [Int: String] = [:]
            for cellMatch in cellMatches {
                let fullCell = Range(cellMatch.range(at: 1), in: rowContent)!
                let refRange = Range(cellMatch.range(at: 2), in: rowContent)!
                let ref = String(rowContent[refRange])
                let col = columnNumber(from: ref)
                
                let valRange = Range(cellMatch.range(at: 3), in: rowContent)!
                let valContent = String(rowContent[valRange])
                let fullCellStr = String(rowContent[fullCell])
                
                // 提取 <v> 标签内容
                let vPattern = "<v>([^<]*)</v>"
                let vRegex = try NSRegularExpression(pattern: vPattern)
                if let vMatch = vRegex.firstMatch(in: valContent, range: NSRange(valContent.startIndex..., in: valContent)) {
                    let vRange = Range(vMatch.range(at: 1), in: valContent)!
                    let vText = String(valContent[vRange])
                    
                    // 检查此单元格的 t 属性
                    if fullCellStr.contains("t=\"s\"") {
                        // 共享字符串
                        if let idx = Int(vText), idx < sharedStrings.count {
                            cells[col] = sharedStrings[idx]
                        }
                    } else {
                        cells[col] = vText
                    }
                }
            }
            
            if !cells.isEmpty {
                let colCount = cells.keys.max() ?? 0
                maxCols = max(maxCols, colCount)
                var rowValues: [String] = []
                for i in 0..<colCount {
                    rowValues.append(cells[i] ?? "")
                }
                rows.append(rowValues)
            }
        }
        
        // 补齐所有行的列数
        for i in 0..<rows.count {
            while rows[i].count < maxCols {
                rows[i].append("")
            }
        }
        
        return rows
    }
    
    private func columnNumber(from ref: String) -> Int {
        var result = 0
        for char in ref.prefix(while: { $0.isLetter }) {
            result = result * 26 + Int(char.asciiValue! - 65)
        }
        return result
    }
    
    /// 写入资产列表为 CSV 文件
    func writeAssets(_ assets: [Asset], to fileName: String) async throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        // CSV 表头
        var csv = "外编号,名称,型号,品牌,内编号,状态,存放位置,最后更新\n"
        
        // 数据行
        for asset in assets {
            let line = [
                asset.id,
                asset.assetName,
                asset.modelName,
                asset.brand,
                asset.internalCode,
                asset.status.rawValue,
                asset.location,
                dateFormatter.string(from: asset.lastUpdated)
            ].map { escapeCSV($0) }.joined(separator: ",")
            csv += line + "\n"
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(fileName).csv")
        try csv.write(to: fileURL, atomically: true, encoding: .utf8)
        
        return fileURL
    }
    
    /// 写入操作记录为 CSV 文件
    func writeOperationRecords(_ records: [OperationRecord], to fileName: String) async throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        // CSV 表头
        var csv = "时间,条码,资产名称,类型,操作人,备注,预计归还时间\n"
        
        // 数据行
        for record in records {
            let returnDateString = record.estimatedReturnDate.map { dateFormatter.string(from: $0) } ?? ""
            let line = [
                dateFormatter.string(from: record.timestamp),
                record.assetId,
                record.assetName,
                record.type.rawValue,
                record.`operator`,
                record.note ?? "",
                returnDateString
            ].map { escapeCSV($0) }.joined(separator: ",")
            csv += line + "\n"
        }
        
        // 保存到临时目录
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(fileName).csv")
        try csv.write(to: fileURL, atomically: true, encoding: .utf8)
        
        return fileURL
    }
    
    // MARK: - 私有方法
    
    private func parseCSVRows(_ content: String) -> [[String]] {
        let normalizedContent = normalizedCSVContent(content)
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        var index = normalizedContent.startIndex
        while index < normalizedContent.endIndex {
            let character = normalizedContent[index]

            if inQuotes {
                if character == "\"" {
                    let nextIndex = normalizedContent.index(after: index)
                    if nextIndex < normalizedContent.endIndex, normalizedContent[nextIndex] == "\"" {
                        currentField.append("\"")
                        index = nextIndex
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case ",":
                    currentRow.append(currentField)
                    currentField = ""
                case "\n":
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                case "\r":
                    break
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

    private func normalizedCSVContent(_ content: String) -> String {
        var normalized = content
        if normalized.hasPrefix("\u{feff}") {
            normalized.removeFirst()
        }
        normalized = normalized.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\r", with: "\n")
        return normalized
    }
    
    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

enum ExcelError: LocalizedError {
    case invalidFormat(String)
    case unsupportedFormat(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg):
            return msg
        case .unsupportedFormat(let msg):
            return msg
        }
    }
}

// MARK: - Data 扩展

extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        precondition(offset + 2 <= count)
        return withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: offset, as: UInt16.self)
        }
    }
    
    func readUInt32(at offset: Int) -> UInt32 {
        precondition(offset + 4 <= count)
        return withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: offset, as: UInt32.self)
        }
    }
    
    func readString(at offset: Int, length: Int) -> String {
        guard offset + length <= count else { return "" }
        let subdata = subdata(in: offset..<offset + length)
        return String(data: subdata, encoding: .utf8) ?? ""
    }
}
