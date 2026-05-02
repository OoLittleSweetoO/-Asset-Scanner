# 资产扫码器 (AssetScanner) / 资产管家 (AssetManager)

**v1.1** | iOS/macOS 应用 - 条形码扫描 + 资产入库/出库管理

---

## 📱 双目标架构

| 目标 | 平台 | 说明 |
|------|------|------|
| `AssetScanner` | iOS 26+ | 扫码 + 管理（相机扫码为主） |
| `AssetManager` | macOS 26+ | 桌面管理（文件导入/导出为主） |

共享 Models / ViewModels / Services 代码

---

## 📦 版本历史

### v1.1 (2026-05-03) - 版本管理启动
- ✅ iOS 和 macOS 双目标均可用
- ✅ iCloud 文件同步重构（单一真相原则）
- ✅ 管理页面重构（ScrollView 结构）
- ✅ 简化同步方法
- ✅ 启动版本管理流程

### v1.0 (2026-04-24 ~ 05-02) - 初始开发
- 基础扫码功能
- Excel/CSV/XLSX 导入
- 出入库管理
- Apple Reminders 同步
- 本地数据持久化

---

## ✨ 功能清单

### 核心功能
- ✅ 全屏相机扫码 (AVFoundation + AVCaptureSession)
- ✅ 条形码扫描 (EAN-13, Code 128, QR, Code 39, Code 93, UPCE, ITF14)
- ✅ 手动输入条码查询 + 模糊匹配
- ✅ 多文件导入管理 (CSV/Excel/XLSX)
- ✅ 资产来源管理 (删除来源、统计)
- ✅ 入库/出库操作 + 操作记录
- ✅ 资产详情显示最近出库记录
- ✅ Apple Reminders 同步 (出库记录)
- ✅ 导出操作记录 (CSV)
- ✅ 本地数据持久化 (UserDefaults)
- ✅ iCloud 文件同步 (导入/导出/双向)
- ✅ 全屏沉浸式 UI (毛玻璃、渐变、卡片)

### 数据模型
- `Asset` - 资产实体 (条码、名称、型号、品牌、状态、内编号、位置、采购日期、备注、来源)
- `AssetStatus` - 在库 / 已出库 / 维修中
- `OperationRecord` - 操作记录 (入库/出库)
- `AssetSource` - 资产来源 (文件导入批次)

---

## 📂 项目结构

```
AssetScanner/
├── AssetScanner/                    # iOS 目标
│   ├── AssetScannerApp.swift        # iOS 应用入口
│   ├── Models/
│   │   ├── Asset.swift              # 资产数据模型
│   │   ├── AssetSource.swift        # 资产来源模型
│   │   └── OperationRecord.swift    # 操作记录模型
│   ├── ViewModels/
│   │   └── AssetViewModel.swift     # 业务逻辑
│   ├── Views/
│   │   ├── ContentView.swift        # 主导航 (TabView)
│   │   ├── ScanView.swift           # 扫码页面
│   │   ├── CameraScannerView.swift  # 相机扫码组件
│   │   ├── AssetListView.swift      # 资产列表
│   │   ├── AssetDetailView.swift    # 资产详情
│   │   ├── AssetManagementView.swift# 资产管理
│   │   └── HistoryView.swift        # 操作记录
│   └── Services/
│       ├── BarcodeScannerService.swift  # 扫码服务
│       ├── ExcelService.swift           # Excel/CSV/XLSX 读写
│       ├── FileBasediCloudSyncService.swift  # iCloud 文件同步
│       ├── RemindersService.swift       # Apple Reminders 同步
│       └── StorageService.swift         # 本地存储
├── AssetManager/                    # macOS 目标
│   ├── AssetManagerApp.swift        # macOS 应用入口
│   ├── Models/
│   │   ├── macOS_Assets.swift
│   │   └── macOS_OperationRecord.swift
│   ├── Views/
│   │   ├── MacMainView.swift
│   │   └── ImportFilesView.swift
│   └── Services/
│       ├── iCloudSyncService.swift
│       ├── StorageService.swift
│       ├── macOS_ExcelService.swift
│       └── RemindersService.swift
├── Assets.xcassets/                 # 资源目录
├── LaunchScreen.storyboard          # 启动画面
├── sample_assets.csv                # 示例资产表
└── README.md
```

