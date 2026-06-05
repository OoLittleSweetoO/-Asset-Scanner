import Foundation
import Combine
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
class AssetViewModel: ObservableObject {
    // MARK: - 数据
    @Published var assets: [Asset] = []
    @Published var operationRecords: [OperationRecord] = []
    @Published var sources: [AssetSource] = []
    @Published var selectedAsset: Asset?
    
    // MARK: - 状态
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showImportSheet = false
    @Published var scannedAssetId: String?
    
    // 文件版 iCloud 同步相关
    @Published var selectedFolderURL: URL? { didSet { objectWillChange.send() } }
    @Published var syncStatus: String = "就绪"
    @Published var isSyncInProgress = false
    @Published var feishuConfigStatus: String = "未导入 AssetManager 配置"
    @Published var hasFeishuConfig = false
    @Published var importedFeishuAppID: String = ""
    @Published var importedFeishuAssetTableID: String = ""
    @Published var importedFeishuRecordTableID: String = ""
    
    private let barcodeService = BarcodeScannerService()
    private let excelService = ExcelService()
    private let storageService = StorageService()
    private let iosFeishuConfigStore = IOSFeishuConfigStore()
    
    // 文件版 iCloud 同步服务 (公开给视图访问)
    let fileBasedSyncService = FileBasediCloudSyncService()
    private var autoSyncTask: Task<Void, Never>?
    
    // Combine 订阅
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        Task { await loadFromStorage() }
        loadFeishuConfig()
        
        // 观察同步服务的 selectedFolderURL 变化
        fileBasedSyncService.$selectedFolderURL
            .receive(on: RunLoop.main)
            .assign(to: &$selectedFolderURL)

        fileBasedSyncService.$syncStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.syncStatus = status
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 扫码
    func processBarcode(_ code: String) {
        // 清理条码字符串
        let cleanedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 精确匹配
        if let asset = assets.first(where: { $0.id == cleanedCode }) {
            selectedAsset = asset
            scannedAssetId = asset.id
            return
        }
        
        // 模糊匹配（包含关系）
        if let asset = assets.first(where: { $0.id.contains(cleanedCode) || cleanedCode.contains($0.id) }) {
            selectedAsset = asset
            scannedAssetId = asset.id
            return
        }
        
        errorMessage = "未找到条码: \(cleanedCode)"
    }
    
    // MARK: - 入库
    func checkIn(asset: Asset, `operator`: String = "当前用户", note: String? = nil) {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        
        // 更新资产状态
        var updatedAsset = assets[index]
        updatedAsset.status = .inStock
        updatedAsset.lastUpdated = Date()
        assets[index] = updatedAsset
        
        // 记录操作
        let record = OperationRecord(
            assetId: asset.id,
            assetName: asset.assetName,
            type: .checkIn,
            operator: `operator`,
            note: note
        )
        operationRecords.insert(record, at: 0)
        
        saveToStorage()
    }
    
    // MARK: - 出库
    func checkOut(asset: Asset, `operator`: String = "当前用户", note: String? = nil, estimatedReturnDate: Date? = nil) {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        
        // 更新资产状态
        var updatedAsset = assets[index]
        updatedAsset.status = .checkedOut
        updatedAsset.lastUpdated = Date()
        assets[index] = updatedAsset
        
        // 记录操作
        let record = OperationRecord(
            assetId: asset.id,
            assetName: asset.assetName,
            type: .checkOut,
            operator: `operator`,
            note: note,
            estimatedReturnDate: estimatedReturnDate
        )
        operationRecords.insert(record, at: 0)
        
        saveToStorage()
    }

    // MARK: - 送修
    func markForMaintenance(asset: Asset, `operator`: String = "当前用户", note: String? = nil) {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        guard assets[index].status != .maintenance else { return }

        var updatedAsset = assets[index]
        updatedAsset.status = .maintenance
        updatedAsset.lastUpdated = Date()
        assets[index] = updatedAsset

        let record = OperationRecord(
            assetId: asset.id,
            assetName: asset.assetName,
            type: .repair,
            operator: `operator`,
            note: note
        )
        operationRecords.insert(record, at: 0)

        saveToStorage()
    }

    // MARK: - 删除设备
    func deleteAsset(_ asset: Asset) {
        deleteAssets(withIDs: Set([asset.id]))
    }

    func deleteAssets(withIDs ids: Set<String>) {
        guard !ids.isEmpty else { return }

        assets.removeAll { ids.contains($0.id) }
        operationRecords.removeAll { ids.contains($0.assetId) }
        sources = sources.compactMap { source in
            let remainingIDs = source.assetIds.filter { !ids.contains($0) }
            guard !remainingIDs.isEmpty else { return nil }
            return AssetSource(
                id: source.id,
                fileName: source.fileName,
                importDate: source.importDate,
                assetCount: remainingIDs.count,
                assetIds: remainingIDs
            )
        }

        saveToStorage()
        errorMessage = ids.count == 1 ? "已删除 1 个设备条目" : "已删除 \(ids.count) 个设备条目"
    }
    
