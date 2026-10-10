import XCTest
@testable import CropCore

final class LaunchPolicyTests:XCTestCase {
    func testOrdinaryLaunchOpensNothing() {
        XCTAssertNil(LaunchPolicy.projectToOpen(arguments:["/Applications/KettleStitch.app/Contents/MacOS/KettleStitch"],testDirectory:nil),"No project is reopened on its own")
        XCTAssertNil(LaunchPolicy.projectToOpen(arguments:["KettleStitch","-NSDocumentRevisionsDebugMode","YES"],testDirectory:nil))
    }
    func testAProjectNamedOnTheCommandLineOrATestFolderIsOpened() {
        XCTAssertEqual(LaunchPolicy.projectToOpen(arguments:["KettleStitch","--project","/books/a.kettlestitch"],testDirectory:nil)?.path,"/books/a.kettlestitch")
        XCTAssertNil(LaunchPolicy.projectToOpen(arguments:["KettleStitch","--project"],testDirectory:nil),"A flag without a path is ignored")
        XCTAssertEqual(LaunchPolicy.projectToOpen(arguments:["KettleStitch","--smoke"],testDirectory:"/tmp/t")?.path,"/tmp/t/Recovery.kettlestitch")
        XCTAssertEqual(LaunchPolicy.projectToOpen(arguments:["KettleStitch","--project","/books/a.kettlestitch"],testDirectory:"/tmp/t")?.path,"/books/a.kettlestitch","The explicit path wins")
    }
    func testOnlyANamedProjectWithChangesIsAutosaved() {
        let untitled=URL(fileURLWithPath:"/support/"+LaunchPolicy.untitledName(Date(timeIntervalSince1970:1_800_000_000)))
        XCTAssertTrue(LaunchPolicy.isUntitled(untitled));XCTAssertFalse(LaunchPolicy.isUntitled(URL(fileURLWithPath:"/books/Untitled.kettlestitch")),"A file the user called Untitled is still theirs")
        XCTAssertFalse(LaunchPolicy.isUntitled(URL(fileURLWithPath:"/books/a.kettlestitch")))
        XCTAssertTrue(LaunchPolicy.shouldAutosave(enabled:true,hasProjectFile:true,unsaved:true));XCTAssertEqual(LaunchPolicy.autosaveInterval,300)
        XCTAssertFalse(LaunchPolicy.shouldAutosave(enabled:false,hasProjectFile:true,unsaved:true),"The setting is off")
        XCTAssertFalse(LaunchPolicy.shouldAutosave(enabled:true,hasProjectFile:false,unsaved:true));XCTAssertFalse(LaunchPolicy.shouldAutosave(enabled:true,hasProjectFile:true,unsaved:false))
    }
    func testUntitledNamesAreDistinctAndSortByTime() {
        let first=LaunchPolicy.untitledName(Date(timeIntervalSince1970:1_800_000_000)),later=LaunchPolicy.untitledName(Date(timeIntervalSince1970:1_800_000_061))
        XCTAssertTrue(first.hasPrefix("Untitled ") && first.hasSuffix(".kettlestitch"));XCTAssertNotEqual(first,later);XCTAssertLessThan(first,later)
        XCTAssertFalse(first.contains(":") || first.contains("/"),"Safe as a file name")
    }
}

