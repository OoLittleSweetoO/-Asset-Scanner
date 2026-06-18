# AssetScanner Windows 平台迁移计划

## 一、原 iOS/Android/macOS 项目架构分析

### 1.1 项目结构

```
AssetScanner/
├── AssetScanner/              # Android 应用 (Kotlin)
│   ├── Models/
│   │   ├── Asset.kt                    # 资产实体模型
│   │   ├── AssetSource.kt              # 资产来源模型
│   │   ├── MacOSCompatibilityModels.kt # macOS 兼容模型
│   │   └── OperationRecord.kt          # 操作记录模型
│   ├── Services/
│   │   ├── BarcodeScannerService.kt    # 条码扫描服务
│   │   ├── ExcelService.kt             # Excel/CSV 读写服务
│   │   ├── StorageService.kt           # 本地存储服务 (Room/SQLite)
│   │   ├── CloudSyncService.kt         # 云同步 (OneDrive/WebDAV)
│   │   ├── LanguageManager.kt          # 多语言管理
│   │   └── CalendarService.kt          # 日历提醒同步
│   ├── ViewModels/
│   │   └── AssetViewModel.kt           # 主视图模型 (业务逻辑核心)
│   └── ui/
│       ├── MainActivity.kt             # 主活动 (BottomNavigationView)
│       ├── ScanFragment.kt             # 扫码界面
│       ├── AssetListFragment.kt        # 资产列表
│       ├── AssetDetailFragment.kt      # 资产详情
│       ├── AssetManagementFragment.kt  # 资产管理
│       ├── HistoryFragment.kt          # 操作历史
│       └── CameraScannerView.kt        # 相机扫描
└── AssetManager/              # macOS 应用
    ├── Models/
    │   └── macOS_Assets.kt
    ├── Services/
    │   ├── ContinuityCameraScanner.kt  # 连续相机扫描
    │   ├── CSVService.kt               # CSV 服务
    │   ├── FeishuBitableService.kt     # 飞书多维表格服务
    │   ├── FeishuService.kt            # 飞书 API 服务
    │   ├── macOS_ExcelService.kt       # macOS Excel 服务
    │   └── StorageService.kt
    ├── ViewModels/
    │   └── AssetViewModel.kt
    └── Views/
        ├── AssetManagementModule.kt    # 资产管理模块
        ├── CameraScanSheet.kt          # 相机扫描面板
        ├── ImportFilesView.kt          # 文件导入
        └── MacMainView.kt              # macOS 主界面
```

### 1.2 核心功能模块

| 模块 | 功能 | 技术实现 |
|------|------|----------|
| **资产管理** | 增删改查、状态管理 | Asset 模型 + ViewModel |
| **条码扫描** | 相机扫描一维/二维码 | ML Kit / ZBar (EAN8/13, Code128/39/93, QR, UPC-E, ITF14) |
| **Excel 导入** | CSV/XLSX 文件读取 | Apache POI / EasyExcel |
| **CSV 导出** | 资产列表和操作记录导出 | 自定义 CSV 生成器 |
| **数据持久化** | 本地存储 | Room (SQLite 包装) |
| **云同步** | OneDrive/WebDAV 文件同步 | Microsoft Graph API / WebDAV SDK |
| **多语言** | 中英文切换 | strings.xml (res/values-zh-rCN/) |
| **飞书集成** | 数据同步到飞书 Bitable | Feishu Open API |
| **提醒事项** | 出库记录同步到日历 | Android Calendar Contract API |

### 1.3 数据模型

```
Asset (资产):
├── id: String              # 外编号/条码 (唯一标识)
├── assetName: String       # 资产名称
├── modelName: String       # 型号
├── brand: String           # 品牌
├── status: AssetStatus     # 状态 (在库/已出库/送修)
├── internalCode: String    # 内编号
├── location: String        # 存放位置
├── purchaseDate: Date?     # 采购日期
├── note: String?           # 备注
├── lastUpdated: Date       # 最后更新时间
└── sourceId: UUID?         # 资产来源 ID

OperationRecord (操作记录):
├── id: UUID
├── assetId: String         # 关联资产条码
├── assetName: String
├── type: OperationType     # (入库/出库/送修)
├── operator: String        # 操作人
├── timestamp: Date
├── note: String?
├── estimatedReturnDate: Date?
└── isSyncedToReminders: Boolean

AssetSource (资产来源):
├── id: UUID
├── fileName: String
├── importDate: Date
├── assetCount: Int
└── assetIds: List<String>
```

