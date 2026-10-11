import AppKit
import CropCore
import Security

/// API keys live in the login keychain, one item for each provider, never in the project or preferences.
/// This is the only code that reads or writes them. A key leaves here in one direction only: `sendToClaude`
/// hands it to `ClaudeReview.run`, which puts it in a header of the request to that provider's own address.
enum Keychain {
    static func query(_ provider:ReviewProvider)->[CFString:Any] {[kSecClass:kSecClassGenericPassword,kSecAttrService:"local.kettlestitch.app."+provider.rawValue,kSecAttrAccount:"api-key"]}
    /// A test run is a different build from the app that saved the key, so touching the keychain makes macOS ask
    /// for the login password. Test mode therefore leaves it alone unless `KETTLESTITCH_TEST_KEYCHAIN` asks for it.
    static let enabled:Bool={
        let environment=ProcessInfo.processInfo.environment
        return environment["KETTLESTITCH_TEST_DIR"] == nil || environment["KETTLESTITCH_TEST_KEYCHAIN"] != nil
    }()
    /// What macOS answered the last time a key was asked for, to explain a refusal.
    private(set) static var lastStatus:OSStatus=errSecSuccess
    static func read(_ service:[CFString:Any])->String? {
        guard enabled else{return nil}
        var request=service;request[kSecReturnData]=true;request[kSecMatchLimit]=kSecMatchLimitOne
        var item:CFTypeRef?
        lastStatus=SecItemCopyMatching(request as CFDictionary,&item)
        guard lastStatus==errSecSuccess,let data=item as? Data else{return nil}
        return String(data:data,encoding:.utf8)
    }
    /// The app's own program file as it was at launch. macOS ties access to a keychain item to the program that
    /// asks; when the file is replaced by a newer build while this copy is still running, the running copy no
    /// longer matches what is on disk and is refused its own key until it is reopened.
    private static let launched=fingerprint()
    private static func fingerprint()->String? {
        guard let path=Bundle.main.executablePath,let attributes=try? FileManager.default.attributesOfItem(atPath:path) else{return nil}
        return "\(attributes[.systemFileNumber] ?? 0)/\(attributes[.modificationDate] ?? Date.distantPast)"
    }
    /// Call once at launch, before anything can have replaced the file.
    static func noteLaunch(){_=launched}
    static var replacedSinceLaunch:Bool {launched != nil && fingerprint() != launched}
    static let reopenAdvice="KettleStitch was updated while it was running, so macOS will not let this copy read the keychain. Quit and reopen KettleStitch."
    /// Why a key that should be there could not be read, in words for the user.
    static var refusal:String {
        if replacedSinceLaunch {return reopenAdvice}
        let said=SecCopyErrorMessageString(lastStatus,nil) as String? ?? "error \(lastStatus)"
        return "macOS would not hand the key back (\(said)). If it asked for permission, choose Always Allow; otherwise quit and reopen KettleStitch."
    }
    /// An Anthropic key saved under one of the app's earlier names is copied to the new one the first time it is needed.
    static func read(_ provider:ReviewProvider = .anthropic)->String? {
        if let key=read(query(provider)) {return key}
        guard provider == .anthropic else{return nil}
        for service in LegacyNames.keychainServices {
            var earlier=query(provider);earlier[kSecAttrService]=service
            if let key=read(earlier),!key.isEmpty {write(key,provider);return key}
        }
        return nil
    }
    @discardableResult static func write(_ key:String,_ provider:ReviewProvider = .anthropic)->Bool {
        guard enabled else{return false}
        SecItemDelete(query(provider) as CFDictionary)
        var item=query(provider);item[kSecValueData]=Data(key.utf8)
        return SecItemAdd(item as CFDictionary,nil)==errSecSuccess
    }
    static func remove(_ provider:ReviewProvider = .anthropic){if enabled{SecItemDelete(query(provider) as CFDictionary)}}
}
/// Which provider and model Send to… uses, as chosen in Settings.
enum ReviewChoice {
    static var provider:ReviewProvider {
        get {UserDefaults.standard.string(forKey:"reviewProvider").flatMap(ReviewProvider.init(rawValue:)) ?? .anthropic}
        set {UserDefaults.standard.set(newValue.rawValue,forKey:"reviewProvider")}
    }
    /// The Anthropic choice keeps the name it was saved under before there were other providers.
    static func modelKey(_ provider:ReviewProvider)->String {provider == .anthropic ? "claudeModel":"reviewModel."+provider.rawValue}
    static func model(for provider:ReviewProvider)->ReviewModel {ReviewModel.chosen(UserDefaults.standard.string(forKey:modelKey(provider)),for:provider)}
    static var model:ReviewModel {model(for:provider)}
    /// The model as it is named while waiting and in the log: "Claude Haiku 5.5", "GPT-6 Luna".
    static func displayName(_ model:ReviewModel)->String {model.provider == .anthropic ? "Claude "+model.title:model.title}
}

