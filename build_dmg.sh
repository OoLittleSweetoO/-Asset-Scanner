#!/bin/bash
# AssetManager 编译 + DMG 打包脚本
# 用法: ./build_dmg.sh

set -e

APP_NAME="AssetManager"
APP_VERSION="2.3.5"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DERIVED_DATA="$PROJECT_DIR/build/DerivedData-Release"
APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
MANUAL_SOURCE="$PROJECT_DIR/AssetManager-简要使用手册.md"
MANUAL_NAME="AssetManager-简要使用手册-v${APP_VERSION}.md"
DMG_NAME="${APP_NAME}-${APP_VERSION}"
DMG_FILE="$PROJECT_DIR/build/${DMG_NAME}.dmg"
VOL_NAME="AssetManager ${APP_VERSION}"

echo "🦀 AssetManager DMG 打包脚本"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. 编译
echo "🔨 开始编译 (Release)..."
cd "$PROJECT_DIR"
xcodebuild \
  -project AssetScanner.xcodeproj \
  -scheme AssetManager \
  -destination 'platform=macOS' \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  build \
  CODE_SIGNING_ALLOWED=NO

if [ ! -d "$APP_PATH" ]; then
    echo "❌ 找不到 .app 文件: $APP_PATH"
    exit 1
fi

echo "✅ 编译完成: $APP_PATH"

echo "🧹 清理扩展属性..."
xattr -cr "$APP_PATH" || true

echo "🔐 执行 ad-hoc 签名，固定应用身份..."
codesign --force --deep --sign - "$APP_PATH" || {
    echo "❌ 应用 ad-hoc 签名失败"
    exit 1
}

echo "🔍 校验签名..."
codesign --verify --deep --strict "$APP_PATH" || {
    echo "❌ 应用签名校验失败"
    exit 1
}

# 2. 清理旧 DMG
if [ -f "$DMG_FILE" ]; then
    rm -f "$DMG_FILE"
    echo "🗑️  已删除旧 DMG"
fi

# 3. 创建临时文件夹用于 DMG 内容
TMP_DIR=$(mktemp -d)
STAGING="$TMP_DIR/$APP_NAME"
mkdir -p "$STAGING"

# 复制 .app
cp -R "$APP_PATH" "$STAGING/"

# 复制使用手册
if [ -f "$MANUAL_SOURCE" ]; then
    cp "$MANUAL_SOURCE" "$STAGING/$MANUAL_NAME"
else
    echo "⚠️  未找到使用手册: $MANUAL_SOURCE"
fi

# 创建 Applications 快捷链接
ln -s /Applications "$STAGING/Applications"

echo "📦 打包 DMG..."

# 4. 创建 DMG
hdiutil create "$DMG_FILE" \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -size 200m

# 等待 hdiutil 完成
sleep 1

# 5. 清理临时文件
rm -rf "$TMP_DIR"

# 6. 获取文件大小
SIZE=$(du -sh "$DMG_FILE" | cut -f1)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ DMG 打包完成！"
echo "📍 位置: $DMG_FILE"
echo "📏 大小: $SIZE"
echo ""
echo "💡 使用方式："
echo "   1. 双击 .dmg 挂载"
echo "   2. 将 AssetManager.app 拖入 Applications 文件夹"
echo "   3. 打开附带的 Markdown 使用手册查看同步与扫码说明"
echo "   3. 卸载磁盘映像"
