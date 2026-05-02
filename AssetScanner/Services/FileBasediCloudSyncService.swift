import Foundation
import UIKit

// MARK: - 精简版 iCloud 同步服务

@MainActor
class FileBasediCloudSyncService: NSObject, ObservableObject {
    
    // MARK: - 单一真相
    @Published var selectedFolderURL: URL?
    @Published var syncStatus = "未选择同步文件夹"
    @Published var syncProgress: Double = 0.0
    
    private let fileManager = FileManager.default
    
    // 文件名常量
    private let assetsFileName = "assets.json"
    private let recordsFileName = "records.json"
    private let sourcesFileName = "sources.json"
    
    override init() {
        super.init()
    }
    
    // MARK: - 选择文件夹
    
    func selectSyncFolder() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        
        DispatchQueue.main.async {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first?.rootViewController {
                root.present(picker, animated: true)
            }
        }
    }
    
    // MARK: - 写入同步
    
    func syncToiCloud(
        assets: [Asset],
        records: [OperationRecord],
        sources: [AssetSource]
    ) async -> Bool {
        
        guard let folderURL = selectedFolderURL else {
            syncStatus = "未选择同步文件夹"
            return false
        }
        
        let access = folderURL.startAccessingSecurityScopedResource()
        defer {
            if access {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            syncStatus = "开始同步..."
            syncProgress = 0.1
            
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            
            // 📦 assets
            let assetsURL = folderURL.appendingPathComponent(assetsFileName)
            let assetsData = try encoder.encode(assets)
            try assetsData.write(to: assetsURL, options: .atomic)
            print("✅ assets.json 写入成功")
            
            syncProgress = 0.4
            
            // 📦 records
            let recordsURL = folderURL.appendingPathComponent(recordsFileName)
            let recordsData = try encoder.encode(records)
            try recordsData.write(to: recordsURL, options: .atomic)
            print("✅ records.json 写入成功")
            
            syncProgress = 0.7
            
            // 📦 sources
            let sourcesURL = folderURL.appendingPathComponent(sourcesFileName)
            let sourcesData = try encoder.encode(sources)
            try sourcesData.write(to: sourcesURL, options: .atomic)
            print("✅ sources.json 写入成功")
            
            syncProgress = 1.0
            syncStatus = "同步成功"
            
            return true
            
        } catch {
            print("❌ sync error:", error)
            syncStatus = "同步失败: \(error.localizedDescription)"
            return false
        }
    }
    
    // MARK: - 读取同步
    
    func syncFromiCloud() async throws -> ([Asset], [OperationRecord], [AssetSource]) {
        
        guard let folderURL = selectedFolderURL else {
            throw NSError(domain: "sync", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "未选择同步文件夹"
            ])
        }
        
        let access = folderURL.startAccessingSecurityScopedResource()
        defer {
            if access {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // 📦 assets
        let assetsURL = folderURL.appendingPathComponent(assetsFileName)
        var assets: [Asset] = []
        if let data = try? Data(contentsOf: assetsURL),
           let decoded = try? decoder.decode([Asset].self, from: data) {
            assets = decoded
            print("✅ assets.json 读取成功: \(assets.count) 条")
        }
        
        // 📦 records
        let recordsURL = folderURL.appendingPathComponent(recordsFileName)
        var records: [OperationRecord] = []
        if let data = try? Data(contentsOf: recordsURL),
           let decoded = try? decoder.decode([OperationRecord].self, from: data) {
            records = decoded
            print("✅ records.json 读取成功: \(records.count) 条")
        }
        
        // 📦 sources
        let sourcesURL = folderURL.appendingPathComponent(sourcesFileName)
        var sources: [AssetSource] = []
        if let data = try? Data(contentsOf: sourcesURL),
           let decoded = try? decoder.decode([AssetSource].self, from: data) {
            sources = decoded
            print("✅ sources.json 读取成功: \(sources.count) 条")
        }
        
        syncStatus = "读取成功"
        return (assets, records, sources)
    }
    
    // MARK: - 双向同步
    
    func bidirectionalSync(
        localAssets: [Asset],
        localRecords: [OperationRecord],
        localSources: [AssetSource]
    ) async throws -> (assets: [Asset], records: [OperationRecord], sources: [AssetSource]) {
        
        // 1. 从云端拉取
        let (cloudAssets, cloudRecords, cloudSources) = try await syncFromiCloud()
        
        // 2. 合并资产
        var mergedAssets = localAssets
        for cloudAsset in cloudAssets {
            if let index = mergedAssets.firstIndex(where: { $0.id == cloudAsset.id }) {
                if cloudAsset.lastUpdated > mergedAssets[index].lastUpdated {
                    mergedAssets[index] = cloudAsset
                }
            } else {
                mergedAssets.append(cloudAsset)
            }
        }
        
        // 3. 合并记录
        var mergedRecords = localRecords
        for cloudRecord in cloudRecords {
            if !mergedRecords.contains(where: { $0.id == cloudRecord.id }) {
                mergedRecords.append(cloudRecord)
            }
        }
        mergedRecords.sort { $0.timestamp > $1.timestamp }
        
        // 4. 合并来源
        var mergedSources = localSources
        for cloudSource in cloudSources {
            if let index = mergedSources.firstIndex(where: { $0.id == cloudSource.id }) {
                if cloudSource.assetCount > mergedSources[index].assetCount {
                    mergedSources[index] = cloudSource
                }
            } else {
                mergedSources.append(cloudSource)
            }
        }
        
        // 5. 推送回云端
        _ = await syncToiCloud(
            assets: mergedAssets,
            records: mergedRecords,
            sources: mergedSources
        )
        
        return (mergedAssets, mergedRecords, mergedSources)
    }
}

// MARK: - UIDocumentPickerDelegate

extension FileBasediCloudSyncService: UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController,
                       didPickDocumentsAt urls: [URL]) {
        
        guard let url = urls.first else { return }
        
        // ⭐ 必须开启安全访问
        let ok = url.startAccessingSecurityScopedResource()
        
        print("📁 选择文件夹:", url.path)
        print("🔐 安全访问:", ok)
        
        // 确保在主线程上更新
        DispatchQueue.main.async {
            self.selectedFolderURL = url
            self.syncStatus = "已选择: \(url.lastPathComponent)"
            print("✅ selectedFolderURL 已设置:", self.selectedFolderURL?.path ?? "nil")
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        syncStatus = "取消选择"
    }
}
