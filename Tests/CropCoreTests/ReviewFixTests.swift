import XCTest
@testable import CropCore
import CoreGraphics

private func square(_ a:Double,_ b:Double)->Quad {Quad([Point(a,a),Point(b,a),Point(b,b),Point(a,b)])}
private func page(_ name:String="a")->Page {var p=Page(path:"/photos/\(name).jpg");p.imageAspectRatio=4.0/3;return p}

final class ClaudeProposalPersistenceTests:XCTestCase {
    func testReloadKeepsClaudeProposalAndACropChosenFromIt() {
        // 0.2...0.9 covers 49% of the photograph, below the 65% the detector's own proposals must reach.
        let small=square(0.2,0.9)
        var p=page();p.quad=small;p.status="Proposal selected"
        p.candidates=[Candidate(quad:square(0.05,0.95),score:0.8,source:"Edges"),Candidate(quad:small,score:0,source:Candidate.claudeSource),Candidate(quad:square(0.3,0.8),score:0.5,source:"Edges refined")]
        let revision=p.revision
        p.filterProposals()
        XCTAssertEqual(p.candidates.map{$0.source},["Edges",Candidate.claudeSource],"The detector's undersized proposal goes; Claude's stays")
        XCTAssertEqual(p.quad,small,"A crop the user chose from Claude's proposal is not replaced");XCTAssertEqual(p.status,"Proposal selected");XCTAssertEqual(p.revision,revision)
    }
    func testReloadStillReplacesAnUndersizedDetectorCrop() {
        var p=page();p.quad=square(0.3,0.8);p.status="Check proposal";p.candidates=[Candidate(quad:square(0.05,0.95),score:0.8,source:"Edges")]
        p.filterProposals()
        XCTAssertEqual(p.quad,square(0.05,0.95));XCTAssertEqual(p.status,"Check proposal")
    }
}

final class ReviewRecordingTests:XCTestCase {
    let sent=square(0.1,0.9)
    func testFixBecomesAProposalWithANote() {
        var p=page();p.quad=sent;p.candidates=[Candidate(quad:square(0.05,0.95),score:0.8,source:"Edges"),Candidate(quad:square(0.2,0.8),score:0,source:Candidate.claudeSource)]
        XCTAssertTrue(p.record(CropReview(good:false,comment:"Top-left moved out.",quad:square(0.08,0.9)),sentQuad:sent))
        XCTAssertEqual(p.candidates.filter{$0.source==Candidate.claudeSource}.map{$0.quad},[square(0.08,0.9)],"The earlier Claude proposal is replaced")
        XCTAssertEqual(p.reviewNote,"Claude proposes a fix — Top-left moved out.");XCTAssertEqual(p.quad,sent,"The crop itself is never changed")
    }
    func testGoodVerdictAndEmptyComment() {
        var p=page();p.quad=sent
        XCTAssertTrue(p.record(CropReview(good:true,comment:"",quad:nil),sentQuad:sent));XCTAssertEqual(p.reviewNote,"Claude: crop looks right")
        XCTAssertTrue(p.record(CropReview(good:false,comment:"Unsure.",quad:nil),sentQuad:sent));XCTAssertEqual(p.reviewNote,"Claude: no usable fix — Unsure.")
    }
    func testVerdictOnACropThatHasSinceChangedIsDiscarded() {
        var p=page();p.quad=square(0.12,0.9);p.reviewNote="earlier"
        XCTAssertFalse(p.record(CropReview(good:true,comment:"Fine.",quad:nil),sentQuad:sent))
        XCTAssertEqual(p.reviewNote,"earlier");XCTAssertTrue(p.candidates.isEmpty)
    }
    func testManualCropClearsTheNoteButChoosingAProposalKeepsIt() {
        var p=page();p.quad=sent;p.reviewed=true;p.reviewNote="Claude: crop looks right"
        p.setManualCrop(square(0.11,0.9))
        XCTAssertEqual(p.quad,square(0.11,0.9));XCTAssertEqual(p.status,"Manual");XCTAssertFalse(p.reviewed);XCTAssertNil(p.reviewNote,"The comment was about a crop that no longer exists")
        p.reviewNote="Claude proposes a fix";p.selectProposal(square(0.08,0.9))
        XCTAssertEqual(p.status,"Proposal selected");XCTAssertEqual(p.reviewNote,"Claude proposes a fix")
    }
}

