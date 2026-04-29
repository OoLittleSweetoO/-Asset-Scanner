import Foundation

/// 本地存储服务
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
