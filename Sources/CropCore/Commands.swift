import Foundation

public enum MenuCommand: CaseIterable {
    case newProject, openProject, importPhotographs, locatePhotographs, save, saveAs, export, settings, help
    case undo, redo, copySettings, pasteSettings, copyRotation, pasteRotation, applySettingsToAll, resetAdjustments
    case nextPage, previousPage, firstPage, lastPage, nextUnreviewed, nextFlagged, accept
    case selectAllPages, flag, reversePages, removePages, rotateLeft, rotateRight
    case detect, detectPending, nextProposal, previousProposal, fullImage, copyPreviousCrop
    case proposeSplit, removeSplit, moveSplitLeft, moveSplitRight, sendToClaude, stop
    case deskew, removeDeskew, deskewClockwise, deskewCounterclockwise, addPictureZone, removePictureZones, showDeviations, nextOutlier
    case preview, zoomIn, zoomOut, zoomToFit, toggleSidebar, toggleInspector
}
/// Everything the menus need to know about the app, gathered in one value so the rules can be tested.
public struct MenuState {
    public var pageCount = 0
    public var current: Int?
    /// Pages a settings command would apply to.
    public var targetCount = 0
    public var canUndo = false
    public var canRedo = false
    public var editingText = false
    public var textCanUndo = false
    public var textCanRedo = false
    public var hasCopiedSettings = false
    public var targetsHaveAdjustments = false
    public var proposalCount = 0
    public var pendingCount = 0
    public var unreviewedCount = 0
    public var flaggedCount = 0
    public var currentFlagged = false
    public var currentHasSplit = false
    public var targetsHaveSplit = false
    public var targetsHaveDeskew = false
    public var targetsHaveZones = false
    public var outlierCount = 0
    public var detecting = false
    public var exporting = false
    public var reviewing = false
    public var previewing = false
    public var sidebarVisible = false
    public var inspectorVisible = false
    /// False while a sheet or another window has the keyboard.
    public var windowActive = true
    /// Who Send to… goes to: Claude, OpenAI or Gemini, as chosen in Settings.
    public var reviewer = "Claude"
    /// True once a page's rotation has been copied, so that it can be pasted.
    public var rotationCopied = false
    public init() {}
}
public enum MenuPolicy {
    public static func isEnabled(_ command: MenuCommand, _ s: MenuState) -> Bool {
        let hasPage=s.current != nil && s.pageCount>0
        let busy=s.detecting || s.exporting || s.reviewing
        // While a field is being edited, keys such as Command-Delete belong to the text.
        let editable=hasPage && !s.editingText
        if !s.windowActive {
            switch command {
            case .settings,.help:return true
            case .undo:return s.editingText && s.textCanUndo
            case .redo:return s.editingText && s.textCanRedo
            default:return false
            }
        }
        switch command {
        case .newProject,.openProject,.importPhotographs,.save,.saveAs,.settings,.help,.zoomIn,.zoomOut,.zoomToFit,.toggleSidebar,.toggleInspector:return true
        case .undo:return s.editingText ? s.textCanUndo:s.canUndo
        case .redo:return s.editingText ? s.textCanRedo:s.canRedo
        case .export:return s.pageCount>0 && !s.exporting
        case .copySettings,.copyRotation,.applySettingsToAll,.selectAllPages,.flag,.rotateLeft,.rotateRight,.preview,.proposeSplit,.locatePhotographs:return hasPage
        case .pasteRotation:return hasPage && s.rotationCopied
        case .pasteSettings:return hasPage && s.hasCopiedSettings
        case .resetAdjustments:return hasPage && s.targetsHaveAdjustments
        case .nextPage:return hasPage && s.current!<s.pageCount-1
        case .previousPage:return hasPage && s.current!>0
        case .firstPage:return hasPage && s.current!>0
        case .lastPage:return hasPage && s.current!<s.pageCount-1
        case .nextUnreviewed:return hasPage && s.unreviewedCount>0
        case .nextFlagged:return hasPage && s.flaggedCount>0
        case .accept,.fullImage:return editable
        case .copyPreviousCrop:return editable && s.current!>0
        // Results of running work are matched to pages; the list must not change underneath them.
        case .reversePages:return editable && s.pageCount>1 && !busy
        case .removePages:return editable && !busy
        case .detect:return hasPage && !s.detecting
        case .detectPending:return s.pendingCount>0 && !s.detecting
        case .nextProposal,.previousProposal:return hasPage && s.proposalCount>0
        case .removeSplit:return hasPage && s.targetsHaveSplit
        case .moveSplitLeft,.moveSplitRight:return hasPage && s.currentHasSplit
        case .sendToClaude:return hasPage && !s.reviewing
        case .deskew,.deskewClockwise,.deskewCounterclockwise:return hasPage
        case .removeDeskew:return hasPage && s.targetsHaveDeskew
        case .addPictureZone:return editable
        case .removePictureZones:return hasPage && s.targetsHaveZones
        case .showDeviations:return s.pageCount>0
        case .nextOutlier:return hasPage && s.outlierCount>0
        case .stop:return busy
        }
    }
    /// A title that depends on state, or nil to keep the menu's own.
    public static func title(_ command: MenuCommand, _ s: MenuState) -> String? {
        let several=s.targetCount>1
        switch command {
        case .flag:return (s.currentFlagged ? "Remove Flag":"Add Flag")+(several ? (s.currentFlagged ? " from":" to")+" \(s.targetCount) Pages":"")
        case .sendToClaude:return several ? "Send \(s.targetCount) Pages to \(s.reviewer)":"Send to \(s.reviewer)"
        case .deskew:return several ? "Deskew \(s.targetCount) Pages":"Deskew"
        case .proposeSplit:return several ? "Propose Page Split on \(s.targetCount) Pages":"Propose Page Split"
        case .rotateLeft:return several ? "Rotate \(s.targetCount) Pages Left":"Rotate Left"
        case .rotateRight:return several ? "Rotate \(s.targetCount) Pages Right":"Rotate Right"
        case .pasteRotation:return several ? "Paste Rotation to \(s.targetCount) Pages":"Paste Rotation"
        case .removePages:return several ? "Remove \(s.targetCount) Pages from Project":"Remove from Project"
        case .toggleSidebar:return s.sidebarVisible ? "Hide Sidebar":"Show Sidebar"
        case .toggleInspector:return s.inspectorVisible ? "Hide Inspector":"Show Inspector"
        default:return nil
        }
    }
    public static func isChecked(_ command: MenuCommand, _ s: MenuState) -> Bool {command == .preview && s.previewing}
}
/// The single-key commands, grouped as the shortcuts window shows them.
public enum ShortcutReference {
    public struct Entry {public let keys: String;public let action: String}
    public struct Section {public let title: String;public let entries: [Entry]}
    /// A letter is shown as it is typed: small on its own, and a capital only where Shift is held with it.
    public static func shown(_ keys: String) -> String {
        guard !keys.contains("Shift") else {return keys}
        return keys.split(separator:" ",omittingEmptySubsequences:false).map{$0.count == 1 ? $0.lowercased():String($0)}.joined(separator:" ")
    }
    private static func section(_ title: String, _ pairs: [(String,String)]) -> Section {Section(title:title,entries:pairs.map{Entry(keys:shown($0.0),action:$0.1)})}
    public static let sections: [Section] = [
        section("Project",[("G","New project"),("O","Open project"),("I","Import photographs or a folder"),("S","Save the project"),("Shift S","Save project as"),("E","Export"),("Esc","Stop background work, or release a corner or edge")]),
        section("Moving between photographs",[("← / →","Previous / next"),("Home / End","First / last"),("Page Up / Page Down","Back / forward ten"),("Return","Accept the crop and go to the next"),("N","Next unreviewed"),(".","Next unusual page"),("M","Add or remove a flag")]),
        section("Cropping frame",[("D","Detect this photograph; with several selected, all pending photographs"),("B","Detect all pending photographs"),("[ / ]","Previous / next proposal"),("C","Copy the previous photograph's crop"),("Shift →","Next photograph, taking this crop along"),("X","Full image"),("; / '","Shrink / expand the whole crop"),("H J K L","Expand the left, bottom, top, right side"),("Shift H J K L","Contract that side"),("Option H J K L","Move the whole crop; add Shift to move farther")]),
        section("Corners and edges",[("1 2 3 4","Select the top-left, top-right, bottom-left, bottom-right corner"),("5 6 7 8","Select the top, left, right, bottom edge"),("Arrow keys","Nudge the selected corner or edge; add Shift for larger steps")]),
        section("Page split",[("T","Propose a split between facing pages; again for the next candidate"),("Shift T","Remove the split"),("Option t","Propose a split on every page that has none"),("Y / U","Move the split left / right; add Shift to move farther")]),
        section("Deskew and picture zones",[("Q","Deskew: level the lines of text"),("Shift Q","Remove the deskew"),("Option , / .","Turn the page counterclockwise / clockwise by 0.1°"),("Option /","On a split spread, deskew both pages, the left or the right"),("W","Draw a picture zone, kept in gray on a black-and-white page"),("Shift W","Remove the picture zones")]),
        section("Smudge",[("Shift B","Pick up or put down the smudge brush, which blurs print to make it hard to read; Escape also puts it down"),("Option Shift B","Remove the smudges"),("Shift C","Pick up or put down the clone brush: Option-click the place to copy from, then paint"),("Option Shift C","Remove what the clone brush painted")]),
        section("Output and view",[("P","Corrected preview"),("V","Copy the previous photograph's image settings: cleanup, exposure, brightness, contrast, sharpness"),("R","Turn the page clockwise"),("Shift R","Turn the page counterclockwise"),("+ / −","Zoom in / out"),("F or 0","Zoom to fit"),("A","Send to Claude, OpenAI or Gemini for a second opinion"),("Z","Undo"),("Shift Z","Redo"),("?","Show this reference")]),
    ]
    public static let notes = "Single keys are off while you type in a field. Only 1–8 hand the arrow keys to a corner or edge; Escape gives them back. Drag a corner, any green edge, or the pink split line. Shift-drag a corner keeps the crop's angles. Drag inside the crop to move the whole crop; hold the space bar and drag to move the picture in the window. Every command is also in the menus. Originals are never modified."
}

