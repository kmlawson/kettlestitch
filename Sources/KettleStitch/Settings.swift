import AppKit
import CropCore
import Security

/// The Anthropic API key lives in the login keychain, never in the project or preferences.
enum Keychain {
    static let query:[CFString:Any]=[kSecClass:kSecClassGenericPassword,kSecAttrService:"local.kettlestitch.app.anthropic",kSecAttrAccount:"api-key"]
    static func read(_ service:[CFString:Any])->String? {
        var request=service;request[kSecReturnData]=true;request[kSecMatchLimit]=kSecMatchLimitOne
        var item:CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary,&item)==errSecSuccess,let data=item as? Data else{return nil}
        return String(data:data,encoding:.utf8)
    }
    /// A key saved under one of the app's earlier names is copied to the new one the first time it is needed.
    static func read()->String? {
        if let key=read(query) {return key}
        for service in LegacyNames.keychainServices {
            var earlier=query;earlier[kSecAttrService]=service
            if let key=read(earlier),!key.isEmpty {write(key);return key}
        }
        return nil
    }
    @discardableResult static func write(_ key:String)->Bool {
        SecItemDelete(query as CFDictionary)
        var item=query;item[kSecValueData]=Data(key.utf8)
        return SecItemAdd(item as CFDictionary,nil)==errSecSuccess
    }
    static func remove(){SecItemDelete(query as CFDictionary)}
}

final class SettingsController: NSObject {
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:520,height:260),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    let key=NSSecureTextField()
    let model=NSPopUpButton()
    let state=NSTextField(labelWithString:"")
    let message=NSTextField(wrappingLabelWithString:"")
    static let autosaveKey="autosaveProject"
    let autosave=NSButton(checkboxWithTitle:"Save changes automatically every 5 minutes",target:nil,action:nil)
    override init(){
        super.init()
        window.title="KettleStitch Settings";window.isReleasedWhenClosed=false
        func label(_ text:String)->NSTextField {let l=NSTextField(labelWithString:text);l.alignment = .right;return l}
        func help(_ text:String)->NSTextField {let l=NSTextField(wrappingLabelWithString:text);l.font = .systemFont(ofSize:11);l.textColor = .secondaryLabelColor;l.preferredMaxLayoutWidth=330;return l}
        key.placeholderString="sk-ant-…";key.widthAnchor.constraint(equalToConstant:330).isActive=true;key.target=self;key.action=#selector(saveKey)
        let save=NSButton(title:"Save Key",target:self,action:#selector(saveKey)),remove=NSButton(title:"Remove Key",target:self,action:#selector(removeKey))
        let buttons=NSStackView(views:[save,remove,state]);buttons.spacing=8
        state.font = .systemFont(ofSize:11);state.textColor = .secondaryLabelColor
        model.addItems(withTitles:ClaudeReview.models.map{$0.title});model.target=self;model.action=#selector(modelChanged)
        let saved=UserDefaults.standard.string(forKey:"claudeModel");model.selectItem(at:ClaudeReview.models.firstIndex{$0.id==saved} ?? 0)
        message.font = .systemFont(ofSize:12);message.textColor = .systemOrange;message.isHidden=true;message.preferredMaxLayoutWidth=460
        let tool=ClaudeReview.locateExecutable()?.path
        let empty=NSGridCell.emptyContentView
        autosave.target=self;autosave.action=#selector(autosaveChanged);autosave.state=UserDefaults.standard.bool(forKey:Self.autosaveKey) ? .on:.off
        let grid=NSGridView(views:[
            [label("Project:"),autosave],
            [empty,help("Applies once the project has been saved to a file; File ▸ Save writes it at any time. An untitled session is always kept as you work.")],
            [label("Anthropic API Key:"),key],
            [empty,buttons],
            [empty,help("Stored in your login keychain. It is passed to the claude command-line tool only when you choose Send to Claude.")],
            [label("Model:"),model],
            [empty,help("Send to Claude uploads a reduced copy of the photograph and its crop coordinates to Anthropic. Haiku is faster and cheaper; Sonnet looks more carefully.")],
            [label("Command-Line Tool:"),help(tool ?? "claude was not found. Install Claude Code to use Send to Claude.")]])
        grid.rowSpacing=8;grid.columnSpacing=10;grid.column(at:0).xPlacement = .trailing;grid.column(at:1).xPlacement = .leading
        let stack=NSStackView(views:[message,grid]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=false
        let content=NSView();content.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo:content.topAnchor,constant:22),stack.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-24),stack.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-22)])
        window.contentView=content;window.setContentSize(content.fittingSize);window.center()
        refresh()
    }
    /// The field never shows a saved key, so the line beside the buttons and the placeholder have to say there is one.
    func refresh(justSaved:Bool=false){
        let saved=Keychain.read()?.isEmpty==false
        state.stringValue=saved ? (justSaved ? "✓ Key saved in your keychain":"✓ A key is saved"):"No key saved"
        state.textColor=saved ? .systemGreen:.secondaryLabelColor
        key.placeholderString=saved ? "A key is saved — paste another to replace it":"sk-ant-…"
    }
    func explain(_ text:String){message.stringValue=text;message.isHidden=false;window.setContentSize(window.contentView!.fittingSize)}
    func show(){refresh();window.makeKeyAndOrderFront(nil);window.makeFirstResponder(key)}
    @objc func saveKey(){
        let value=key.stringValue.trimmingCharacters(in:.whitespacesAndNewlines);guard !value.isEmpty else{return}
        guard Keychain.write(value) else{state.stringValue="The keychain refused the key";state.textColor = .systemRed;return}
        key.stringValue="";message.isHidden=true;refresh(justSaved:true)
        // Written but not readable back would fail later, at Send to Claude; say so now.
        if Keychain.read() != value {state.stringValue="The key was saved but cannot be read back from the keychain";state.textColor = .systemRed}
    }
    @objc func removeKey(){Keychain.remove();key.stringValue="";refresh()}
    @objc func autosaveChanged(){UserDefaults.standard.set(autosave.state == .on,forKey:Self.autosaveKey)}
    @objc func modelChanged(){UserDefaults.standard.set(ClaudeReview.models[model.indexOfSelectedItem].id,forKey:"claudeModel")}
}
