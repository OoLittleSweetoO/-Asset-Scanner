#!/bin/bash
# AssetManager 安装脚本
# 用法: ./install_assetmanager.sh

set -e

APP_NAME="AssetManager"
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)/build/Debug"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications"
TARGET="$INSTALL_DIR/$APP_NAME.app"

echo "🦀 AssetManager 安装脚本"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. 编译
echo "🔨 开始编译..."
cd "$(dirname "$0")"
xcodebuild -project AssetScanner.xcodeproj -scheme AssetManager -destination 'platform=macOS' -configuration Release build
if [ $? -ne 0 ]; then
    echo "❌ 编译失败"
    exit 1
fi
echo "✅ 编译完成"

# 2. 查找 build 产物
# Release 模式在 build/Release/ 下
APP_PATH="$(cd "$(dirname "$0")" && pwd)/build/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    APP_PATH="$(cd "$(dirname "$0")" && pwd)/build/Debug/$APP_NAME.app"
fi

if [ ! -d "$APP_PATH" ]; then
    echo "❌ 找不到 .app 文件"
    exit 1
fi

# 3. 卸载旧版本
if [ -d "$TARGET" ]; then
    echo "🗑️  卸载旧版本..."
    sudo rm -rf "$TARGET"
    echo "✅ 旧版本已删除"
fi

# 4. 安装
echo "📦 安装到 $INSTALL_DIR..."
sudo cp -R "$APP_PATH" "$TARGET"
sudo chmod -R a+rX "$TARGET"

echo "✅ 安装完成！"
echo "📍 位置: $TARGET"
echo "💡 在 Launchpad 或 /Applications 中打开"
