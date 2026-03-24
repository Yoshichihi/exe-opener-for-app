# ExMac-Bridge フェーズ6 実装計画書

## 根本原因の分析

### 🔴 問題1: 文字化けが直らない
**根本原因**: フォントのコピー処理が条件 `if [ ! -d "$WINEPREFIX" ]` の中にある。しかし `BlockDestroy` ゲームを使い回していると **WINEPREFIXはすでに存在**しているため、**フォントコピー処理が一度も実行されない**。また、フォント名を `Osaka` にマッピングしているが macOS 13+ では Osaka フォントは廃止されている。

**修正方針**:
- フォントコピーを WINEPREFIX 存在チェックから**独立させ**、`.font_copied` フラグだけで制御する
- フォールバックとして `Hiragino Sans GB` から `.ttf` へ正式変換して配置
- Wine のレジストリも `msgothic.ttc` を直接参照するよう書き換える

---

### 🔴 問題2: 矢印キー・スペースが効かない
**根本原因**: KeyMapper の「Wineがアクティブか」判定が `frontmost.contains("wine")` だが、実際のMac上のプロセス名は **`wine-preloader`** や **`BlockDestroy`** など様々なため判定に漏れが生じる。また、Numpad コードへの変換はWineが仮想NumLockをOFFとして扱うため逆効果になることがある。

**修正方針**:
- KeyMapper の判定を「ExMac-Bridge から起動された **任意のウィンドウ**がフォアグラウンドの場合」に拡張。プロセス名のリストではなく、**判定を特定のPID（KeyMapper起動時に受け取る）**で行う
- 矢印キーは **Numpadコードではなく、CGEventの `flags` を操作して通常矢印として送り直す**方式に変更
- スペース（keyCode 49）もそのまま透過させる（変換不要）

---

### 🟡 問題3: ゲーム中に通常の文字入力（'a' 等）が発生する
**根本原因**: キーイベントをそのまま透過しているためWineが文字入力として受け取ってしまう。

**修正方針**:
- ゲームウィンドウがアクティブな場合、**文字コード（unicodeString）をクリア（空に差し替え）**してから送出する。これにより「a」と認識されず、キーコードだけが届く

---

### 🟡 問題4: アクセシビリティ設定が既に有効な場合も不要なダイアログが出る
**修正方針**:
- `AXIsProcessTrusted()` でチェックし、**許可済みの場合は完全にダイアログをスキップ**する

---

## 実装対象ファイル

| ファイル | 変更内容 |
|---|---|
| [keymapper.swift](file:///Users/yoshichihi/Documents/exe-opener%20for%20mac/keymapper.swift) | 判定方法変更・矢印/スペース透過・文字列クリア・許可チェック改善 |
| [launch_wrapper.sh](file:///Users/yoshichihi/Documents/exe-opener%20for%20mac/ExMac-Bridge.app/Contents/MacOS/launch_wrapper.sh) | フォントコピー処理を WINEPREFIX 生成から独立させる |
| [main.swift](file:///Users/yoshichihi/Documents/exe-opener%20for%20mac/main.swift) | フォールバックスクリプト内の同修正 |

## 実装順序（一つずつ）
1. **[今回] [keymapper.swift](file:///Users/yoshichihi/Documents/exe-opener%20for%20mac/keymapper.swift) の全面改修**: 矢印・スペース対応 + 文字入力抑制 + アクセシビリティ判定
2. **[次回] [launch_wrapper.sh](file:///Users/yoshichihi/Documents/exe-opener%20for%20mac/ExMac-Bridge.app/Contents/MacOS/launch_wrapper.sh) のフォントコピー修正**: 文字化け根本解決
3. **[次々回] 音質改善**: WINEDLLOVERRIDES の winecoreaudio ドライバ設定追加
