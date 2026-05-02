# AssetScanner / AssetManager 版本历史

## v1.1 (2026-05-03) - 版本管理启动

### 新增
- 启动版本管理流程
- iOS 和 macOS 双目标均可用

### 改进
- iCloud 文件同步重构（单一真相原则）
- 管理页面重构（ScrollView 结构）
- 简化同步方法

### 修复
- 修复 iCloud 同步状态管理问题
- 修复管理页面按钮样式问题

---

## v1.0 (2026-04-24 ~ 05-02) - 初始版本

### 功能
- 全屏相机扫码 (AVFoundation)
- 条形码扫描 (EAN-13, Code 128, QR 等)
- 手动输入条码查询 + 模糊匹配
- 多文件导入管理 (CSV/Excel/XLSX)
- 资产来源管理
- 入库/出库操作
- Apple Reminders 同步
- 导出操作记录 (CSV)
- 本地数据持久化 (UserDefaults)
- iCloud 文件同步
- 全屏沉浸式 UI

### 踩坑解决
- SDKROOT 配置问题
- macOS 颜色适配
- XLSX 解析 (iOS 不支持 Process)
- 文件权限管理
- API 弃用适配

---

**维护者**: 小螃蟹 🦀  
**更新频率**: 每次重要更新后更新
