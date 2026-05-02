# AssetManager 与 AssetScanner JSON 结构差异分析报告

## 1. 模型结构差异

### AssetManager (macOS) 模型：
- `macOS_Asset`：资产模型
- `macOS_OperationRecord`：操作记录模型  
- `macOS_AssetSource`：资产来源模型
- `macOS_AssetStatus`：资产状态枚举
- `macOS_OperationType`：操作类型枚举

### AssetScanner (iOS) 模型：
- `Asset`：资产模型
- `OperationRecord`：操作记录模型
- `AssetSource`：资产来源模型
- `AssetStatus`：资产状态枚举
- `OperationType`：操作类型枚举

## 2. 模型字段差异

### Asset 模型对比：
**macOS_Asset**:
```swift
var id: String
var assetName: String
var modelName: String
var brand: String
var status: macOS_AssetStatus
var internalCode: String
var location: String
var purchaseDate: Date?
var note: String?
var lastUpdated: Date
var sourceId: UUID?
```

**iOS Asset**:
```swift
let id: String
let assetName: String
let modelName: String
let brand: String
var status: AssetStatus
let internalCode: String
let location: String
let purchaseDate: Date?
let note: String?
var lastUpdated: Date
let sourceId: UUID?

enum CodingKeys: String, CodingKey {
    case id = "外编号"
    case assetName = "名称"
    case modelName = "型号"
    case brand = "品牌"
    case status = "一级状态"
    case internalCode = "内编号"
    case location = "一级存放地"
    case purchaseDate = "采购日期"
    case note = "备注"
    case lastUpdated = "最后更新"
    case sourceId
}
```

**关键差异**：
1. AssetScanner 使用了 `CodingKeys` 映射，将字段序列化为中文键名
2. AssetScanner 的属性多为 `let`（不可变），而 macOS 版多为 `var`（可变）

### OperationRecord 模型对比：
**macOS_OperationRecord**:
```swift
let id: UUID
let assetId: String
let assetName: String
let type: macOS_OperationType
let operatorName: String  // 注意这里的字段名
let timestamp: Date
let note: String?
let estimatedReturnDate: Date?
var isSyncedToReminders: Bool = false
```

**iOS OperationRecord**:
```swift
let id: UUID
let assetId: String
let assetName: String
let type: OperationType
let `operator`: String  // 注意这里的字段名
let timestamp: Date
let note: String?
let estimatedReturnDate: Date?
var isSyncedToReminders: Bool = false
```

**关键差异**：
1. macOS 版使用 `operatorName`，iOS 版使用 `operator`，这会导致 JSON 序列化/反序列化不匹配

## 3. 同步服务实现差异

### AssetManager 的 iCloudSyncService：
- 使用本地文件系统（JSON 文件）进行同步
- 文件名：`assets.json`, `records.json`, `sources.json`, `meta.json`
- 使用 `UserDefaults` 存储同步路径
- 使用 `JSONEncoder`/`JSONDecoder` 直接序列化/反序列化模型对象

### AssetScanner 的 FileBasediCloudSyncService：
- 使用文件系统进行同步（同样支持 iCloud Drive）
- 文件名：`assets.json`, `records.json`, `sources.json`
- 使用 `UIDocumentPickerViewController` 选择同步文件夹
- 使用 `JSONEncoder`/`JSONDecoder` 序列化/反序列化模型对象

## 4. 核心问题分析

### 导致导入失败的根本原因：

1. **模型类型不匹配**：
   - AssetManager 使用 `macOS_Asset`, `macOS_OperationRecord`, `macOS_AssetSource`
   - AssetScanner 使用 `Asset`, `OperationRecord`, `AssetSource`
   - 这些是完全不同的类型，尽管结构相似

2. **JSON 字段名不一致**：
   - AssetManager 直接使用 Swift 属性名作为 JSON 键
   - AssetScanner 使用 `CodingKeys` 将字段映射为中文键名（如"外编号", "名称"等）

3. **OperationRecord 字段名不匹配**：
   - macOS 版使用 `"operatorName"` 作为字段名
   - iOS 版使用 `"operator"` 作为字段名
   - 这会导致反序列化失败

## 5. 修复建议

### 方案一：修改 AssetScanner 的导入逻辑
在 AssetScanner 的 `FileBasediCloudSyncService` 中添加对 macOS 格式的支持：

```swift
func syncFromiCloud() async throws -> (assets: [Asset], records: [OperationRecord], sources: [AssetSource]) {
    // ... 现有代码 ...
    
    // 1. 尝试按标准格式读取
    var assets: [Asset] = []
    if fileManager.fileExists(atPath: assetsFileURL.path) {
        let assetsData = try Data(contentsOf: assetsFileURL)
        do {
            // 尝试按 iOS 格式解码（带中文键名）
            assets = try JSONDecoder().decode([Asset].self, from: assetsData)
        } catch {
            // 如果失败，尝试按 macOS 格式解码（直接属性名）
            assets = try decodeMacOSAssets(from: assetsData)
        }
    }
    
    // 对 records 和 sources 也做类似的处理
}

// 添加辅助函数来处理 macOS 格式的 JSON
private func decodeMacOSAssets(from data: Data) throws -> [Asset] {
    // 需要创建一个适配器来处理 macOS_Asset 到 Asset 的转换
    struct MacOSAssetAdapter: Codable {
        let id: String
        let assetName: String
        let modelName: String
        let brand: String
        let status: String // 直接使用字符串
        let internalCode: String
        let location: String
        let purchaseDate: Date?
        let note: String?
        let lastUpdated: Date
        let sourceId: UUID?
        
        // 将适配器转换为 Asset
        func toAsset() -> Asset {
            let statusEnum = AssetStatus(rawValue: status) ?? .inStock
            return Asset(
                id: id,
                assetName: assetName,
                modelName: modelName,
                brand: brand,
                status: statusEnum,
                internalCode: internalCode,
                location: location,
                purchaseDate: purchaseDate,
                note: note,
                lastUpdated: lastUpdated,
                sourceId: sourceId
            )
        }
    }
    
    let adapters = try JSONDecoder().decode([MacOSAssetAdapter].self, from: data)
    return adapters.map { $0.toAsset() }
}
```

### 方案二：统一模型定义
在两个项目中使用相同的模型定义，或者创建共享的模型库。

### 方案三：修改 AssetManager 的序列化格式
让 AssetManager 也使用与 AssetScanner 相同的 JSON 键名格式。

## 6. 推荐解决方案

建议采用方案一，因为：
1. 不需要修改 AssetManager（已经正常工作）
2. 只需要在 AssetScanner 中增加对 macOS 格式的支持
3. 保持向后兼容性
4. 实现相对简单

这样 AssetScanner 就能够导入由 AssetManager 导出的 JSON 文件了。