    // MARK: - 删除操作记录
    func deleteRecord(at offsets: IndexSet) {
        operationRecords.remove(atOffsets: offsets)
        saveToStorage()
    }
    
    func deleteRecord(_ record: OperationRecord) {
        if let index = operationRecords.firstIndex(where: { $0.id == record.id }) {
            operationRecords.remove(at: index)
            saveToStorage()
        }
    }
    
    func updateRecordSyncStatus(_ recordId: UUID, isSynced: Bool) {
        if let index = operationRecords.firstIndex(where: { $0.id == recordId }) {
            var record = operationRecords[index]
            record.isSyncedToReminders = isSynced
            operationRecords[index] = record
            saveToStorage()
        }
    }
    
    // MARK: - 获取资产的最近出库记录
    func getRecentCheckOutRecords(for assetId: String, limit: Int = 5) -> [OperationRecord] {
        return operationRecords
            .filter { $0.assetId == assetId && $0.type == .checkOut }
            .prefix(limit)
            .map { $0 }
    }
    
    // MARK: - 获取资产来源信息
    func source(for asset: Asset) -> AssetSource? {
        guard let sourceId = asset.sourceId else { return nil }
        return sources.first(where: { $0.id == sourceId })
    }
    
    // MARK: - 获取指定来源的资产
    func assets(for sourceId: UUID) -> [Asset] {
        guard let source = sources.first(where: { $0.id == sourceId }) else {
            return assets.filter { $0.sourceId == sourceId }
        }
        let sourceAssetIDs = Set(source.assetIds)
        return assets.filter { $0.sourceId == sourceId || ($0.sourceId == nil && sourceAssetIDs.contains($0.id)) }
    }
    
    // MARK: - 导入 Excel
    func importAssets(from url: URL) async {
        isLoading = true
        defer { isLoading = false }
        
        // 获取安全作用域访问权限
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        
        do {
            let rows = try await excelService.readExcel(from: url)
            var newAssets: [Asset] = []
            
            let fileName = url.lastPathComponent
            if let existingSource = sources.first(where: { $0.fileName == fileName }) {
                let existingAssetIDs = Set(existingSource.assetIds)
                assets.removeAll { $0.sourceId == existingSource.id || ($0.sourceId == nil && existingAssetIDs.contains($0.id)) }
                sources.removeAll { $0.id == existingSource.id }
            }

            let source = AssetSource(fileName: fileName, assetCount: 0)
            var reservedIDs = Set(assets.map(\.id))
            
            for (rowIndex, row) in rows.enumerated() {
                if let asset = Asset(fromDict: row, sourceId: source.id) {
                    let resolvedID = makeImportAssetID(for: asset, row: row, rowIndex: rowIndex, reservedIDs: reservedIDs)
                    reservedIDs.insert(resolvedID)
                    newAssets.append(asset.withID(resolvedID))
                }
            }
            
            // 更新来源的资产数量
            let updatedSource = AssetSource(
                id: source.id,
                fileName: fileName,
                importDate: source.importDate,
                assetCount: newAssets.count,
                assetIds: newAssets.map(\.id)
            )
            
            assets.append(contentsOf: newAssets)
            sources.append(updatedSource)
            
            saveToStorage()
        } catch {
            errorMessage = String(format: L("error_import_failed"), error.localizedDescription)
        }
    }

