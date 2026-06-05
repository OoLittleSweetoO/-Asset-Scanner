#!/bin/bash
# AssetManager 卸载脚本
# 用法: ./uninstall_assetmanager.sh

APP_NAME="AssetManager"
TARGET="/Applications/$APP_NAME.app"

echo "🦀 AssetManager 卸载脚本"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -d "$TARGET" ]; then
    echo "ℹ️  未安装（$TARGET 不存在）"
    exit 0
fi

echo "🗑️  正在卸载 $TARGET..."
sudo rm -rf "$TARGET"

if [ $? -eq 0 ]; then
    echo "✅ 卸载完成"
else
    echo "❌ 卸载失败"
    exit 1
fi

# 可选：清理 UserDefaults
read -p "是否同时清除偏好设置？(y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    defaults delete honghaoliu.AssetManager 2>/dev/null
    echo "✅ 偏好设置已清除"
fi
