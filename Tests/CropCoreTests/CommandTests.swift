import XCTest
@testable import CropCore

final class MenuPolicyTests:XCTestCase {
    func state(_ change:(inout MenuState)->Void={_ in})->MenuState {
        var s=MenuState();s.pageCount=10;s.current=3;s.targetCount=1;change(&s);return s
    }
    func testEmptyProjectOnlyAllowsProjectCommands() {
        let empty=MenuState()
        for command in [MenuCommand.newProject,.openProject,.importPhotographs,.save,.saveAs,.settings,.help,.zoomIn,.zoomOut,.zoomToFit,.toggleSidebar,.toggleInspector] {XCTAssertTrue(MenuPolicy.isEnabled(command,empty),"\(command)")}
        for command in [MenuCommand.export,.detect,.detectPending,.accept,.rotateLeft,.proposeSplit,.sendToClaude,.removePages,.preview,.nextPage,.flag,.copySettings,.selectAllPages] {XCTAssertFalse(MenuPolicy.isEnabled(command,empty),"\(command)")}
    }
    func testUndoAndRedoFollowTheStacksOrTheTextBeingEdited() {
        XCTAssertFalse(MenuPolicy.isEnabled(.undo,state()))
        XCTAssertTrue(MenuPolicy.isEnabled(.undo,state{$0.canUndo=true}))
        XCTAssertTrue(MenuPolicy.isEnabled(.redo,state{$0.canRedo=true}))
        // While a field is being edited the command belongs to the text, not the project.
        XCTAssertFalse(MenuPolicy.isEnabled(.undo,state{$0.canUndo=true;$0.editingText=true}))
        XCTAssertTrue(MenuPolicy.isEnabled(.undo,state{$0.editingText=true;$0.textCanUndo=true}))
        XCTAssertTrue(MenuPolicy.isEnabled(.redo,state{$0.editingText=true;$0.textCanRedo=true}))
    }
    func testTypingInAFieldNeverRemovesPagesOrChangesTheCrop() {
        let typing=state{$0.editingText=true}
        for command in [MenuCommand.removePages,.reversePages,.fullImage,.copyPreviousCrop,.accept] {XCTAssertFalse(MenuPolicy.isEnabled(command,typing),"\(command)")}
        XCTAssertTrue(MenuPolicy.isEnabled(.removePages,state()))
        XCTAssertTrue(MenuPolicy.isEnabled(.export,typing),"Commands that do not edit the page stay available")
    }
    func testNavigationStopsAtTheEnds() {
        XCTAssertFalse(MenuPolicy.isEnabled(.previousPage,state{$0.current=0}));XCTAssertTrue(MenuPolicy.isEnabled(.nextPage,state{$0.current=0}))
        XCTAssertFalse(MenuPolicy.isEnabled(.nextPage,state{$0.current=9}));XCTAssertTrue(MenuPolicy.isEnabled(.previousPage,state{$0.current=9}))
        XCTAssertFalse(MenuPolicy.isEnabled(.firstPage,state{$0.current=0}));XCTAssertFalse(MenuPolicy.isEnabled(.lastPage,state{$0.current=9}))
        XCTAssertFalse(MenuPolicy.isEnabled(.copyPreviousCrop,state{$0.current=0}));XCTAssertTrue(MenuPolicy.isEnabled(.copyPreviousCrop,state()))
        XCTAssertFalse(MenuPolicy.isEnabled(.reversePages,state{$0.pageCount=1;$0.current=0}))
        XCTAssertFalse(MenuPolicy.isEnabled(.nextUnreviewed,state()));XCTAssertTrue(MenuPolicy.isEnabled(.nextUnreviewed,state{$0.unreviewedCount=2}))
        XCTAssertFalse(MenuPolicy.isEnabled(.nextFlagged,state()));XCTAssertTrue(MenuPolicy.isEnabled(.nextFlagged,state{$0.flaggedCount=1}))
    }
    func testCommandsNeedTheirSubject() {
        XCTAssertFalse(MenuPolicy.isEnabled(.pasteSettings,state()));XCTAssertTrue(MenuPolicy.isEnabled(.pasteSettings,state{$0.hasCopiedSettings=true}))
        XCTAssertFalse(MenuPolicy.isEnabled(.resetAdjustments,state()));XCTAssertTrue(MenuPolicy.isEnabled(.resetAdjustments,state{$0.targetsHaveAdjustments=true}))
        XCTAssertFalse(MenuPolicy.isEnabled(.nextProposal,state()));XCTAssertTrue(MenuPolicy.isEnabled(.previousProposal,state{$0.proposalCount=2}))
        XCTAssertFalse(MenuPolicy.isEnabled(.moveSplitLeft,state()));XCTAssertTrue(MenuPolicy.isEnabled(.moveSplitRight,state{$0.currentHasSplit=true}))
        XCTAssertFalse(MenuPolicy.isEnabled(.removeSplit,state()));XCTAssertTrue(MenuPolicy.isEnabled(.removeSplit,state{$0.targetsHaveSplit=true}))
        XCTAssertFalse(MenuPolicy.isEnabled(.detectPending,state()));XCTAssertTrue(MenuPolicy.isEnabled(.detectPending,state{$0.pendingCount=4}))
        XCTAssertFalse(MenuPolicy.isEnabled(.stop,state()))
    }
    func testBusyWorkBlocksItsOwnRestartAndEnablesStop() {
        let detecting=state{$0.detecting=true;$0.pendingCount=4}
        XCTAssertFalse(MenuPolicy.isEnabled(.detect,detecting));XCTAssertFalse(MenuPolicy.isEnabled(.detectPending,detecting));XCTAssertTrue(MenuPolicy.isEnabled(.stop,detecting))
        let exporting=state{$0.exporting=true}
        XCTAssertFalse(MenuPolicy.isEnabled(.export,exporting));XCTAssertTrue(MenuPolicy.isEnabled(.stop,exporting));XCTAssertTrue(MenuPolicy.isEnabled(.detect,exporting))
        let reviewing=state{$0.reviewing=true}
        XCTAssertFalse(MenuPolicy.isEnabled(.sendToClaude,reviewing));XCTAssertTrue(MenuPolicy.isEnabled(.stop,reviewing))
        // Changing the page list under running work would misdirect its results.
        for busy in [detecting,exporting,reviewing] {XCTAssertFalse(MenuPolicy.isEnabled(.removePages,busy));XCTAssertFalse(MenuPolicy.isEnabled(.reversePages,busy))}
    }
    func testTitlesReflectState() {
        XCTAssertEqual(MenuPolicy.title(.flag,state()),"Add Flag");XCTAssertEqual(MenuPolicy.title(.flag,state{$0.currentFlagged=true}),"Remove Flag")
        XCTAssertEqual(MenuPolicy.title(.flag,state{$0.targetCount=3}),"Add Flag to 3 Pages")
        XCTAssertEqual(MenuPolicy.title(.sendToClaude,state()),"Send to Claude");XCTAssertEqual(MenuPolicy.title(.sendToClaude,state{$0.targetCount=4}),"Send 4 Pages to Claude")
        XCTAssertEqual(MenuPolicy.title(.proposeSplit,state{$0.targetCount=2}),"Propose Page Split on 2 Pages")
        XCTAssertEqual(MenuPolicy.title(.removePages,state{$0.targetCount=2}),"Remove 2 Pages from Project");XCTAssertEqual(MenuPolicy.title(.removePages,state()),"Remove from Project")
        XCTAssertEqual(MenuPolicy.title(.toggleSidebar,state{$0.sidebarVisible=true}),"Hide Sidebar");XCTAssertEqual(MenuPolicy.title(.toggleSidebar,state()),"Show Sidebar")
        XCTAssertEqual(MenuPolicy.title(.toggleInspector,state{$0.inspectorVisible=true}),"Hide Inspector")
        XCTAssertNil(MenuPolicy.title(.export,state()),"Most commands keep the title the menu gave them")
        XCTAssertTrue(MenuPolicy.isChecked(.preview,state{$0.previewing=true}));XCTAssertFalse(MenuPolicy.isChecked(.preview,state()))
    }
}

