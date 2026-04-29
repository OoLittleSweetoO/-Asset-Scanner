import Foundation

// MARK: - 资产来源
struct AssetSource: Codable, Identifiable, Hashable {
    let id: UUID
    let fileName: String
    let importDate: Date
    let assetCount: Int
    
    init(id: UUID = UUID(), fileName: String, importDate: Date = Date(), assetCount: Int) {
        self.id = id
        self.fileName = fileName
        self.importDate = importDate
        self.assetCount = assetCount
    }
}