---

## 二、Windows 平台技术选型

### 2.1 推荐方案：WPF (.NET 8) + MVVM

| 技术 | 理由 |
|------|------|
| **框架** | WPF (.NET 8) | 成熟的桌面 UI 框架，数据绑定强大，与 SwiftUI/Jetpack Compose 理念相似 |
| **MVVM 框架** | CommunityToolkit.Mvvm | Microsoft 官方提供的 MVVM 工具包，自动实现 INotifyPropertyChanged |
| **数据库** | SQLite (Microsoft.Data.Sqlite + Dapper) | 轻量、零配置、跨平台，替代 Room/UserDefaults |
| **Excel 处理** | ClosedXML / MiniExcel | ClosedXML 适合完整 Excel 操作，MiniExcel 适合高性能 CSV |
| **条码扫描** | ZXing.Net + MediaCapture | 支持所有一维/二维码，.NET 可用 |
| **相机捕获** | MediaCapture API | Windows 原生相机 API |
| **云同步** | OneDrive API / WebDAV | 替代 iCloud/云同步 |
| **多语言** | .resx / .json 资源文件 | .NET 原生支持多语言 |
| **UI 样式** | MaterialDesignInXaml | 现代化 Material Design 风格 |

### 2.2 备选方案：Avalonia UI (.NET 8)

| 优势 | 劣势 |
|------|------|
| 跨平台 (Windows/macOS/Linux) | macOS 版本生态稍弱 |
| 自绘引擎，UI 一致性高 | 学习曲线略陡 |
| 同样使用 MVVM 模式 | 某些 Windows 原生功能受限 |

### 2.3 备选方案：PyQt6 / PySide6 (Python)

| 优势 | 劣势 |
|------|------|
| 与原项目开发者技术栈一致 | PyQt6 商业许可费用 |
| 快速原型开发 | 打包体积较大 |
| 丰富的 Python 生态 | Windows 原生体验略逊 WPF |

---

## 三、Windows 版本项目结构设计

```
AssetScanner-Windows/
├── src/
│   ├── AssetScanner/                    # 主项目 (WPF .NET 8)
│   │   ├── AssetScanner.csproj
│   │   │
│   │   ├── Models/
│   │   │   ├── Asset.cs                      # 资产实体 (对应 Android/iOS Asset.kt)
│   │   │   ├── AssetSource.cs                # 资产来源 (对应 AssetSource.kt)
│   │   │   ├── OperationRecord.cs            # 操作记录 (对应 OperationRecord.kt)
│   │   │   └── Enums.cs                      # 枚举 (AssetStatus, OperationType)
│   │   │
│   │   ├── Services/
│   │   │   ├── StorageService.cs             # SQLite 存储服务 (替代 Room)
│   │   │   ├── ExcelService.cs               # Excel/CSV 读写 (替代 Apache POI)
│   │   │   ├── BarcodeScannerService.cs      # 条码扫描 (替代 ML Kit)
│   │   │   ├── CloudSyncService.cs           # OneDrive 同步 (替代云同步)
│   │   │   ├── LanguageService.cs            # 多语言服务 (替代 strings.xml)
│   │   │   ├── CsvExportService.cs           # CSV 导出
│   │   │   └── CameraService.cs              # 相机捕获
│   │   │
│   │   ├── ViewModels/
│   │   │   ├── AssetViewModel.cs             # 主视图模型 (对应 AssetViewModel.kt)
│   │   │   ├── ScanViewModel.cs              # 扫码页面 VM
│   │   │   ├── AssetListViewModel.cs         # 资产列表 VM
│   │   │   ├── AssetDetailViewModel.cs       # 资产详情 VM
│   │   │   └── SettingsViewModel.cs          # 设置 VM
│   │   │
│   │   ├── Views/
│   │   │   ├── MainWindow.xaml/cs            # 主窗口
│   │   │   ├── ScanView.xaml/cs              # 扫码界面
│   │   │   ├── AssetListView.xaml/cs         # 资产列表
│   │   │   ├── AssetDetailView.xaml/cs       # 资产详情
│   │   │   ├── AssetManagementView.xaml/cs   # 资产管理
│   │   │   ├── HistoryView.xaml/cs           # 操作历史
│   │   │   ├── ImportView.xaml/cs            # 文件导入
│   │   │   └── SettingsView.xaml/cs          # 设置
│   │   │
│   │   ├── Converters/                     # 值转换器
│   │   ├── Behaviors/                      # 行为
│   │   ├── Resources/
│   │   │   ├── Strings.zh-CN.resx          # 中文资源
│   │   │   └── Strings.en-US.resx          # 英文资源
│   │   └── Controls/                       # 自定义控件
│   │
│   ├── AssetScanner.Desktop/               # 桌面打包项目
│   │   └── AssetScanner.Desktop.csproj     # MSIX/Inno Setup 打包
│   │
│   └── AssetScanner.Tests/                 # 单元测试
│       ├── Models/
│       ├── Services/
│       └── ViewModels/
│
├── docs/
│   ├── ARCHITECTURE.md                     # 架构文档
│   ├── MIGRATION_GUIDE.md                  # 迁移对照指南
│   └── API_DOCUMENTATION.md
│
├── assets/
│   └── icons/                              # 应用图标
│
├── nuget.config
├── AssetScanner.sln                        # 解决方案
├── Directory.Build.props                   # 全局构建属性
└── README.md
```

