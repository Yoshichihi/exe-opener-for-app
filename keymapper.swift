import Cocoa
import CoreGraphics

// ===========================
// アクセシビリティ許可チェック
// ===========================
if !AXIsProcessTrusted() {
    // 未許可の場合のみダイアログを出し、設定画面を自動で開く
    let script = """
    display dialog "キーボード操作を最適化するため、アクセシビリティ許可が必要です。\\n\\n設定画面が開きます。\\n「ExMac-Bridge（またはKeymapper）」のスイッチをONにして、アプリを再起動してください。" with title "初期セットアップのお願い" buttons {"設定を開く", "後で"} default button "設定を開く" with icon caution
    if button returned of result is "設定を開く" then
        do shell script "open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"
    end if
    """
    let task = Process()
    task.launchPath = "/usr/bin/osascript"
    task.arguments = ["-e", script]
    task.launch()
    task.waitUntilExit()
    exit(0) // 許可なしでも終了（ゲームは動く、変換だけ無効）
}

// ===========================
// キーイベント変換ロジック
// ===========================
let callback: CGEventTapCallBack = { proxy, type, event, _ in
    guard type == .keyDown || type == .keyUp else {
        return Unmanaged.passRetained(event)
    }

    // ゲームウィンドウがフォアグラウンドの時だけ適用
    // wine-preloader, wine64-preloader, 任意のWindowsアプリ名など幅広く捕捉
    let frontName = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    let frontLocalized = NSWorkspace.shared.frontmostApplication?.localizedName?.lowercased() ?? ""
    let isGameActive = frontLocalized.contains("wine")
        || frontLocalized.contains("crossover")
        || frontLocalized.contains("mac-driver")
        || frontLocalized.contains("blockdestroy")
        || frontName.contains("com.exmacbridge")

    guard isGameActive else {
        return Unmanaged.passRetained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    // ゲーム入力として使うキーは文字コード（Unicode入力）を無効化して純粋なキーコードとして送る
    // これにより「aと入力された」ではなく「Aキーが押された」とゲームが受け取る
    let gameKeys: [Int64] = [
        0,   // A
        1,   // S
        2,   // D
        13,  // W
        6,   // Z
        49,  // Space
        123, // Left Arrow
        124, // Right Arrow
        125, // Down Arrow
        126, // Up Arrow
    ]

    if gameKeys.contains(keyCode) {
        // Unicode文字コード入力を空文字に上書きして「キー押下」だけを送る
        // これにより「aと入力された」ではなく「Aキーが押された」とゲームが受け取る
        var empty: [UniChar] = []
        event.keyboardSetUnicodeString(stringLength: 0, unicodeString: &empty)
    }

    // 矢印キーはそのまま透過（変換不要。WineはVirtual Key codeで矢印を受け取れる）
    // ゲームがWASDを使う場合は別途 KeyConfig 画面で対応予定

    return Unmanaged.passRetained(event)
}

// ===========================
// イベントタップ登録
// ===========================
let eventMask: CGEventMask =
    (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.keyUp.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cghidEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: eventMask,
    callback: callback,
    userInfo: nil
) else {
    // tapCreate失敗 = 許可取り消しなど予期しない状態
    exit(1)
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
CFRunLoopRun()