final class SettingsController: NSObject {
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:520,height:260),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    let provider=NSPopUpButton()
    let key=NSSecureTextField()
    let keyLabel=NSTextField(labelWithString:"")
    let model=NSPopUpButton()
    let state=NSTextField(labelWithString:"")
    let message=NSTextField(wrappingLabelWithString:"")
    let sends=NSTextField(wrappingLabelWithString:"")
    static let autosaveKey="autosaveProject"
    /// Off unless the user turns it on: the app then asks GitHub once at launch whether a newer version exists.
    static let startupUpdateKey="checkForUpdatesOnStartup"
    let startupUpdates=NSButton(checkboxWithTitle:"Check for updates on startup",target:nil,action:nil)
    /// How picture zones on Black & White pages are rendered, in the order offered.
    static let zoneKey="pictureZoneMode",zoneModes:[(title:String,mode:Cleanup)]=[("Grayscale",.grayscale),("Color",.color),("None",.none)]
    static var zoneMode:Cleanup {zoneModes.first{$0.mode.rawValue==UserDefaults.standard.string(forKey:zoneKey)}?.mode ?? .grayscale}
    let zones=NSPopUpButton()
    let autosave=NSButton(checkboxWithTitle:"Save changes automatically every 5 minutes",target:nil,action:nil)
    /// The Shortcuts tab.
    let keys=ShortcutSettings()
    let tabs=NSTabView()
    var general:NSView!
    /// Called when the provider changes, so the main window's command can say who it sends to.
    var onChange:(()->Void)?
    var chosen:ReviewProvider {ReviewProvider.allCases[max(0,provider.indexOfSelectedItem)]}
    override init(){
        super.init()
        window.title="KettleStitch Settings";window.isReleasedWhenClosed=false
        func label(_ text:String)->NSTextField {let l=NSTextField(labelWithString:text);l.alignment = .right;return l}
        func help(_ text:String)->NSTextField {let l=NSTextField(wrappingLabelWithString:text);l.font = .systemFont(ofSize:11);l.textColor = .secondaryLabelColor;l.preferredMaxLayoutWidth=330;return l}
        provider.addItems(withTitles:ReviewProvider.allCases.map{$0.name == $0.company ? $0.name:"\($0.name) (\($0.company))"});provider.target=self;provider.action=#selector(providerChanged)
        provider.selectItem(at:ReviewProvider.allCases.firstIndex(of:ReviewChoice.provider) ?? 0)
        key.widthAnchor.constraint(equalToConstant:330).isActive=true;key.target=self;key.action=#selector(saveKey)
        keyLabel.alignment = .right
        let save=NSButton(title:"Save Key",target:self,action:#selector(saveKey)),remove=NSButton(title:"Remove Key",target:self,action:#selector(removeKey))
        let buttons=NSStackView(views:[save,remove,state]);buttons.spacing=8
        state.font = .systemFont(ofSize:11);state.textColor = .secondaryLabelColor
        model.target=self;model.action=#selector(modelChanged)
        message.font = .systemFont(ofSize:12);message.textColor = .systemOrange;message.isHidden=true;message.preferredMaxLayoutWidth=460
        sends.font = .systemFont(ofSize:11);sends.textColor = .secondaryLabelColor;sends.preferredMaxLayoutWidth=330
        let empty=NSGridCell.emptyContentView
        autosave.target=self;autosave.action=#selector(autosaveChanged);autosave.state=UserDefaults.standard.bool(forKey:Self.autosaveKey) ? .on:.off
        zones.addItems(withTitles:Self.zoneModes.map{$0.title});zones.selectItem(at:Self.zoneModes.firstIndex{$0.mode==Self.zoneMode} ?? 0)
        zones.target=self;zones.action=#selector(zonesChanged)
        startupUpdates.target=self;startupUpdates.action=#selector(startupUpdatesChanged);startupUpdates.state=UserDefaults.standard.bool(forKey:Self.startupUpdateKey) ? .on:.off
        let grid=NSGridView(views:[
            [label("Project:"),autosave],
            [empty,help("Applies once the project has been saved to a file; File ▸ Save writes it at any time. An untitled session is always kept as you work.")],
            [label("Updates:"),startupUpdates],
            [empty,help("Asks GitHub once, when KettleStitch opens, whether a newer version exists, and says so in the status bar. Nothing is downloaded, and nothing about you or your work is sent.")],
            [label("Picture Zones:"),zones],
            [empty,help("How a picture zone on a Black & White page is kept. Grayscale keeps its gray tones and Color its colours, both with the page's exposure, brightness and contrast. None leaves it exactly as photographed.")],
            [label("Second Opinion From:"),provider],
            [empty,help("Optional. Sends a page's crop to a model of your choice to be checked, using your own API key for that provider. Nothing else needs to be installed.")],
            [keyLabel,key],
            [empty,buttons],
            [empty,help("Stored in your login keychain, one key for each provider. A key is sent only to its own provider, and only when you choose Send.")],
            [label("Model:"),model],
            [empty,sends]])
        grid.rowSpacing=8;grid.columnSpacing=10;grid.column(at:0).xPlacement = .trailing;grid.column(at:1).xPlacement = .leading
        let stack=NSStackView(views:[message,grid]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=false
        let content=NSView();content.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo:content.topAnchor,constant:22),stack.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-24),stack.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-22)])
        general=content
        let first=NSTabViewItem(identifier:"general");first.label="General";first.view=content
        let second=NSTabViewItem(identifier:"shortcuts");second.label="Shortcuts";second.view=keys.view
        tabs.addTabViewItem(first);tabs.addTabViewItem(second)
        let holder=NSView(frame:NSRect(x:0,y:0,width:600,height:500));tabs.frame=holder.bounds.insetBy(dx:8,dy:8);tabs.autoresizingMask=[.width,.height];holder.addSubview(tabs)
        window.contentView=holder
        showProvider()
        resize();window.center()
    }
    /// Fills the key and model rows for the provider chosen.
    func showProvider(){
        let which=chosen,models=ReviewModel.models(for:which)
        keyLabel.stringValue="\(which.company) API Key:"
        model.removeAllItems();model.addItems(withTitles:models.map{$0.title})
        model.selectItem(at:models.firstIndex(of:ReviewChoice.model(for:which)) ?? 0)
        sends.stringValue="Send to \(which.name) uploads a reduced copy of the photograph and its crop coordinates to \(which.company), billed to your key. The models are listed cheapest first; the later ones look more carefully."
        key.stringValue="";refresh()
    }
    /// The field never shows a saved key, so the line beside the buttons and the placeholder have to say there is one.
    func refresh(justSaved:Bool=false){
        let saved=Keychain.read(chosen)?.isEmpty==false
        state.stringValue=saved ? (justSaved ? "✓ Key saved in your keychain":"✓ A key is saved"):"No key saved"
        state.textColor=saved ? .systemGreen:.secondaryLabelColor
        key.placeholderString=saved ? "A key is saved — paste another to replace it":chosen.keyHint
        // A key may be there and yet unreadable by this copy of the app; say why instead of "No key saved".
        if !saved,Keychain.replacedSinceLaunch {state.stringValue="Cannot read the keychain until reopened";state.textColor = .systemOrange;explain(Keychain.reopenAdvice)}
    }
    func explain(_ text:String){message.stringValue=text;message.isHidden=false;resize()}
    func show(){provider.selectItem(at:ReviewProvider.allCases.firstIndex(of:ReviewChoice.provider) ?? 0);showProvider();window.makeKeyAndOrderFront(nil);window.makeFirstResponder(key)}
    /// Sizes the window to the General tab, which is the taller; the Shortcuts tab's list fills whatever that gives it.
    func resize(){
        let fit=general.fittingSize,chrome=NSSize(width:tabs.frame.width-tabs.contentRect.width+16,height:tabs.frame.height-tabs.contentRect.height+16)
        window.setContentSize(NSSize(width:max(fit.width,560)+chrome.width,height:max(fit.height,380)+chrome.height))
    }
    @objc func providerChanged(){ReviewChoice.provider=chosen;message.isHidden=true;showProvider();resize();onChange?()}
    @objc func saveKey(){
        let value=key.stringValue.trimmingCharacters(in:.whitespacesAndNewlines);guard !value.isEmpty else{return}
        guard Keychain.write(value,chosen) else{state.stringValue="The keychain refused the key";state.textColor = .systemRed;return}
        key.stringValue="";message.isHidden=true;refresh(justSaved:true)
        // Written but not readable back would fail later, at Send; say so now.
        if Keychain.read(chosen) != value {state.stringValue="Saved, but it cannot be read back";state.textColor = .systemRed;explain("Your key is saved. "+Keychain.refusal)}
    }
    @objc func removeKey(){Keychain.remove(chosen);key.stringValue="";refresh()}
    @objc func zonesChanged(){
        let mode=Self.zoneModes[max(0,zones.indexOfSelectedItem)].mode
        UserDefaults.standard.set(mode.rawValue,forKey:Self.zoneKey);Imaging.pictureZoneMode=mode;onChange?()
    }
    @objc func startupUpdatesChanged(){UserDefaults.standard.set(startupUpdates.state == .on,forKey:Self.startupUpdateKey)}
    @objc func autosaveChanged(){UserDefaults.standard.set(autosave.state == .on,forKey:Self.autosaveKey)}
    @objc func modelChanged(){UserDefaults.standard.set(ReviewModel.models(for:chosen)[max(0,model.indexOfSelectedItem)].id,forKey:ReviewChoice.modelKey(chosen))}
}

