import Foundation

// MARK: - 资产来源
struct AssetSource: Codable, Identifiable, Hashable {
    let id: UUID
    let fileName: String
    let importDate: Date
    let assetCount: Int
    let assetIds: [String]
    
    enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case importDate
        case assetCount
        case assetIds
        
        // 中文字段名（用于向后兼容）
        case chineseFileName = "文件名"
        case chineseImportDate = "导入日期"
        case chineseAssetCount = "资产数量"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 尝试解析英文字段，如果失败则尝试中文字段
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ??
                   container.decodeIfPresent(String.self, forKey: .chineseFileName) ?? ""
        importDate = try container.decodeIfPresent(Date.self, forKey: .importDate) ??
                     container.decodeIfPresent(Date.self, forKey: .chineseImportDate) ?? Date()
        assetCount = try container.decodeIfPresent(Int.self, forKey: .assetCount) ??
                     container.decodeIfPresent(Int.self, forKey: .chineseAssetCount) ?? 0
        assetIds = try container.decodeIfPresent([String].self, forKey: .assetIds) ?? []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(importDate, forKey: .importDate)
        try container.encode(assetCount, forKey: .assetCount)
        try container.encode(assetIds, forKey: .assetIds)
    }
    
    init(id: UUID = UUID(), fileName: String, importDate: Date = Date(), assetCount: Int, assetIds: [String] = []) {
        self.id = id
        self.fileName = fileName
        self.importDate = importDate
        self.assetCount = assetCount
        self.assetIds = assetIds
    }
}
