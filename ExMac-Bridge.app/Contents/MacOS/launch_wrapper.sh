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
export WINEDLLOVERRIDES="xaudio2_7=n,b;dsound=b;dinput8=n,b;xinput1_3=n,b"

# WINEPREFIXとフォントディレクトリの自動生成
mkdir -p "$WINEPREFIX/drive_c/windows/Fonts"

# 描画サーバーの環境変数（Quartz/X11等に依存する場合）
export DISPLAY=:0

# ===== 文字化け対策: フォントコピー＋Wineレジストリ直接登録 =====
if [ ! -f "$WINEPREFIX/.font_registered" ]; then
    # Step1: AppleSDGothicNeo（日本語フォント）をWine用にコピー
    JP_FONT_PATH=$(find /System/Library/Fonts -name "AppleSDGothicNeo.ttc" 2>/dev/null | head -n 1)
    if [ -z "$JP_FONT_PATH" ]; then
        JP_FONT_PATH=$(find /System/Library/Fonts -name "Hiragino Sans GB.ttc" 2>/dev/null | head -n 1)
    fi
    if [ ! -z "$JP_FONT_PATH" ]; then
        cp "$JP_FONT_PATH" "$WINEPREFIX/drive_c/windows/Fonts/msgothic.ttc" 2>/dev/null
        cp "$JP_FONT_PATH" "$WINEPREFIX/drive_c/windows/Fonts/msmincho.ttc" 2>/dev/null
        cp "$JP_FONT_PATH" "$WINEPREFIX/drive_c/windows/Fonts/meiryo.ttc" 2>/dev/null
    fi
    
    # Step2: system.regにフォントエントリを直接Python書き込み（wine regedit不要）
    SYSREG="$WINEPREFIX/system.reg"
    if [ -f "$SYSREG" ]; then
        python3 - "$SYSREG" << 'PYEOF'
import sys, re, shutil
path = sys.argv[1]
with open(path, 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

# Fontsセクションにフォント登録
font_section = '[Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\Fonts]'
font_entries = '\n"MS Gothic (TrueType)"="msgothic.ttc"\n"MS PGothic (TrueType)"="msgothic.ttc"\n"MS UI Gothic (TrueType)"="msgothic.ttc"\n"MS Mincho (TrueType)"="msmincho.ttc"\n"MS PMincho (TrueType)"="msmincho.ttc"\n"Meiryo (TrueType)"="meiryo.ttc"\n"Meiryo UI (TrueType)"="meiryo.ttc"\n'
if '"MS Gothic (TrueType)"' not in content:
    idx = content.find(font_section)
    if idx != -1:
        eol = content.find('\n', idx)
        content = content[:eol] + font_entries + content[eol:]

# FontSubstitutesセクションにArialやTahomaも日本語フォントへフォールバック
subst_section = '[Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\FontSubstitutes]'
subst_entries = '\n"Arial"="MS Gothic"\n"MS Shell Dlg"="MS Gothic"\n"MS Shell Dlg 2"="MS Gothic"\n"Tahoma"="MS Gothic"\n"@MS Gothic"="MS Gothic"\n"@Meiryo"="MS Gothic"\n'
if '"Arial"="MS Gothic"' not in content:
    idx2 = content.find(subst_section)
    if idx2 != -1:
        eol2 = content.find('\n', idx2)
        content = content[:eol2] + subst_entries + content[eol2:]

shutil.copy(path, path + '.bak')
with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
PYEOF
    fi
    touch "$WINEPREFIX/.font_registered"
fi

# キーマッパーの起動
if [ -x "$APP_ROOT/MacOS/KeyMapper" ]; then
    "$APP_ROOT/MacOS/KeyMapper" "wine" &
    MAPPER_PID=$!
fi

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
if [ ! -z "$MAPPER_PID" ]; then
    kill -9 $MAPPER_PID 2>/dev/null
fi
exit $WINE_EXIT_CODE