final class ImportPolicyTests:XCTestCase {
    func url(_ path:String)->URL {URL(fileURLWithPath:path)}
    let folder:[String:[String]]=["/shots/book":["/shots/book/IMG_10.HEIC","/shots/book/IMG_2.heic","/shots/book/notes.txt","/shots/book/.hidden.jpg","/shots/book/sub"]]
    func contents(_ u:URL)->[URL]? {folder[u.path]?.map{URL(fileURLWithPath:$0)}}
    func testPhotographsAndFoldersAreGatheredInNaturalOrder() {
        let incoming=ImportPolicy.sort([url("/shots/b.jpg"),url("/shots/book"),url("/shots/a.PNG"),url("/shots/readme.md")],existing:[],contents:contents)
        XCTAssertNil(incoming.project)
        XCTAssertEqual(incoming.photographs.map{$0.lastPathComponent},["a.PNG","b.jpg","IMG_2.heic","IMG_10.HEIC"],"Supported images only, 2 before 10, hidden files left out")
    }
    func testPhotographsAlreadyInTheProjectAndRepeatsAreSkipped() {
        let incoming=ImportPolicy.sort([url("/shots/a.jpg"),url("/shots/a.jpg"),url("/shots/b.jpg")],existing:["/shots/b.jpg"],contents:contents)
        XCTAssertEqual(incoming.photographs.map{$0.path},["/shots/a.jpg"])
    }
    func testAProjectFileIsOpenedRatherThanImported() {
        let incoming=ImportPolicy.sort([url("/shots/a.jpg"),url("/books/One.kettlestitch"),url("/books/Two.kettlestitch")],existing:[],contents:contents)
        XCTAssertEqual(incoming.project?.lastPathComponent,"One.kettlestitch","The first project wins");XCTAssertEqual(incoming.photographs.count,1)
        XCTAssertTrue(ImportPolicy.isProject(url("/x/Y.KETTLESTITCH")));XCTAssertFalse(ImportPolicy.isProject(url("/x/y.json")))
        XCTAssertTrue(ImportPolicy.isProject(url("/x/old.pagecrop")),"Projects saved under the app's earlier names still open")
        XCTAssertTrue(ImportPolicy.isProject(url("/x/old.scanseamstress")))
        XCTAssertEqual(ImportPolicy.projectExtension,"kettlestitch");XCTAssertEqual(ImportPolicy.projectExtensions,["kettlestitch","scanseamstress","pagecrop"])
    }
    func testWorkFromEarlierNamesIsCarriedOverOnceNewestFirst() {
        XCTAssertEqual(LegacyNames.supportFolders,["ScanSeamstress","PageCrop"])
        XCTAssertEqual(LegacyNames.keychainServices,["local.scanseamstress.app.anthropic","local.pagecrop.app.anthropic"])
        XCTAssertEqual(LegacyNames.preferencesDomains,["local.scanseamstress.app","local.pagecrop.app"])
        XCTAssertTrue(LegacyNames.shouldCarryOver(oldExists:true,newExists:false))
        XCTAssertFalse(LegacyNames.shouldCarryOver(oldExists:true,newExists:true),"Never over anything already saved under the new name")
        XCTAssertFalse(LegacyNames.shouldCarryOver(oldExists:false,newExists:false))
        // The most recent earlier name that has anything is the one carried over.
        XCTAssertEqual(LegacyNames.firstExisting(["a","b","c"]){$0 != "a"},"b");XCTAssertNil(LegacyNames.firstExisting(["a","b"]){_ in false})
    }
    func testEveryFormatTheAppReadsIsAccepted() {
        for ext in ["jpg","jpeg","png","tif","tiff","heic","heif","bmp"] {XCTAssertTrue(ImportPolicy.isPhotograph(url("/a/b."+ext)),ext)}
        for ext in ["pdf","raw","txt",""] {XCTAssertFalse(ImportPolicy.isPhotograph(url("/a/b."+ext)),ext)}
        XCTAssertEqual(ImportPolicy.sort([],existing:[],contents:contents).photographs.count,0)
    }
    func testEmptyProjectsAreNotWorthSaving() {
        XCTAssertFalse(LaunchPolicy.shouldWrite(pageCount:0,fileExists:false),"An untouched untitled project leaves no file behind")
        XCTAssertTrue(LaunchPolicy.shouldWrite(pageCount:0,fileExists:true),"Emptying a saved project is still a change to save")
        XCTAssertTrue(LaunchPolicy.shouldWrite(pageCount:3,fileExists:false))
    }
}
