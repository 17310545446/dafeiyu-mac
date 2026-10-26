#!/bin/bash
# 打包成 Dafeiyu.app(Universal)+ zip/dmg
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Dafeiyu"
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.1.0)}"
ARM_BIN=".build/arm64-apple-macosx/release/Dafeiyu"
X86_BIN=".build/x86_64-apple-macosx/release/Dafeiyu"
DIST="dist"

echo "==> 编译 (arm64)"
swift build -c release
echo "==> 编译 (x86_64, 交叉)"
swift build -c release --triple x86_64-apple-macosx13.0 || echo "(x86_64 交叉编译失败,仅 arm64)"

APP="${DIST}/${APP_NAME}.app"
rm -rf "$APP" "${DIST:?}/${APP_NAME}-${VERSION}-macos.zip" "${DIST:?}/${APP_NAME}-${VERSION}.dmg"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/sprites" "$APP/Contents/Resources/dafeiyu" "$APP/Contents/Resources/bigfish"

if [ -f "$X86_BIN" ]; then
  echo "==> lipo 合并 Universal"
  lipo -create -output "$APP/Contents/MacOS/${APP_NAME}" "$ARM_BIN" "$X86_BIN"
else
  cp "$ARM_BIN" "$APP/Contents/MacOS/${APP_NAME}"
fi
cp Resources/sprites/*.png "$APP/Contents/Resources/sprites/"
if [ -d Resources/dafeiyu ]; then
  cp -R Resources/dafeiyu/sprites Resources/dafeiyu/voice Resources/dafeiyu/sfx Resources/dafeiyu/bgm "$APP/Contents/Resources/dafeiyu/"
fi
if [ -d Resources/bigfish ]; then
  cp Resources/bigfish/*.png "$APP/Contents/Resources/bigfish/"
fi

# 图标
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>大肥鱼</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>io.github.dafeiyu.mac</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> 签名(ad-hoc)"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "(ad-hoc 签名失败,可忽略)"

echo "==> 打包 zip / dmg"
ditto -c -k --keepParent "$APP" "${DIST}/${APP_NAME}-${VERSION}-macos.zip"
hdiutil create -volname "大肥鱼" -srcfolder "$APP" -ov -format UDZO "${DIST}/${APP_NAME}-${VERSION}.dmg" >/dev/null

echo "==> 完成:"
ls -lh "$DIST"