final class StructuralUndoTests:XCTestCase {
    func testRestoringOrderKeepsWorkDoneSince() {
        var a=page("a"),b=page("b"),c=page("c")
        let before=[a,b,c]
        // After the reorder was made, detection and a Claude review wrote to the pages.
        a.status="Check proposal";a.quad=square(0.1,0.9);b.reviewNote="Claude: crop looks right";c.split = .centre
        let restored=Project.restoringStructure(before,current:[c,b,a])
        XCTAssertEqual(restored.map{$0.id},before.map{$0.id},"The order goes back")
        XCTAssertEqual(restored[0].status,"Check proposal");XCTAssertEqual(restored[0].quad,square(0.1,0.9));XCTAssertEqual(restored[1].reviewNote,"Claude: crop looks right");XCTAssertEqual(restored[2].split,.centre)
    }
    func testRestoringARemovalBringsThePageBackAndRedoRemovesItAgain() {
        let a=page("a"),b=page("b"),c=page("c")
        var keptA=a;keptA.reviewed=true
        let undone=Project.restoringStructure([a,b,c],current:[keptA,c])
        XCTAssertEqual(undone.map{$0.id},[a.id,b.id,c.id]);XCTAssertTrue(undone[0].reviewed)
        let redone=Project.restoringStructure([keptA,c],current:undone)
        XCTAssertEqual(redone.map{$0.id},[a.id,c.id],"Pages absent from the snapshot are removed, so an import can be undone too")
    }
}

final class SelectionPolicyTests:XCTestCase {
    func testContextClickActsOnTheRowUnderThePointer() {
        XCTAssertEqual(SelectionPolicy.contextSelection(clicked:7,selected:IndexSet([2]),count:10),IndexSet([7]),"An unselected row becomes the selection")
        XCTAssertEqual(SelectionPolicy.contextSelection(clicked:3,selected:IndexSet([2,3,4]),count:10),IndexSet([2,3,4]),"A row inside the selection keeps it")
        XCTAssertEqual(SelectionPolicy.contextSelection(clicked:-1,selected:IndexSet([2]),count:10),IndexSet([2]),"A click on empty space changes nothing")
        XCTAssertEqual(SelectionPolicy.contextSelection(clicked:12,selected:IndexSet([2]),count:10),IndexSet([2]))
    }
}

final class OtherWindowMenuTests:XCTestCase {
    func testPageCommandsAreOffWhileASheetOrAnotherWindowHasTheKeyboard() {
        var s=MenuState();s.pageCount=10;s.current=3;s.targetCount=1;s.canUndo=true;s.windowActive=false
        for command in [MenuCommand.removePages,.accept,.undo,.export,.rotateLeft,.nextPage,.detect,.sendToClaude,.proposeSplit,.flag,.newProject,.importPhotographs] {XCTAssertFalse(MenuPolicy.isEnabled(command,s),"\(command)")}
        XCTAssertTrue(MenuPolicy.isEnabled(.settings,s));XCTAssertTrue(MenuPolicy.isEnabled(.help,s))
        s.editingText=true;s.textCanUndo=true
        XCTAssertTrue(MenuPolicy.isEnabled(.undo,s),"Undo still serves the text being typed there")
        XCTAssertTrue(MenuState().windowActive,"The main window is assumed active unless stated")
    }
}

final class ClaudeLaunchTests:XCTestCase {
    func testEnvironmentCarriesTheKeyAndASearchPathThatFindsNode() {
        let env=ClaudeReview.environment(base:["PATH":"/usr/bin:/bin","HOME":"/Users/me","OTHER":"1"],apiKey:"sk-test",executable:URL(fileURLWithPath:"/opt/custom/bin/claude"),home:"/Users/me")
        XCTAssertEqual(env["ANTHROPIC_API_KEY"],"sk-test");XCTAssertEqual(env["OTHER"],"1")
        let path=env["PATH"]!.split(separator:":").map(String.init)
        XCTAssertEqual(path.first,"/opt/custom/bin","The tool's own folder comes first; its interpreter usually sits beside it")
        for expected in ["/opt/homebrew/bin","/usr/local/bin","/Users/me/.local/bin","/usr/bin","/bin"] {XCTAssertTrue(path.contains(expected),expected)}
        XCTAssertEqual(Set(path).count,path.count,"No duplicates")
        XCTAssertNotNil(ClaudeReview.environment(base:[:],apiKey:"k",executable:URL(fileURLWithPath:"/usr/local/bin/claude"),home:"/Users/me")["PATH"])
    }
    func testFailureMessagesDistinguishTimeoutFromStop() {
        XCTAssertEqual(ClaudeReview.failureMessage(timedOut:true,timeout:240,stopped:true,status:15,detail:""),"Claude did not answer within 4 minutes")
        XCTAssertEqual(ClaudeReview.failureMessage(timedOut:false,timeout:240,stopped:true,status:15,detail:""),"Claude was stopped before it answered")
        XCTAssertEqual(ClaudeReview.failureMessage(timedOut:false,timeout:240,stopped:false,status:127,detail:"env: node: No such file or directory\n"),"env: node: No such file or directory")
        XCTAssertEqual(ClaudeReview.failureMessage(timedOut:false,timeout:240,stopped:false,status:2,detail:""),"Claude exited with status 2 and no reply")
    }
    func testPromptNamesCornersWithTheSchemaKeys() {
        let prompt=ClaudeReview.prompt(quad:.full)
        for key in ClaudeReview.cornerKeys {XCTAssertTrue(prompt.contains(key+" (x"),key)}
    }
}

