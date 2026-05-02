import Foundation
import Combine

@MainActor
class AssetViewModel: ObservableObject {
    @Published var assets: [macOS_Asset] = []
    @Published var operationRecords: [macOS_OperationRecord] = []
    @Published var sources: [macOS_AssetSource] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showImportSheet = false
    @Published var syncStatus: String = "未同步"
    var syncPath: String { syncService.syncPath }
    @Published var selectedAsset: macOS_Asset? = nil
    
    private let excelService = ExcelService()
    private let storageService = StorageService()
    let syncService: iCloudSyncService
    let remindersService = RemindersService()
    
    init() {
        self.syncService = iCloudSyncService()
        Task { await loadFromStorage() }
    }
    
    func checkIn(asset: macOS_Asset, operatorName: String = "当前用户", note: String? = nil) {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        
        var updated = assets[index]
        updated.status = .inStock
        updated.lastUpdated = Date()
        assets[index] = updated
        
        let record = macOS_OperationRecord(assetId: asset.id, assetName: asset.assetName, type: .checkIn, operatorName: operatorName, note: note)
        operationRecords.insert(record, at: 0)
        saveToStorage()
    }
    
    func checkOut(asset: macOS_Asset, operatorName: String = "当前用户", note: String? = nil, estimatedReturnDate: Date? = nil) {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        
        var updated = assets[index]
        updated.status = .checkedOut
        updated.lastUpdated = Date()
        assets[index] = updated
        
        let record = macOS_OperationRecord(assetId: asset.id, assetName: asset.assetName, type: .checkOut, operatorName: operatorName, note: note, estimatedReturnDate: estimatedReturnDate)
        operationRecords.insert(record, at: 0)
        saveToStorage()
    }
    
    func deleteRecord(_ record: macOS_OperationRecord) {
        if let index = operationRecords.firstIndex(where: { $0.id == record.id }) {
            operationRecords.remove(at: index)
            saveToStorage()
        }
    }
    
    func getRecentCheckOutRecords(for assetId: String, limit: Int = 5) -> [macOS_OperationRecord] {
        return operationRecords.filter { $0.assetId == assetId && $0.type == .checkOut }.prefix(limit).map { $0 }
    }
    
    func importAssets(from url: URL) async {
        isLoading = true
        defer { isLoading = false }
        
        print("📁 开始导入文件: \(url.path)")
        
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        
        print("🔒 文件访问权限: \(accessed)")
        
        do {
            let rows = try await excelService.readExcel(from: url)
            print("📊 解析到 \(rows.count) 行数据")
            
            var newAssets: [macOS_Asset] = []
            let sourceId = UUID()
            
            for row in rows {
                if var asset = createAsset(from: row) {
                    asset.sourceId = sourceId
                    print("✅ 创建资产: \(asset.id) - \(asset.assetName)")
                    newAssets.append(asset)
                } else {
                    print("❌ 创建资产失败，行数据: \(row)")
                }
            }
            
            if !newAssets.isEmpty {
                let source = macOS_AssetSource(id: sourceId, fileName: url.lastPathComponent, assetCount: newAssets.count)
                assets.append(contentsOf: newAssets)
                sources.append(source)
                saveToStorage()
                errorMessage = "导入成功：\(newAssets.count) 个资产"
            } else {
                errorMessage = "未解析到任何资产数据，请检查 CSV 格式"
            }
        } catch {
            errorMessage = "导入失败: \(error.localizedDescription)"
        }
    }
    
