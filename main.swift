import AppKit
import Foundation

class DropView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let url = urls.first {
            if url.pathExtension.lowercased() == "exe" {
                return .copy
            }
        }
        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let url = urls.first else {
            return false
        }
        
        let exePath = url.path
        if url.pathExtension.lowercased() == "exe" {
            generateAppWrapper(for: exePath)
            return true
        }
        return false
    }

    func generateAppWrapper(for exePath: String) {
        let fileManager = FileManager.default
        let exeURL = URL(fileURLWithPath: exePath)
        let exeName = exeURL.deletingPathExtension().lastPathComponent
        
        // 生成先の決定 (デスクトップ等)
        guard let desktopURL = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first else { return }
        let targetAppURL = desktopURL.appendingPathComponent("\(exeName).app")
        
        // 既存のExMac-Bridge.app(自分のバンドル)のパスを取得
        let bundleURL = Bundle.main.bundleURL
        
        if fileManager.fileExists(atPath: targetAppURL.path) {
            let alert = NSAlert()
            alert.messageText = "エラー：既に同名のアプリケーションが存在します。"
            alert.runModal()
            return
        }
        
        do {
            // テンプレとして自分自身（または作成したテンプレートディレクトリ）をコピー
            // 今回は、あらかじめ用意した launch_wrapper.sh などを利用する簡易生成ロジック
            try fileManager.createDirectory(at: targetAppURL, withIntermediateDirectories: true, attributes: nil)
            
            let contentsURL = targetAppURL.appendingPathComponent("Contents")
            let macosURL = contentsURL.appendingPathComponent("MacOS")
            let resourcesURL = contentsURL.appendingPathComponent("Resources")
            let frameworksURL = contentsURL.appendingPathComponent("Frameworks")
            
            try fileManager.createDirectory(at: macosURL, withIntermediateDirectories: true, attributes: nil)
            try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true, attributes: nil)
            try fileManager.createDirectory(at: frameworksURL, withIntermediateDirectories: true, attributes: nil)
            
            // exeをコピー
            let targetExeURL = resourcesURL.appendingPathComponent("target_app.exe")
            try fileManager.copyItem(at: exeURL, to: targetExeURL)
            
            // launch_wrapper.shをコピーまたは作成
            let scriptURL = macosURL.appendingPathComponent("launch_wrapper")
            
            // bundle_executable の解決
            var templateScriptPath = ""
            if let path = Bundle.main.path(forResource: "launch_wrapper", ofType: "sh") {
                templateScriptPath = path
            } else {
                // ローカルの作業ディレクトリにあると仮定
                let localPath = Bundle.main.bundlePath.replacingOccurrences(of: "/ExMac-Bridge.app", with: "") + "/ExMac-Bridge.app/Contents/MacOS/launch_wrapper.sh"
                if fileManager.fileExists(atPath: localPath) {
                    templateScriptPath = localPath
                }
            }
            
            if !templateScriptPath.isEmpty && fileManager.fileExists(atPath: templateScriptPath) {
                try fileManager.copyItem(atPath: templateScriptPath, toPath: scriptURL.path)
            } else {
                // フォールバックとして直接書き込む
                let scriptContent = """
                #!/bin/bash
                DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
                APP_ROOT="$( dirname "$DIR" )"
                TARGET_EXE="$APP_ROOT/Resources/target_app.exe"
                WINE_BIN="/opt/homebrew/bin/wine"
                export WINEPREFIX="$HOME/Library/Application Support/ExMac-Bridge/Prefixes/\(exeName)"
                export WINEDEBUG=-all
                export LANG="ja_JP.UTF-8"
                export LC_ALL="ja_JP.UTF-8"
                export WINEDLLOVERRIDES="xaudio2_7=n,b;dsound=b;dinput8=n,b;xinput1_3=n,b"
                if [ ! -d "$WINEPREFIX" ]; then 
                    mkdir -p "$WINEPREFIX/drive_c/windows/Fonts"
                    ln -sf /System/Library/Fonts/* "$WINEPREFIX/drive_c/windows/Fonts/" 2>/dev/null
                    ln -sf /System/Library/Fonts/Supplemental/* "$WINEPREFIX/drive_c/windows/Fonts/" 2>/dev/null
                    echo 'REGEDIT4' > "$WINEPREFIX/font_fix.reg"
                    echo '[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes]' >> "$WINEPREFIX/font_fix.reg"
                    echo '"MS Gothic"="Osaka"' >> "$WINEPREFIX/font_fix.reg"
                    echo '"MS PGothic"="Osaka"' >> "$WINEPREFIX/font_fix.reg"
                    echo '"MS UI Gothic"="Osaka"' >> "$WINEPREFIX/font_fix.reg"
                    echo '"MS Mincho"="Osaka"' >> "$WINEPREFIX/font_fix.reg"
                    "$WINE_BIN" regedit "$WINEPREFIX/font_fix.reg" >/dev/null 2>&1
                fi
                export DISPLAY=:0
                if [ ! -f "$WINEPREFIX/.winetricks_done" ]; then
                    /opt/homebrew/bin/winetricks -q fakejapanese xact dsound xaudio2_7 >/dev/null 2>&1
                    touch "$WINEPREFIX/.winetricks_done"
                fi
                if [ -x "$APP_ROOT/MacOS/KeyMapper" ]; then
                    "$APP_ROOT/MacOS/KeyMapper" "wine" &
                    MAPPER_PID=$!
                fi
                (
                    sleep 1.5
                    osascript -e 'tell application "System Events" to set frontmost of every process whose name contains "wine" to true' 2>/dev/null
                ) &
                script -q /tmp/wine_error.log "$WINE_BIN" "$TARGET_EXE" > /dev/null
                if [ ! -z "$MAPPER_PID" ]; then kill -9 $MAPPER_PID 2>/dev/null; fi
                """
                try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            }
            
            // 実行権限付与
            var attributes = try fileManager.attributesOfItem(atPath: scriptURL.path)
            attributes[.posixPermissions] = NSNumber(value: 0o755)
            try fileManager.setAttributes(attributes, ofItemAtPath: scriptURL.path)
            
            // キーマッパーのコピー
            let mapperURL = macosURL.appendingPathComponent("KeyMapper")
            let sourceMapper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/KeyMapper")
            if fileManager.fileExists(atPath: sourceMapper.path) {
                try fileManager.copyItem(at: sourceMapper, to: mapperURL)
                var attr = try fileManager.attributesOfItem(atPath: mapperURL.path)
                attr[.posixPermissions] = NSNumber(value: 0o755)
                try fileManager.setAttributes(attr, ofItemAtPath: mapperURL.path)
            } else {
                let localMapper = URL(fileURLWithPath: "ExMac-Bridge.app/Contents/MacOS/KeyMapper")
                if fileManager.fileExists(atPath: localMapper.path) {
                    try fileManager.copyItem(at: localMapper, to: mapperURL)
                    var attr = try fileManager.attributesOfItem(atPath: mapperURL.path)
                    attr[.posixPermissions] = NSNumber(value: 0o755)
                    try fileManager.setAttributes(attr, ofItemAtPath: mapperURL.path)
                }
            }
            
            // アイコン抽出処理
            let iconTmpDir = targetAppURL.appendingPathComponent("icon_temp")
            try? fileManager.createDirectory(at: iconTmpDir, withIntermediateDirectories: true, attributes: nil)
            
            let extractProcess = Process()
            extractProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
            let iconScript = """
            export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
            wrestool -x -t 14 "\(exePath)" > "\(iconTmpDir.path)/icon.ico" 2>/dev/null
            if [ -s "\(iconTmpDir.path)/icon.ico" ]; then
                mkdir -p "\(iconTmpDir.path)/icon.iconset"
                sips -s format png "\(iconTmpDir.path)/icon.ico" --out "\(iconTmpDir.path)/icon.iconset/icon_256x256.png" 2>/dev/null
                iconutil -c icns "\(iconTmpDir.path)/icon.iconset" -o "\(resourcesURL.path)/AppIcon.icns" 2>/dev/null
            fi
            """
            extractProcess.arguments = ["-c", iconScript]
            try? extractProcess.run()
            extractProcess.waitUntilExit()
            try? fileManager.removeItem(at: iconTmpDir)
            
            // Info.plist生成
            let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
            let infoPlistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>CFBundleExecutable</key>
                <string>launch_wrapper</string>
                <key>CFBundleIconFile</key>
                <string>AppIcon</string>
                <key>CFBundleIdentifier</key>
                <string>com.exmacbridge.\(exeName)</string>
                <key>CFBundleName</key>
                <string>\(exeName)</string>
                <key>CFBundlePackageType</key>
                <string>APPL</string>
                <key>CFBundleShortVersionString</key>
                <string>1.0</string>
                <key>LSRequiresCarbon</key>
                <true/>
            </dict>
            </plist>
            """
            try infoPlistContent.write(to: infoPlistURL, atomically: true, encoding: .utf8)
            
            // quarantine属性（開く際の許可ダイアログの原因）の強制解除
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            process.arguments = ["-cr", targetAppURL.path]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("xattr processing failed: \\(error)")
            }
            
            let alert = NSAlert()
            alert.messageText = "変換完了"
            alert.informativeText = "デスクトップに \(exeName).app を作成しました！"
            alert.runModal()
            
        } catch {
            let alert = NSAlert()
            alert.messageText = "エラー"
            alert.informativeText = "変換に失敗しました: \(error.localizedDescription)"
            alert.runModal()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let windowSize = NSSize(width: 400, height: 300)
        let rect = NSRect(origin: .zero, size: windowSize)
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered,
                          defer: false)
        window.title = "ExMac-Bridge - Drop .exe Here"
        window.center()

        let dropView = DropView(frame: rect)
        
        let label = NSTextField(labelWithString: "ここに .exe ファイルをドロップしてください")
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 16)
        label.frame = NSRect(x: 0, y: 130, width: 400, height: 40)
        dropView.addSubview(label)
        
        window.contentView = dropView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
