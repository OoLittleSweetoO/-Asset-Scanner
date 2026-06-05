import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

struct SourceRemovedAssetPreview: Identifiable, Hashable {
    let id: String
    let assetName: String
    let externalCode: String
    let statusDisplayName: String
}

struct SourceUpdatePreview: Identifiable {
    let id = UUID()
    let source: macOS_AssetSource
    let replacementAssets: [macOS_Asset]
    let replacementImportKeys: [String: String]
    let removedAssetIDs: Set<String>
    let removedAssets: [SourceRemovedAssetPreview]
    let addedCount: Int
    let updatedCount: Int
}

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
    var checkedOutAssetCount: Int {
        assets.filter { $0.status == .checkedOut }.count
    }
    
    private let excelService = ExcelService()
    private let storageService = StorageService()
    var syncService: iCloudSyncService
    var remindersService = RemindersService()
    var feishuBitableService = FeishuBitableService()
    private var feishuAutoSyncTask: Task<Void, Never>?
    
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

    func markForMaintenance(asset: macOS_Asset) {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        guard assets[index].status != .maintenance else { return }

        var updated = assets[index]
        updated.status = .maintenance
        updated.lastUpdated = Date()
        assets[index] = updated

        let record = macOS_OperationRecord(
            assetId: asset.id,
            assetName: asset.assetName,
            type: .repair,
            operatorName: "当前用户"
        )
        operationRecords.insert(record, at: 0)
        saveToStorage()
    }

    func markAsScrapped(asset: macOS_Asset) {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        guard assets[index].status != .scrapped else { return }

        var updated = assets[index]
        updated.status = .scrapped
        updated.lastUpdated = Date()
        assets[index] = updated

        let record = macOS_OperationRecord(
            assetId: asset.id,
            assetName: asset.assetName,
            type: .scrap,
            operatorName: "当前用户"
        )
        operationRecords.insert(record, at: 0)
        saveToStorage()
    }

    func restoreToInStock(asset: macOS_Asset) {
        checkIn(asset: asset)
    }

    func checkOutAllInStockAssets(operatorName: String = "当前用户", note: String? = nil, estimatedReturnDate: Date? = nil) {
        let targetIndexes = assets.indices.filter { assets[$0].status == .inStock }
        guard !targetIndexes.isEmpty else { return }

        var newRecords: [macOS_OperationRecord] = []

        for index in targetIndexes {
            assets[index].status = .checkedOut
            assets[index].lastUpdated = Date()

            let asset = assets[index]
            let record = macOS_OperationRecord(
                assetId: asset.id,
                assetName: asset.assetName,
                type: .checkOut,
                operatorName: operatorName,
                note: note,
                estimatedReturnDate: estimatedReturnDate
            )
            newRecords.append(record)
        }

        operationRecords.insert(contentsOf: newRecords.reversed(), at: 0)
        saveToStorage()
    }
    
    func deleteRecord(_ record: macOS_OperationRecord) {
        if let index = operationRecords.firstIndex(where: { $0.id == record.id }) {
            operationRecords.remove(at: index)
            saveToStorage()
        }
    }

    func deleteRecords(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        operationRecords.removeAll { ids.contains($0.id) }
        saveToStorage()
    }

    func updateRecord(
        _ recordID: UUID,
        operatorName: String,
        note: String?,
        estimatedReturnDate: Date?
    ) {
        guard let index = operationRecords.firstIndex(where: { $0.id == recordID }) else { return }

        let existing = operationRecords[index]
        operationRecords[index] = macOS_OperationRecord(
            id: existing.id,
            assetId: existing.assetId,
            assetName: existing.assetName,
            type: existing.type,
            operatorName: operatorName,
            timestamp: existing.timestamp,
            note: note,
            estimatedReturnDate: existing.type == .checkOut ? estimatedReturnDate : nil,
            isSyncedToReminders: existing.isSyncedToReminders
        )
        saveToStorage()
    }

    func clearOperationRecords() {
        guard !operationRecords.isEmpty else { return }
        operationRecords.removeAll()
        saveToStorage()
    }

    func updateAssets(
        withIDs ids: Set<String>,
        to status: macOS_AssetStatus,
        operatorName: String = "当前用户",
        note: String? = nil,
        estimatedReturnDate: Date? = nil
    ) {
        guard !ids.isEmpty else { return }
        let targetIndexes = assets.indices.filter { ids.contains(assets[$0].id) }
        guard !targetIndexes.isEmpty else { return }

        let timestamp = Date()
        var newRecords: [macOS_OperationRecord] = []

        for index in targetIndexes {
            guard assets[index].status != status else { continue }

            assets[index].status = status
            assets[index].lastUpdated = timestamp

            let asset = assets[index]
            let recordType: macOS_OperationType
            switch status {
            case .inStock:
                recordType = .checkIn
            case .checkedOut:
                recordType = .checkOut
            case .maintenance:
                recordType = .repair
            case .scrapped:
                recordType = .scrap
            }

            newRecords.append(
                macOS_OperationRecord(
                    assetId: asset.id,
                    assetName: asset.assetName,
                    type: recordType,
                    operatorName: operatorName,
                    timestamp: timestamp,
                    note: note,
                    estimatedReturnDate: status == .checkedOut ? estimatedReturnDate : nil
                )
            )
        }

        guard !newRecords.isEmpty else { return }
        operationRecords.insert(contentsOf: newRecords.reversed(), at: 0)
        saveToStorage()
    }

    func deleteAsset(_ asset: macOS_Asset) {
        deleteAssets(withIDs: Set([asset.id]))
    }

    func deleteAssets(withIDs ids: Set<String>) {
        guard !ids.isEmpty else { return }

        assets.removeAll { ids.contains($0.id) }
        operationRecords.removeAll { ids.contains($0.assetId) }
        sources = sources.compactMap { source in
            let remainingIDs = source.assetIds.filter { !ids.contains($0) }
            guard !remainingIDs.isEmpty else { return nil }
            return macOS_AssetSource(
                id: source.id,
                fileName: source.fileName,
                importDate: source.importDate,
                assetCount: remainingIDs.count,
                assetIds: remainingIDs,
                assetImportKeys: source.assetImportKeys.filter { remainingIDs.contains($0.key) }
            )
        }

        saveToStorage()
        errorMessage = ids.count == 1 ? "已删除 1 个设备条目" : "已删除 \(ids.count) 个设备条目"
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
            var reservedIDs = Set(assets.map(\.id))
            var keyOccurrences: [String: Int] = [:]
            var importKeys: [String: String] = [:]
            
            for (rowIndex, row) in rows.enumerated() {
                if var asset = createAsset(from: row) {
                    let resolvedID = makeImportAssetID(for: asset, row: row, rowIndex: rowIndex, reservedIDs: reservedIDs)
                    reservedIDs.insert(resolvedID)
                    asset.id = resolvedID
                    asset.sourceId = sourceId
                    importKeys[resolvedID] = makeSourceComparisonKey(for: row, rowIndex: rowIndex, occurrences: &keyOccurrences)
                    print("✅ 创建资产: \(asset.id) - \(asset.assetName)")
                    newAssets.append(asset)
                } else {
                    print("❌ 创建资产失败，行数据: \(row)")
                }
            }
            
            if !newAssets.isEmpty {
                let source = macOS_AssetSource(
                    id: sourceId,
                    fileName: url.lastPathComponent,
                    assetCount: newAssets.count,
                    assetIds: newAssets.map(\.id),
                    assetImportKeys: importKeys
                )
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

    func prepareSourceUpdate(_ source: macOS_AssetSource, from url: URL) async -> SourceUpdatePreview? {
        isLoading = true
        defer { isLoading = false }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let rows = try await excelService.readExcel(from: url)
            let sourceAssetIDs = Set(source.assetIds)
            let ownedAssets = assets.filter { $0.sourceId == source.id || ($0.sourceId == nil && sourceAssetIDs.contains($0.id)) }
            let ownedByID = Dictionary(uniqueKeysWithValues: ownedAssets.map { ($0.id, $0) })
            let existingOwnedIDs = Set(ownedAssets.map(\.id))
            let existingByExternalCode = Dictionary(
                uniqueKeysWithValues: ownedAssets.compactMap { asset -> (String, String)? in
                    let normalized = normalizedImportValue(normalizedLegacyAssetID(asset.id))
                    guard let normalized else { return nil }
                    return (normalized, asset.id)
                }
            )

            var fallbackOccurrences: [String: Int] = [:]
            let existingPairs = source.assetIds.compactMap { assetID -> (String, String)? in
                guard let asset = ownedByID[assetID] else { return nil }
                let fallbackKey = fallbackComparisonKey(for: asset, occurrences: &fallbackOccurrences)
                let key = source.assetImportKeys[assetID] ?? fallbackKey
                return (key, assetID)
            }
            var existingAssetIDByKey = Dictionary(uniqueKeysWithValues: existingPairs)

            var replacementAssets: [macOS_Asset] = []
            var replacementImportKeys: [String: String] = [:]
            var reservedIDs = Set(assets.map(\.id)).subtracting(sourceAssetIDs)
            var keyOccurrences: [String: Int] = [:]
            var retainedAssetIDs = Set<String>()
            var addedCount = 0
            var updatedCount = 0

            for (rowIndex, row) in rows.enumerated() {
                guard var importedAsset = createAsset(from: row) else { continue }
                let externalCode = normalizedImportValue(row["外编号"] ?? row["条码"] ?? row["barcode"])

                if let externalCode,
                   let existingID = existingByExternalCode[externalCode],
                   let existingAsset = ownedByID[existingID],
                   !retainedAssetIDs.contains(existingID) {
                    reservedIDs.insert(existingAsset.id)
                    importedAsset.id = existingAsset.id
                    importedAsset.sourceId = source.id
                    importedAsset.status = existingAsset.status
                    importedAsset.lastUpdated = existingAsset.lastUpdated
                    replacementAssets.append(importedAsset)
                    replacementImportKeys[existingAsset.id] = makeSourceComparisonKey(for: row, rowIndex: rowIndex, occurrences: &keyOccurrences)
                    retainedAssetIDs.insert(existingAsset.id)
                    updatedCount += 1
                    continue
                }

                let comparisonKey = makeSourceComparisonKey(for: row, rowIndex: rowIndex, occurrences: &keyOccurrences)

                if let existingID = existingAssetIDByKey.removeValue(forKey: comparisonKey),
                   let existingAsset = ownedByID[existingID] {
                    reservedIDs.insert(existingAsset.id)
                    importedAsset.id = existingAsset.id
                    importedAsset.sourceId = source.id
                    importedAsset.status = existingAsset.status
                    importedAsset.lastUpdated = existingAsset.lastUpdated
                    replacementAssets.append(importedAsset)
                    replacementImportKeys[existingAsset.id] = comparisonKey
                    retainedAssetIDs.insert(existingAsset.id)
                    updatedCount += 1
                    continue
                }

                let resolvedID = makeImportAssetID(for: importedAsset, row: row, rowIndex: rowIndex, reservedIDs: reservedIDs)
                reservedIDs.insert(resolvedID)
                importedAsset.id = resolvedID
                importedAsset.sourceId = source.id
                replacementAssets.append(importedAsset)
                replacementImportKeys[resolvedID] = comparisonKey
                retainedAssetIDs.insert(resolvedID)
                addedCount += 1
            }

            let removedIDs = existingOwnedIDs.subtracting(retainedAssetIDs)
            let removableAssets = ownedAssets
                .filter { removedIDs.contains($0.id) }
            let removedAssets = removableAssets
                .map { asset in
                    SourceRemovedAssetPreview(
                        id: asset.id,
                        assetName: asset.assetName.isEmpty ? asset.id : asset.assetName,
                        externalCode: asset.id,
                        statusDisplayName: asset.status.displayName
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.assetName == rhs.assetName {
                        return lhs.externalCode < rhs.externalCode
                    }
                    return lhs.assetName < rhs.assetName
                }
            return SourceUpdatePreview(
                source: source,
                replacementAssets: replacementAssets,
                replacementImportKeys: replacementImportKeys,
                removedAssetIDs: removedIDs,
                removedAssets: removedAssets,
                addedCount: addedCount,
                updatedCount: updatedCount
            )
        } catch {
            errorMessage = "更新来源失败: \(error.localizedDescription)"
            return nil
        }
    }

    func applySourceUpdate(_ preview: SourceUpdatePreview) {
        let source = preview.source
        let sourceAssetIDs = Set(source.assetIds)
        let retainedAssetIDs = Set(preview.replacementAssets.map(\.id))

        assets.removeAll { asset in
            (asset.sourceId == source.id || (asset.sourceId == nil && sourceAssetIDs.contains(asset.id))) &&
            !retainedAssetIDs.contains(asset.id)
        }
        operationRecords.removeAll { preview.removedAssetIDs.contains($0.assetId) }

        for replacement in preview.replacementAssets {
            if let index = assets.firstIndex(where: { $0.id == replacement.id }) {
                assets[index] = replacement
            } else {
                assets.append(replacement)
            }
        }

        if let sourceIndex = sources.firstIndex(where: { $0.id == source.id }) {
            sources[sourceIndex] = macOS_AssetSource(
                id: source.id,
                fileName: source.fileName,
                importDate: source.importDate,
                assetCount: preview.replacementAssets.count,
                assetIds: preview.replacementAssets.map(\.id),
                assetImportKeys: preview.replacementImportKeys
            )
        }

        saveToStorage()

        if preview.removedAssets.isEmpty {
            errorMessage = "来源更新完成：新增 \(preview.addedCount) 个，保持/更新 \(preview.updatedCount) 个，删除 0 个"
        } else {
            let previewNames = preview.removedAssets.prefix(6).map(\.assetName).joined(separator: "、")
            let suffix = preview.removedAssets.count > 6 ? " 等 \(preview.removedAssets.count) 个" : ""
            errorMessage = "来源更新完成：新增 \(preview.addedCount) 个，保持/更新 \(preview.updatedCount) 个，删除 \(preview.removedAssetIDs.count) 个（\(previewNames)\(suffix)）"
        }
    }

    func renameSource(_ source: macOS_AssetSource, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "来源名称不能为空"
            return
        }
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }

        sources[index] = macOS_AssetSource(
            id: source.id,
            fileName: trimmed,
            importDate: source.importDate,
            assetCount: source.assetCount,
            assetIds: source.assetIds,
            assetImportKeys: source.assetImportKeys
        )
        saveToStorage()
        errorMessage = "来源名称已更新为「\(trimmed)」"
    }

    func sourceName(for asset: macOS_Asset) -> String? {
        if let sourceID = asset.sourceId,
           let source = sources.first(where: { $0.id == sourceID }) {
            return source.fileName
        }

        return sources.first(where: { $0.assetIds.contains(asset.id) })?.fileName
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
        let barcode = (dict["外编号"] ?? dict["条码"] ?? dict["barcode"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let statusStr = dict["一级状态"] ?? dict["状态"] ?? dict["status"] ?? "在库"
        let status = macOS_AssetStatus.fromStoredValue(statusStr)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let purchaseDate = (dict["采购日期"] ?? "").isEmpty ? nil : dateFormatter.date(from: dict["采购日期"] ?? "")
        let note = buildImportNote(from: dict)
        
        return macOS_Asset(
            id: barcode,
            assetName: dict["名称"] ?? dict["name"] ?? "",
            modelName: dict["型号"] ?? dict["model"] ?? "",
            brand: dict["品牌"] ?? dict["brand"] ?? "",
            status: status,
            internalCode: dict["内编号"] ?? dict["internalCode"] ?? "",
            location: dict["一级存放地"] ?? dict["location"] ?? "",
            purchaseDate: purchaseDate,
            note: note,
            lastUpdated: Date()
        )
    }

    private func makeImportAssetID(for asset: macOS_Asset, row: [String: String], rowIndex: Int, reservedIDs: Set<String>) -> String {
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

    private func makeSourceComparisonKey(
        for row: [String: String],
        rowIndex: Int,
        occurrences: inout [String: Int]
    ) -> String {
        let barcode = normalizedImportValue(row["外编号"] ?? row["条码"] ?? row["barcode"])
        let internalCode = normalizedImportValue(row["内编号"] ?? row["internalCode"])
        let name = normalizedImportValue(row["名称"] ?? row["name"])
        let model = normalizedImportValue(row["型号"] ?? row["model"])
        let brand = normalizedImportValue(row["品牌"] ?? row["brand"])

        let fallbackKey = [brand, model].compactMap { $0 }.joined(separator: "|")
        let baseKey = [barcode, internalCode, name, fallbackKey]
            .compactMap { $0 }
            .first(where: { !$0.isEmpty })
        let resolvedBase = baseKey ?? "ROW-\(rowIndex + 1)"
        let currentCount = (occurrences[resolvedBase] ?? 0) + 1
        occurrences[resolvedBase] = currentCount
        return "\(resolvedBase)#\(currentCount)"
    }

    private func fallbackComparisonKey(
        for asset: macOS_Asset,
        occurrences: inout [String: Int]
    ) -> String {
        let normalizedAssetID = normalizedLegacyAssetID(asset.id)
        let fallbackKey = [normalizedImportValue(asset.brand), normalizedImportValue(asset.modelName)]
            .compactMap { $0 }
            .joined(separator: "|")
        let baseKey = [
            normalizedImportValue(normalizedAssetID),
            normalizedImportValue(asset.internalCode),
            normalizedImportValue(asset.assetName),
            fallbackKey
        ]
        .compactMap { $0 }
        .first(where: { !$0.isEmpty })
        let resolvedBase = baseKey ?? UUID().uuidString
        let currentCount = (occurrences[resolvedBase] ?? 0) + 1
        occurrences[resolvedBase] = currentCount
        return "\(resolvedBase)#\(currentCount)"
    }

    private func normalizedLegacyAssetID(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        guard let hashIndex = trimmed.lastIndex(of: "#") else { return trimmed }
        let suffix = trimmed[trimmed.index(after: hashIndex)...]
        if !suffix.isEmpty && suffix.allSatisfy(\.isNumber) {
            return String(trimmed[..<hashIndex])
        }
        return trimmed
    }

    private func buildImportNote(from dict: [String: String]) -> String? {
        let directNote = normalizedImportValue(dict["备注"]) ?? normalizedImportValue(dict["note"])
        let extras: [(String, String?)] = [
            ("数量", normalizedImportValue(dict["数量"])),
            ("保管科室", normalizedImportValue(dict["保管科室"])),
            ("资产专管", normalizedImportValue(dict["资产专管"])),
            ("保管人", normalizedImportValue(dict["保管人"])),
            ("使用人", normalizedImportValue(dict["使用人"])),
            ("二级状态", normalizedImportValue(dict["二级状态"])),
            ("二级存放地", normalizedImportValue(dict["二级存放地"])),
            ("其他附件", normalizedImportValue(dict["其他附件"]))
        ]

        let extraLines = extras.compactMap { item -> String? in
            let (label, value) = item
            guard let value else { return nil }
            return "\(label)：\(value)"
        }

        let parts = [directNote].compactMap { $0 } + extraLines
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    private func normalizedImportValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    private func generateCSV(from assets: [macOS_Asset]) -> String {
        let rows = [
            ["外编号", "名称", "型号", "品牌", "一级状态", "内编号", "一级存放地", "采购日期", "备注"]
        ] + assets.map { asset in
            [
                asset.id, asset.assetName, asset.modelName, asset.brand,
                asset.status.rawValue, asset.internalCode, asset.location,
                asset.purchaseDate?.toString() ?? "", asset.note ?? ""
            ]
        }
        return CSVService.encode(rows: rows)
    }
    
    // MARK: - 公共方法
    func saveToStorage(syncFeishu: Bool = true) {
        print("💾 [saveToStorage] 保存本地存储: assets=\(assets.count), records=\(operationRecords.count), sources=\(sources.count)")
        storageService.save(assets: assets, records: operationRecords, sources: sources)
        print("✅ [saveToStorage] 本地存储保存完成")
        guard syncFeishu else { return }
        scheduleFeishuAutoSync()
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
        saveToStorage(syncFeishu: false)
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
        saveToStorage(syncFeishu: false)
        syncStatus = syncService.syncStatus
    }

    func syncAllToFeishu() async {
        await feishuBitableService.syncAllData(assets: assets, records: operationRecords)
    }

    func configureFeishuAndSync() {
        feishuBitableService.saveConfig(
            appId: feishuBitableService.appId,
            appSecret: feishuBitableService.appSecret,
            assetAppToken: feishuBitableService.assetAppToken,
            assetTableId: feishuBitableService.assetTableId,
            recordAppToken: feishuBitableService.recordAppToken,
            recordTableId: feishuBitableService.recordTableId
        )
        feishuBitableService.lastMessage = "已保存飞书配置，正在准备首次自动同步"
        feishuBitableService.lastError = nil

        guard feishuBitableService.isReadyForAutoSync() else { return }
        feishuAutoSyncTask?.cancel()
        feishuAutoSyncTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            await self.syncAllToFeishu()
        }
    }

    func importFromFeishu() async {
        guard let snapshot = await feishuBitableService.importRemoteData() else { return }
        applyFeishuSnapshot(snapshot, mode: .merge)
    }

    func syncFeishuBidirectionally() async {
        guard let snapshot = await feishuBitableService.syncBidirectionally(localAssets: assets, localRecords: operationRecords) else { return }
        applyFeishuSnapshot(snapshot, mode: .merge)
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
        let sourceAssetIDs = Set(source.assetIds)
        operationRecords.removeAll { sourceAssetIDs.contains($0.assetId) }
        assets.removeAll { asset in
            let matches = asset.sourceId == source.id || (asset.sourceId == nil && sourceAssetIDs.contains(asset.id))
            if matches { print("🗑️ 删除资产: \(asset.id)") }
            return matches
        }
        let assetsRemoved = assetsBefore - assets.count
        
        sources.removeAll { $0.id == source.id }
        
        print("✅ 删除完成: 移除了 \(assetsRemoved) 个资产, 剩余 \(assets.count) 个")
        
        saveToStorage()
        errorMessage = "已删除导入源「\(source.fileName)」及其 \(assetsRemoved) 个资产"
    }

    private func applyFeishuSnapshot(_ snapshot: FeishuSyncSnapshot, mode: FeishuImportMode) {
        switch mode {
        case .replace:
            assets = snapshot.assets
            operationRecords = snapshot.records.sorted { $0.timestamp > $1.timestamp }
        case .merge:
            assets = mergeAssets(local: assets, remote: snapshot.assets)
            operationRecords = mergeRecords(local: operationRecords, remote: snapshot.records)
        }

        saveToStorage(syncFeishu: false)

        let warningText = snapshot.warnings.isEmpty ? "" : "；" + snapshot.warnings.joined(separator: "；")
        errorMessage = "飞书同步完成：资产 \(snapshot.assets.count) 个，记录 \(snapshot.records.count) 条\(warningText)"
    }

    private func mergeAssets(local: [macOS_Asset], remote: [macOS_Asset]) -> [macOS_Asset] {
        var merged = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })

        for remoteAsset in remote {
            guard let existing = merged[remoteAsset.id] else {
                merged[remoteAsset.id] = remoteAsset
                continue
            }
            merged[remoteAsset.id] = preferredAsset(local: existing, remote: remoteAsset)
        }

        return merged.values.sorted { $0.lastUpdated > $1.lastUpdated }
    }

    private func mergeRecords(local: [macOS_OperationRecord], remote: [macOS_OperationRecord]) -> [macOS_OperationRecord] {
        var merged = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })

        for record in remote {
            if let existing = merged[record.id] {
                merged[record.id] = preferredRecord(local: existing, remote: record)
            } else {
                merged[record.id] = record
            }
        }

        return merged.values.sorted { $0.timestamp > $1.timestamp }
    }

    private func preferredAsset(local: macOS_Asset, remote: macOS_Asset) -> macOS_Asset {
        if remote.lastUpdated > local.lastUpdated { return remote }
        if local.lastUpdated > remote.lastUpdated { return local }
        return assetCompletenessScore(remote) >= assetCompletenessScore(local) ? remote : local
    }

    private func preferredRecord(local: macOS_OperationRecord, remote: macOS_OperationRecord) -> macOS_OperationRecord {
        if remote.timestamp > local.timestamp { return remote }
        if local.timestamp > remote.timestamp { return local }
        return recordCompletenessScore(remote) >= recordCompletenessScore(local) ? remote : local
    }

    private func assetCompletenessScore(_ asset: macOS_Asset) -> Int {
        [
            !asset.assetName.isEmpty,
            !asset.modelName.isEmpty,
            !asset.brand.isEmpty,
            !asset.internalCode.isEmpty,
            !asset.location.isEmpty,
            asset.purchaseDate != nil,
            !(asset.note ?? "").isEmpty
        ].filter { $0 }.count
    }

    private func recordCompletenessScore(_ record: macOS_OperationRecord) -> Int {
        [
            !record.assetName.isEmpty,
            !record.operatorName.isEmpty,
            !(record.note ?? "").isEmpty,
            record.estimatedReturnDate != nil
        ].filter { $0 }.count
    }

    private func scheduleFeishuAutoSync() {
        guard feishuBitableService.isReadyForAutoSync() else { return }
        feishuAutoSyncTask?.cancel()
        feishuAutoSyncTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            await self.syncAllToFeishu()
        }
    }

    func saveCurrentConfigurationToFile() {
        let panel = NSSavePanel()
        panel.title = "保存 AssetManager 配置"
        panel.nameFieldStringValue = "AssetManager-配置.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(currentConfigurationSnapshot())
            try data.write(to: url, options: .atomic)
            errorMessage = "配置已保存：\(url.lastPathComponent)"
        } catch {
            errorMessage = "保存配置失败: \(error.localizedDescription)"
        }
    }

    func loadConfigurationFromFile() {
        let panel = NSOpenPanel()
        panel.title = "读取 AssetManager 配置"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let configuration = try decoder.decode(AssetManagerConfigurationFile.self, from: data)
            applyConfiguration(configuration)
            errorMessage = "配置已读取：\(url.lastPathComponent)"
        } catch {
            errorMessage = "读取配置失败: \(error.localizedDescription)"
        }
    }

    private func currentConfigurationSnapshot() -> AssetManagerConfigurationFile {
        AssetManagerConfigurationFile(
            version: 1,
            savedAt: Date(),
            syncPath: syncService.syncPath,
            syncBookmarkBase64: syncService.exportBookmarkData()?.base64EncodedString(),
            feishu: AssetManagerFeishuConfiguration(
                appId: feishuBitableService.appId,
                appSecret: feishuBitableService.appSecret,
                assetAppToken: feishuBitableService.assetAppToken,
                assetTableId: feishuBitableService.assetTableId,
                recordAppToken: feishuBitableService.recordAppToken,
                recordTableId: feishuBitableService.recordTableId
            )
        )
    }

    private func applyConfiguration(_ configuration: AssetManagerConfigurationFile) {
        let bookmarkData = configuration.syncBookmarkBase64.flatMap { Data(base64Encoded: $0) }
        _ = syncService.restoreSyncDirectory(path: configuration.syncPath, bookmarkData: bookmarkData)

        feishuBitableService.saveConfig(
            appId: configuration.feishu.appId,
            appSecret: configuration.feishu.appSecret,
            assetAppToken: configuration.feishu.assetAppToken,
            assetTableId: configuration.feishu.assetTableId,
            recordAppToken: configuration.feishu.recordAppToken,
            recordTableId: configuration.feishu.recordTableId
        )
        syncStatus = syncService.syncStatus
    }
}

private enum FeishuImportMode {
    case replace
    case merge
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
