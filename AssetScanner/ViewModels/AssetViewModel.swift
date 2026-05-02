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
    
    private let barcodeService = BarcodeScannerService()
    private let excelService = ExcelService()
    private let storageService = StorageService()
    
    // 文件版 iCloud 同步服务 (公开给视图访问)
    let fileBasedSyncService = FileBasediCloudSyncService()
    
    // Combine 订阅
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        Task { await loadFromStorage() }
        
        // 观察同步服务的 selectedFolderURL 变化
        fileBasedSyncService.$selectedFolderURL
            .receive(on: RunLoop.main)
            .assign(to: &$selectedFolderURL)
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
        assets.filter { $0.sourceId == sourceId }
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
            
            // 创建新的来源
            let fileName = url.lastPathComponent
            let source = AssetSource(fileName: fileName, assetCount: 0)
            
            for row in rows {
                if let asset = Asset(fromDict: row, sourceId: source.id) {
                    newAssets.append(asset)
                }
            }
            
            // 更新来源的资产数量
            let updatedSource = AssetSource(
                id: source.id,
                fileName: fileName,
                importDate: source.importDate,
                assetCount: newAssets.count
            )
            
            // 追加资产（不覆盖已有资产）
            assets.append(contentsOf: newAssets)
            sources.append(updatedSource)
            
            saveToStorage()
        } catch {
            errorMessage = String(format: L("error_import_failed"), error.localizedDescription)
        }
    }
    
    // MARK: - 删除来源及其资产
    func deleteSource(_ source: AssetSource) {
        assets.removeAll { $0.sourceId == source.id }
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
    private func saveToStorage() {
        storageService.save(assets: assets, records: operationRecords, sources: sources)
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
            syncStatus = "双向同步完成"
        } catch {
            syncStatus = "双向同步失败：\(error.localizedDescription)"
        }
    }
}