---

## 🚀 使用方法

### 1. 准备资产表

创建 CSV/Excel 文件，支持以下列名（多种映射）：
```
外编号/条码/barcode, 名称/资产名称/name, 型号/model, 品牌/brand, 
一级状态/状态/status, 内编号/internalCode, 一级存放地/存放位置/location, 采购日期, 备注
```

### 2. 导入资产

**iOS (AssetScanner)**:
- 在扫码页面点击"导入资产表"
- 选择 CSV/Excel 文件
- 每次导入自动创建新的资产来源
- 资产追加到已有列表（不覆盖）

**macOS (AssetManager)**:
- 使用"导入文件"功能
- 支持拖拽文件
- 批量导入多个文件

### 3. 扫码操作 (iOS)

- 扫描条码 → 显示资产详情
- 点击"入库"或"出库" → 填写操作人/备注 → 确认
- 出库时可设置预计归还时间
- 支持模糊匹配条码

### 4. 导出记录

- 在记录页面点击"导出"
- 通过 AirDrop/文件分享 CSV 文件

### 5. Apple Reminders 同步

- 在记录页面点击右上角同步图标（🔄）
- 同步未归还的出库记录到提醒事项
- 自动创建 "AssetScanner" 列表
- 包含：资产名称、借用人、预计归还时间

### 6. 资产管理

- 查看所有导入的文件来源
- 显示统计信息（文件数、资产数）
- 左滑删除某个来源及其所有资产
- 点击来源可查看该来源下的资产列表

### 7. iCloud 文件同步

**设置同步文件夹**:
- 在"管理"Tab 选择同步目录（建议使用 iCloud Drive）

**同步操作**:
- **导入** - 从同步文件夹读取数据到 APP
- **导出** - 将 APP 数据写入同步文件夹
- **双向同步** - 同时执行导入和导出，合并两边数据

**技术特点**:
- 单一真相原则：只保留 `selectedFolderURL: URL?`
- Combine 订阅：ViewModel 通过 Combine 订阅服务的 `@Published` 属性变化
- JSON 编码：使用 `.dateEncodingStrategy = .iso8601` 确保日期格式一致
- 安全访问：`startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` 配对使用

---

## 🔧 开发

### 环境要求
- **Xcode**: 15.0+
- **Swift**: 5.9+
- **iOS**: 26.0+
- **macOS**: 26.0+

### 构建命令
```bash
# iOS 构建
xcodebuild -project AssetScanner.xcodeproj \
  -scheme AssetScanner \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build

# macOS 构建
xcodebuild -project AssetScanner.xcodeproj \
  -scheme AssetManager \
  -destination 'platform=macOS' \
  build
```

### 安装到 iPhone (免费 Apple ID)
```bash
# 使用安装脚本
./install_to_iphone.sh

# 注意：免费证书 7 天过期，需重新安装
```

---

## 🐛 踩坑记录

### 项目配置
- `SDKROOT` 从 `macosx` 改为 `iphoneos`
- 添加 `IPHONEOS_DEPLOYMENT_TARGET = 26.0`
- 添加 `TARGETED_DEVICE_FAMILY = "1,2"`

### macOS 适配
- `Color(.systemGray5)` → `Color(NSColor.controlBackgroundColor)`
- `.navigationViewStyle(.stack)` 在 macOS 不可用，需移除
- `.commaSeparatedText` → `UTType(filenameExtension: "csv")!`

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
- 安全访问资源后必须配对调用 `stopAccessingSecurityScopedResource()`

---

## 📋 待办事项

- [ ] 真机测试同步功能
- [ ] 离线缓存优化
- [ ] 批量扫码功能
- [ ] 数据同步增强
- [ ] 更多 XLSX 特性支持（公式、合并单元格等）

---

**创建时间**: 2026-04-24  
**当前版本**: v1.1 (2026-05-03)  
**开发者**: 小螃蟹 🦀  
**许可**: 个人项目
