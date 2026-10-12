import XCTest
@testable import CropCore

final class RecoveryTests: XCTestCase {
    var support: URL!
    override func setUpWithError() throws {
        support=FileManager.default.temporaryDirectory.appendingPathComponent("recovery-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:support,withIntermediateDirectories:true)
    }
    override func tearDown() {try? FileManager.default.removeItem(at:support)}
    func book(_ names: [String]) -> Project {
        var p=Project();p.pages=names.map{Page(path:"/photos/\($0).jpg")};return p
    }
    func testASnapshotIsWrittenReadBackAndRemovedByItsOwnName() throws {
        let id=UUID(),when=Date(timeIntervalSince1970:1_800_000_000)
        let snapshot=RecoverySnapshot(id:id,originalPath:"/books/Atlas.kettlestitch",written:when,project:book(["a","b","c"]))
        try snapshot.write(in:support)
        let file=RecoverySnapshot.url(id,in:support)
        XCTAssertEqual(file.deletingLastPathComponent().lastPathComponent,"Recovery");XCTAssertTrue(FileManager.default.fileExists(atPath:file.path))
        let back=try RecoverySnapshot.read(file)
        XCTAssertEqual(back.id,id);XCTAssertEqual(back.originalPath,"/books/Atlas.kettlestitch");XCTAssertEqual(back.written,when);XCTAssertEqual(back.project.pages.map{$0.path},["/photos/a.jpg","/photos/b.jpg","/photos/c.jpg"])
        // Writing again replaces the copy; it never makes a second one.
        var later=snapshot;later.project=book(["a"]);try later.write(in:support)
        XCTAssertEqual(try RecoverySnapshot.read(file).project.pages.count,1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:file.deletingLastPathComponent().path).count,1)
        RecoverySnapshot.remove(id,in:support);XCTAssertFalse(FileManager.default.fileExists(atPath:file.path))
        RecoverySnapshot.remove(id,in:support)
        // The project file itself is never touched by any of this.
        XCTAssertFalse(FileManager.default.fileExists(atPath:"/books/Atlas.kettlestitch"))
    }
    func testADamagedCopyIsRefusedAndLeftOutOfTheList() throws {
        let folder=support.appendingPathComponent("Recovery");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let bad=folder.appendingPathComponent(UUID().uuidString+".kettlestitch-recovery");try Data("{ not a copy".utf8).write(to:bad)
        XCTAssertThrowsError(try RecoverySnapshot.read(bad))
        XCTAssertTrue(RecoveryList.entries(in:support,exists:{_ in true},modified:{_ in nil}).isEmpty)
    }
    func testADamagedCopyIsListedAsDamagedNotHidden() throws {
        let when=Date(timeIntervalSince1970:1_800_000_000)
        // A copy whose project is damaged, but which still says whose it is.
        let folder=support.appendingPathComponent("Recovery");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let named=folder.appendingPathComponent(UUID().uuidString+".kettlestitch-recovery")
        try Data(#"{"version":1,"id":"not an id","originalPath":"/books/Atlas.kettlestitch","project":{"pages":"lost"}}"#.utf8).write(to:named)
        // One that is nothing but noise, and an untitled session that no longer opens.
        let noise=folder.appendingPathComponent(UUID().uuidString+".kettlestitch-recovery");try Data("{ not a copy".utf8).write(to:noise)
        let untitled=support.appendingPathComponent(LaunchPolicy.untitledName(when));try Data("[]".utf8).write(to:untitled)
        let entries=RecoveryList.damaged(in:support,modified:{_ in when})
        XCTAssertEqual(entries.count,3);XCTAssertTrue(entries.allSatisfy{$0.reason == .damaged && $0.pageCount==0 && $0.snapshot==nil})
        XCTAssertEqual(Set(entries.map{$0.name}),["Atlas","Recovery copy",untitled.deletingPathExtension().lastPathComponent]);XCTAssertEqual(entries.first{$0.name=="Atlas"}?.originalPath,"/books/Atlas.kettlestitch")
        XCTAssertFalse(RecoveryList.Reason.damaged.explanation.isEmpty);XCTAssertTrue(RecoveryList.Reason.damaged.needsAttention,"Work that may be lost is worth raising")
        // A whole copy is not among them, and a file that is still being written elsewhere is not judged twice.
        try RecoverySnapshot(id:UUID(),originalPath:"/books/Herbal.kettlestitch",written:when,project:book(["a"])).write(in:support)
        XCTAssertEqual(RecoveryList.damaged(in:support,modified:{_ in when}).count,3)
        XCTAssertEqual(RecoveryList.damaged(in:support,exceptFile:untitled,modified:{_ in when}).count,2,"The session that is open is not judged")
    }
    func testTheListSaysWhatEachCopyIsAndWhyItExists() throws {
        let saved=Date(timeIntervalSince1970:1_800_000_000)
        // Changes to a named project that never reached its file.
        let lost=RecoverySnapshot(id:UUID(),originalPath:"/books/Atlas.kettlestitch",written:saved.addingTimeInterval(600),project:book(["a","b","c"]));try lost.write(in:support)
        // A copy the project's own file has since overtaken.
        let stale=RecoverySnapshot(id:UUID(),originalPath:"/books/Herbal.kettlestitch",written:saved.addingTimeInterval(-600),project:book(["a"]));try stale.write(in:support)
        // A project whose file is gone.
        let orphan=RecoverySnapshot(id:UUID(),originalPath:"/books/Gone.kettlestitch",written:saved,project:book(["a","b"]));try orphan.write(in:support)
        // Work that was never given a name.
        let untitled=support.appendingPathComponent(LaunchPolicy.untitledName(saved));try book(["x","y"]).save(untitled)
        // Other things in the folder are not recovery copies.
        try Data().write(to:support.appendingPathComponent("usage.json"))
        let entries=RecoveryList.entries(in:support,exists:{$0 != "/books/Gone.kettlestitch" && $0 != "/photos/b.jpg"},modified:{$0.hasSuffix(untitled.lastPathComponent) || $0.hasPrefix("/books/") ? saved:nil})
        XCTAssertEqual(entries.count,4)
        XCTAssertEqual(entries.map{$0.name},["Atlas","Gone",untitled.deletingPathExtension().lastPathComponent,"Herbal"],"Newest first")
        let atlas=entries[0];XCTAssertEqual(atlas.reason,.unsavedChanges);XCTAssertEqual(atlas.pageCount,3);XCTAssertEqual(atlas.missing,1,"One photograph is not where the copy expects");XCTAssertEqual(atlas.originalPath,"/books/Atlas.kettlestitch");XCTAssertEqual(atlas.snapshot,lost.id)
        XCTAssertEqual(entries[1].reason,.originalMissing);XCTAssertEqual(entries[2].reason,.neverNamed);XCTAssertNil(entries[2].snapshot);XCTAssertNil(entries[2].originalPath);XCTAssertEqual(entries[2].pageCount,2)
        XCTAssertEqual(entries[3].reason,.savedSince)
        XCTAssertTrue(atlas.reason.needsAttention && entries[1].reason.needsAttention);XCTAssertFalse(entries[2].reason.needsAttention || entries[3].reason.needsAttention,"Only work that would otherwise be lost is raised at launch")
        for reason in [RecoveryList.Reason.unsavedChanges,.originalMissing,.neverNamed,.savedSince] {XCTAssertFalse(reason.explanation.isEmpty)}
        // The session that is open now is not offered to itself.
        XCTAssertEqual(RecoveryList.entries(in:support,except:lost.id,exists:{_ in true},modified:{_ in saved}).count,3)
        XCTAssertEqual(RecoveryList.entries(in:support,exceptFile:untitled,exists:{_ in true},modified:{_ in saved}).count,3)
    }
    func testAnEmptyFolderHasNothingToRecover() {
        XCTAssertTrue(RecoveryList.entries(in:support,exists:{_ in true},modified:{_ in nil}).isEmpty)
    }
}
