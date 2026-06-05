import Foundation

// macOS 版本的资产模型 - 独立定义避免冲突

enum macOS_AssetStatus: String, Codable, CaseIterable {
    case inStock = "在库"
    case checkedOut = "已出库"
    case maintenance = "送修"
    case scrapped = "待报废"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self.fromStoredValue(try container.decode(String.self))
    }
    
    var displayName: String {
        switch self {
        case .inStock: return "在库"
        case .checkedOut: return "已出库"
        case .maintenance: return "送修"
        case .scrapped: return "待报废"
        }
    }

    static func fromStoredValue(_ rawValue: String) -> Self {
        switch rawValue {
        case macOS_AssetStatus.inStock.rawValue:
            return .inStock
        case macOS_AssetStatus.checkedOut.rawValue:
            return .checkedOut
        case "维修中", macOS_AssetStatus.maintenance.rawValue:
            return .maintenance
        case macOS_AssetStatus.scrapped.rawValue:
            return .scrapped
        default:
            return .inStock
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
    let assetIds: [String]
    let assetImportKeys: [String: String]
    
    init(
        id: UUID = UUID(),
        fileName: String,
        importDate: Date = Date(),
        assetCount: Int,
        assetIds: [String] = [],
        assetImportKeys: [String: String] = [:]
    ) {
        self.id = id
        self.fileName = fileName
        self.importDate = importDate
        self.assetCount = assetCount
        self.assetIds = assetIds
        self.assetImportKeys = assetImportKeys
    }

    enum CodingKeys: String, CodingKey {
        case id, fileName, importDate, assetCount, assetIds, assetImportKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        importDate = try container.decode(Date.self, forKey: .importDate)
        assetCount = try container.decode(Int.self, forKey: .assetCount)
        assetIds = try container.decodeIfPresent([String].self, forKey: .assetIds) ?? []
        assetImportKeys = try container.decodeIfPresent([String: String].self, forKey: .assetImportKeys) ?? [:]
    }
}
