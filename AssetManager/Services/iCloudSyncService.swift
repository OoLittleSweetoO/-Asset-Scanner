import Foundation
import Combine

/// iCloud 文件同步服务 - 基于文件系统的同步方案
@MainActor
class iCloudSyncService: ObservableObject {
    @Published var isICloudAvailable = false
    @Published var lastSyncTime: Date?
    @Published var lastImportTime: Date?
    @Published var syncError: String?
    @Published var syncStatus: String = "未同步"
    
    /// 同步目录路径
    @Published var syncPath: String {
        didSet {
            UserDefaults.standard.set(syncPath, forKey: "AssetManagerSyncPath")
        }
    }
    
    private let assetsFileName = "assets.json"
    private let recordsFileName = "records.json"
    private let sourcesFileName = "sources.json"
    private let csvFileName = "import.csv"
    private let metaFileName = "meta.json"
    
    private let legacyUserDefaultsKey = "iCloud.com.user.AssetsScanner"
    
    init() {
        print("🔄 [iCloudSyncService.init] 初始化同步服务...")
        
        // 从 UserDefaults 读取自定义同步路径，默认使用 ~/Documents/AssetManagerFile
        // 用户可通过 NSOpenPanel 选择任意目录（包括 iCloud Drive）
        let defaultPath = "\(NSHomeDirectory())/Documents/AssetManagerFile"
        self.syncPath = UserDefaults.standard.string(forKey: "AssetManagerSyncPath") ?? defaultPath
        print("📂 [iCloudSyncService.init] 初始同步路径: \(syncPath)")
        
        // 检查目录是否可访问，如果不可用则尝试创建
        if !checkPathAccessible() {
            print("⚠️ [iCloudSyncService.init] 同步目录不可用，尝试创建...")
            if setSyncPath(defaultPath) {
                syncPath = defaultPath
                UserDefaults.standard.set(defaultPath, forKey: "AssetManagerSyncPath")
                print("✅ [iCloudSyncService.init] 已切换到默认目录: \(defaultPath)")
            } else {
                isICloudAvailable = false
                syncStatus = "❌ 目录不可用"
                print("❌ [iCloudSyncService.init] 默认目录也无法创建")
            }
        }
        
        // 确保 isICloudAvailable 状态正确
        if isICloudAvailable {
            print("✅ [iCloudSyncService.init] 同步目录可用: \(syncPath)")
            loadMetadata()
        } else {
            if FileManager.default.fileExists(atPath: syncPath) && FileManager.default.isWritableFile(atPath: syncPath) {
                isICloudAvailable = true
                syncStatus = "✅ 已同步"
                syncError = nil
                print("✅ [iCloudSyncService.init] 同步目录可用，已启用: \(syncPath)")
                loadMetadata()
            } else {
                syncStatus = "❌ 目录不可用"
                print("❌ [iCloudSyncService.init] 同步目录不可用: \(syncPath)")
            }
        }
    }
    
    // MARK: - 路径管理
    
    /// 检查同步路径是否可访问
    private func checkPathAccessible() -> Bool {
        let url = URL(fileURLWithPath: syncPath)
        print("🔍 [checkPathAccessible] 检查路径: \(syncPath)")
        
        // 如果目录不存在，尝试创建
        if !FileManager.default.fileExists(atPath: syncPath) {
            print("ℹ️ [checkPathAccessible] 目录不存在，尝试创建...")
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                print("✅ [checkPathAccessible] 创建同步目录成功: \(syncPath)")
                isICloudAvailable = true
                return true
            } catch {
                syncError = "创建同步目录失败: \(error.localizedDescription)"
                print("❌ [checkPathAccessible] 创建目录失败: \(error.localizedDescription)")
                print("❌ [checkPathAccessible] 错误域: \(error._domain), 错误码: \((error as NSError).code)")
                return false
            }
        }
        
