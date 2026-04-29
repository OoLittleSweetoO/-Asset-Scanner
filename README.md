# 资产扫码器 (AssetScanner)

iOS 应用 - 条形码扫描 + 资产入库/出库管理

## 项目结构

```
AssetScanner/
├── AssetScanner/
│   ├── AssetScannerApp.swift      # 应用入口
│   ├── Models/
│   │   ├── Asset.swift            # 资产数据模型
│   │   ├── AssetSource.swift      # 资产来源模型
│   │   └── OperationRecord.swift  # 操作记录模型
│   ├── ViewModels/
│   │   └── AssetViewModel.swift   # 业务逻辑
│   ├── Views/
│   │   ├── ContentView.swift          # 主导航 (TabView)
│   │   ├── ScanView.swift             # 扫码页面 (全屏相机 + 毛玻璃)
│   │   ├── CameraScannerView.swift    # 相机扫码组件 (UIViewRepresentable)
│   │   ├── AssetListView.swift        # 资产列表 (卡片式)
│   │   ├── AssetDetailView.swift      # 资产详情 + 最近出库记录
│   │   ├── AssetManagementView.swift  # 资产管理 (多文件管理)
│   │   └── HistoryView.swift          # 操作记录 (卡片式 + Reminders 同步)
│   └── Services/
│       ├── BarcodeScannerService.swift  # 扫码服务
│       ├── ExcelService.swift           # Excel/CSV/XLSX 读写
│       ├── RemindersService.swift       # Apple Reminders 同步
│       └── StorageService.swift         # 本地存储
├── Assets.xcassets/               # 资源目录 (App Icon)
├── LaunchScreen.storyboard        # 启动画面
├── sample_assets.csv              # 示例资产表
└── README.md
```

## 功能

- ✅ 全屏相机扫码 (AVFoundation + AVCaptureSession)
- ✅ 条形码扫描 (EAN-13, Code 128, QR 等)
- ✅ 手动输入条码查询
- ✅ 模糊匹配条码
- ✅ 多文件导入管理 (CSV/Excel/XLSX)
- ✅ 资产来源管理 (删除来源、统计)
- ✅ 入库/出库操作
- ✅ 操作记录查看 + 删除
- ✅ 资产详情显示最近出库记录
- ✅ Apple Reminders 同步 (出库记录)
- ✅ 导出操作记录 (CSV)
- ✅ 本地数据持久化 (UserDefaults)
- ✅ 全屏沉浸式 UI (毛玻璃、渐变、卡片)
- ✅ App Icon + LaunchScreen

## 使用方法

### 1. 准备资产表

创建 CSV/Excel 文件，支持以下列名（多种映射）：
```
外编号/条码/barcode, 名称/资产名称/name, 型号/model, 品牌/brand, 
一级状态/状态/status, 内编号/internalCode, 一级存放地/存放位置/location, 采购日期, 备注
```

### 2. 导入资产

在扫码页面点击"导入资产表"，选择 CSV/Excel 文件。
- 每次导入自动创建新的资产来源
- 资产追加到已有列表（不覆盖）
- 可在"管理"Tab 查看所有来源

### 3. 扫码操作

- 扫描条码 → 显示资产详情
- 点击"入库"或"出库" → 填写操作人/备注 → 确认
- 出库时可设置预计归还时间

### 4. 导出记录

在记录页面点击"导出" → 通过 AirDrop/文件分享。

### 5. Apple Reminders 同步

在记录页面点击右上角同步图标（🔄）：
- 同步未归还的出库记录到提醒事项
- 自动创建 "AssetScanner" 列表
- 包含：资产名称、借用人、预计归还时间

### 6. 资产管理

在"管理"Tab：
- 查看所有导入的文件来源
- 显示统计信息（文件数、资产数）
- 左滑删除某个来源及其所有资产
- 点击来源可查看该来源下的资产列表

## 开发

- **平台**: iOS 26+
- **语言**: Swift 5.9+
- **UI 框架**: SwiftUI
- **数据持久化**: UserDefaults (JSON)
- **相机**: AVFoundation
- **提醒事项**: EventKit

## 踩坑记录

### 项目配置
- `SDKROOT` 从 `macosx` 改为 `iphoneos`
- 添加 `IPHONEOS_DEPLOYMENT_TARGET = 26.0`
- 添加 `TARGETED_DEVICE_FAMILY = "1,2"`

### 黑边问题
- 缺少 LaunchScreen 导致 letterbox
- 解决：创建 LaunchScreen.storyboard + 配置 `INFOPLIST_KEY_UILaunchStoryboardName`

### API 弃用
- `.navigationBarHidden(true)` → `.toolbar(.hidden, for: .navigationBar)`
- `NavigationView` → `NavigationStack`
- `NavigationLink(isActive:)` → `navigationDestination(isPresented:)`
- `requestAccess(to:)` → `requestFullAccessToReminders()` (iOS 17+)

### XLSX 解析
- iOS 不支持 `Process` 类（macOS only）
- 改用 `compression_decode_buffer` (Compression 框架) 解压 ZIP
- 手动解析 XML（sharedStrings.xml + sheet1.xml）

### 文件权限
- `fileImporter` 需要 `startAccessingSecurityScopedResource()`
- `.commaSeparatedText` → `UTType(filenameExtension: "csv")!`


---

**创建时间**: 2026-04-24
**最后更新**: 2026-04-29
**开发者**: 小螃蟹 🦀
