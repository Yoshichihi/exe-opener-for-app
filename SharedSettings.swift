import AppKit
import Foundation

// MARK: - 設定データモデル
struct KeyMapProfile: Codable {
    var name: String
    var controllerType: String // "Xbox", "PlayStation", "Nintendo", "Keyboard"
    var mappings: [String: Int] // コントローラ用: ["buttonA": 49, "dpad.up": 126]
    var keyboardMappings: [Int: Int]? // キーボード置換用: [元のキーコード: 変換後キーコード] (例: [123: 0] = 左矢印をAに)
    var disabledKeys: [Int] // 無効化するキーコード
}

struct SettingsRoot: Codable {
    var currentProfileName: String
    var profiles: [KeyMapProfile]
}

class SettingsManager {
    static let shared = SettingsManager()
    
    let configDirectory: URL
    let configFileURL: URL
    
    var currentProfileName: String = "Default"
    var profiles: [KeyMapProfile] = []
    
    init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        configDirectory = appSupport.appendingPathComponent("ExMac-Bridge")
        configFileURL = configDirectory.appendingPathComponent("keymap.json")
        
        load()
    }
    
    func load() {
        do {
            if !FileManager.default.fileExists(atPath: configDirectory.path) {
                try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true, attributes: nil)
            }
            
            if FileManager.default.fileExists(atPath: configFileURL.path) {
                let data = try Data(contentsOf: configFileURL)
                let decoded = try JSONDecoder().decode(SettingsRoot.self, from: data)
                self.currentProfileName = decoded.currentProfileName
                self.profiles = decoded.profiles
            }
            
            if profiles.isEmpty {
                generateDefaultProfiles()
            }
        } catch {
            print("Settings load error: \(error)")
            generateDefaultProfiles()
        }
    }
    
    func save() {
        do {
            let root = SettingsRoot(currentProfileName: currentProfileName, profiles: profiles)
            let data = try JSONEncoder().encode(root)
            try data.write(to: configFileURL)
        } catch {
            print("Settings save error: \(error)")
        }
    }
    
    func updateActiveProfileMappings(newMappings: [String: Int]) {
        if let idx = profiles.firstIndex(where: { $0.name == currentProfileName }) {
            profiles[idx].mappings = newMappings
            save()
        }
    }
    
    private func generateDefaultProfiles() {
        let keyboardProfile = KeyMapProfile(
            name: "Keyboard Default",
            controllerType: "Keyboard",
            mappings: [:],
            keyboardMappings: [:],
            disabledKeys: []
        )
        let keyboardWASDProfile = KeyMapProfile(
            name: "Keyboard (WASD)",
            controllerType: "Keyboard",
            mappings: [:],
            keyboardMappings: [123: 0, 124: 2, 125: 1, 126: 13, 49: 49],
            disabledKeys: []
        )
        let xboxProfile = KeyMapProfile(
            name: "Xbox Standard",
            controllerType: "Xbox",
            mappings: [
                "buttonA": 49, "buttonB": 6, "buttonX": 0, "buttonY": 1,
                "dpad.up": 126, "dpad.down": 125, "dpad.left": 123, "dpad.right": 124,
                "buttonMenu": 53
            ],
            keyboardMappings: nil,
            disabledKeys: []
        )
        let nintendoProfile = KeyMapProfile(
            name: "Nintendo Switch",
            controllerType: "Nintendo",
            mappings: [
                "buttonA": 6, "buttonB": 49, "buttonX": 1, "buttonY": 0,
                "dpad.up": 126, "dpad.down": 125, "dpad.left": 123, "dpad.right": 124,
                "buttonOptions": 53
            ],
            keyboardMappings: nil,
            disabledKeys: []
        )
        let psProfile = KeyMapProfile(
            name: "PlayStation",
            controllerType: "PlayStation",
            mappings: [
                "buttonA": 49, "buttonB": 6, "buttonX": 0, "buttonY": 1,
                "dpad.up": 126, "dpad.down": 125, "dpad.left": 123, "dpad.right": 124,
                "buttonMenu": 53
            ],
            keyboardMappings: nil,
            disabledKeys: []
        )
        
        self.profiles = [keyboardProfile, keyboardWASDProfile, xboxProfile, nintendoProfile, psProfile]
        currentProfileName = "Keyboard Default"
        save()
    }
    
    var activeProfile: KeyMapProfile {
        return profiles.first(where: { $0.name == currentProfileName }) ?? profiles.first!
    }
}

