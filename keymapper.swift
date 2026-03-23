import Cocoa
import CoreGraphics

let targetApp = CommandLine.arguments.count > 1 ? CommandLine.arguments[1].lowercased() : "wine"

func CGEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let workspace = NSWorkspace.shared
    let frontmost = workspace.frontmostApplication?.localizedName?.lowercased() ?? ""
    
    // Wine本体やラップしたゲームがアクティブな時だけ変換を適用
    if frontmost.contains(targetApp) || frontmost.contains("wine") || frontmost.contains("mac-driver") || frontmost.contains("crossover") {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        var newKeyCode = keyCode
        
        switch keyCode {
        case 126: newKeyCode = 91 // Up Arrow -> Numpad 8 (Up)
        case 125: newKeyCode = 84 // Down Arrow -> Numpad 2 (Down)
        case 123: newKeyCode = 86 // Left Arrow -> Numpad 4 (Left)
        case 124: newKeyCode = 88 // Right Arrow -> Numpad 6 (Right)
        // Space(49) は横取りによる文字化けを防ぐためそのまま（Wineバグ回避は入力リダイレクト等で対応）
        default: break
        }
        
        if newKeyCode != keyCode {
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(newKeyCode))
        }
    }
    return Unmanaged.passRetained(event)
}

let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

guard let eventTap = CGEvent.tapCreate(tap: .cghidEventTap,
                                       place: .headInsertEventTap,
                                       options: .defaultTap,
                                       eventsOfInterest: CGEventMask(eventMask),
                                       callback: CGEventCallback,
                                       userInfo: nil) else {
    // アクセシビリティ許可がない場合、設定画面を開くAppleScriptを実行
    let script = """
    display dialog "キーボード操作を最適化するため、Macの『アクセシビリティ』許可が必要です。\\n設定画面を開きますので、許可スイッチをONにしてゲームをもう一度起動してください。" with title "初期セットアップのお願い" buttons {"設定を開く", "後で"} default button "設定を開く" with icon caution
    if button returned of result is "設定を開く" then
        do shell script "open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"
    end if
    """
    let task = Process()
    task.launchPath = "/usr/bin/osascript"
    task.arguments = ["-e", script]
    task.launch()
    task.waitUntilExit()
    exit(1)
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: eventTap, enable: true)
CFRunLoopRun()
