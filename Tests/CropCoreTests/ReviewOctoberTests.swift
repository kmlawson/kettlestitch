import XCTest
@testable import CropCore

/// Regression tests for the defects found in the review of 11 October 2026.
final class ReviewOctoberTests: XCTestCase {
    func page(_ name: String = "a") -> Page {var p=Page(path:"/photos/\(name).jpg");p.imageAspectRatio=4.0/3;return p}
    // R01, R02: a measurement that finishes late is not laid over what the user did meanwhile.
    func testALateSplitOrDeskewResultIsDroppedWhenThePageHasMovedOn() {
        var asked=page();asked.split=PageSplit(top:0.5,bottom:0.5);asked.deskew=[0.4,0.2]
        XCTAssertTrue(asked.splitResultApplies(to:asked));XCTAssertTrue(asked.deskewResultApplies(to:asked))
        var moved=asked;moved.split=PageSplit(top:0.46,bottom:0.47);moved.splitByHand=true
        XCTAssertFalse(asked.splitResultApplies(to:moved),"The user moved the line");XCTAssertFalse(asked.deskewResultApplies(to:moved),"and the halves measured are no longer the halves there")
        var removed=asked;removed.split=nil;XCTAssertFalse(asked.splitResultApplies(to:removed),"The user removed the split")
        var accepted=asked;accepted.splitByHand=true;XCTAssertFalse(asked.splitResultApplies(to:accepted),"The user settled on the line as it is")
        var nudged=asked;nudged.deskew=[0.5,0.2];XCTAssertFalse(asked.deskewResultApplies(to:nudged),"The user turned it by hand");XCTAssertTrue(asked.splitResultApplies(to:nudged))
        var levelled=asked;levelled.deskew=nil;XCTAssertFalse(asked.deskewResultApplies(to:levelled))
        var turned=asked;turned.rotation=1;XCTAssertFalse(asked.splitResultApplies(to:turned) || asked.deskewResultApplies(to:turned))
        var cropped=asked;cropped.quad=Quad([Point(0.1,0.1),Point(0.9,0.1),Point(0.9,0.9),Point(0.1,0.9)]);XCTAssertFalse(asked.splitResultApplies(to:cropped) || asked.deskewResultApplies(to:cropped))
        // Undo leaves the same values but a later revision.
        var undone=asked;undone.revision+=1;XCTAssertFalse(asked.splitResultApplies(to:undone) || asked.deskewResultApplies(to:undone))
    }
    // R14: a deskew measured for one layout is not carried into another.
    func testDeskewFollowsThePageThroughTurnsAndSplits() {
        XCTAssertEqual(Page.deskew([0.4],afterQuarterTurns:1,parts:1),[0.4],"A single page keeps its tilt however it is turned")
        XCTAssertEqual(Page.deskew([0.4,-0.2],afterQuarterTurns:2,parts:2),[-0.2,0.4],"A half turn puts the left page on the right")
        XCTAssertNil(Page.deskew([0.4,-0.2],afterQuarterTurns:1,parts:2),"A quarter turn makes different halves, so the measurement no longer applies")
        XCTAssertEqual(Page.deskew([0.4,-0.2],afterQuarterTurns:4,parts:2),[0.4,-0.2]);XCTAssertEqual(Page.deskew([0.4,-0.2],afterQuarterTurns:-2,parts:2),[-0.2,0.4])
        XCTAssertNil(Page.deskew(nil,afterQuarterTurns:2,parts:2))
        XCTAssertNil(Page.deskew([0.4,-0.2],fitting:1),"Two angles are not kept for an unsplit page");XCTAssertNil(Page.deskew([0.4],fitting:2));XCTAssertEqual(Page.deskew([0.4,-0.2],fitting:2),[0.4,-0.2])
    }
    // R21: a second opinion on a page that has been turned since is not applied.
    func testAReviewOfAPageTurnedSinceIsNotApplied() {
        var p=page();p.split=PageSplit.centre
        let review=CropReview(good:true,comment:"",quad:nil,split:PageSplit(top:0.4,bottom:0.4))
        var turned=p;turned.rotation=2
        XCTAssertFalse(turned.record(review,sentQuad:p.quad,sentSplit:p.split,sentRotation:p.rotation),"The quad and split are the same numbers but mean another place");XCTAssertEqual(turned.split,PageSplit.centre);XCTAssertNil(turned.reviewNote)
        XCTAssertTrue(p.record(review,sentQuad:p.quad,sentSplit:p.split,sentRotation:p.rotation));XCTAssertEqual(p.split,PageSplit(top:0.4,bottom:0.4))
    }
    // R11: only a session file in the app's own folder is untitled work.
    func testAProjectTheUserNamedUntitledIsAProjectFile() {
        let support=URL(fileURLWithPath:"/Users/someone/Library/Application Support/KettleStitch")
        XCTAssertTrue(LaunchPolicy.isUntitled(support.appendingPathComponent(LaunchPolicy.untitledName(Date())),in:support))
        XCTAssertFalse(LaunchPolicy.isUntitled(URL(fileURLWithPath:"/Users/someone/Books/Untitled My Book.kettlestitch"),in:support))
        XCTAssertFalse(LaunchPolicy.isUntitled(support.appendingPathComponent("Atlas.kettlestitch"),in:support))
        XCTAssertNotEqual(LaunchPolicy.untitledName(Date(),unique:"A1B2"),LaunchPolicy.untitledName(Date(),unique:"C3D4"),"Two sessions begun in the same second get different files")
        XCTAssertTrue(LaunchPolicy.isUntitled(support.appendingPathComponent(LaunchPolicy.untitledName(Date(),unique:"A1B2")),in:support))
    }
    // R05: a moved photograph is matched by as much of its old location as can be, and never two to one file.
    func testRelinkingPrefersTheFullerMatchAndRefusesToSendTwoPagesToOnePhotograph() {
        let folder=URL(fileURLWithPath:"/new")
        // The same name in two old folders, and only one file of that name at the top of the chosen folder.
        var twins=[page(),page()];twins[0].path="/missing/a/0001.jpg";twins[1].path="/missing/b/0001.jpg"
        XCTAssertEqual(Relink.relink(&twins,in:folder,exists:{$0 == "/new/0001.jpg"}),0,"Which of the two it is cannot be told")
        XCTAssertEqual(twins.map{$0.path},["/missing/a/0001.jpg","/missing/b/0001.jpg"]);XCTAssertEqual(Relink.ambiguous(twins,in:folder,exists:{$0 == "/new/0001.jpg"}),2)
        // With their folders moved along, each goes to its own, even though a stray file of that name sits above them.
        let moved:Set<String>=["/new/0001.jpg","/new/a/0001.jpg","/new/b/0001.jpg"]
        XCTAssertEqual(Relink.relink(&twins,in:folder,exists:moved.contains),2);XCTAssertEqual(twins.map{$0.path},["/new/a/0001.jpg","/new/b/0001.jpg"])
        // A page already at a photograph keeps it; a missing page is not pointed at one another page has.
        var pair=[page(),page()];pair[0].path="/new/0002.jpg";pair[1].path="/old/0002.jpg"
        XCTAssertEqual(Relink.relink(&pair,in:folder,exists:{$0 == "/new/0002.jpg"}),0);XCTAssertEqual(pair[1].path,"/old/0002.jpg")
        // The ordinary case is unchanged, and the same photograph on two pages on purpose moves together.
        var plain=[page(),page(),page()];plain[0].path="/old/x/1.jpg";plain[1].path="/old/x/2.jpg";plain[2].path="/old/x/2.jpg"
        XCTAssertEqual(Relink.relink(&plain,in:folder,exists:{["/new/1.jpg","/new/2.jpg"].contains($0)}),3);XCTAssertEqual(plain.map{$0.path},["/new/1.jpg","/new/2.jpg","/new/2.jpg"])
    }
    // R06: a project file is checked as a whole before it is opened.
    func testAProjectWithValuesThatCannotBeMeantIsRefusedOrPutRight() throws {
        func project(_ change: (inout [String:Any]) -> Void, _ file: StaticString = #filePath, _ line: UInt = #line) throws -> Result<Project,Error> {
            var p=Project();p.pages=[page("a"),page("b")]
            var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(p)) as? [String:Any],file:file,line:line)
            change(&json)
            let data=try JSONSerialization.data(withJSONObject:json)
            return Result{try JSONDecoder().decode(Project.self,from:data).checked()}
        }
        func edit(_ json: inout [String:Any], page: Int = 0, _ change: (inout [String:Any]) -> Void) {var pages=json["pages"] as! [[String:Any]];change(&pages[page]);json["pages"]=pages}
        XCTAssertNoThrow(try project{_ in}.get())
        // Two pages cannot be the same page.
        XCTAssertThrowsError(try project{json in var pages=json["pages"] as! [[String:Any]];pages[1]["id"]=pages[0]["id"];json["pages"]=pages}.get()){XCTAssertTrue("\($0.localizedDescription)".contains("same"),"\($0.localizedDescription)")}
        // Numbers too large to be a place on a photograph are refused, with the page named.
        for (field,value) in [("deskew",[1e100] as Any),("pictureZones",[["minU":0.1,"minV":0.1,"maxU":1e100,"maxV":0.5]]),("format",["widthCM":1e100]),
                              ("smudges",[["points":[["x":1e300,"y":0.5]],"radius":0.02,"strength":0.5]]),("clones",[["points":[["x":0.5,"y":0.5]],"radius":0.02,"offset":["x":1e300,"y":0]]])] {
            XCTAssertThrowsError(try project{json in edit(&json){$0[field]=value}}.get(),field){XCTAssertTrue($0.localizedDescription.contains("a.jpg"),"\(field): \($0.localizedDescription)")}
        }
        // What can only mean one thing is put right.
        let odd=try project{json in
            json["selected"] = -999
            edit(&json){$0["split"]=["top":-9,"bottom":22];$0["deskew"]=[40.0];$0["rotation"]=7;$0["imageAspectRatio"] = -3;$0["revision"] = -5
                $0["adjustments"]=["cleanup":"grayscale","brightness":9,"contrast":-9,"sharpness":4,"exposure":-7,"despeckle":12]
                $0["smudges"]=[["points":[["x":0.5,"y":0.5]],"radius":9,"strength":-2,"grain":7],["points":[],"radius":0.02,"strength":0.5]]
                $0["pictureZones"]=[["minU":0.7,"minV":-0.2,"maxU":0.2,"maxV":1.4]]}
        }.get()
        let first=odd.pages[0]
        XCTAssertEqual(odd.selected,0);XCTAssertEqual(first.split,PageSplit(top:-9,bottom:22).clamped);XCTAssertEqual(first.deskew,[SkewDetector.limit]);XCTAssertEqual(first.rotation,3);XCTAssertEqual(first.revision,0)
        XCTAssertEqual(first.adjustments?.brightness,1);XCTAssertEqual(first.adjustments?.contrast,-1);XCTAssertEqual(first.adjustments?.sharpness,1);XCTAssertEqual(first.adjustments?.exposure,-1);XCTAssertEqual(first.adjustments?.despeckle,3)
        XCTAssertEqual(first.smudges?.count,1,"A stroke with no points is dropped");XCTAssertEqual(first.smudges?[0].radius,0.25);XCTAssertEqual(first.smudges?[0].strength,0);XCTAssertEqual(first.smudges?[0].grain,1)
        XCTAssertEqual(first.pictureZones,[PictureZone(from:(0.2,0),to:(0.7,1))])
        // Three angles are for no layout the app makes.
        XCTAssertNil(try project{json in edit(&json){$0["deskew"]=[0.1,0.2,0.3]}}.get().pages[0].deskew)
    }
    // R29: a usage log that cannot be read is set aside, not written over.
    func testAnUnreadableUsageLogIsSetAsideBeforeANewOneIsBegun() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("usage-"+UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent(UsageLog.fileName);try Data("{ damaged".utf8).write(to:url)
        let entry=UsageEntry(date:Date(timeIntervalSince1970:1_800_000_000),file:"a.jpg",model:"claude-haiku-5-5",seconds:2,usage:ReviewUsage(inputTokens:10,outputTokens:5))
        try UsageLog.append(entry,to:url)
        XCTAssertEqual(UsageLog.read(url).count,1)
        let kept=try FileManager.default.contentsOfDirectory(atPath:folder.path).filter{$0.contains("unreadable")}
        XCTAssertEqual(kept.count,1,"The damaged log is still there under another name");XCTAssertEqual(try String(contentsOf:folder.appendingPathComponent(kept[0])),"{ damaged")
        try UsageLog.append(entry,to:url);XCTAssertEqual(UsageLog.read(url).count,2);XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:folder.path).count,2,"A good log is appended to as before")
    }
}
