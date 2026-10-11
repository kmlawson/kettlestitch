import Foundation

/// A key pressed without Command or Control: the character it types, lower-cased, and whether Shift and Option are held.
public struct KeyStroke: Codable, Hashable {
    public var key: String
    public var shift: Bool
    public var option: Bool
    public init(key: String, shift: Bool = false, option: Bool = false) {self.key=key;self.shift=shift;self.option=option}
    var isLetter: Bool {key.count == 1 && key.unicodeScalars.allSatisfy{CharacterSet.letters.contains($0)}}
    /// As it is typed: a small letter on its own, a capital with Shift. A symbol that needs Shift is shown as the symbol.
    public var display: String {
        (option ? "Option ":"")+(shift && isLetter ? "Shift "+key.uppercased():key)
    }
}
/// A command with a key of its own that the user may change.
public struct KeyCommand: Equatable {
    public let id: String
    public let title: String
    public let group: String
    /// The key it has until the user gives it another.
    public let stroke: KeyStroke
}
public enum KeyCommands {
    private static func make(_ group: String, _ rows: [(String,String,String,Bool,Bool)]) -> [KeyCommand] {
        rows.map{KeyCommand(id:$0.0,title:$0.1,group:group,stroke:KeyStroke(key:$0.2,shift:$0.3,option:$0.4))}
    }
    public static let all: [KeyCommand] =
        make("Project",[("new","New project","g",false,false),("open","Open project","o",false,false),("import","Import photographs or a folder","i",false,false),("save","Save the project","s",false,false),("saveAs","Save project as","s",true,false),("export","Export","e",false,false)])
        + make("Pages",[("nextUnreviewed","Next unreviewed page","n",false,false),("nextUnusual","Next unusual page",".",false,false),("flag","Add or remove a flag","m",false,false),("rotateRight","Turn the page clockwise","r",false,false),("rotateLeft","Turn the page counterclockwise","r",true,false)])
        + make("Cropping frame",[("detect","Detect this photograph; with several selected, all pending","d",false,false),("detectPending","Detect all pending photographs","b",false,false),("previousProposal","Previous proposal","[",false,false),("nextProposal","Next proposal","]",false,false),("copyCrop","Copy the previous photograph's crop","c",false,false),("fullImage","Set the crop to the full image","x",false,false),("shrink","Shrink the whole crop",";",false,false),("expand","Expand the whole crop","'",false,false),
            ("corner1","Select the top-left corner","1",false,false),("corner2","Select the top-right corner","2",false,false),("corner3","Select the bottom-left corner","3",false,false),("corner4","Select the bottom-right corner","4",false,false),("edge1","Select the top edge","5",false,false),("edge2","Select the left edge","6",false,false),("edge3","Select the right edge","7",false,false),("edge4","Select the bottom edge","8",false,false)])
        + make("Page split",[("split","Propose a split; again for the next candidate","t",false,false),("removeSplit","Remove the split","t",true,false),("splitAll","Propose a split on every page that has none","t",false,true),("splitLeft","Move the split left","y",false,false),("splitRight","Move the split right","u",false,false),("splitLeftFar","Move the split left, farther","y",true,false),("splitRightFar","Move the split right, farther","u",true,false)])
        + make("Deskew and picture zones",[("deskew","Deskew: level the lines of text","q",false,false),("removeDeskew","Remove the deskew","q",true,false),("deskewCounterclockwise","Turn the page counterclockwise by 0.1°",",",false,true),("deskewClockwise","Turn the page clockwise by 0.1°",".",false,true),("deskewHalf","On a split spread, deskew both pages, the left or the right","/",false,true),("zone","Draw a picture zone","w",false,false),("removeZones","Remove the picture zones","w",true,false)])
        + make("Smudge and clone",[("smudge","Pick up or put down the smudge brush","b",true,false),("removeSmudges","Remove the smudges","b",true,true),("clone","Pick up or put down the clone brush","c",true,false),("removeClones","Remove what the clone brush painted","c",true,true)])
        + make("Output and view",[("preview","Corrected preview","p",false,false),("copyImageSettings","Copy the previous photograph's image settings","v",false,false),("fit","Zoom to fit","f",false,false),("zoomIn","Zoom in","=",false,false),("zoomOut","Zoom out","-",false,false),("secondOpinion","Send for a second opinion","a",false,false),("undo","Undo","z",false,false),("redo","Redo","z",true,false),("help","Show the keyboard shortcuts","/",false,false)])
    private static let byID=Dictionary(uniqueKeysWithValues:all.map{($0.id,$0)})
    public static func named(_ id: String) -> KeyCommand? {byID[id]}
    /// Keys whose every combination with Shift and Option resizes or moves the crop. They are not offered for change.
    public static let reserved: Set<String> = ["h","j","k","l"]
    /// Other ways of typing a command's key that have always worked: ? for /, + for =, 0 for f.
    static let spellings: [KeyStroke:String] = [KeyStroke(key:"?",shift:true):"help",KeyStroke(key:"+",shift:true):"zoomIn",KeyStroke(key:"0"):"fit"]
}
/// Which key runs which command: the defaults, with the user's changes over them. Every command always has
/// exactly one key and no two share one.
public struct KeyBindings: Equatable {
    public private(set) var overrides: [String:KeyStroke] = [:]
    public init() {}
    public static let key = "keyBindings"
    /// Why a key cannot be given to a command, or nil if it can.
    public static func refusal(_ stroke: KeyStroke) -> String? {
        guard stroke.key.count == 1,let scalar=stroke.key.unicodeScalars.first,stroke.key.unicodeScalars.count == 1 else {return "Press a single key."}
        if KeyCommands.reserved.contains(stroke.key) {return "h, j, k and l resize and move the crop with every combination of Shift and Option, so they cannot be given to another command."}
        if scalar.value<0x21 || scalar.value == 0x7f || (0xF700...0xF8FF).contains(scalar.value) || CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return "The arrow keys, Return, Escape, Space, Tab, Delete and the function keys keep their own jobs."
        }
        return nil
    }
    public func stroke(for id: String) -> KeyStroke? {overrides[id] ?? KeyCommands.named(id)?.stroke}
    public func command(for stroke: KeyStroke) -> KeyCommand? {KeyCommands.all.first{self.stroke(for:$0.id) == stroke}}
    /// The command that holds `stroke` now, if it is not `id` itself.
    public func conflict(_ stroke: KeyStroke, with id: String) -> KeyCommand? {command(for:stroke).flatMap{$0.id == id ? nil:$0}}
    /// The commands whose key is not the one they started with.
    public var changed: [KeyCommand] {KeyCommands.all.filter{overrides[$0.id] != nil}}
    private mutating func set(_ id: String, _ stroke: KeyStroke) {overrides[id]=stroke == KeyCommands.named(id)?.stroke ? nil:stroke}
    /// Gives `stroke` to a command. A command that held it takes this command's old key in exchange, and is returned.
    @discardableResult public mutating func assign(_ stroke: KeyStroke, to id: String) -> KeyCommand? {
        guard KeyCommands.named(id) != nil,Self.refusal(stroke) == nil,let old=self.stroke(for:id),old != stroke else {return nil}
        let other=conflict(stroke,with:id)
        set(id,stroke);if let other {set(other.id,old)}
        return other
    }
    public mutating func reset(_ id: String) {if let command=KeyCommands.named(id) {assign(command.stroke,to:id)}}
    public mutating func resetAll() {overrides=[:]}
    public enum Translation: Equatable {
        /// The key pressed runs the command that has this key by default.
        case run(KeyStroke)
        /// The key belonged to a command that now has another, so it does nothing.
        case nothing
        /// Not a key the bindings govern: it means what it always has.
        case unchanged
    }
    /// What a key press means with these bindings, in terms of the default keys the app's key handling is written for.
    public func translate(_ pressed: KeyStroke) -> Translation {
        if let command=command(for:pressed) {return .run(command.stroke)}
        if let id=KeyCommands.spellings[pressed] {return overrides[id] == nil ? .unchanged:.nothing}
        // A key whose command has moved away is free, whatever is held with it.
        return changed.contains{$0.stroke.key == pressed.key} ? .nothing:.unchanged
    }
    public func encode() throws -> Data {try JSONEncoder().encode(overrides)}
    /// Reads saved changes, leaving out any that no longer make sense.
    public static func decode(_ data: Data?) -> KeyBindings {
        var bindings=KeyBindings()
        guard let data,let saved=try? JSONDecoder().decode([String:KeyStroke].self,from:data) else {return bindings}
        for (id,stroke) in saved where KeyCommands.named(id) != nil && refusal(stroke) == nil {bindings.set(id,stroke)}
        // Two commands on one key cannot both be meant; those changes are dropped until every key is its own again.
        while true {
            let held=Dictionary(grouping:KeyCommands.all,by:{bindings.stroke(for:$0.id)!}).values.filter{$0.count>1}.flatMap{$0}.filter{bindings.overrides[$0.id] != nil}
            guard !held.isEmpty else {break}
            for command in held {bindings.overrides[command.id]=nil}
        }
        return bindings
    }
}
extension ShortcutReference {
    /// Which commands each row of the reference describes, by the row's keys as written.
    public static let rowCommands: [String:[String]] = [
        "G":["new"],"O":["open"],"I":["import"],"S":["save"],"Shift S":["saveAs"],"E":["export"],
        "N":["nextUnreviewed"],".":["nextUnusual"],"M":["flag"],
        "D":["detect"],"B":["detectPending"],"[ / ]":["previousProposal","nextProposal"],"C":["copyCrop"],"X":["fullImage"],"; / '":["shrink","expand"],
        "1 2 3 4":["corner1","corner2","corner3","corner4"],"5 6 7 8":["edge1","edge2","edge3","edge4"],
        "T":["split"],"Shift T":["removeSplit"],"Option t":["splitAll"],"Y / U":["splitLeft","splitRight","splitLeftFar","splitRightFar"],
        "Q":["deskew"],"Shift Q":["removeDeskew"],"Option , / .":["deskewCounterclockwise","deskewClockwise"],"Option /":["deskewHalf"],"W":["zone"],"Shift W":["removeZones"],
        "Shift B":["smudge"],"Option Shift B":["removeSmudges"],"Shift C":["clone"],"Option Shift C":["removeClones"],
        "P":["preview"],"V":["copyImageSettings"],"R":["rotateRight"],"Shift R":["rotateLeft"],"+ / −":["zoomIn","zoomOut"],"F or 0":["fit"],"A":["secondOpinion"],"Z":["undo"],"Shift Z":["redo"],"?":["help"],
    ]
    /// The reference with the user's keys. A row is left as written unless one of its commands has moved; then each
    /// of its commands gets a line of its own with the key it has now.
    public static func sections(with bindings: KeyBindings) -> [Section] {
        let moved=Set(bindings.changed.map{$0.id});guard !moved.isEmpty else {return sections}
        let rows=Dictionary(uniqueKeysWithValues:rowCommands.map{(shown($0.key),$0.value)})
        return sections.map{section in
            Section(title:section.title,entries:section.entries.flatMap{entry->[Entry] in
                guard let ids=rows[entry.keys],!moved.isDisjoint(with:ids) else {return [entry]}
                return ids.compactMap{id in KeyCommands.named(id).map{Entry(keys:bindings.stroke(for:id)!.display,action:$0.title)}}
            })
        }
    }
    /// The few keys kept in view in the inspector, as they are now.
    public static func brief(with bindings: KeyBindings) -> [Entry] {
        func key(_ id: String) -> String {bindings.stroke(for:id)?.display ?? ""}
        return [Entry(keys:"← / →",action:"Previous / next image"),Entry(keys:key("copyCrop"),action:"Set crop to same as previous image"),Entry(keys:key("copyImageSettings"),action:"Copy image settings from previous image"),
                Entry(keys:key("split"),action:"Propose split"),Entry(keys:key("rotateRight"),action:"Rotate (\(key("rotateLeft")) for reverse)"),Entry(keys:key("shrink")+" / "+key("expand"),action:"Decrease / increase current crop"),
                Entry(keys:"h j k l",action:"Increase crop edges (Shift to decrease, Option to move crop)"),Entry(keys:key("help"),action:"See more shortcuts")]
    }
}