final class ShortcutReferenceTests:XCTestCase {
    func testEveryEntryIsCompleteAndSingleKeysAreUnique() {
        XCTAssertGreaterThanOrEqual(ShortcutReference.sections.count,5)
        var seen:[String:String]=[:]
        for section in ShortcutReference.sections {
            XCTAssertFalse(section.title.isEmpty);XCTAssertFalse(section.entries.isEmpty)
            for entry in section.entries {
                XCTAssertFalse(entry.keys.isEmpty);XCTAssertFalse(entry.action.isEmpty)
                XCTAssertNil(seen[entry.keys],"\(entry.keys) is listed for both “\(seen[entry.keys] ?? "")” and “\(entry.action)”")
                seen[entry.keys]=entry.action
            }
        }
    }
    func testCoversTheCommandsAddedSinceTheFirstVersion() {
        let all=ShortcutReference.sections.flatMap{$0.entries}
        for expected in ["t","Shift T","q","Shift Q",", / .","a","m","Shift R","e","[ / ]","1 2 3 4","5 6 7 8","h j k l","Shift H J K L","Option h j k l","f or 0","z / y","Esc","Page Up / Page Down","Option Shift B"] {XCTAssertTrue(all.contains{$0.keys==expected},"Missing \(expected)")}
    }
}
