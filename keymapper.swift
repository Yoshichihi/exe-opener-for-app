import Cocoa
import CoreGraphics

// ===========================
// キーイベント変換ロジック
// ===========================
let callback: CGEventTapCallBack = { proxy, type, event, _ in
    guard type == .keyDown || type == .keyUp else {
        return Unmanaged.passRetained(event)
    }

    // ゲームウィンドウがフォアグラウンドの時だけ適用
    let frontLocalized = NSWorkspace.shared.frontmostApplication?.localizedName?.lowercased() ?? ""
    let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() ?? ""
    let isGameActive = frontLocalized.contains("wine")
        || frontLocalized.contains("crossover")
        || frontLocalized.contains("mac-driver")
        || frontBundle.contains("com.exmacbridge")
        || frontLocalized.contains("blockdestroy")
        || frontLocalized.contains("block")

    guard isGameActive else {
        return Unmanaged.passRetained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    // ゲームキーはUnicode文字出力を無効化（文字入力ではなくキー入力として送る）
    let gameKeys: [Int64] = [0, 1, 2, 13, 6, 49, 123, 124, 125, 126, 36, 53]
    if gameKeys.contains(keyCode) {
        var empty: [UniChar] = []
        event.keyboardSetUnicodeString(stringLength: 0, unicodeString: &empty)
    }

    return Unmanaged.passRetained(event)
}

// ===========================
// イベントタップ登録（ダイアログなし）
// アクセシビリティが許可されていれば動作、なければ静かに終了
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
    // 許可されていない場合は静かに終了（ゲームの邪魔をしない）
    exit(0)
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
CFRunLoopRun()
