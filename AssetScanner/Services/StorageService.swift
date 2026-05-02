import Foundation

import Dispatch

/// 存储服务 - 支持本地和 iCloud 存储
@MainActor
class StorageService {
    private let userDefaults = UserDefaults.standard
    private let assetsKey = "saved_assets"
    private let recordsKey = "saved_records"
    private let sourcesKey = "saved_sources"
    
    /// 保存数据到本地
    func save(assets: [Asset], records: [OperationRecord], sources: [AssetSource]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let assetsData = try? encoder.encode(assets) {
            userDefaults.set(assetsData, forKey: assetsKey)
        }
        
        if let recordsData = try? encoder.encode(records) {
            userDefaults.set(recordsData, forKey: recordsKey)
        }
        
        if let sourcesData = try? encoder.encode(sources) {
            userDefaults.set(sourcesData, forKey: sourcesKey)
        }
    }
    
    /// 异步保存数据到本地 - 在后台队列中执行编码操作以避免阻塞主线程
    func save(assets: [Asset], records: [OperationRecord], sources: [AssetSource]) async {
        await withCheckedContinuation { continuation in
            Task.detached {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                
                // 在后台队列执行编码操作
                let assetsData = try? encoder.encode(assets)
                let recordsData = try? encoder.encode(records)
                let sourcesData = try? encoder.encode(sources)
                
                // 回到主线程执行 UserDefaults 操作
                await MainActor.run {
                    if let assetsData = assetsData {
                        self.userDefaults.set(assetsData, forKey: self.assetsKey)
                    }
                    
                    if let recordsData = recordsData {
                        self.userDefaults.set(recordsData, forKey: self.recordsKey)
                    }
                    
                    if let sourcesData = sourcesData {
                        self.userDefaults.set(sourcesData, forKey: self.sourcesKey)
                    }
                    
                    continuation.resume()
                }
            }
        }
    }
    
    /// 保存数据到指定的 UserDefaults
    func save(assets: [Asset], records: [OperationRecord], sources: [AssetSource], to userDefaults: UserDefaults) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let assetsKey = "saved_assets"
        let recordsKey = "saved_records"
        let sourcesKey = "saved_sources"
        
        if let assetsData = try? encoder.encode(assets) {
            userDefaults.set(assetsData, forKey: assetsKey)
        }
        
        if let recordsData = try? encoder.encode(records) {
            userDefaults.set(recordsData, forKey: recordsKey)
        }
        
        if let sourcesData = try? encoder.encode(sources) {
            userDefaults.set(sourcesData, forKey: sourcesKey)
        }
    }
    
    /// 从指定的 UserDefaults 加载数据
    func load(from userDefaults: UserDefaults) -> (assets: [Asset], records: [OperationRecord], sources: [AssetSource]) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let assetsKey = "saved_assets"
        let recordsKey = "saved_records"
        let sourcesKey = "saved_sources"
        
        var assets: [Asset] = []
        var records: [OperationRecord] = []
        var sources: [AssetSource] = []
        
        if let assetsData = userDefaults.data(forKey: assetsKey),
           let decodedAssets = try? decoder.decode([Asset].self, from: assetsData) {
            assets = decodedAssets
        }
        
        if let recordsData = userDefaults.data(forKey: recordsKey),
           let decodedRecords = try? decoder.decode([OperationRecord].self, from: recordsData) {
            records = decodedRecords
        }
        
        if let sourcesData = userDefaults.data(forKey: sourcesKey),
           let decodedSources = try? decoder.decode([AssetSource].self, from: sourcesData) {
            sources = decodedSources
        }
        
        return (assets, records, sources)
    }
    
    /// 从本地加载数据
    func load() -> (assets: [Asset], records: [OperationRecord], sources: [AssetSource]) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        var assets: [Asset] = []
        var records: [OperationRecord] = []
        var sources: [AssetSource] = []
        
        if let assetsData = userDefaults.data(forKey: assetsKey),
           let decodedAssets = try? decoder.decode([Asset].self, from: assetsData) {
            assets = decodedAssets
        }
        
        if let recordsData = userDefaults.data(forKey: recordsKey),
           let decodedRecords = try? decoder.decode([OperationRecord].self, from: recordsData) {
            records = decodedRecords
        }
        
        if let sourcesData = userDefaults.data(forKey: sourcesKey),
           let decodedSources = try? decoder.decode([AssetSource].self, from: sourcesData) {
            sources = decodedSources
        }
        
        return (assets, records, sources)
    }
    
    /// 清除所有本地数据
    func clear() {
        userDefaults.removeObject(forKey: assetsKey)
        userDefaults.removeObject(forKey: recordsKey)
        userDefaults.removeObject(forKey: sourcesKey)
    }
}
