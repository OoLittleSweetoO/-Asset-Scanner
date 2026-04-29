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
struct OperationRecord: Codable, Identifiable {
    let id: UUID
    let assetId: String         // 关联资产条码
    let assetName: String       // 资产名称 (冗余，方便显示)
    let type: OperationType     // 类型
    let `operator`: String        // 操作人
    let timestamp: Date         // 时间
    let note: String?           // 备注
    let estimatedReturnDate: Date?  // 预计归还时间
    var isSyncedToReminders: Bool = false  // 是否已同步到提醒事项
    
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
}
