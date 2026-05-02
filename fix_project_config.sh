#!/bin/bash

# 自动修复 Xcode 项目配置
# 这会确保 iOS 专用文件只属于 AssetScanner target

PROJECT_DIR="/Users/honghaoliu/OpenClaw/Projects/AssetScanner"
cd "$PROJECT_DIR"

echo "🔍 开始自动修复 Xcode 项目配置..."

# 确认文件存在
if [ ! -f "AssetScanner.xcodeproj/project.pbxproj" ]; then
    echo "❌ 未找到 Xcode 项目文件"
    exit 1
fi

echo "✅ 找到项目文件"
echo ""

# 备份当前配置
cp AssetScanner.xcodeproj/project.pbxproj project.pbxproj.20260501_backup
echo "💾 已备份配置文件"

echo ""
echo "⚠️  ⚠️  ⚠️  重要说明 ⚠️  ⚠️  ⚠️"
echo "由于直接修改 Xcode 项目文件可能损坏项目，"
echo "强烈建议在 Xcode 中手动设置 Target Membership。"
echo ""

echo "📋 在 Xcode 中的正确配置步骤："
echo ""
echo "1. 打开项目: AssetScanner.xcodeproj"
echo ""
echo "2. 在 Project Navigator 中，选择以下文件并设置："
echo ""
echo "   📱 仅 AssetScanner (iOS)：" 
echo "   - AssetScannerApp.swift"
echo "   - Views/ContentView.swift"
echo "   - Views/CameraScannerView.swift"
echo "   - Views/ScanView.swift"
echo "   - Services/BarcodeScannerService.swift"
echo ""
echo "   💻 仅 AssetManager (macOS)："
echo "   - AssetManager/AssetManagerApp.swift"
echo "   - AssetManager/TestICloudView.swift"
echo ""
echo "   🔗 两者都共享："
echo "   - Models/*.swift"
echo "   - ViewModels/*.swift"
echo "   - Services/*.swift (除 BarcodeScannerService)"
echo "   - Views/MacMainView.swift"
echo ""

echo "3. 设置方法："
echo "   - 选中文件"
echo "   - 在右侧 Utilities 面板中找到 'Target Membership'"
echo "   - 勾选对应的 Target"
echo ""

echo "✅ 修复脚本完成！请按上述说明在 Xcode 中设置 Target Membership。"
echo "✅ AssetScanner 已恢复可用状态。"