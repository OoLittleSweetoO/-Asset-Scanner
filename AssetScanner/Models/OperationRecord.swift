import Foundation

// MARK: - 操作类型
enum OperationType: String, Codable, CaseIterable {
    case checkIn = "入库"
    case checkOut = "出库"

    var displayName: String {
        switch self {
        case .checkIn: return L("type_check_in")
        case .checkOut: return L("type_check_out")
        }
    }
}

// MARK: - 操作记录
struct OperationRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let assetId: String         // 关联资产条码
    let assetName: String       // 资产名称 (冗余,方便显示)
    let type: OperationType     // 类型
    let `operator`: String        // 操作人
    let timestamp: Date         // 时间
    let note: String?           // 备注
    let estimatedReturnDate: Date?  // 预计归还时间
    var isSyncedToReminders: Bool = false  // 是否已同步到提醒事项

    enum CodingKeys: String, CodingKey {
        case id
        case assetId
        case assetName
        case type
        case operatorName
        case timestamp
        case note
        case estimatedReturnDate
        case isSyncedToReminders

        // 旧版字段名(用于向后兼容)
        case oldOperator = "operator"
        case chineseAssetId = "外编号"
        case chineseAssetName = "名称"
        case chineseType = "类型"
        case chineseOperator = "操作人"
        case chineseTimestamp = "时间"
        case chineseNote = "备注"
        case chineseEstimatedReturnDate = "预计归还时间"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 尝试解析英文字段,如果失败则尝试中文字段
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        assetId = try container.decodeIfPresent(String.self, forKey: .assetId) ??
                  container.decodeIfPresent(String.self, forKey: .chineseAssetId) ?? ""
        assetName = try container.decodeIfPresent(String.self, forKey: .assetName) ??
                    container.decodeIfPresent(String.self, forKey: .chineseAssetName) ?? ""
        type = try container.decodeIfPresent(OperationType.self, forKey: .type) ??
               container.decodeIfPresent(OperationType.self, forKey: .chineseType) ?? .checkIn
        `operator` = try container.decodeIfPresent(String.self, forKey: .operatorName) ??
                     container.decodeIfPresent(String.self, forKey: .oldOperator) ??
                     container.decodeIfPresent(String.self, forKey: .chineseOperator) ?? L("current_user")
        
        // 日期字段用 try? 避免自定义解码器抛错时 propagate
        timestamp = (try? container.decodeIfPresent(Date.self, forKey: .timestamp)) ??
                    (try? container.decodeIfPresent(Date.self, forKey: .chineseTimestamp)) ?? Date()
        note = try container.decodeIfPresent(String.self, forKey: .note) ??
               container.decodeIfPresent(String.self, forKey: .chineseNote)
        estimatedReturnDate = (try? container.decodeIfPresent(Date.self, forKey: .estimatedReturnDate)) ??
                              (try? container.decodeIfPresent(Date.self, forKey: .chineseEstimatedReturnDate))
        isSyncedToReminders = try container.decodeIfPresent(Bool.self, forKey: .isSyncedToReminders) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(assetId, forKey: .assetId)
        try container.encode(assetName, forKey: .assetName)
        try container.encode(type, forKey: .type)
        try container.encode(`operator`, forKey: .operatorName)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(estimatedReturnDate, forKey: .estimatedReturnDate)
        try container.encode(isSyncedToReminders, forKey: .isSyncedToReminders)
    }
    
    init(
        id: UUID = UUID(),
        assetId: String,
        assetName: String,
        type: OperationType,
        `operator`: String = L("current_user"),
        timestamp: Date = Date(),
        note: String? = nil,
        estimatedReturnDate: Date? = nil,
        isSyncedToReminders: Bool = false
    ) {
        self.id = id
        self.assetId = assetId
        self.assetName = assetName
        self.type = type
        self.`operator` = `operator`
        self.timestamp = timestamp
        self.note = note
        self.estimatedReturnDate = estimatedReturnDate
        self.isSyncedToReminders = isSyncedToReminders
    }

    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func ==(lhs: OperationRecord, rhs: OperationRecord) -> Bool {
        lhs.id == rhs.id
    }
}
