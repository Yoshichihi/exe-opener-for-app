import Cocoa
import CoreGraphics
import GameController
import Foundation

// MARK: - Logger
func logMessage(_ message: String) {
    let fileManager = FileManager.default
    guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
    let configDirectory = appSupport.appendingPathComponent("ExMac-Bridge")
    let logFileURL = configDirectory.appendingPathComponent("keymapper.log")
    
    if !fileManager.fileExists(atPath: configDirectory.path) {
        try? fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let timestamp = formatter.string(from: Date())
    let logLine = String(format: "[%@] %@\n", timestamp, message)
    
    if let data = logLine.data(using: .utf8) {
        if fileManager.fileExists(atPath: logFileURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try? data.write(to: logFileURL)
        }
    }
}

class KeyMapperAppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var settingsController: SettingsWindowController?
    var eventTap: CFMachPort?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        logMessage("KeyMapper started.")
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: "ExMac-Bridge")
            if button.image == nil {
                button.title = "🎮"
            }
        }
        
        let menu = NSMenu()
        let prefsItem = NSMenuItem(title: "ExMac-Bridge 設定...", action: #selector(showSettings), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        
        setupGameControllerObserver()
        setupEventTap()
        
        NSApp.setActivationPolicy(.accessory)
    }
    
    @objc func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController()
        }
        settingsController?.showWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func setupGameControllerObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(controllerConnected), name: .GCControllerDidConnect, object: nil)
        GCController.startWirelessControllerDiscovery { }
    }
    
    @objc func controllerConnected(note: Notification) {
        guard let controller = note.object as? GCController else { return }
        logMessage("Controller connected: \(controller.vendorName ?? "Unknown")")
        
        controller.extendedGamepad?.valueChangedHandler = { [weak self] gamepad, element in
            guard let self = self else { return }
            let profile = SettingsManager.shared.activeProfile
            self.handleGamepadElement(gamepad: gamepad, element: element, profile: profile)
        }
    }
    
    func handleGamepadElement(gamepad: GCExtendedGamepad, element: GCControllerElement, profile: KeyMapProfile) {
        let mappings = profile.mappings
        var pressed = false
        var elementKey = ""
        
        if element == gamepad.buttonA { elementKey = "buttonA"; pressed = gamepad.buttonA.isPressed }
        else if element == gamepad.buttonB { elementKey = "buttonB"; pressed = gamepad.buttonB.isPressed }
        else if element == gamepad.buttonX { elementKey = "buttonX"; pressed = gamepad.buttonX.isPressed }
        else if element == gamepad.buttonY { elementKey = "buttonY"; pressed = gamepad.buttonY.isPressed }
        else if element == gamepad.dpad.up { elementKey = "dpad.up"; pressed = gamepad.dpad.up.isPressed }
        else if element == gamepad.dpad.down { elementKey = "dpad.down"; pressed = gamepad.dpad.down.isPressed }
        else if element == gamepad.dpad.left { elementKey = "dpad.left"; pressed = gamepad.dpad.left.isPressed }
        else if element == gamepad.dpad.right { elementKey = "dpad.right"; pressed = gamepad.dpad.right.isPressed }
        else if element == gamepad.buttonMenu { elementKey = "buttonMenu"; pressed = gamepad.buttonMenu.isPressed }
        else if element == gamepad.buttonOptions { elementKey = "buttonOptions"; pressed = gamepad.buttonOptions?.isPressed ?? false }
        
        if elementKey.isEmpty { return }
        
        if let keyCode = mappings[elementKey] {
            logMessage("Gamepad: \(elementKey) pressed=\(pressed) -> keyCode:\(keyCode)")
            postKeyEvent(keyCode: CGKeyCode(keyCode), keyDown: pressed)
        }
    }
    
    func postKeyEvent(keyCode: CGKeyCode, keyDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) else { return }
        
        let arrowKeys: [CGKeyCode] = [123, 124, 125, 126]
        if arrowKeys.contains(keyCode) {
            event.flags.remove(.maskNumericPad)
        }
        
        event.post(tap: .cghidEventTap)
        logMessage("Posted CGEvent keyCode:\(keyCode) keyDown:\(keyDown)")
    }
    
    func setupEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        if !AXIsProcessTrustedWithOptions(options as CFDictionary) {
            logMessage("Accessibility permission denied. Please enable it in System Settings.")
        } else {
            logMessage("Accessibility permission granted.")
        }
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            logMessage("Event tap creation failed.")
            return
        }
        logMessage("Event tap creation successful.")
        eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

let eventTapCallback: CGEventTapCallBack = { proxy, type, event, _ in
    guard type == .keyDown || type == .keyUp else { return Unmanaged.passRetained(event) }
    
    let frontLocalized = NSWorkspace.shared.frontmostApplication?.localizedName?.lowercased() ?? ""
    let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() ?? ""
    let isGameActive = frontLocalized.contains("wine")
        || frontLocalized.contains("crossover")
        || frontLocalized.contains("mac-driver")
        || frontBundle.contains("com.exmacbridge")
        || frontLocalized.contains("blockdestroy")
        || frontLocalized.contains("block")

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags.rawValue

    // 全ての keyDown イベントで詳細なログを出力する
    if type == .keyDown {
        logMessage("KEY DOWN: code=\(keyCode), flags=\(flags), isGameActive=\(isGameActive), frontAppName=\(frontLocalized), frontBundle=\(frontBundle)")
    }

    guard isGameActive else { return Unmanaged.passRetained(event) }
    let profile = SettingsManager.shared.activeProfile
    
    // unicodeStringのクリア処理（※これをやるとWine側でキー入力自体がブロックされてしまうため無効化）
    /*
    if profile.disabledKeys.contains(Int(keyCode)) {
        var empty: [UniChar] = []
        event.keyboardSetUnicodeString(stringLength: 0, unicodeString: &empty)
        if type == .keyDown {
            logMessage("Cleared unicodeString for disabled key: \(keyCode)")
        }
    }
    */
    
    // NumpadおよびFnキー修飾の回避処理（Mac特有の暴発やWineでの認識エラーを防ぐため）
    let arrowKeys: [Int64] = [123, 124, 125, 126]
    if arrowKeys.contains(keyCode) || profile.keyboardMappings?[Int(keyCode)] != nil {
        let oldFlags = event.flags.rawValue
        event.flags.remove(.maskNumericPad)
        event.flags.remove(.maskSecondaryFn) // 音声入力の暴発などを防ぐ
        if type == .keyDown {
            logMessage("Cleaned flags for key: \(keyCode). OldFlags: \(oldFlags), NewFlags: \(event.flags.rawValue)")
        }
    }
    
    // キーマッピング（置換）処理
    if let keyboardMappings = profile.keyboardMappings, let newKeyCode = keyboardMappings[Int(keyCode)] {
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(newKeyCode))
        if type == .keyDown {
            logMessage("Mapped keyCode: \(keyCode) -> \(newKeyCode)")
        }
    }

    return Unmanaged.passRetained(event)
}

@main
struct KeyMapperMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = KeyMapperAppDelegate()
        app.delegate = delegate
        app.run()
    }
}
