import XCTest
@testable import CropCore

final class LaunchPolicyTests:XCTestCase {
    func testOrdinaryLaunchOpensNothing() {
        XCTAssertNil(LaunchPolicy.projectToOpen(arguments:["/Applications/PageCrop.app/Contents/MacOS/PageCrop"],testDirectory:nil),"No project is reopened on its own")
        XCTAssertNil(LaunchPolicy.projectToOpen(arguments:["PageCrop","-NSDocumentRevisionsDebugMode","YES"],testDirectory:nil))
    }
    func testAProjectNamedOnTheCommandLineOrATestFolderIsOpened() {
        XCTAssertEqual(LaunchPolicy.projectToOpen(arguments:["PageCrop","--project","/books/a.pagecrop"],testDirectory:nil)?.path,"/books/a.pagecrop")
        XCTAssertNil(LaunchPolicy.projectToOpen(arguments:["PageCrop","--project"],testDirectory:nil),"A flag without a path is ignored")
        XCTAssertEqual(LaunchPolicy.projectToOpen(arguments:["PageCrop","--smoke"],testDirectory:"/tmp/t")?.path,"/tmp/t/Recovery.pagecrop")
        XCTAssertEqual(LaunchPolicy.projectToOpen(arguments:["PageCrop","--project","/books/a.pagecrop"],testDirectory:"/tmp/t")?.path,"/books/a.pagecrop","The explicit path wins")
    }
    func testUntitledNamesAreDistinctAndSortByTime() {
        let first=LaunchPolicy.untitledName(Date(timeIntervalSince1970:1_800_000_000)),later=LaunchPolicy.untitledName(Date(timeIntervalSince1970:1_800_000_061))
        XCTAssertTrue(first.hasPrefix("Untitled ") && first.hasSuffix(".pagecrop"));XCTAssertNotEqual(first,later);XCTAssertLessThan(first,later)
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
        let incoming=ImportPolicy.sort([url("/shots/a.jpg"),url("/books/One.pagecrop"),url("/books/Two.pagecrop")],existing:[],contents:contents)
        XCTAssertEqual(incoming.project?.lastPathComponent,"One.pagecrop","The first project wins");XCTAssertEqual(incoming.photographs.count,1)
        XCTAssertTrue(ImportPolicy.isProject(url("/x/Y.PAGECROP")));XCTAssertFalse(ImportPolicy.isProject(url("/x/y.json")))
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
