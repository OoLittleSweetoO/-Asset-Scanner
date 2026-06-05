import Foundation

// MARK: - macOS AssetManager 兼容模型
// 用于处理从 macOS AssetManager 导入的数据

enum MacOSAssetStatus: String, Codable {
    case inStock = "在库"
    case checkedOut = "已出库"
    case maintenance = "送修"
    case scrapped = "待报废"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self.fromStoredValue(try container.decode(String.self))
    }

    static func fromStoredValue(_ rawValue: String) -> Self {
        switch rawValue {
        case MacOSAssetStatus.inStock.rawValue:
            return .inStock
        case MacOSAssetStatus.checkedOut.rawValue:
            return .checkedOut
        case "维修中", MacOSAssetStatus.maintenance.rawValue:
            return .maintenance
        case MacOSAssetStatus.scrapped.rawValue:
            return .scrapped
        default:
            return .inStock
        }
    }
}

enum MacOSOperationType: String, Codable {
    case checkIn = "入库"
    case checkOut = "出库"
    case repair = "送修"
    case scrap = "报废"
}

// MARK: - macOS Asset 模型
struct MacOSAsset: Codable {
    let id: String              // 外编号
    let assetName: String       // 名称
    let modelName: String       // 型号
    let brand: String           // 品牌
    let status: MacOSAssetStatus // 一级状态
    let internalCode: String    // 内编号
    let location: String        // 一级存放地
    let purchaseDate: Date?     // 采购日期
    let note: String?           // 备注
    let lastUpdated: Date       // 最后更新
    let sourceId: UUID?         // 来源ID
    
    enum CodingKeys: String, CodingKey {
        case id
        case assetName
        case modelName
        case brand
        case status
        case internalCode
        case location
        case purchaseDate
        case note
        case lastUpdated
        case sourceId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        assetName = try container.decode(String.self, forKey: .assetName)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName) ?? ""
        brand = try container.decodeIfPresent(String.self, forKey: .brand) ?? ""
        
        // 状态可能是中文字符串
        let statusStr = try container.decodeIfPresent(String.self, forKey: .status) ?? "在库"
        status = MacOSAssetStatus.fromStoredValue(statusStr)
        
        internalCode = try container.decodeIfPresent(String.self, forKey: .internalCode) ?? ""
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        
        // 处理采购日期 - 支持字符串和时间戳格式
        if let purchaseTimestamp = try? container.decode(Double.self, forKey: .purchaseDate) {
            purchaseDate = Date(timeIntervalSince1970: purchaseTimestamp)
        } else if let purchaseDateString = try? container.decode(String.self, forKey: .purchaseDate) {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: purchaseDateString) {
                purchaseDate = date
            } else {
                purchaseDate = nil
            }
        } else {
            purchaseDate = nil
        }
        
        note = try container.decodeIfPresent(String.self, forKey: .note)
        sourceId = try container.decodeIfPresent(UUID.self, forKey: .sourceId)
        
        // lastUpdated 可能是时间戳（Double）或 ISO8601 字符串
        if let timestamp = try? container.decode(Double.self, forKey: .lastUpdated) {
            lastUpdated = Date(timeIntervalSince1970: timestamp)
        } else {
            let dateString = try container.decode(String.self, forKey: .lastUpdated)
            let formatter = ISO8601DateFormatter()
            lastUpdated = formatter.date(from: dateString) ?? Date()
        }
    }
}

// MARK: - macOS 操作记录模型
struct MacOSOperationRecord: Codable {
    let id: UUID
    let assetId: String         // 外编号
    let assetName: String       // 名称
    let type: MacOSOperationType // 类型
    let operatorName: String    // 操作人
    let note: String?           // 备注
    let estimatedReturnDate: Date? // 预计归还时间
    let timestamp: Date         // 时间
    let isSyncedToReminders: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case assetId
        case assetName
        case type
        case operatorName
        case note
        case estimatedReturnDate
        case timestamp
        case isSyncedToReminders
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        assetId = try container.decode(String.self, forKey: .assetId)
        assetName = try container.decode(String.self, forKey: .assetName)
        
        // 类型可能是中文字符串
        let typeStr = try container.decodeIfPresent(String.self, forKey: .type) ?? "出库"
        type = MacOSOperationType(rawValue: typeStr) ?? .checkOut
        
        operatorName = try container.decode(String.self, forKey: .operatorName)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        
        // 处理预计归还日期 - 支持字符串和时间戳格式
        if let estimatedReturnDateString = try? container.decode(String.self, forKey: .estimatedReturnDate) {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: estimatedReturnDateString) {
                estimatedReturnDate = date
            } else {
                let altFormatter = DateFormatter()
                altFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                estimatedReturnDate = altFormatter.date(from: estimatedReturnDateString)
            }
        } else if let estimatedReturnTimestamp = try? container.decode(Double.self, forKey: .estimatedReturnDate) {
            estimatedReturnDate = Date(timeIntervalSince1970: estimatedReturnTimestamp)
        } else {
            estimatedReturnDate = nil
        }
        
        // 处理时间戳 - 支持字符串和时间戳格式
        if let timestampString = try? container.decode(String.self, forKey: .timestamp) {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: timestampString) {
                timestamp = date
            } else {
                let altFormatter = DateFormatter()
                altFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                if let altDate = altFormatter.date(from: timestampString) {
                    timestamp = altDate
                } else {
                    timestamp = Date() // 默认为当前时间
                }
            }
        } else if let timestampValue = try? container.decode(Double.self, forKey: .timestamp) {
            timestamp = Date(timeIntervalSince1970: timestampValue)
        } else {
            timestamp = Date() // 默认为当前时间
        }
        
        isSyncedToReminders = try container.decodeIfPresent(Bool.self, forKey: .isSyncedToReminders) ?? false
    }
}

// MARK: - macOS 资产来源模型
struct MacOSAssetSource: Codable {
    let id: UUID
    let fileName: String
    let importDate: Date
    let assetCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case importDate
        case assetCount
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        
        // 处理导入日期 - 支持字符串和时间戳格式
        if let importDateString = try? container.decode(String.self, forKey: .importDate) {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: importDateString) {
                importDate = date
            } else {
                let altFormatter = DateFormatter()
                altFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                if let altDate = altFormatter.date(from: importDateString) {
                    importDate = altDate
                } else {
                    importDate = Date() // 默认为当前时间
                }
            }
        } else if let importTimestamp = try? container.decode(Double.self, forKey: .importDate) {
            importDate = Date(timeIntervalSince1970: importTimestamp)
        } else {
            importDate = Date() // 默认为当前时间
        }
        
        assetCount = try container.decode(Int.self, forKey: .assetCount)
    }
}
