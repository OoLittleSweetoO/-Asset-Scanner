import Foundation

/// 本地存储服务 - macOS 版本
class macOS_StorageService {
    private let userDefaults = UserDefaults.standard
    
    func save(assets: [macOS_Asset], records: [macOS_OperationRecord], sources: [macOS_AssetSource]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let assetsKey = "saved_assets"
        let recordsKey = "saved_records"
        let sourcesKey = "saved_sources"
        
        if let data = try? encoder.encode(assets) { userDefaults.set(data, forKey: assetsKey) }
        if let data = try? encoder.encode(records) { userDefaults.set(data, forKey: recordsKey) }
        if let data = try? encoder.encode(sources) { userDefaults.set(data, forKey: sourcesKey) }
    }
    
    func load() -> (assets: [macOS_Asset], records: [macOS_OperationRecord], sources: [macOS_AssetSource]) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        var assets: [macOS_Asset] = []
        var records: [macOS_OperationRecord] = []
        var sources: [macOS_AssetSource] = []
        
        let assetsKey = "saved_assets"
        let recordsKey = "saved_records"
        let sourcesKey = "saved_sources"
        
        if let data = userDefaults.data(forKey: assetsKey), 
           let decoded = try? decoder.decode([macOS_Asset].self, from: data) { assets = decoded }
        if let data = userDefaults.data(forKey: recordsKey), 
           let decoded = try? decoder.decode([macOS_OperationRecord].self, from: data) { records = decoded }
        if let data = userDefaults.data(forKey: sourcesKey), 
           let decoded = try? decoder.decode([macOS_AssetSource].self, from: data) { sources = decoded }
        
        return (assets, records, sources)
    }
    
func clearAllData() {
        let userDefaults = UserDefaults.standard
        userDefaults.removeObject(forKey: "saved_assets")
        userDefaults.removeObject(forKey: "saved_records")
        userDefaults.removeObject(forKey: "saved_sources")
        userDefaults.synchronize()
    }
    
    /// 从 CSV 内容导入资产
    func importFromCSV(csvContent: String) -> [macOS_Asset] {
        var newAssets: [macOS_Asset] = []
        
        let lines = csvContent.split(separator: "\n")
        guard !lines.isEmpty else { return [] }
        
        let headers = lines[0].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty { continue }
            
            let values = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            var row: [String: String] = [:]
            
            for (j, header) in headers.enumerated() {
                if j < values.count { row[header] = values[j] }
            }
            
            print("✅ 解析行 \(i): \(row)")
            if let asset = createAsset(from: row) {
                print("✅ 创建资产成功: \(asset.id) - \(asset.assetName)")
                newAssets.append(asset)
            } else {
                print("❌ 创建资产失败: \(row)")
            }
        }
        
        return newAssets
    }
    
    private func createAsset(from dict: [String: String]) -> macOS_Asset? {
        let barcode = dict["外编号"] ?? dict["条码"] ?? dict["barcode"] ?? ""
        print("🔍 外编号查找: Barcode='\(barcode)' (来自 dict: \(dict))")
        
        let statusStr = dict["一级状态"] ?? dict["状态"] ?? dict["status"] ?? "在库"
        print("📊 状态查找: statusStr='\(statusStr)'")
        let status = macOS_AssetStatus(rawValue: statusStr) ?? .inStock
        print("✅ 状态解析: \(status.displayName)")
        
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
}

typealias StorageService = macOS_StorageService