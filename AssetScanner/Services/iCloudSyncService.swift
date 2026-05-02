import Foundation
import Combine

/// iCloud 同步服务 - 支持 iOS 和 macOS 双向同步
@MainActor
class iCloudSyncService: ObservableObject {
    private let userDefaults = UserDefaults.standard
    private let icloudDefaults: UserDefaults?
    
    // 同步键名
    private let assetsKey = "synced_assets"
    private let recordsKey = "synced_records" 
    private let sourcesKey = "synced_sources"
    private let lastSyncKey = "last_sync_timestamp"
    
    @Published var isICloudAvailable = false
    @Published var lastSyncTime: Date?
    @Published var syncError: String?
    
    init() {
        // 尝试初始化 iCloud UserDefaults
        self.icloudDefaults = UserDefaults(suiteName: "iCloud.com.user.AssetsScanner")
        self.isICloudAvailable = (icloudDefaults != nil)
        
        if isICloudAvailable {
            loadLastSyncTime()
            setupICloudNotifications()
        }
    }
    
    // MARK: - 同步操作
    
    /// 从 iCloud 下载数据到本地
    func syncFromICloud(to viewModel: AssetViewModel) {
        guard isICloudAvailable, let icloud = icloudDefaults else {
            syncError = "iCloud 不可用"
            return
        }
        
        let storageService = StorageService()
        let (assets, records, sources) = storageService.load(from: icloud)
        
        viewModel.assets = assets
        viewModel.operationRecords = records
        viewModel.sources = sources
        
        updateLastSyncTime()
        syncError = nil
    }
    
    /// 上传本地数据到 iCloud
    func syncToICloud(from viewModel: AssetViewModel) {
        guard isICloudAvailable, let icloud = icloudDefaults else {
            syncError = "iCloud 不可用"
            return
        }
        
        let storageService = StorageService()
        storageService.save(
            assets: viewModel.assets,
            records: viewModel.operationRecords,
            sources: viewModel.sources,
            to: icloud
        )
        
        updateLastSyncTime()
        syncError = nil
    }
    
    /// 双向同步：合并本地和 iCloud 数据
    func syncBidirectional(with viewModel: AssetViewModel) {
        guard isICloudAvailable else {
            syncError = "iCloud 不可用"
            return
        }
        
        // 先保存当前本地状态
        let localAssets = viewModel.assets
        let localRecords = viewModel.operationRecords  
        let localSources = viewModel.sources
        
        // 从 iCloud 下载
        syncFromICloud(to: viewModel)
        
        // 简单合并策略：如果本地有新数据，优先保留本地
        // 这里可以根据时间戳做更复杂的冲突解决
        if localAssets.count > viewModel.assets.count {
            viewModel.assets = localAssets
        }
        if localRecords.count > viewModel.operationRecords.count {
            viewModel.operationRecords = localRecords
        }
        if localSources.count > viewModel.sources.count {
            viewModel.sources = localSources
        }
        
        // 上传合并后的数据
        syncToICloud(from: viewModel)
    }
    
    // MARK: - 私有方法
    
    private func loadLastSyncTime() {
        if let timestamp = icloudDefaults?.double(forKey: lastSyncKey),
           timestamp > 0 {
            lastSyncTime = Date(timeIntervalSince1970: timestamp)
        }
    }
    
    private func updateLastSyncTime() {
        lastSyncTime = Date()
        icloudDefaults?.set(lastSyncTime?.timeIntervalSince1970 ?? 0, forKey: lastSyncKey)
    }
    
    private func setupICloudNotifications() {
        // 监听 iCloud 数据变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(icloudDataDidChange),
            name: UserDefaults.didChangeNotification,
            object: icloudDefaults
        )
    }
    
    @objc private func icloudDataDidChange() {
        // iCloud 数据发生变化时的通知处理
        print("iCloud 数据已更新")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}