    func exportAssets() async -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("asset_list.csv")
        do { try await excelService.exportAssets(assets, to: url); return url }
        catch { errorMessage = "导出失败: \(error.localizedDescription)"; return nil }
    }
    
    func exportRecords() async -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("operation_records.csv")
        do { try await excelService.exportRecords(operationRecords, to: url); return url }
        catch { errorMessage = "导出失败: \(error.localizedDescription)"; return nil }
    }
    
    func importCSVFromICloud() {
        syncService.importCSVFromICloud(to: &assets)
        syncStatus = syncService.syncStatus
    }
    
    func saveCSVToICloud() {
        let csvContent = generateCSV(from: assets)
        syncService.saveCSVToICloud(csvContent: csvContent)
        syncStatus = syncService.syncStatus
    }
    
    // MARK: - 私有方法
    private func syncFromICloud() {
        syncService.syncFromICloud(to: &assets, records: &operationRecords, sources: &sources)
        syncStatus = syncService.syncStatus
    }
    
    private func loadFromStorage() async {
        let (savedAssets, savedRecords, savedSources) = storageService.load()
        assets = savedAssets
        operationRecords = savedRecords
        sources = savedSources
    }
    
    private func createAsset(from dict: [String: String]) -> macOS_Asset? {
        let barcode = dict["外编号"] ?? dict["条码"] ?? dict["barcode"] ?? ""
        guard !barcode.isEmpty else { return nil }
        
        let statusStr = dict["一级状态"] ?? dict["状态"] ?? dict["status"] ?? "在库"
        let status = macOS_AssetStatus(rawValue: statusStr) ?? .inStock
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let purchaseDate = (dict["采购日期"] ?? "").isEmpty ? nil : dateFormatter.date(from: dict["采购日期"] ?? "")
        
        return macOS_Asset(
            id: barcode,
            assetName: dict["名称"] ?? dict["name"] ?? "",
            modelName: dict["型号"] ?? dict["model"] ?? "",
            brand: dict["品牌"] ?? dict["brand"] ?? "",
            status: status,
            internalCode: dict["内编号"] ?? dict["internalCode"] ?? "",
            location: dict["一级存放地"] ?? dict["location"] ?? "",
            purchaseDate: purchaseDate,
            note: dict["备注"] ?? dict["note"],
            lastUpdated: Date()
        )
    }
    
    private func generateCSV(from assets: [macOS_Asset]) -> String {
        var csv = "外编号,名称,型号,品牌,一级状态,内编号,一级存放地,采购日期,备注\n"
        for asset in assets {
            let row = [
                asset.id, asset.assetName, asset.modelName, asset.brand,
                asset.status.rawValue, asset.internalCode, asset.location,
                asset.purchaseDate?.toString() ?? "", asset.note ?? ""
            ].map { $0.replacingOccurrences(of: ",", with: "\\,") }
            csv += row.joined(separator: ",") + "\n"
        }
        return csv
    }
    
    // MARK: - 公共方法
    func saveToStorage() {
        print("💾 [saveToStorage] 保存本地存储: assets=\(assets.count), records=\(operationRecords.count), sources=\(sources.count)")
        storageService.save(assets: assets, records: operationRecords, sources: sources)
        print("✅ [saveToStorage] 本地存储保存完成")
    }
    
    func syncToICloud() {
        print("🔄 [syncToICloud] 调用同步服务: assets=\(assets.count), records=\(operationRecords.count), sources=\(sources.count)")
        print("🔄 [syncToICloud] syncService.isICloudAvailable=\(syncService.isICloudAvailable), syncPath=\(syncService.syncPath)")
        syncService.syncToICloud(from: assets, records: operationRecords, sources: sources)
        syncStatus = syncService.syncStatus
        print("🔄 [syncToICloud] 同步完成, status=\(syncStatus)")
    }
    
    /// 从同步目录导入数据（拉取到本地，覆盖当前数据）
    func importFromSync() {
        syncService.syncFromICloud(to: &assets, records: &operationRecords, sources: &sources)
        saveToStorage()
        syncStatus = syncService.syncStatus + "（已导入）"
    }
    
    /// 导出当前数据到同步目录（推送本地数据）
    func exportToSync() {
        syncToICloud()
        syncStatus = syncService.syncStatus + "（已导出）"
    }
    
    /// 双向同步：比较本地与云端数据，保留较多的一方
    func bidirectionalSync() {
        syncService.syncBidirectional(assets: &assets, records: &operationRecords, sources: &sources)
        saveToStorage()
        syncStatus = syncService.syncStatus
    }
    
    func clearAllData() {
        print("🔥 清除所有数据")
        storageService.clearAllData()
        assets = []
        operationRecords = []
        sources = []
        errorMessage = "已清除所有数据"
        print("✅ 清除完成: assets=\(assets.count), records=\(operationRecords.count), sources=\(sources.count)")
    }
    
    func deleteSource(_ source: macOS_AssetSource) {
        print("🚨 开始删除导入源: \(source.fileName), ID: \(source.id)")
        print("📊 当前资产总数: \(assets.count)")
        
        let assetsBefore = assets.count
        assets.removeAll { asset in
            let matches = asset.sourceId == source.id
            if matches { print("🗑️ 删除资产: \(asset.id)") }
            return matches
        }
        let assetsRemoved = assetsBefore - assets.count
        
        sources.removeAll { $0.id == source.id }
        
        print("✅ 删除完成: 移除了 \(assetsRemoved) 个资产, 剩余 \(assets.count) 个")
        
        saveToStorage()
        errorMessage = "已删除导入源「\(source.fileName)」及其 \(assetsRemoved) 个资产"
    }
}