/// Settings ▸ Shortcuts: every command that has a key of its own, with the key it has now, and a way to change it.
final class ShortcutSettings: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let view=NSView()
    let table=NSTableView(),search=NSSearchField(),note=NSTextField(wrappingLabelWithString:"")
    let changeButton=NSButton(title:"Change Key…",target:nil,action:nil),resetButton=NSButton(title:"Reset",target:nil,action:nil),resetAllButton=NSButton(title:"Reset All",target:nil,action:nil)
    var bindings:(()->KeyBindings)?
    var change:((KeyBindings)->Void)?
    private(set) var rows:[KeyCommand]=KeyCommands.all
    /// The command whose new key is being waited for.
    private(set) var capturing:String?
    private var monitor:Any?
    static let standing="Select a command and choose Change Key, then press the key you want, with Shift or Option if you like. A key already in use is exchanged with the command that had it. Command shortcuts, the arrow keys and h j k l are fixed."
    override init(){
        super.init()
        for (id,title,width) in [("command","Command",250),("group","Group",130),("key","Key",130)] as [(String,String,CGFloat)] {
            let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(id));column.title=title;column.width=width;table.addTableColumn(column)
        }
        table.dataSource=self;table.delegate=self;table.usesAlternatingRowBackgroundColors=true;table.allowsMultipleSelection=false;table.target=self;table.doubleAction=#selector(startChange)
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.documentView=table;scroll.borderType = .bezelBorder
        search.placeholderString="Search commands and keys";search.delegate=self;search.target=self;search.action=#selector(filter)
        note.font = .systemFont(ofSize:11);note.textColor = .secondaryLabelColor;note.stringValue=Self.standing
        changeButton.target=self;changeButton.action=#selector(startChange);resetButton.target=self;resetButton.action=#selector(resetSelected);resetAllButton.target=self;resetAllButton.action=#selector(resetAll)
        let buttons=NSStackView(views:[changeButton,resetButton,NSView(),resetAllButton])
        let stack=NSStackView(views:[search,scroll,note,buttons]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=false
        view.addSubview(stack)
        for item in [search,scroll,note,buttons] as [NSView] {item.translatesAutoresizingMaskIntoConstraints=false;item.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true}
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo:view.topAnchor,constant:16),stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-16),stack.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-16)])
        showSelection()
    }
    var current:KeyBindings {bindings?() ?? KeyBindings()}
    var selected:KeyCommand? {rows.indices.contains(table.selectedRow) ? rows[table.selectedRow]:nil}
    @objc func filter(){
        let wanted=search.stringValue.trimmingCharacters(in:.whitespaces).lowercased(),now=current
        rows=KeyCommands.all.filter{wanted.isEmpty || $0.title.lowercased().contains(wanted) || $0.group.lowercased().contains(wanted) || (now.stroke(for:$0.id)?.display.lowercased() ?? "")==wanted}
        table.reloadData();showSelection()
    }
    func controlTextDidChange(_ notification:Notification){filter()}
    func showSelection(){
        let chosen=selected,now=current
        changeButton.isEnabled=chosen != nil;resetButton.isEnabled=chosen.map{now.stroke(for:$0.id) != $0.stroke} ?? false;resetAllButton.isEnabled = !now.changed.isEmpty
    }
    func numberOfRows(in tableView:NSTableView)->Int {rows.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        let id=tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("command"),command=rows[row],stroke=current.stroke(for:command.id)
        let cell=tableView.makeView(withIdentifier:id,owner:nil) as? NSTableCellView ?? {
            let cell=NSTableCellView(),label=NSTextField(labelWithString:"");label.lineBreakMode = .byTruncatingTail;label.translatesAutoresizingMaskIntoConstraints=false
            cell.identifier=id;cell.addSubview(label);cell.textField=label
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:2),label.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-2),label.centerYAnchor.constraint(equalTo:cell.centerYAnchor)])
            return cell
        }()
        let moved=stroke != command.stroke
        switch id.rawValue {
        case "group":cell.textField?.stringValue=command.group;cell.textField?.textColor = .secondaryLabelColor;cell.textField?.font = .systemFont(ofSize:12)
        case "key":
            cell.textField?.stringValue=capturing==command.id ? "Press a key…":(stroke?.display ?? "")
            cell.textField?.font = .monospacedSystemFont(ofSize:12,weight:moved ? .bold:.medium);cell.textField?.textColor=capturing==command.id ? .controlAccentColor:.labelColor
            cell.textField?.toolTip=moved ? "Changed from \(command.stroke.display)":nil
        default:cell.textField?.stringValue=command.title;cell.textField?.textColor = .labelColor;cell.textField?.font = .systemFont(ofSize:12);cell.textField?.toolTip=command.title
        }
        return cell
    }
    func tableViewSelectionDidChange(_ notification:Notification){if capturing != nil {stopCapture()};showSelection()}
    /// Waits for the next key press in this window and gives it to the selected command. Escape cancels.
    @objc func startChange(){
        guard let command=selected else{return}
        stopCapture();capturing=command.id;note.stringValue="Press the new key for “\(command.title)”. Escape cancels.";note.textColor = .controlAccentColor
        view.window?.makeFirstResponder(table);table.reloadData(forRowIndexes:IndexSet(integer:table.selectedRow),columnIndexes:IndexSet(integer:2))
        monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in
            guard let self,let id=self.capturing,event.window===self.view.window else{return event}
            if event.keyCode==53 {self.stopCapture();return nil}
            guard event.modifierFlags.isDisjoint(with:[.command,.control]),let typed=event.charactersIgnoringModifiers?.lowercased() else{self.stopCapture("Shortcuts with Command or Control are fixed. Choose a key on its own, or with Shift or Option.");return nil}
            self.stopCapture()
            self.assign(KeyStroke(key:typed,shift:event.modifierFlags.contains(.shift),option:event.modifierFlags.contains(.option)),to:id){other,stroke in
                let alert=NSAlert();alert.messageText="“\(stroke.display)” is the key for “\(other.title)”";alert.informativeText="Exchange the two? “\(other.title)” would take the key this command has now."
                alert.addButton(withTitle:"Exchange");alert.addButton(withTitle:"Cancel");return alert.runModal() == .alertFirstButtonReturn
            }
            return nil
        }
    }
    func stopCapture(_ message:String?=nil){
        if let monitor {NSEvent.removeMonitor(monitor)};monitor=nil;capturing=nil
        note.stringValue=message ?? Self.standing;note.textColor=message == nil ? .secondaryLabelColor:.systemOrange;table.reloadData();showSelection()
    }
    /// Gives a key to a command. `confirm` is asked before a key is taken from the command that has it.
    @discardableResult func assign(_ stroke:KeyStroke,to id:String,confirm:(KeyCommand,KeyStroke)->Bool)->Bool {
        if let refusal=KeyBindings.refusal(stroke) {stopCapture(refusal);return false}
        var now=current
        if let other=now.conflict(stroke,with:id),!confirm(other,stroke) {return false}
        let exchanged=now.assign(stroke,to:id);change?(now)
        let title=KeyCommands.named(id)?.title ?? id
        stopCapture();note.stringValue=exchanged.map{"“\(title)” is now \(stroke.display), and “\($0.title)” is \(now.stroke(for:$0.id)?.display ?? "")."} ?? "“\(title)” is now \(stroke.display)."
        return true
    }
    @objc func resetSelected(){guard let command=selected else{return};var now=current;now.reset(command.id);change?(now);stopCapture()}
    @objc func resetAll(){var now=current;now.resetAll();change?(now);stopCapture()}
}
