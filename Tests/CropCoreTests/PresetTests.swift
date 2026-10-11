import XCTest
@testable import CropCore

final class PresetTests: XCTestCase {
    func settings(_ cleanup: Cleanup, brightness: Double = 0) -> Adjustments {var a=Adjustments();a.cleanup=cleanup;a.brightness=brightness;return a}
    func testAPresetAppliesItsImageSettingsAndItsFormatOnlyWhenItHasOne() {
        var page=Page(path:"/photos/a.jpg");page.rotation=1;page.format=PageFormat(widthCM:12);page.adjustments=settings(.color)
        let quad=page.quad
        SettingsPreset(name:"Text",adjustments:settings(.blackAndWhite,brightness:0.2),format:nil).apply(to:&page)
        XCTAssertEqual(page.adjustments,settings(.blackAndWhite,brightness:0.2));XCTAssertEqual(page.format,PageFormat(widthCM:12),"A preset without a format leaves the page's alone")
        XCTAssertEqual(page.rotation,1);XCTAssertEqual(page.quad,quad,"Nothing but settings is touched")
        SettingsPreset(name:"A5 plates",adjustments:Adjustments(),format:PageFormat(fitInto:.a5)).apply(to:&page)
        XCTAssertNil(page.adjustments,"Neutral settings are stored as none");XCTAssertEqual(page.format,PageFormat(fitInto:.a5))
    }
    func testPresetsAreKeptByNameInTheOrderTheyWereMade() {
        var list:[SettingsPreset]=[]
        list=PresetStore.adding(SettingsPreset(name:"  Text  ",adjustments:settings(.blackAndWhite),format:nil),to:list)
        list=PresetStore.adding(SettingsPreset(name:"Plates",adjustments:settings(.color),format:nil),to:list)
        XCTAssertEqual(list.map{$0.name},["Text","Plates"],"Names are trimmed")
        // Saving under a name already in use replaces that preset where it stands, whatever the capitals.
        list=PresetStore.adding(SettingsPreset(name:"text",adjustments:settings(.grayscale),format:nil),to:list)
        XCTAssertEqual(list.map{$0.name},["text","Plates"]);XCTAssertEqual(list[0].adjustments.cleanup,.grayscale)
        XCTAssertEqual(PresetStore.adding(SettingsPreset(name:"   ",adjustments:Adjustments(),format:nil),to:list).count,2,"A preset needs a name")
        XCTAssertEqual(PresetStore.removing("PLATES",from:list).map{$0.name},["text"]);XCTAssertEqual(PresetStore.removing("nothing",from:list).count,2)
        XCTAssertTrue(PresetStore.isTaken("Text",in:list));XCTAssertFalse(PresetStore.isTaken("Maps",in:list))
    }
    func testPresetsSurviveBeingSavedAndUnreadableOnesAreNone() throws {
        var sharp=settings(.grayscale,brightness:-0.1);sharp.sharpness=0.4;sharp.exposure=0.25;sharp.despeckle=2
        let list=[SettingsPreset(name:"Text",adjustments:sharp,format:PageFormat(fitInto:.a4)),SettingsPreset(name:"Plain",adjustments:Adjustments(),format:nil)]
        XCTAssertEqual(PresetStore.decode(try PresetStore.encode(list)),list)
        XCTAssertEqual(PresetStore.decode(Data("nonsense".utf8)),[]);XCTAssertEqual(PresetStore.decode(nil),[])
    }
    func testTheMostUsedPresetsComeFirstAndTiesKeepTheirOrder() {
        let list=["Text","Plates","Maps","Covers"].map{SettingsPreset(name:$0,adjustments:Adjustments(),format:nil)}
        XCTAssertEqual(PresetStore.mostUsed(list,uses:[:]),["Text","Plates","Maps"],"Before any is used, the first three made")
        XCTAssertEqual(PresetStore.mostUsed(list,uses:["Covers":5,"Maps":2,"Gone":9]),["Covers","Maps","Text"],"A count for a preset that is gone is ignored")
        XCTAssertEqual(PresetStore.mostUsed(list,uses:["Plates":1,"Covers":1]),["Plates","Covers","Text"])
        XCTAssertEqual(PresetStore.mostUsed(Array(list.prefix(2)),uses:[:]),["Text","Plates"]);XCTAssertEqual(PresetStore.mostUsed(list,uses:["Maps":1],limit:1),["Maps"])
        XCTAssertEqual(PresetStore.counting("Maps",in:["Maps":2]),["Maps":3]);XCTAssertEqual(PresetStore.counting("Text",in:[:]),["Text":1])
    }
    func testAPresetSaysWhatItHolds() {
        var a=settings(.grayscale,brightness:0.2);a.sharpness=0.5
        let summary=SettingsPreset(name:"Text",adjustments:a,format:PageFormat(fitInto:.a5)).summary
        XCTAssertTrue(summary.contains("Grayscale") && summary.contains("brightness +20") && summary.contains("sharpness 50") && summary.contains("A5"),summary)
        XCTAssertFalse(summary.contains("contrast"),"Neutral values are left out: \(summary)")
    }
}