// MARK: - 設定画面 UI
class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var profilePopup: NSPopUpButton!
    var tableView: NSTableView!
    
    var mappingKeys: [String] = []
    var currentMappings: [String: Int] = [:]
    
    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "ExMac-Bridge 設定"
        window.center()
        self.init(window: window)
        setupUI()
    }
    
    func setupUI() {
        guard let window = self.window else { return }
        let view = NSView(frame: window.contentView!.bounds)
        
        let label = NSTextField(labelWithString: "現在のプロファイル:")
        label.frame = NSRect(x: 20, y: 350, width: 150, height: 20)
        view.addSubview(label)
        
        profilePopup = NSPopUpButton(frame: NSRect(x: 180, y: 345, width: 200, height: 25))
        profilePopup.target = self
        profilePopup.action = #selector(profileSelected(_:))
        view.addSubview(profilePopup)
        
        let descLabel = NSTextField(labelWithString: "キーバインディング (行動名 : 仮想キーコード)")
        descLabel.frame = NSRect(x: 20, y: 310, width: 300, height: 20)
        view.addSubview(descLabel)
        
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 60, width: 410, height: 240))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        
        tableView = NSTableView()
        let col1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ActionColumn"))
        col1.title = "行動 (Action)"
        col1.width = 150
        tableView.addTableColumn(col1)
        
        let col2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("KeyColumn"))
        col2.title = "キーコード (数値)"
        col2.width = 150
        tableView.addTableColumn(col2)
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        
        scrollView.documentView = tableView
        view.addSubview(scrollView)
        
        let saveButton = NSButton(title: "変更を保存", target: self, action: #selector(saveMappings))
        saveButton.frame = NSRect(x: 330, y: 15, width: 100, height: 30)
        saveButton.bezelStyle = .rounded
        view.addSubview(saveButton)
        
        let infoLabel = NSTextField(labelWithString: "※ 変更後「変更を保存」をクリックしてください。\n矢印キー等: 126(上) 125(下) 123(左) 124(右), 49(Space), 6(Z)")
        infoLabel.frame = NSRect(x: 20, y: 15, width: 300, height: 35)
        infoLabel.font = NSFont.systemFont(ofSize: 11)
        infoLabel.textColor = .tertiaryLabelColor
        view.addSubview(infoLabel)
        
        window.contentView = view
        updatePopup()
    }
    
    func updatePopup() {
        profilePopup.removeAllItems()
        let manager = SettingsManager.shared
        manager.load()
        for p in manager.profiles {
            profilePopup.addItem(withTitle: p.name)
        }
        profilePopup.selectItem(withTitle: manager.currentProfileName)
        loadTableData()
    }
    
    func loadTableData() {
        let profile = SettingsManager.shared.activeProfile
        currentMappings = profile.mappings
        mappingKeys = Array(currentMappings.keys).sorted()
        tableView.reloadData()
    }
    
    @objc func profileSelected(_ sender: NSPopUpButton) {
        if let title = sender.titleOfSelectedItem {
            SettingsManager.shared.currentProfileName = title
            SettingsManager.shared.save()
            loadTableData()
        }
    }
    
    @objc func saveMappings() {
        SettingsManager.shared.updateActiveProfileMappings(newMappings: currentMappings)
        let alert = NSAlert()
        alert.messageText = "保存しました"
        alert.informativeText = "キーバインディングを更新しました。"
        alert.runModal()
    }
    
    func showWindow() {
        updatePopup()
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: NSTableViewDataSource
    func numberOfRows(in tableView: NSTableView) -> Int {
        return mappingKeys.count
    }
    
    // MARK: NSTableViewDelegate
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let key = mappingKeys[row]
        let cellIdentifier = NSUserInterfaceItemIdentifier("Cell")
        var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTextField
        
        if cell == nil {
            cell = NSTextField()
            cell?.identifier = cellIdentifier
            cell?.isBordered = false
            cell?.drawsBackground = false
        }
        
        if tableColumn?.identifier.rawValue == "ActionColumn" {
            cell?.stringValue = key
            cell?.isEditable = false
        } else if tableColumn?.identifier.rawValue == "KeyColumn" {
            let val = currentMappings[key] ?? 0
            cell?.stringValue = "\(val)"
            cell?.isEditable = true
            cell?.delegate = self
            // 行番号をタグに保存しておく
            cell?.tag = row
        }
        
        return cell
    }
    
    // テキスト編集完了時に呼ばれる
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        let row = textField.tag
        if row >= 0 && row < mappingKeys.count {
            let key = mappingKeys[row]
            if let intValue = Int(textField.stringValue) {
                currentMappings[key] = intValue
            } else {
                // 不正な値の場合は元に戻す
                textField.stringValue = "\(currentMappings[key] ?? 0)"
            }
        }
    }
}
