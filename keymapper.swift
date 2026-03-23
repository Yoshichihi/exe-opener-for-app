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
        case 126: newKeyCode = 13 // Up Arrow -> W
        case 125: newKeyCode = 1  // Down Arrow -> S
        case 123: newKeyCode = 0  // Left Arrow -> A
        case 124: newKeyCode = 2  // Right Arrow -> D
        case 49: newKeyCode = 6   // Space -> Z
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
    let script = "display dialog \"キー変換機能を利用するには、Macの『システム設定』＞『プライバシーとセキュリティ』＞『アクセシビリティ』から許可を与え、アプリを再起動してください。許可しなくてもキー変換なしでゲームはプレイ可能です。\" with title \"アクセス権限が必要です\" buttons {\"OK\"} default button \"OK\" with icon caution"
    let task = Process()
    task.launchPath = "/usr/bin/osascript"
    task.arguments = ["-e", script]
    task.launch()
    exit(1)
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: eventTap, enable: true)
CFRunLoopRun()
