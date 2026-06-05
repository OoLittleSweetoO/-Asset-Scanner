import Foundation
import UniformTypeIdentifiers
import CoreFoundation

/// Excel 文件服务 - macOS 版本
class ExcelService {
    
    func readExcel(from url: URL) async throws -> [[String: String]] {
        print("📖 开始读取 Excel/CSV 文件")
        let ext = url.pathExtension.lowercased()
        if ext == "csv" { return try await readCSV(from: url) }
        else if ext == "xlsx" { return try await readXLSX(from: url) }
        else { throw NSError(domain: "ExcelError", code: 1, userInfo: [NSLocalizedDescriptionKey: "不支持的格式"]) }
    }
    
    private func readCSV(from url: URL) async throws -> [[String: String]] {
        print("📄 读取 CSV 文件: \(url.lastPathComponent)")
        
        // 检查文件大小（限制 100MB）
        if let attrs = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let size = attrs.fileSize, size > 100 * 1024 * 1024 {
            throw NSError(domain: "ExcelError", code: 2, userInfo: [NSLocalizedDescriptionKey: "文件过大（\(size) 字节），最大支持 100MB"])
        }
        
        let content = try readCSVContent(from: url)
        print("✅ 读取成功，\(content.count) 字符")
        
        let rows = CSVService.parse(content)
        let nonEmptyRows = rows.filter { row in
            !row.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        print("📊 行数: \(nonEmptyRows.count)")

        guard nonEmptyRows.count >= 2 else {
            throw NSError(domain: "ExcelError", code: 3, userInfo: [NSLocalizedDescriptionKey: "文件至少需要包含表头和一行数据"])
        }

        let headers = nonEmptyRows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        print("📋 表头: \(headers)")

        var parsedRows: [[String: String]] = []
        for i in 1..<nonEmptyRows.count {
            let values = nonEmptyRows[i]
            if values.count == headers.count {
                var row: [String: String] = [:]
                for (index, header) in headers.enumerated() {
                    row[header] = values[index]
                }
                parsedRows.append(row)
            }
            
            if i % 100 == 0 {
                print("➡️ 解析到第 \(i) 行...")
            }
        }

        print("✅ 总共解析 \(parsedRows.count) 行数据")
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
        throw NSError(domain: "ExcelError", code: 2, userInfo: [NSLocalizedDescriptionKey: "XLSX 需要第三方库"])
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
