#!/bin/bash

# ==============================================================================
# ExMac-Bridge: launch_wrapper.sh
# macOSとWineコアエンジンをブリッジする実行制御スクリプト
# ==============================================================================

# スクリプトのディレクトリとベースディレクトリの取得
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_ROOT="$( dirname "$DIR" )"

# ターゲットとなるexeファイル（Resources以下に配置される前提）
TARGET_EXE="$APP_ROOT/Resources/target_app.exe"

# Wineエンジンのパス（Frameworks以下にカプセル化されたWine、またはシステムのもの）
# 本番環境では "$APP_ROOT/Frameworks/Wine.framework/Versions/Current/bin/wine" などを指定
WINE_BIN="/opt/homebrew/bin/wine"
if [ -f "$APP_ROOT/Frameworks/wine/bin/wine" ]; then
    WINE_BIN="$APP_ROOT/Frameworks/wine/bin/wine"
fi

# サンドボックス用のWINEPREFIX設定
export WINEPREFIX="$HOME/Library/Application Support/ExMac-Bridge/Prefixes/Default"
export WINEDEBUG=-all  # デバッグ出力を抑制しパフォーマンス向上
export LANG="ja_JP.UTF-8"
export LC_ALL="ja_JP.UTF-8"
export WINEDLLOVERRIDES="xaudio2_7=n,b"

# WINEPREFIXディレクトリの自動生成
if [ ! -d "$WINEPREFIX" ]; then
    mkdir -p "$WINEPREFIX"
fi

# 描画サーバーの環境変数（Quartz/X11等に依存する場合）
export DISPLAY=:0

# 実行前チェック
if [ ! -f "$TARGET_EXE" ]; then
    osascript -e 'display alert "ExMac-Bridge Error" message "実行対象の .exe ファイルが見つかりません。"'
    exit 1
fi

if ! command -v "$WINE_BIN" &> /dev/null; then
    osascript -e 'display alert "ExMac-Bridge Error" message "Wineエンジンが見つかりません。\nパス: '"$WINE_BIN"'"'
    exit 1
fi

# ==============================================================================
# Wine実行とエラーハンドリング
# 標準エラー出力を一時ファイルにリダイレクトし、終了・クラッシュ時に判定する
# ==============================================================================

TMP_STDERR=$(mktemp)

# 強制フォーカス要求をバックグラウンドで仕掛ける（起動時の操作不能対策）
(
    sleep 1.5
    osascript -e 'tell application "System Events" to set frontmost of every process whose name contains "wine" to true' 2>/dev/null
) &

# Wineの実行 (PTYを割り当ててPyInstallerのコンソール初期化エラーを完全に回避)
script -q "$TMP_STDERR" "$WINE_BIN" "$TARGET_EXE" > /dev/null
WINE_EXIT_CODE=$?

# エラーハンドリング（MacネイティブのOSAScript通知へのブリッジ）
if [ $WINE_EXIT_CODE -ne 0 ]; then
    # 直近のエラーログを抜粋
    ERROR_MSG=$(tail -n 5 "$TMP_STDERR" | sed 's/"/\\"/g')
    osascript -e "display dialog \"Windowsアプリケーションの実行中にエラーが発生しました。\n\n詳細:\n$ERROR_MSG\" with title \"ExMac-Bridge 実行エラー\" buttons {\"OK\"} default button \"OK\" with icon caution"
fi

rm -f "$TMP_STDERR"
exit $WINE_EXIT_CODE
