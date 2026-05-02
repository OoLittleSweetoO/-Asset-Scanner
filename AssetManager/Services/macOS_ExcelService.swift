import Foundation
import UniformTypeIdentifiers

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
        
        let content = try String(contentsOf: url, encoding: .utf8)
        print("✅ 读取成功，\(content.count) 字符")
        
        // 使用 components(separatedBy: .newlines) 过滤空行
        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        print("📊 行数: \(lines.count)")
        
        guard lines.count >= 2 else {
            throw NSError(domain: "ExcelError", code: 3, userInfo: [NSLocalizedDescriptionKey: "文件至少需要包含表头和一行数据"])
        }
        
        // 解析表头
        let headers = parseCSVLine(lines[0])
        print("📋 表头: \(headers)")
        
        // 解析数据行
        var rows: [[String: String]] = []
        for i in 1..<lines.count {
            let values = parseCSVLine(lines[i])
            if values.count == headers.count {
                var row: [String: String] = [:]
                for (index, header) in headers.enumerated() {
                    row[header] = values[index]
                }
                rows.append(row)
            }
            
            if i % 100 == 0 {
                print("➡️ 解析到第 \(i) 行...")
            }
        }
        
        print("✅ 总共解析 \(rows.count) 行数据")
        return rows
    }
    
    /// 解析 CSV 一行（处理引号分隔的字段）
    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var currentField = ""
        var inQuotes = false
        
        for char in line {
            if char == "\"" {
                inQuotes = !inQuotes
            } else if char == "," && !inQuotes {
                result.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        result.append(currentField.trimmingCharacters(in: .whitespaces))
        
        return result
    }
    
    private func readXLSX(from url: URL) async throws -> [[String: String]] {
        throw NSError(domain: "ExcelError", code: 2, userInfo: [NSLocalizedDescriptionKey: "XLSX 需要第三方库"])
    }
    
    func exportAssets(_ assets: [macOS_Asset], to url: URL) async throws {
        var csv = "外编号,名称,型号,品牌,一级状态,内编号,一级存放地,采购日期,备注\n"
        for asset in assets {
            let row = [
                asset.id, asset.assetName, asset.modelName, asset.brand,
                asset.status.rawValue, asset.internalCode, asset.location,
                asset.purchaseDate?.toString() ?? "", asset.note ?? ""
            ].map { $0.replacingOccurrences(of: ",", with: "\\,") }
            csv += row.joined(separator: ",") + "\n"
        }
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }
    
    func exportRecords(_ records: [macOS_OperationRecord], to url: URL) async throws {
        var csv = "id,外编号,名称,类型,操作人,时间,备注,预计归还时间\n"
        for record in records {
            let row = [
                record.id.uuidString, record.assetId, record.assetName,
                record.type.rawValue, record.operatorName,
                record.timestamp.toString(), record.note ?? "",
                record.estimatedReturnDate?.toString() ?? ""
            ]
            csv += row.joined(separator: ",") + "\n"
        }
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