        print("ℹ️ [checkPathAccessible] 目录已存在，检查可写性...")
        // 检查是否可写
        if FileManager.default.isWritableFile(atPath: syncPath) {
            isICloudAvailable = true
            print("📂 [checkPathAccessible] 同步目录可访问: \(syncPath)")
            return true
        } else {
            syncError = "同步目录不可写: \(syncPath)"
            print("❌ [checkPathAccessible] 目录不可写: \(syncPath)")
            // 尝试写入测试文件来确认
            let testFile = url.appendingPathComponent(".write_test")
            do {
                try "test".write(to: testFile, atomically: true, encoding: .utf8)
                try? FileManager.default.removeItem(at: testFile)
                print("ℹ️ [checkPathAccessible] 实际写入测试成功，但 isWritableFile 返回 false，可能是权限缓存问题")
                isICloudAvailable = true
                return true
            } catch {
                print("❌ [checkPathAccessible] 实际写入测试也失败: \(error.localizedDescription)")
                return false
            }
        }
    }
    
    /// 设置新的同步路径
    func setSyncPath(_ newPath: String) -> Bool {
        let url = URL(fileURLWithPath: newPath)
        
        // 检查路径是否存在或可创建
        if !FileManager.default.fileExists(atPath: newPath) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            } catch {
                syncError = "创建目录失败: \(error.localizedDescription)"
                return false
            }
        }
        
        // 检查是否可写
        if !FileManager.default.isWritableFile(atPath: newPath) {
            syncError = "目录不可写"
            return false
        }
        
        syncPath = newPath
        isICloudAvailable = true
        syncError = nil
        return true
    }
    
    // MARK: - 数据同步
    
    /// 从同步目录拉取数据（应用启动时调用）
    func syncFromICloud(to assets: inout [macOS_Asset], records: inout [macOS_OperationRecord], sources: inout [macOS_AssetSource]) {
        print("🔄 [syncFromICloud] 开始从同步目录拉取数据, syncPath=\(syncPath)")
        guard isICloudAvailable else {
            syncError = "同步目录不可用"
            syncStatus = "❌ 目录不可用"
            print("❌ [syncFromICloud] 目录不可用")
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // 读取 assets
        let assetsURL = fileURL(for: assetsFileName)
        if FileManager.default.fileExists(atPath: assetsURL.path) {
            do {
                let fileData = try Data(contentsOf: assetsURL)
                let decodedAssets = try decoder.decode([macOS_Asset].self, from: fileData)
                assets = decodedAssets
                print("✅ [syncFromICloud] assets 读取成功: \(assets.count) 个")
            } catch {
                print("⚠️ [syncFromICloud] assets 读取失败: \(error.localizedDescription)")
            }
        } else {
            print("ℹ️ [syncFromICloud] assets 文件不存在: \(assetsURL.path)")
        }
        
        // 读取 records
        let recordsURL = fileURL(for: recordsFileName)
        if FileManager.default.fileExists(atPath: recordsURL.path) {
            do {
                let fileData = try Data(contentsOf: recordsURL)
                let decodedRecords = try decoder.decode([macOS_OperationRecord].self, from: fileData)
                records = decodedRecords
                print("✅ [syncFromICloud] records 读取成功: \(records.count) 个")
            } catch {
                print("⚠️ [syncFromICloud] records 读取失败: \(error.localizedDescription)")
            }
        } else {
            print("ℹ️ [syncFromICloud] records 文件不存在: \(recordsURL.path)")
        }
        
        // 读取 sources
        let sourcesURL = fileURL(for: sourcesFileName)
        if FileManager.default.fileExists(atPath: sourcesURL.path) {
            do {
                let fileData = try Data(contentsOf: sourcesURL)
                let decodedSources = try decoder.decode([macOS_AssetSource].self, from: fileData)
                sources = decodedSources
                print("✅ [syncFromICloud] sources 读取成功: \(sources.count) 个")
            } catch {
                print("⚠️ [syncFromICloud] sources 读取失败: \(error.localizedDescription)")
            }
        } else {
            print("ℹ️ [syncFromICloud] sources 文件不存在: \(sourcesURL.path)")
        }
        
        updateLastSyncTime()
        syncStatus = "✅ 已同步"
        syncError = nil
    }
    
    /// 将数据上传到同步目录（操作后调用）
    func syncToICloud(from assets: [macOS_Asset], records: [macOS_OperationRecord], sources: [macOS_AssetSource]) {
        print("🔄 [syncToICloud] 开始同步, isICloudAvailable=\(isICloudAvailable), syncPath=\(syncPath)")
        print("🔄 [syncToICloud] 数据量: assets=\(assets.count), records=\(records.count), sources=\(sources.count)")
        
        guard isICloudAvailable else {
            let msg = "同步目录不可用 (isICloudAvailable=false)"
            syncError = msg
            syncStatus = "❌ 目录不可用"
            print("❌ [syncToICloud] \(msg)")
            return
        }
        
        // 确保目录存在且可写
        let dirURL = URL(fileURLWithPath: syncPath)
        if !FileManager.default.fileExists(atPath: syncPath) {
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
                print("✅ [syncToICloud] 创建同步目录: \(syncPath)")
            } catch {
                let msg = "创建同步目录失败: \(error.localizedDescription)"
                syncError = msg
                syncStatus = "❌ 目录创建失败"
                print("❌ [syncToICloud] \(msg)")
                return
            }
        }
        
        if !FileManager.default.isWritableFile(atPath: syncPath) {
            let msg = "同步目录不可写: \(syncPath)"
            syncError = msg
            syncStatus = "❌ 目录不可写"
            print("❌ [syncToICloud] \(msg)")
            return
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        var hasError = false
        
        // 写入 assets
        let assetsURL = fileURL(for: assetsFileName)
        do {
            let assetsData = try encoder.encode(assets)
            print("📝 [syncToICloud] assets JSON 编码成功, \(assetsData.count) bytes")
            try assetsData.write(to: assetsURL, options: .atomic)
            print("✅ [syncToICloud] assets 写入成功: \(assetsURL.path)")
        } catch {
            print("❌ [syncToICloud] assets 写入失败: \(error.localizedDescription)")
            print("❌ [syncToICloud] 目标路径: \(assetsURL.path)")
            hasError = true
        }
        
        // 写入 records
        let recordsURL = fileURL(for: recordsFileName)
        do {
            let recordsData = try encoder.encode(records)
            print("📝 [syncToICloud] records JSON 编码成功, \(recordsData.count) bytes")
            try recordsData.write(to: recordsURL, options: .atomic)
            print("✅ [syncToICloud] records 写入成功: \(recordsURL.path)")
        } catch {
            print("❌ [syncToICloud] records 写入失败: \(error.localizedDescription)")
            print("❌ [syncToICloud] 目标路径: \(recordsURL.path)")
            hasError = true
        }
        
        // 写入 sources
        let sourcesURL = fileURL(for: sourcesFileName)
        do {
            let sourcesData = try encoder.encode(sources)
            print("📝 [syncToICloud] sources JSON 编码成功, \(sourcesData.count) bytes")
            try sourcesData.write(to: sourcesURL, options: .atomic)
            print("✅ [syncToICloud] sources 写入成功: \(sourcesURL.path)")
        } catch {
            print("❌ [syncToICloud] sources 写入失败: \(error.localizedDescription)")
            print("❌ [syncToICloud] 目标路径: \(sourcesURL.path)")
            hasError = true
        }
        
        if hasError {
            syncError = "部分文件写入失败，请检查日志"
            syncStatus = "⚠️ 同步部分失败"
        } else {
            // 验证文件确实存在
            var allExist = true
            for (name, url) in [(assetsFileName, assetsURL), (recordsFileName, recordsURL), (sourcesFileName, sourcesURL)] {
                if FileManager.default.fileExists(atPath: url.path) {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let size = attrs[.size] as? UInt64 {
                        print("✅ [syncToICloud] 验证: \(name) 存在, \(size) bytes")
                    } else {
                        print("✅ [syncToICloud] 验证: \(name) 存在")
                    }
                } else {
                    print("❌ [syncToICloud] 验证失败: \(name) 不存在!")
                    allExist = false
                }
            }
            
            if allExist {
                updateLastSyncTime()
                syncStatus = "✅ 已同步"
                syncError = nil
                print("✅ [syncToICloud] 全部同步完成")
            } else {
                syncError = "文件验证失败，部分文件未成功写入"
                syncStatus = "⚠️ 同步验证失败"
                print("⚠️ [syncToICloud] 同步验证失败")
            }
        }
    }
    
    /// 双向同步
    func syncBidirectional(
        assets: inout [macOS_Asset],
        records: inout [macOS_OperationRecord],
        sources: inout [macOS_AssetSource]
    ) {
        guard isICloudAvailable else {
            syncError = "同步目录不可用"
            syncStatus = "❌ 目录不可用"
            return
        }
        
        let oldAssets = assets
        let oldRecords = records
        let oldSources = sources
        
        syncFromICloud(to: &assets, records: &records, sources: &sources)
        
        // 保留本地较多的数据
        if oldAssets.count > assets.count { assets = oldAssets }
        if oldRecords.count > records.count { records = oldRecords }
        if oldSources.count > sources.count { sources = oldSources }
        
        syncToICloud(from: assets, records: records, sources: sources)
        
        syncStatus = "🔄 同步完成"
    }
    
    // MARK: - CSV 导入
    
    /// 从同步目录导入 CSV 内容
    func importCSVFromICloud(to assets: inout [macOS_Asset]) {
        guard isICloudAvailable else {
            syncStatus = "❌ 目录不可用"
            return
        }
        
        let csvURL = fileURL(for: csvFileName)
        guard let csvContent = try? String(contentsOf: csvURL, encoding: .utf8), !csvContent.isEmpty else {
            syncStatus = "📋 无 CSV 数据"
            return
        }
        
        let newAssets = StorageService().importFromCSV(csvContent: csvContent)
        assets.append(contentsOf: newAssets)
        
        updateLastImportTime()
        syncStatus = "📥 CSV 导入完成：\(newAssets.count) 个资产"
    }
    
    /// 将 CSV 内容保存到同步目录
    func saveCSVToICloud(csvContent: String) {
        guard isICloudAvailable else {
            syncStatus = "❌ 目录不可用"
            print("❌ [saveCSVToICloud] 目录不可用")
            return
        }
        
        let csvURL = fileURL(for: csvFileName)
        do {
            try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)
            print("✅ [saveCSVToICloud] CSV 写入成功: \(csvURL.path), \(csvContent.count) chars")
            updateLastImportTime()
            syncStatus = "📤 CSV 已保存到同步目录"
        } catch {
            print("❌ [saveCSVToICloud] CSV 写入失败: \(error.localizedDescription)")
            print("❌ [saveCSVToICloud] 目标路径: \(csvURL.path)")
            syncError = "CSV 写入失败: \(error.localizedDescription)"
            syncStatus = "❌ CSV 写入失败"
        }
    }
    
    // MARK: - 元数据管理
    
    private struct SyncMeta: Codable {
        var lastSyncTimestamp: TimeInterval?
        var lastImportTimestamp: TimeInterval?
    }
    
    private func fileURL(for fileName: String) -> URL {
        URL(fileURLWithPath: syncPath).appendingPathComponent(fileName)
    }
    
    private func loadMetadata() {
        let metaURL = fileURL(for: metaFileName)
        if let data = try? Data(contentsOf: metaURL),
           let meta = try? JSONDecoder().decode(SyncMeta.self, from: data) {
            if let ts = meta.lastSyncTimestamp, ts > 0 {
                lastSyncTime = Date(timeIntervalSince1970: ts)
            }
            if let ts = meta.lastImportTimestamp, ts > 0 {
                lastImportTime = Date(timeIntervalSince1970: ts)
            }
        }
    }
    
    private func saveMetadata() {
        let meta = SyncMeta(
            lastSyncTimestamp: lastSyncTime?.timeIntervalSince1970,
            lastImportTimestamp: lastImportTime?.timeIntervalSince1970
        )
        do {
            let data = try JSONEncoder().encode(meta)
            let metaURL = fileURL(for: metaFileName)
            try data.write(to: metaURL, options: .atomic)
            print("✅ [saveMetadata] 元数据写入成功: \(metaURL.path)")
        } catch {
            print("❌ [saveMetadata] 元数据写入失败: \(error.localizedDescription)")
        }
    }
    
    private func updateLastSyncTime() {
        lastSyncTime = Date()
        saveMetadata()
    }
    
    private func updateLastImportTime() {
        lastImportTime = Date()
        saveMetadata()
    }
    
    // MARK: - 向后兼容：从旧 UserDefaults 迁移数据
    
    /// 尝试从旧的 UserDefaults 同步方式迁移数据
    func migrateFromUserDefaults() -> Bool {
        guard let oldDefaults = UserDefaults(suiteName: legacyUserDefaultsKey) else {
            return false
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        var migrated = false
        
        // 迁移 assets
        if let assetsData = oldDefaults.data(forKey: "synced_assets"),
           let decodedAssets = try? decoder.decode([macOS_Asset].self, from: assetsData),
           !decodedAssets.isEmpty {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let assetsData = try? encoder.encode(decodedAssets) {
                try? assetsData.write(to: fileURL(for: assetsFileName))
                migrated = true
            }
        }
        
        // 迁移 records
        if let recordsData = oldDefaults.data(forKey: "synced_records"),
           let decodedRecords = try? decoder.decode([macOS_OperationRecord].self, from: recordsData),
           !decodedRecords.isEmpty {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let recordsData = try? encoder.encode(decodedRecords) {
                try? recordsData.write(to: fileURL(for: recordsFileName))
                migrated = true
            }
        }
        
        // 迁移 sources
        if let sourcesData = oldDefaults.data(forKey: "synced_sources"),
           let decodedSources = try? decoder.decode([macOS_AssetSource].self, from: sourcesData),
           !decodedSources.isEmpty {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let sourcesData = try? encoder.encode(decodedSources) {
                try? sourcesData.write(to: fileURL(for: sourcesFileName))
                migrated = true
            }
        }
        
        if migrated {
            syncStatus = "🔄 已从旧同步方式迁移"
        }
        
        return migrated
    }
}
