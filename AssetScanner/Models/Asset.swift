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
        case id = "外编号"
        case assetName = "名称"
        case modelName = "型号"
        case brand = "品牌"
        case status = "一级状态"
        case internalCode = "内编号"
        case location = "一级存放地"
        case purchaseDate = "采购日期"
        case note = "备注"
        case lastUpdated = "最后更新"
        case sourceId
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
