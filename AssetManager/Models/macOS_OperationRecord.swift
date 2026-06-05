import Foundation

struct macOS_OperationRecord: Codable, Identifiable {
    let id: UUID
    let assetId: String
    let assetName: String
    let type: macOS_OperationType
    let operatorName: String
    let timestamp: Date
    let note: String?
    let estimatedReturnDate: Date?
    var isSyncedToReminders: Bool = false
    
    init(
        id: UUID = UUID(),
        assetId: String,
        assetName: String,
        type: macOS_OperationType,
        operatorName: String = "当前用户",
        timestamp: Date = Date(),
        note: String? = nil,
        estimatedReturnDate: Date? = nil,
        isSyncedToReminders: Bool = false
    ) {
        self.id = id
        self.assetId = assetId
        self.assetName = assetName
        self.type = type
        self.operatorName = operatorName
        self.timestamp = timestamp
        self.note = note
        self.estimatedReturnDate = estimatedReturnDate
        self.isSyncedToReminders = isSyncedToReminders
    }
}

enum macOS_OperationType: String, Codable, CaseIterable {
    case checkIn = "入库"
    case checkOut = "出库"
    case repair = "送修"
    case scrap = "报废"
    
    var displayName: String {
        switch self {
        case .checkIn: return "入库"
        case .checkOut: return "出库"
        case .repair: return "送修"
        case .scrap: return "报废"
        }
    }
}