public enum SelectionPolicy {
    /// The rows a context menu acts on: the row under the pointer, or the whole selection when that row is part of it.
    public static func contextSelection(clicked: Int, selected: IndexSet, count: Int) -> IndexSet {
        guard clicked>=0,clicked<count,!selected.contains(clicked) else {return selected}
        return IndexSet(integer:clicked)
    }
}
/// One progress bar shared by work that can overlap.
public struct ProgressTracker {
    public enum Kind: Hashable {case detect, export, review, split}
    private var tasks: [Kind:(done: Int, total: Int)] = [:]
    public init() {}
    public mutating func begin(_ kind: Kind, total: Int) {tasks[kind]=(0,max(1,total))}
    public mutating func advance(_ kind: Kind, to done: Int) {if let task=tasks[kind] {tasks[kind]=(min(task.total,max(0,done)),task.total)}}
    public mutating func end(_ kind: Kind) {tasks[kind]=nil}
    public mutating func endAll() {tasks=[:]}
    public func isRunning(_ kind: Kind) -> Bool {tasks[kind] != nil}
    public var isActive: Bool {!tasks.isEmpty}
    /// True when nothing running has more than one step to count.
    public var isIndeterminate: Bool {isActive && tasks.values.allSatisfy{$0.total<=1}}
    public var fraction: Double {
        let total=tasks.values.reduce(0){$0+$1.total}
        return total == 0 ? 0:Double(tasks.values.reduce(0){$0+$1.done})/Double(total)
    }
}