final class ProgressTrackerTests:XCTestCase {
    func testIndependentTasksShareOneBar() {
        var t=ProgressTracker()
        XCTAssertFalse(t.isActive)
        t.begin(.review,total:50);t.advance(.review,to:10)
        XCTAssertTrue(t.isActive);XCTAssertEqual(t.fraction,0.2,accuracy:1e-9);XCTAssertFalse(t.isIndeterminate)
        t.begin(.export,total:3);t.advance(.export,to:3)
        XCTAssertEqual(t.fraction,13.0/53,accuracy:1e-9)
        t.end(.export)
        XCTAssertTrue(t.isActive,"Finishing the export must not hide the review's progress");XCTAssertEqual(t.fraction,0.2,accuracy:1e-9);XCTAssertTrue(t.isRunning(.review));XCTAssertFalse(t.isRunning(.export))
        t.end(.review);XCTAssertFalse(t.isActive);XCTAssertEqual(t.fraction,0)
    }
    func testSingleStepWorkIsIndeterminateAndEndingTwiceIsHarmless() {
        var t=ProgressTracker();t.begin(.review,total:1)
        XCTAssertTrue(t.isIndeterminate)
        t.begin(.detect,total:20);XCTAssertFalse(t.isIndeterminate,"Countable work alongside it gives the bar something to show")
        t.advance(.detect,to:99);XCTAssertLessThanOrEqual(t.fraction,1)
        t.end(.detect);t.end(.detect);t.end(.split);XCTAssertTrue(t.isIndeterminate)
        t.endAll();XCTAssertFalse(t.isActive)
    }
}

final class ExportFixTests:XCTestCase {
    func testPasswordsCoreGraphicsCannotStoreAreRefused() {
        XCTAssertNil(ExportOptions.passwordProblem("open sesame 123!"))
        XCTAssertNotNil(ExportOptions.passwordProblem("pässwört"),"Core Graphics only accepts ASCII")
        XCTAssertNotNil(ExportOptions.passwordProblem(String(repeating:"a",count:33)),"and at most 32 characters")
        XCTAssertNil(ExportOptions.passwordProblem(String(repeating:"a",count:32)))
        XCTAssertNotNil(ExportOptions.passwordProblem(""))
    }
    func testMaximumDPIIsAppliedToEachFittedHalfNotTheSpread() throws {
        let c=CGContext(data:nil,width:1200,height:900,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(gray:0.8,alpha:1));c.fill(CGRect(x:0,y:0,width:1200,height:900))
        let photo=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".jpg")
        try Exporter.encode(c.makeImage()!,as:.jpeg,quality:0.9,dpi:nil).write(to:photo)
        defer{try? FileManager.default.removeItem(at:photo)}
        var p=Page(path:photo.path);p.split = .centre;p.format=PageFormat(fitInto:.a4)
        var options=ExportOptions();options.format = .jpeg;options.maxDPI=60
        // A 600 x 900 half on portrait A4 is about 77 DPI; the 1200 x 900 spread on landscape A4 would be about 109.
        let half=try Exporter.renderAll(p,options:options)[0]
        XCTAssertEqual(half.layout.dpi,60,accuracy:1.5);XCTAssertEqual(Double(half.image.width),600*60/76.97,accuracy:6)
        options.maxDPI=100
        XCTAssertEqual(try Exporter.renderAll(p,options:options)[0].image.width,600,accuracy:3,"Already below the limit: untouched")
    }
    func testMonochromeModes() {
        XCTAssertTrue(Cleanup.grayscale.isMonochrome);XCTAssertTrue(Cleanup.blackAndWhite.isMonochrome);XCTAssertFalse(Cleanup.color.isMonochrome);XCTAssertFalse(Cleanup.none.isMonochrome)
    }
}
