#!/bin/bash

# AssetScanner macOS Target Membership 配置脚本
# 运行此脚本前请确保 Xcode 项目已关闭

PROJECT_DIR="/Users/honghaoliu/OpenClaw/Projects/AssetScanner"
cd "$PROJECT_DIR"

echo "🔍 检查项目文件..."
if [ ! -f "AssetScanner.xcodeproj/project.pbxproj" ]; then
    echo "❌ 未找到 Xcode 项目文件"
    exit 1
fi

echo "✅ 找到项目文件"

# 备份项目文件
cp AssetScanner.xcodeproj/project.pbxproj AssetScanner.xcodeproj/project.pbxproj.backup_$(date +%Y%m%d_%H%M%S)

echo "💾 已备份项目文件"

# 获取 Target UUIDs
IOS_TARGET_UUID=$(grep -A10 "F01 /* AssetScanner */" AssetScanner.xcodeproj/project.pbxproj | grep "isa = PBXNativeTarget" -B10 | head -1 | cut -d' ' -f1)
MACOS_TARGET_UUID=$(grep -A10 "AssetManager" AssetScanner.xcodeproj/project.pbxproj | grep "isa = PBXNativeTarget" -B10 | head -1 | cut -d' ' -f1)

echo "📱 iOS Target UUID: $IOS_TARGET_UUID"
echo "💻 macOS Target UUID: $MACOS_TARGET_UUID"

# 由于直接编辑 pbxproj 文件很复杂，建议在 Xcode 中手动设置
echo ""
echo "⚠️  注意：自动编辑 Xcode 项目文件风险较高"
echo "💡  建议在 Xcode 中手动设置 Target Membership："
echo ""
echo "1. 打开 Xcode 项目"
echo "2. 在 Project Navigator 中选择以下文件："
echo ""
echo "   共享文件（两个 Target 都勾选）："
echo "   - Models/*.swift"
echo "   - ViewModels/*.swift"  
echo "   - Services/*.swift (除了 BarcodeScannerService.swift)"
echo "   - Views/AssetDetailView.swift"
echo "   - Views/AssetListView.swift"
echo "   - Views/AssetManagementView.swift"
echo "   - Views/HistoryView.swift"
echo "   - Views/MacMainView.swift"
echo ""
echo "   仅 iOS（只勾选 AssetScanner）："
echo "   - AssetScannerApp.swift"
echo "   - Services/BarcodeScannerService.swift"
echo "   - Views/CameraScannerView.swift"
echo "   - Views/ScanView.swift"
echo "   - Views/ContentView.swift"
echo ""
echo "   仅 macOS（只勾选 AssetManager）："
echo "   - AssetManager/AssetManagerApp.swift"
echo "   - AssetManager/AssetManagerContentView.swift"
echo "   - AssetManager/TestICloudView.swift"
echo ""
echo "3. 在右侧 Utilities 面板中设置 Target Membership"

echo ""
echo "✅ 脚本执行完成！请按上述说明在 Xcode 中设置 Target Membership。"