#!/bin/bash

# アプリケーション名
APP_NAME="ExMac-Bridge.app"

echo "1. 既存のアプリを削除中..."
rm -rf "$APP_NAME"
rm -rf "ExMac-Bridge_v2.app"

echo "2. フォルダ構造を作成中..."
mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Resources"

echo "3. Info.plist を生成中..."
cat << 'EOF' > "$APP_NAME/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ExMac-Bridge</string>
    <key>CFBundleIdentifier</key>
    <string>com.exmacbridge.packager.v3</string>
    <key>CFBundleName</key>
    <string>ExMac-Bridge</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>3.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.10</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "4. ソースコードをコンパイル中..."
# ExMac-Bridge パッケージャー本体
swiftc main.swift SharedSettings.swift -o "$APP_NAME/Contents/MacOS/ExMac-Bridge"

# KeyMapper 共有バックグラウンドプロセス
swiftc keymapper.swift SharedSettings.swift -o "$APP_NAME/Contents/MacOS/KeyMapper"

echo "5. launch_wrapper.sh を配置中..."
# ルートディレクトリの launch_wrapper.sh をコピー
cp launch_wrapper.sh "$APP_NAME/Contents/MacOS/"
chmod +x "$APP_NAME/Contents/MacOS/launch_wrapper.sh"

echo "6. タイムスタンプとシステムキャッシュを更新中..."
# タイムスタンプを強制的に現在時刻に設定
find "$APP_NAME" -exec touch {} +

# LaunchServicesのキャッシュを強制クリア
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_NAME"

echo "=== ビルド完了: $APP_NAME が完全に新しくなりました ==="
