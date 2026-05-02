import Foundation

// macOS 版本的资产模型 - 独立定义避免冲突

enum macOS_AssetStatus: String, Codable, CaseIterable {
    case inStock = "在库"
    case checkedOut = "已出库"
    case maintenance = "维修中"
    
    var displayName: String {
        switch self {
        case .inStock: return "在库"
        case .checkedOut: return "已出库"
        case .maintenance: return "维修中"
        }
    }
}

struct macOS_Asset: Codable, Identifiable, Hashable {
    var id: String
    var assetName: String
    var modelName: String
    var brand: String
    var status: macOS_AssetStatus
    var internalCode: String
    var location: String
    var purchaseDate: Date?
    var note: String?
    var lastUpdated: Date
    var sourceId: UUID?
    
    init(id: String, assetName: String, modelName: String, brand: String,
         status: macOS_AssetStatus, internalCode: String, location: String,
         purchaseDate: Date? = nil, note: String? = nil,
         lastUpdated: Date = Date(), sourceId: UUID? = nil) {
        self.id = id
        self.assetName = assetName
        self.modelName = modelName
        self.brand = brand
        self.status = status
        self.internalCode = internalCode
        self.location = location
        self.purchaseDate = purchaseDate
        self.note = note
        self.lastUpdated = lastUpdated
        self.sourceId = sourceId
    }
}

struct macOS_AssetSource: Codable, Identifiable, Hashable {
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