---

## 四、核心功能迁移映射表

### 4.1 数据模型迁移

| Android (Kotlin) | Windows (.NET C#) | 说明 |
|-------------------|-------------------|------|
| `data class Asset` (Room Entity) | `class Asset : ObservableObject` | data class → class (MVVM) |
| `@ColumnInfo` / `@PrimaryKey` | `[JsonProperty]` / 主键约束 | ORM → JSON/SQL |
| `Room Database` | `SQLite + Dapper` | 持久化方案 |
| `@ViewModelScoped` / `liveData` | `[ObservableProperty]` | CommunityToolkit.Mvvm |
| `@Inject` / Hilt DI | DI 容器 (Microsoft.Extensions.DependencyInjection) | 依赖注入 |
| `Coroutine` | `async/await` | 协程 → 异步任务 |
| `Moshi/Gson` | `System.Text.Json` | JSON 序列化 |

### 4.2 服务迁移

| Android Service | Windows Service | 技术替换 |
|-----------------|-----------------|----------|
| `BarcodeScannerService` (ML Kit) | `BarcodeScannerService` (ZXing.Net + MediaCapture) | 条码扫描 |
| `ExcelService` (Apache POI) | `ExcelService` (ClosedXML / MiniExcel) | Excel 读写 |
| `StorageService` (Room) | `StorageService` (SQLite + Dapper) | 数据持久化 |
| `CloudSyncService` (OneDrive SDK) | `CloudSyncService` (Microsoft Graph API) | 云同步 |
| `CalendarService` (Calendar Contract) | `CalendarService` (Outlook API / iCal) | 日历提醒 |
| `LanguageManager` | `LanguageService` (.resx) | 多语言 |

### 4.3 UI 迁移对照

| Android (Jetpack) | WPF Control | 说明 |
|-------------------|-------------|------|
| `MainActivity` + `BottomNavigationView` | `MainWindow` + `TabControl` | 主导航 |
| `Fragment` | `UserControl` / `Page` | 页面组件 |
| `RecyclerView` | `DataGrid` / `ItemsControl` | 数据列表 |
| `ViewModel` | `ViewModel` (CommunityToolkit.Mvvm) | 视图模型 |
| `LiveData` / `StateFlow` | `ObservableCollection<T>` / `[ObservableProperty]` | 响应式数据 |
| `NavigationComponent` | `Frame` / `NavigationService` | 页面导航 |
| `CameraX / ImageCapture` | `CaptureElement` (MediaCapture) | 相机预览 |
| `BottomSheetDialog` | `Window` / `UserControl` | 弹出面板 |
| `AlertDialog` | `MessageBox` / 自定义 Dialog | 提示框 |

---

## 五、详细实现计划

### Phase 1: 项目搭建与核心模型 (1-2 周)

**目标**: 搭建 WPF 项目框架，实现数据模型和存储

```
Week 1:
├── [ ] 创建 .NET 8 WPF 解决方案
├── [ ] 配置 CommunityToolkit.Mvvm
├── [ ] 配置 Microsoft.Extensions.DependencyInjection
├── [ ] 实现数据模型 (Asset, AssetSource, OperationRecord)
├── [ ] 实现 SQLite 存储层 (StorageService)
└── [ ] 实现 JSON 序列化/反序列化

Week 2:
├── [ ] 实现多语言服务 (中英双语)
├── [ ] 实现基础 MVVM 架构
├── [ ] 实现主窗口框架 (TabControl 导航)
└── [ ] 配置 MaterialDesignInXAML 主题
```

### Phase 2: 资产管理功能 (2-3 周)

**目标**: 实现资产 CRUD、列表展示

```
Week 3:
├── [ ] 实现 AssetViewModel (业务逻辑)
├── [ ] 实现 AssetListView (数据网格)
├── [ ] 实现 AssetDetailView (详情面板)
└── [ ] 实现搜索/筛选/排序功能

Week 4:
├── [ ] 实现资产增删改功能
├── [ ] 实现资产状态管理 (在库/出库/送修)
├── [ ] 实现批量操作功能
└── [ ] 实现操作记录 (OperationRecord)

Week 5 (如有需要):
├── [ ] 资产导入/导出
├── [ ] 数据验证和错误处理
└── [ ] UI 优化和测试
```

### Phase 3: 条码扫描与相机 (2 周)

**目标**: 实现条码扫描功能

```
Week 6:
├── [ ] 集成 ZXing.Net 条码识别
├── [ ] 实现相机捕获 (MediaCapture / OpenCV)
├── [ ] 实现相机预览 UI (CaptureElement)
└── [ ] 实现扫码结果处理逻辑

Week 7:
├── [ ] 支持条码类型: EAN8/13, Code128/39/93, QR, UPC-E, ITF14
├── [ ] 实现条码清理和验证
├── [ ] 实现扫码后自动查找/新建资产
└── [ ] 相机权限和异常处理
```

### Phase 4: Excel 导入导出 (1-2 周)

**目标**: 实现 Excel/CSV 文件读写

```
Week 8:
├── [ ] 集成 ClosedXML 库
├── [ ] 实现 XLSX 导入
├── [ ] 实现 CSV 导入 (支持 GB18030 编码)
└── [ ] 实现文件选择对话框

Week 9 (如有需要):
├── [ ] 实现资产列表 CSV 导出
├── [ ] 实现操作记录 CSV 导出
├── [ ] 实现 Excel 导入源追踪
└── [ ] 处理重复条码冲突
```

### Phase 5: 云同步与高级功能 (2-3 周)

**目标**: 实现 OneDrive 同步和飞书集成

```
Week 10:
├── [ ] 集成 Microsoft Graph API (OneDrive)
├── [ ] 实现文件同步服务
├── [ ] 实现自动同步机制
└── [ ] 实现冲突解决逻辑

Week 11-12 (如有需要):
├── [ ] 飞书 Bitable API 集成
├── [ ] 飞书配置导入功能
├── [ ] Outlook 日历集成 (替代 Reminders)
└── [ ] 数据加密和隐私保护
```

### Phase 6: 测试与发布 (1-2 周)

```
Week 13:
├── [ ] 单元测试编写
├── [ ] 集成测试
├── [ ] Bug 修复
└── [ ] 性能优化

Week 14 (如有需要):
├── [ ] 打包为 MSIX 或 Inno Setup
├── [ ] 应用图标和 About 页面
├── [ ] 用户文档编写
└── [ ] 发布准备
```

---

## 六、关键代码示例

### 6.1 数据模型 (C# 对应 Kotlin)

```csharp
// Enums.cs
namespace AssetScanner.Models;

public enum AssetStatus
{
    InStock = 0,      // 在库
    CheckedOut = 1,   // 已出库
    Maintenance = 2   // 送修
}

public enum OperationType
{
    CheckIn = 0,      // 入库
    CheckOut = 1,     // 出库
    Repair = 2        // 送修
}

// Asset.cs
using CommunityToolkit.Mvvm.ComponentModel;
using System.Text.Json.Serialization;

namespace AssetScanner.Models;

public partial class Asset : ObservableObject
{
    [ObservableProperty] private string _id = string.Empty;           // 外编号
    [ObservableProperty] private string _assetName = string.Empty;   // 名称
    [ObservableProperty] private string _modelName = string.Empty;   // 型号
    [ObservableProperty] private string _brand = string.Empty;      // 品牌
    [ObservableProperty] private AssetStatus _status;               // 状态
    [ObservableProperty] private string _internalCode = string.Empty; // 内编号
    [ObservableProperty] private string _location = string.Empty;   // 存放位置
    [ObservableProperty] private DateTime? _purchaseDate;           // 采购日期
    [ObservableProperty] private string? _note;                     // 备注
    [ObservableProperty] private DateTime _lastUpdated;             // 更新时间
    [ObservableProperty] private Guid? _sourceId;                   // 来源 ID
}

// OperationRecord.cs
public partial class OperationRecord : ObservableObject
{
    [ObservableProperty] private Guid _id = Guid.NewGuid();
    [ObservableProperty] private string _assetId = string.Empty;
    [ObservableProperty] private string _assetName = string.Empty;
    [ObservableProperty] private OperationType _type;
    [ObservableProperty] private string _operator = string.Empty;
    [ObservableProperty] private DateTime _timestamp = DateTime.Now;
    [ObservableProperty] private string? _note;
    [ObservableProperty] private DateTime? _estimatedReturnDate;
    [ObservableProperty] private bool _isSyncedToReminders;
}
```

### 6.2 存储服务 (SQLite)

```csharp
// Services/StorageService.cs
using Microsoft.Data.Sqlite;
using Dapper;

namespace AssetScanner.Services;

public class StorageService
{
    private readonly string _connectionString;

    public StorageService(string dbPath = null!)
    {
        var basePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "AssetScanner");
        Directory.CreateDirectory(basePath);
        _connectionString = $"Data Source={Path.Combine(basePath, "assets.db")}";
    }

    public async Task InitializeAsync()
    {
        using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync();
        
        await connection.ExecuteAsync(@"
            CREATE TABLE IF NOT EXISTS Assets (
                id TEXT PRIMARY KEY,
                assetName TEXT NOT NULL,
                modelName TEXT,
                brand TEXT,
                status INTEGER NOT NULL,
                internalCode TEXT,
                location TEXT,
                purchaseDate REAL,
                note TEXT,
                lastUpdated REAL NOT NULL,
                sourceId TEXT
            );
            
            CREATE TABLE IF NOT EXISTS OperationRecords (
                id TEXT PRIMARY KEY,
                assetId TEXT NOT NULL,
                assetName TEXT,
                type INTEGER NOT NULL,
                operator TEXT,
                timestamp REAL NOT NULL,
                note TEXT,
                estimatedReturnDate REAL,
                isSyncedToReminders INTEGER DEFAULT 0
            );
            
            CREATE TABLE IF NOT EXISTS AssetSources (
                id TEXT PRIMARY KEY,
                fileName TEXT NOT NULL,
                importDate REAL NOT NULL,
                assetCount INTEGER,
                assetIds TEXT
            );
        ");
    }

    public async Task<List<Asset>> GetAssetsAsync()
    {
        using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync();
        return (await connection.QueryAsync<Asset>(
            "SELECT * FROM Assets ORDER BY lastUpdated DESC")).ToList();
    }

    public async Task SaveAssetsAsync(List<Asset> assets)
    {
        using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync();
        await connection.ExecuteAsync("DELETE FROM Assets");
        
        foreach (var asset in assets)
        {
            await connection.ExecuteAsync(@"
                INSERT INTO Assets (id, assetName, modelName, brand, status, 
                    internalCode, location, purchaseDate, note, lastUpdated, sourceId)
                VALUES (@id, @assetName, @modelName, @brand, @status, 
                    @internalCode, @location, @purchaseDate, @note, @lastUpdated, @sourceId)", asset);
        }
    }
}
```

### 6.3 条码扫描服务

```csharp
// Services/BarcodeScannerService.cs
using ZXing;
using ZXing.QrCode;

namespace AssetScanner.Services;

public class BarcodeScannerService
{
    private readonly BarcodeReader _barcodeReader;

    public BarcodeScannerService()
    {
        _barcodeReader = new BarcodeReader
        {
            PossibleFormats = new List<BarcodeFormat>
            {
                BarcodeFormat.EAN_8, BarcodeFormat.EAN_13,
                BarcodeFormat.CODE_128, BarcodeFormat.CODE_39,
                BarcodeFormat.CODE_93, BarcodeFormat.QR_CODE,
                BarcodeFormat.UPC_E, BarcodeFormat.ITF_14
            },
            AutoRotate = true,
            TryInvert = true
        };
    }

    public string? ScanFromImage(byte[] imageData)
    {
        using var bitmap = new System.Drawing.Bitmap(System.IO.MemoryStream(imageData));
        var result = _barcodeReader.Decode(bitmap);
        return result?.Text;
    }

    public bool ValidateBarcode(string code) => !string.IsNullOrWhiteSpace(code) && code.Length >= 3;

    public string CleanBarcode(string code) => code.Trim();
}
```

### 6.4 Excel 服务 (ClosedXML)

```csharp
// Services/ExcelService.cs
using ClosedXML.Excel;

namespace AssetScanner.Services;

public class ExcelService
{
    public async Task<List<Dictionary<string, string>>> ReadExcelAsync(string filePath)
    {
        var result = new List<Dictionary<string, string>>();
        
        using var workbook = new XLWorkbook(filePath);
        var worksheet = workbook.Worksheet(1);
        
        // 读取表头
        var headers = new List<string>();
        for (int col = 1; col <= worksheet.FirstCellUsed()?.Address.ColumnNumber; col++)
        {
            headers.Add(worksheet.Cell(1, col)?.StringValue ?? "");
        }
        
        // 读取数据行
        for (int row = 2; row <= worksheet.LastCellUsed()?.Address.RowNumber; row++)
        {
            var dict = new Dictionary<string, string>();
            for (int col = 0; col < headers.Count; col++)
            {
                dict[headers[col]] = worksheet.Cell(row, col + 1)?.StringValue ?? "";
            }
            result.Add(dict);
        }
        
        return result;
    }

    public async Task<string> ExportAssetsAsync(List<Asset> assets, string fileName)
    {
        using var workbook = new XLWorkbook();
        var worksheet = workbook.Worksheets.Add(fileName);
        
        // 表头
        worksheet.Cell(1, 1).Value = "外编号";
        worksheet.Cell(1, 2).Value = "名称";
        worksheet.Cell(1, 3).Value = "型号";
        worksheet.Cell(1, 4).Value = "品牌";
        worksheet.Cell(1, 5).Value = "内编号";
        worksheet.Cell(1, 6).Value = "状态";
        worksheet.Cell(1, 7).Value = "存放位置";
        worksheet.Cell(1, 8).Value = "最后更新";
        
        // 数据行
        for (int i = 0; i < assets.Count; i++)
        {
            var asset = assets[i];
            worksheet.Cell(i + 2, 1).Value = asset.Id;
            worksheet.Cell(i + 2, 2).Value = asset.AssetName;
            worksheet.Cell(i + 2, 3).Value = asset.ModelName;
            worksheet.Cell(i + 2, 4).Value = asset.Brand;
            worksheet.Cell(i + 2, 5).Value = asset.InternalCode;
            worksheet.Cell(i + 2, 6).Value = asset.Status.ToString();
            worksheet.Cell(i + 2, 7).Value = asset.Location;
            worksheet.Cell(i + 2, 8).Value = asset.LastUpdated.ToString("yyyy-MM-dd");
        }
        
        var outputPath = Path.Combine(Path.GetTempPath(), $"{fileName}.xlsx");
        workbook.SaveAs(outputPath);
        return outputPath;
    }
}
```

---

## 七、依赖库清单 (NuGet Packages)

```xml
<ItemGroup>
    <!-- MVVM -->
    <PackageReference Include="CommunityToolkit.Mvvm" Version="8.2.0" />
    
    <!-- 数据库 -->
    <PackageReference Include="Microsoft.Data.Sqlite" Version="8.0.0" />
    <PackageReference Include="Dapper" Version="2.1.15" />
    
    <!-- Excel/CSV -->
    <PackageReference Include="ClosedXML" Version="0.102.2" />
    <PackageReference Include="MiniExcel" Version="1.28.0" />
    
    <!-- 条码扫描 -->
    <PackageReference Include="ZXing.Net" Version="0.16.9" />
    
    <!-- UI -->
    <PackageReference Include="MaterialDesignThemes" Version="5.0.0" />
    
    <!-- DI -->
    <PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="8.0.0" />
    
    <!-- OneDrive 同步 -->
    <PackageReference Include="Microsoft.Graph" Version="5.0.0" />
    
    <!-- JSON -->
    <PackageReference Include="System.Text.Json" Version="8.0.0" />
    
    <!-- 图像处理 -->
    <PackageReference Include="SixLabors.ImageSharp" Version="3.1.1" />
</ItemGroup>
```

---

## 八、注意事项与迁移挑战

### 8.1 平台差异

| 功能 | Android/iOS | Windows | 备注 |
|------|-------------|---------|------|
| 相机访问 | CameraX / AVFoundation | MediaCapture / OpenCV | Windows 需要手动请求摄像头权限 |
| 文件选择 | Intent / UIDocumentPicker | OpenFileDialog | Windows 需要配置文件过滤器 |
| 云同步 | OneDrive SDK / iCloud | Microsoft Graph API | 统一使用 Microsoft Graph |
| 持久化 | Room (SQLite) | SQLite + Dapper | 推荐用 SQLite 替代 Room |
| 多语言 | strings.xml | .resx / .json | .NET 原生支持 .resx |
| 通知 | WorkManager / Notifications | Windows Toast / WinUI | Windows 通知 API 不同 |

### 8.2 性能优化建议

1. **大数据列表**: 使用 `DataGrid` 虚拟化和分页
2. **条码扫描**: 使用异步流式处理，避免阻塞 UI
3. **Excel 处理**: 大数据量时使用 MiniExcel (流式) 而非 ClosedXML
4. **缓存**: 实现资产列表的内存缓存

### 8.3 安全考虑

1. **摄像头权限**: 需要在 appxmanifest 中声明 webcam 能力
2. **文件访问**: 使用 `FileDialog` API 处理沙盒
3. **API 密钥**: 飞书/OneDrive API 密钥加密存储
4. **数据加密**: SQLite 数据库使用 SQLCipher 加密

---

## 九、开发环境要求

| 工具 | 版本 | 用途 |
|------|------|------|
| Visual Studio 2022 | 17.8+ | IDE (推荐 Enterprise 或 Community) |
| .NET 8 SDK | 8.0.x | 运行时框架 |
| Windows 11 SDK | 10.0.22621+ | 平台 SDK |
| Git | latest | 版本控制 |

---

## 十、项目时间线总览

```
Month 1: Phase 1-2 (模型搭建 + 资产管理)
Month 2: Phase 3-4 (条码扫描 + Excel)
Month 3: Phase 5-6 (云同步 + 测试发布)
```

**总计**: 约 10-14 周 (2.5-3.5 个月)

---

## 十一、下一步行动

1. [ ] 确认技术选型 (WPF vs Avalonia vs PySide6)
2. [ ] 搭建项目骨架
3. [ ] 实现数据模型和存储层
4. [ ] 逐个实现功能模块
5. [ ] 与原 Android/iOS 版本进行功能对比测试