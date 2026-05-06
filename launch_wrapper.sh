#!/bin/bash

# ==============================================================================
# ExMac-Bridge: launch_wrapper.sh
# macOSとWineコアエンジンをブリッジする実行制御スクリプト
# ==============================================================================

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_ROOT="$( dirname "$DIR" )"
TARGET_EXE="$APP_ROOT/Resources/target_app.exe"
WINE_BIN="/opt/homebrew/bin/wine"
if [ -f "$APP_ROOT/Frameworks/wine/bin/wine" ]; then
    WINE_BIN="$APP_ROOT/Frameworks/wine/bin/wine"
fi

export WINEPREFIX="$HOME/Library/Application Support/ExMac-Bridge/Prefixes/Default"
export WINEDEBUG=-all
export LANG="ja_JP.UTF-8"
export LC_ALL="ja_JP.UTF-8"
export WINEDLLOVERRIDES="xaudio2_7=n,b;dsound=b;dinput8=n,b;xinput1_3=n,b"

# IMEがキー入力を奪うのを防ぐ
export XMODIFIERS="@im=none"
export XIM=""
export GTK_IM_MODULE=""
export QT_IM_MODULE=""

mkdir -p "$WINEPREFIX/drive_c/windows/Fonts"
export DISPLAY=:0

if [ ! -f "$WINEPREFIX/.font_registered" ]; then
    JP_FONT_PATH=$(find /System/Library/Fonts -name "AppleSDGothicNeo.ttc" 2>/dev/null | head -n 1)
    if [ -z "$JP_FONT_PATH" ]; then
        JP_FONT_PATH=$(find /System/Library/Fonts -name "Hiragino Sans GB.ttc" 2>/dev/null | head -n 1)
    fi
    if [ ! -z "$JP_FONT_PATH" ]; then
        cp "$JP_FONT_PATH" "$WINEPREFIX/drive_c/windows/Fonts/msgothic.ttc" 2>/dev/null
        cp "$JP_FONT_PATH" "$WINEPREFIX/drive_c/windows/Fonts/msmincho.ttc" 2>/dev/null
        cp "$JP_FONT_PATH" "$WINEPREFIX/drive_c/windows/Fonts/meiryo.ttc" 2>/dev/null
    fi
    
    SYSREG="$WINEPREFIX/system.reg"
    if [ -f "$SYSREG" ]; then
        python3 - "$SYSREG" << 'PYEOF'
import sys, re, shutil
path = sys.argv[1]
with open(path, 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()
font_section = '[Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\Fonts]'
font_entries = '\n"MS Gothic (TrueType)"="msgothic.ttc"\n"MS PGothic (TrueType)"="msgothic.ttc"\n"MS UI Gothic (TrueType)"="msgothic.ttc"\n"MS Mincho (TrueType)"="msmincho.ttc"\n"MS PMincho (TrueType)"="msmincho.ttc"\n"Meiryo (TrueType)"="meiryo.ttc"\n"Meiryo UI (TrueType)"="meiryo.ttc"\n'
if '"MS Gothic (TrueType)"' not in content:
    idx = content.find(font_section)
    if idx != -1:
        eol = content.find('\n', idx)
        content = content[:eol] + font_entries + content[eol:]
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

# キーマッパーの起動（絶対パスで共有KeyMapperを呼び出す）
MAPPER_PATH="$HOME/Library/Application Support/ExMac-Bridge/KeyMapper"
if [ -x "$MAPPER_PATH" ]; then
    "$MAPPER_PATH" "wine" &
    MAPPER_PID=$!
fi

if [ ! -f "$TARGET_EXE" ]; then
    osascript -e 'display alert "ExMac-Bridge Error" message "実行対象の .exe ファイルが見つかりません。"'
    exit 1
fi

if ! command -v "$WINE_BIN" &> /dev/null; then
    osascript -e 'display alert "ExMac-Bridge Error" message "Wineエンジンが見つかりません。\nパス: '"$WINE_BIN"'"'
    exit 1
fi

TMP_STDERR=$(mktemp)
(
    sleep 1.5
    osascript -e 'tell application "System Events" to set frontmost of every process whose name contains "wine" to true' 2>/dev/null
) &

script -q "$TMP_STDERR" "$WINE_BIN" "$TARGET_EXE" > /dev/null
WINE_EXIT_CODE=$?

if [ $WINE_EXIT_CODE -ne 0 ]; then
    ERROR_MSG=$(tail -n 5 "$TMP_STDERR" | sed 's/"/\\"/g')
    osascript -e "display dialog \"Windowsアプリケーションの実行中にエラーが発生しました。\n\n詳細:\n$ERROR_MSG\" with title \"ExMac-Bridge 実行エラー\" buttons {\"OK\"} default button \"OK\" with icon caution"
fi

rm -f "$TMP_STDERR"
if [ ! -z "$MAPPER_PID" ]; then
    kill -9 $MAPPER_PID 2>/dev/null
fi
exit $WINE_EXIT_CODE
