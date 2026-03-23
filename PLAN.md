# ExMac-Bridge 開発計画書

## 1. プロジェクト概要と目的
本プロジェクト「ExMac-Bridge」は、macOS上でWindows実行ファイル（.exe）を動作させるためのラッパーアプリケーションの開発を目的とします。
Wine（互換レイヤー）技術およびApple Rosetta 2を統合し、ユーザーが仮想マシンを意識することなく、Macネイティブの「.app」アプリケーションとして直接exeファイルを起動できるシームレスな環境を提供します。

## 2. 必要な環境状況の分析
企画書から、本実装には以下のツールチェーンおよび環境の理解と準備が必要となります。
- **ホストOS設定**: Apple Silicon (ARM64) と Intel (x86_64) における「動的バイナリトランスレーション（Rosetta 2）」の利用が不可欠です。
- **非互換性の吸収**: Windows API (NTカーネル) と macOS API (XNUカーネル) 間のシステムコール、ABIの差異を吸収・翻訳する互換レイヤー（Wine）のビルド環境。
- **ネイティブGUIの知識**: macOSネイティブのアプリケーションバンドル構造（`.app`）への準拠と、AppKitを用いたUI開発環境。

## 3. 環境構築手順

開発を始めるにあたり、以下の手順でホストMacの環境を構築します。

### 3.1 必須ツールのインストール
macOSの開発コマンドラインツールおよびパッケージマネージャを導入します。

1. **Xcode Command Line Tools のインストール**
   ```bash
   xcode-select --install
   ```
2. **Xcode (IDE) のインストール**
   Mac App Storeより最新のXcodeをインストールします（Swiftを用いたUI開発とAppKitフレームワークの利用に必須）。
3. **Homebrew のインストール** (未導入の場合)
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

### 3.2 Wineコアエンジンビルド・動作環境の構築
本プロジェクトではカスタム機能を持つWineを使用するため、C/C++でのコンパイル環境や依存ライブラリをホストMacに準備します。

1. **依存関係のインストール**
   Homebrewを用いてWineのコンパイルに必要なモジュールを導入します。
   ```bash
   brew install cmake ninja pkg-config
   brew install mingw-w64 bison flex freetype
   ```
   *(※CrossOverのソースを利用する場合は、さらにApple特有の追加依存関係が必要になる場合があります)*
2. **Rosetta 2 の有効化** (Apple Silicon機での未有効化時)
   ```bash
   softwareupdate --install-rosetta --agree-to-license
   ```

### 3.3 プロジェクトリポジトリの準備
- 作業ディレクトリ（本ディレクトリ）を用意し、Git等によるバージョン管理を初期化します。
- カスタムWineのベースとなるソースコード（例: CrossOver Macベースのもの）をクローンして準備します。

## 4. プロジェクトマイルストーン
開発は以下の4つのフェーズに基づくマイルストーンで進行します。

| マイルストーン | 概要 | 成果物 |
|---|---|---|
| **Phase 1** | コアシステム（Wine）のビルドとコマンドラインでの動作確立 | コンパイル済みのカスタムWineバイナリ群 |
| **Phase 2** | macOSとWineのブリッジング用シェルスクリプトの完成 | `launch_wrapper.sh` および自動WINEPREFIX構築処理 |
| **Phase 3** | AppKitを用いた「EXEカプセル化UI」機能の実装 | ExMac-Bridge メインUIとなるSwiftアプリケーション |
| **Phase 4** | 様々な形態のexeファイルをパッキングし、動作検証とバグ修正 | 最終的な.app生成テストと最適化されたリリースビルド |

## 5. 留意事項・リスク管理
- **完全な互換性の保証不可**: Windowsの非公開API依存アプリや難読化(DRM)、アンチチートシステム（Vanguard等）が含まれるソフトウェアなどは、技術的な制約（停止性問題含む）により動作させられないことを前提として設計します。
- **メンテナンスコスト**: 今後のmacOSメジャーアップデートによる仕様変更や、Apple Siliconへのより深い対応に対する追従（Wineプロジェクト側の更新）にあわせた継続的なビルド設定の見直しが必要になる可能性があります。
