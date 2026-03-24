import Cocoa
import CoreGraphics
import ApplicationServices

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
    // tapCreate失敗 = アクセシビリティが許可されていない場合のみここに来る
    // 許可済みなのにここに来る場合は別の問題（無視して終了）
    let trusted = AXIsProcessTrustedWithOptions(
        [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
    )
    if !trusted {
        // 本当に未許可の場合のみ設定画面へ案内
        let script = """
        set msg to "キーボード操作を最適化するため、アクセシビリティの許可が必要です。\\n\\n【設定手順】\\n1. 設定画面を開く\\n2. 「KeyMapper」または「ExMac-Bridge」を探す\\n3. スイッチをONにする\\n4. ゲームを再起動する"
        display dialog msg with title "アクセシビリティ許可が必要です" buttons {"設定を開く", "後で"} default button "設定を開く" with icon caution
        if button returned of result is "設定を開く" then
            do shell script "open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"
        end if
        """
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        task.launch()
        task.waitUntilExit()
    }
    // 許可済みでもtapCreateが失敗する場合は静かに終了（ゲームの邪魔をしない）
    exit(0)
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
CFRunLoopRun()