    private func makeImportAssetID(for asset: Asset, row: [String: String], rowIndex: Int, reservedIDs: Set<String>) -> String {
        let barcode = asset.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let internalCode = (row["内编号"] ?? row["internalCode"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = asset.assetName.trimmingCharacters(in: .whitespacesAndNewlines)

        let baseID = [barcode, internalCode, name]
            .first(where: { !$0.isEmpty }) ?? "NO-CODE"

        if !reservedIDs.contains(baseID) {
            return baseID
        }

        var candidateIndex = max(rowIndex + 1, 2)
        while reservedIDs.contains("\(baseID)#\(candidateIndex)") {
            candidateIndex += 1
        }
        return "\(baseID)#\(candidateIndex)"
    }
    
    // MARK: - 删除来源及其资产
    func deleteSource(_ source: AssetSource) {
        let sourceAssetIDs = Set(source.assetIds)
        assets.removeAll { $0.sourceId == source.id || ($0.sourceId == nil && sourceAssetIDs.contains($0.id)) }
        sources.removeAll { $0.id == source.id }
        saveToStorage()
    }
    
    // MARK: - 导出资产列表
    func exportAssets() async -> URL? {
        do {
            return try await excelService.writeAssets(assets, to: L("asset_list_title"))
        } catch {
            errorMessage = String(format: L("error_export_failed"), error.localizedDescription)
            return nil
        }
    }
    
    // MARK: - 导出操作记录
    func exportRecords() async -> URL? {
        do {
            return try await excelService.writeOperationRecords(operationRecords, to: L("history_title"))
        } catch {
            errorMessage = String(format: L("error_export_failed"), error.localizedDescription)
            return nil
        }
    }
    
    // MARK: - 本地存储
    private func saveToStorage(syncRemote: Bool = true) {
        storageService.save(assets: assets, records: operationRecords, sources: sources)
        guard syncRemote else { return }
        scheduleAutoSyncToSharedFolder()
    }
    
    private func loadFromStorage() async {
        let (savedAssets, savedRecords, savedSources) = storageService.load()
        assets = savedAssets
        operationRecords = savedRecords
        sources = savedSources
    }
    
    // MARK: - 文件版 iCloud 同步
    
    func selectSyncFolder() {
        fileBasedSyncService.selectSyncFolder()
    }
    
    func syncToiCloud() async {
        guard fileBasedSyncService.selectedFolderURL != nil else { return }

        isSyncInProgress = true
        defer { isSyncInProgress = false }

        let success = await fileBasedSyncService.syncToiCloud(
            assets: assets,
            records: operationRecords,
            sources: sources
        )

        syncStatus = success ? "同步成功" : "同步失败"
    }
    
    func syncFromiCloud() async {
        guard fileBasedSyncService.selectedFolderURL != nil else { return }

        isSyncInProgress = true
        defer { isSyncInProgress = false }

        do {
            let result = try await fileBasedSyncService.syncFromiCloud()
            assets = result.0
            operationRecords = result.1
            sources = result.2
            saveToStorage(syncRemote: false)
            syncStatus = "导入成功"
        } catch {
            syncStatus = "导入失败：\(error.localizedDescription)"
        }
    }
    
    func bidirectionalSync() async {
        guard fileBasedSyncService.selectedFolderURL != nil else { return }

        isSyncInProgress = true
        defer { isSyncInProgress = false }

        do {
            let result = try await fileBasedSyncService.bidirectionalSync(
                localAssets: assets,
                localRecords: operationRecords,
                localSources: sources
            )

            assets = result.assets
            operationRecords = result.records
            sources = result.sources
            saveToStorage(syncRemote: false)
            syncStatus = "双向同步完成"
        } catch {
            syncStatus = "双向同步失败：\(error.localizedDescription)"
        }
    }

    func importAssetManagerFeishuConfig(from url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let configuration = try decoder.decode(AssetManagerConfigurationFile.self, from: data)

            iosFeishuConfigStore.save(
                .init(
                    appId: configuration.feishu.appId,
                    appSecret: configuration.feishu.appSecret,
                    assetAppToken: configuration.feishu.assetAppToken,
                    assetTableId: configuration.feishu.assetTableId,
                    recordAppToken: configuration.feishu.recordAppToken,
                    recordTableId: configuration.feishu.recordTableId
                )
            )
            loadFeishuConfig()
            errorMessage = "已导入 AssetManager 配置：\(url.lastPathComponent)"
        } catch {
            errorMessage = "导入 AssetManager 配置失败: \(error.localizedDescription)"
        }
    }

    private func loadFeishuConfig() {
        guard let config = iosFeishuConfigStore.load() else {
            hasFeishuConfig = false
            feishuConfigStatus = "未导入 AssetManager 配置"
            importedFeishuAppID = ""
            importedFeishuAssetTableID = ""
            importedFeishuRecordTableID = ""
            return
        }

        hasFeishuConfig = true
        importedFeishuAppID = config.appId
        importedFeishuAssetTableID = config.assetTableId
        importedFeishuRecordTableID = config.recordTableId
        feishuConfigStatus = "已导入飞书配置"
    }

    private func scheduleAutoSyncToSharedFolder() {
        guard fileBasedSyncService.selectedFolderURL != nil else { return }
        autoSyncTask?.cancel()
        autoSyncTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            await self.syncToiCloud()
        }
    }
}

private struct AssetManagerConfigurationFile: Codable {
    let version: Int
    let savedAt: Date
    let syncPath: String
    let syncBookmarkBase64: String?
    let feishu: AssetManagerFeishuConfiguration
}

private struct AssetManagerFeishuConfiguration: Codable {
    let appId: String
    let appSecret: String
    let assetAppToken: String
    let assetTableId: String
    let recordAppToken: String
    let recordTableId: String
}

private struct IOSImportedFeishuConfiguration: Codable {
    let appId: String
    let appSecret: String
    let assetAppToken: String
    let assetTableId: String
    let recordAppToken: String
    let recordTableId: String
}

private struct IOSFeishuConfigStore {
    private let storageKey = "ios_imported_feishu_config"

    func save(_ config: IOSImportedFeishuConfiguration) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(config) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func load() -> IOSImportedFeishuConfiguration? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(IOSImportedFeishuConfiguration.self, from: data)
    }
}
