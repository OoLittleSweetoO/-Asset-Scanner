import Foundation

// 加载并测试 JSON 文件导入功能
func testJSONImport() {
    print("开始测试 JSON 导入功能...")
    
    // 测试 assets.json
    if let assetsPath = Bundle.main.path(forResource: "assets", ofType: "json") ??
        "/Users/honghaoliu/OpenClaw/Projects/AssetScanner/test_data/assets.json" {
        let assetsData = try! Data(contentsOf: URL(fileURLWithPath: assetsPath))
        let assets = try! JSONDecoder().decode([MacOSAsset].self, from: assetsData)
        print("成功导入 \\(assets.count) 个资产")
        for asset in assets {
            print("- 资产: \\(asset.assetName), 品牌: \\(asset.brand), 型号: \\(asset.modelName), 状态: \\(asset.status.rawValue)")
        }
    }
    
    // 测试 records.json
    if let recordsPath = Bundle.main.path(forResource: "records", ofType: "json") ??
        "/Users/honghaoliu/OpenClaw/Projects/AssetScanner/test_data/records.json" {
        let recordsData = try! Data(contentsOf: URL(fileURLWithPath: recordsPath))
        let records = try! JSONDecoder().decode([MacOSOperationRecord].self, from: recordsData)
        print("\\n成功导入 \\(records.count) 条操作记录")
        for record in records {
            print("- 记录: \\(record.assetName), 类型: \\(record.type.rawValue), 操作员: \\(record.operatorName)")
        }
    }
    
    // 测试 sources.json
    if let sourcesPath = Bundle.main.path(forResource: "sources", ofType: "json") ??
        "/Users/honghaoliu/OpenClaw/Projects/AssetScanner/test_data/sources.json" {
        let sourcesData = try! Data(contentsOf: URL(fileURLWithPath: sourcesPath))
        let sources = try! JSONDecoder().decode([MacOSAssetSource].self, from: sourcesData)
        print("\\n成功导入 \\(sources.count) 个数据源")
        for source in sources {
            print("- 数据源: \\(source.fileName), 资产数量: \\(source.assetCount)")
        }
    }
    
    print("\\nJSON 导入测试完成！")
}

// 调用测试函数
testJSONImport()