import Foundation

// MARK: - 资产状态
enum AssetStatus: String, Codable, CaseIterable {
    case inStock = "在库"
    case checkedOut = "已出库"
    case maintenance = "维修中"
    
    var displayName: String {
        switch self {
        case .inStock: return L("status_in_stock")
        case .checkedOut: return L("status_checked_out")
        case .maintenance: return L("status_maintenance")
        }
    }
}

// MARK: - 资产实体
struct Asset: Codable, Identifiable, Hashable {
    let id: String              // 外编号(条码) (唯一标识)
    let assetName: String       // 资产名称
    let modelName: String       // 型号
    let brand: String           // 品牌
    var status: AssetStatus     // 状态
    let internalCode: String    // 内编号
    let location: String        // 存放位置
    let purchaseDate: Date?     // 采购日期
    let note: String?           // 备注
    var lastUpdated: Date       // 最后更新时间
    let sourceId: UUID?         // 资产来源 ID
    
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
        
        // 中文字段名（用于向后兼容）
        case chineseId = "外编号"
        case chineseAssetName = "名称"
        case chineseModelName = "型号"
        case chineseBrand = "品牌"
        case chineseStatus = "一级状态"
        case chineseInternalCode = "内编号"
        case chineseLocation = "一级存放地"
        case chinesePurchaseDate = "采购日期"
        case chineseNote = "备注"
        case chineseLastUpdated = "最后更新"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 尝试解析英文字段，如果失败则尝试中文字段
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? 
             container.decodeIfPresent(String.self, forKey: .chineseId) ?? ""
        
        assetName = try container.decodeIfPresent(String.self, forKey: .assetName) ?? 
                    container.decodeIfPresent(String.self, forKey: .chineseAssetName) ?? ""
        
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName) ?? 
                    container.decodeIfPresent(String.self, forKey: .chineseModelName) ?? ""
        
        brand = try container.decodeIfPresent(String.self, forKey: .brand) ?? 
               container.decodeIfPresent(String.self, forKey: .chineseBrand) ?? ""
        
        let statusStr = try container.decodeIfPresent(String.self, forKey: .status) ?? 
                        container.decodeIfPresent(String.self, forKey: .chineseStatus) ?? "在库"
        status = AssetStatus(rawValue: statusStr) ?? .inStock
        
        internalCode = try container.decodeIfPresent(String.self, forKey: .internalCode) ?? 
                       container.decodeIfPresent(String.self, forKey: .chineseInternalCode) ?? ""
        
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? 
                   container.decodeIfPresent(String.self, forKey: .chineseLocation) ?? ""
        
        // 日期字段用 try? 避免自定义解码器抛错时 propagate
        purchaseDate = (try? container.decodeIfPresent(Date.self, forKey: .purchaseDate)) ?? 
                       (try? container.decodeIfPresent(Date.self, forKey: .chinesePurchaseDate))
        
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? 
               container.decodeIfPresent(String.self, forKey: .chineseNote)
        
        lastUpdated = (try? container.decodeIfPresent(Date.self, forKey: .lastUpdated)) ?? 
                      (try? container.decodeIfPresent(Date.self, forKey: .chineseLastUpdated)) ?? Date()
        
        sourceId = try container.decodeIfPresent(UUID.self, forKey: .sourceId)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(assetName, forKey: .assetName)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(brand, forKey: .brand)
        try container.encode(status, forKey: .status)
        try container.encode(internalCode, forKey: .internalCode)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(purchaseDate, forKey: .purchaseDate)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(lastUpdated, forKey: .lastUpdated)
        try container.encodeIfPresent(sourceId, forKey: .sourceId)
    }
    
    // 标准初始化方法
    init(id: String, assetName: String, modelName: String, brand: String, status: AssetStatus, internalCode: String, location: String, purchaseDate: Date?, note: String?, lastUpdated: Date, sourceId: UUID?) {
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
    
    // 从 Excel 行解析
    init?(fromDict: [String: String], sourceId: UUID? = nil) {
        // 支持多种列名映射
        let barcode = fromDict["外编号"] ?? fromDict["条码"] ?? fromDict["barcode"] ?? ""
        guard !barcode.isEmpty else { return nil }
        
        self.id = barcode
        self.assetName = fromDict["名称"] ?? fromDict["资产名称"] ?? fromDict["name"] ?? ""
        self.modelName = fromDict["型号"] ?? fromDict["model"] ?? ""
        self.brand = fromDict["品牌"] ?? fromDict["brand"] ?? ""
        
        let statusStr = fromDict["一级状态"] ?? fromDict["状态"] ?? fromDict["status"] ?? "在库"
        self.status = AssetStatus(rawValue: statusStr) ?? .inStock
        
        self.internalCode = fromDict["内编号"] ?? fromDict["internalCode"] ?? ""
        self.location = fromDict["一级存放地"] ?? fromDict["存放位置"] ?? fromDict["location"] ?? ""
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        self.purchaseDate = (fromDict["采购日期"] ?? fromDict["purchaseDate"] ?? "").isEmpty ? nil : dateFormatter.date(from: fromDict["采购日期"] ?? fromDict["purchaseDate"] ?? "")
        
        self.note = fromDict["备注"] ?? fromDict["note"]
        self.lastUpdated = Date()
        self.sourceId = sourceId
    }
}
