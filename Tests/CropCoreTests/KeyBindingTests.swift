import XCTest
@testable import CropCore

final class KeyBindingTests: XCTestCase {
    func stroke(_ key: String, shift: Bool = false, option: Bool = false) -> KeyStroke {KeyStroke(key:key,shift:shift,option:option)}
    func testEveryCommandHasItsOwnDefaultKeyAndNoneIsReserved() {
        let all=KeyCommands.all
        XCTAssertGreaterThan(all.count,40);XCTAssertEqual(Set(all.map{$0.id}).count,all.count,"Ids are unique");XCTAssertEqual(Set(all.map{$0.stroke}).count,all.count,"No two commands share a key")
        for command in all {XCTAssertNil(KeyBindings.refusal(command.stroke),"\(command.id)");XCTAssertFalse(command.title.isEmpty || command.group.isEmpty)}
        XCTAssertEqual(KeyCommands.named("preview")?.stroke,stroke("p"));XCTAssertEqual(KeyCommands.named("removeSmudges")?.stroke,stroke("b",shift:true,option:true))
    }
    func testAKeyIsShownAsItIsTyped() {
        XCTAssertEqual(stroke("t").display,"t");XCTAssertEqual(stroke("t",shift:true).display,"Shift T");XCTAssertEqual(stroke("t",option:true).display,"Option t")
        XCTAssertEqual(stroke("b",shift:true,option:true).display,"Option Shift B");XCTAssertEqual(stroke(",",option:true).display,"Option ,")
        XCTAssertEqual(stroke("?",shift:true).display,"?","A symbol typed with Shift is shown as the symbol")
    }
    func testWithNothingChangedEveryKeyDoesWhatItAlwaysDid() {
        let bindings=KeyBindings()
        for command in KeyCommands.all {XCTAssertEqual(bindings.translate(command.stroke),.run(command.stroke),command.id)}
        // Keys that are not commands of their own pass through: other spellings, and modifiers a command ignores.
        XCTAssertEqual(bindings.translate(stroke("?",shift:true)),.unchanged);XCTAssertEqual(bindings.translate(stroke("0")),.unchanged);XCTAssertEqual(bindings.translate(stroke("h",shift:true)),.unchanged)
        XCTAssertEqual(bindings.translate(stroke("\r")),.unchanged);XCTAssertTrue(bindings.changed.isEmpty)
    }
    func testAChangedKeyRunsItsCommandAndTheOldKeyDoesNothing() {
        var bindings=KeyBindings()
        XCTAssertNil(bindings.assign(stroke("9"),to:"preview"),"Nothing held 9")
        XCTAssertEqual(bindings.stroke(for:"preview"),stroke("9"));XCTAssertEqual(bindings.command(for:stroke("9"))?.id,"preview")
        XCTAssertEqual(bindings.translate(stroke("9")),.run(stroke("p")),"The new key does what p did");XCTAssertEqual(bindings.translate(stroke("p")),.nothing,"p is free now")
        XCTAssertEqual(bindings.translate(stroke("p",option:true)),.nothing,"with any modifier")
        XCTAssertEqual(bindings.changed.map{$0.id},["preview"])
        // Its neighbours are untouched.
        XCTAssertEqual(bindings.translate(stroke("t",shift:true)),.run(stroke("t",shift:true)))
        bindings.reset("preview");XCTAssertEqual(bindings,KeyBindings())
    }
    func testAKeyAlreadyInUseIsSwappedSoNoCommandIsLeftWithoutOne() {
        var bindings=KeyBindings()
        XCTAssertEqual(bindings.conflict(stroke("t"),with:"preview")?.id,"split");XCTAssertNil(bindings.conflict(stroke("p"),with:"preview"),"Its own key is no conflict")
        XCTAssertEqual(bindings.assign(stroke("t"),to:"preview")?.id,"split","Says which command it swapped with")
        XCTAssertEqual(bindings.stroke(for:"preview"),stroke("t"));XCTAssertEqual(bindings.stroke(for:"split"),stroke("p"))
        XCTAssertEqual(bindings.translate(stroke("t")),.run(stroke("p")));XCTAssertEqual(bindings.translate(stroke("p")),.run(stroke("t")))
        XCTAssertEqual(Set(KeyCommands.all.map{bindings.stroke(for:$0.id)}).count,KeyCommands.all.count,"Still one key each")
        bindings.reset("preview");XCTAssertEqual(bindings,KeyBindings(),"Putting one back puts the other back")
        bindings.assign(stroke("9"),to:"preview");bindings.assign(stroke("8"),to:"split");bindings.resetAll();XCTAssertEqual(bindings,KeyBindings())
    }
    func testOtherSpellingsOfAKeyFollowTheirCommand() {
        var bindings=KeyBindings()
        bindings.assign(stroke("9"),to:"help")
        XCTAssertEqual(bindings.translate(stroke("?",shift:true)),.nothing,"? went with / when help moved");XCTAssertEqual(bindings.translate(stroke("9")),.run(stroke("/")))
        // A spelling can be given to another command.
        bindings.assign(stroke("0"),to:"preview");XCTAssertEqual(bindings.translate(stroke("0")),.run(stroke("p")))
    }
    func testKeysThatCannotBeGivenAwayAreRefusedWithAReason() {
        for key in ["h","j","k","l"] {XCTAssertNotNil(KeyBindings.refusal(stroke(key)));XCTAssertNotNil(KeyBindings.refusal(stroke(key,shift:true,option:true)))}
        for key in ["\r","\u{1b}"," ","\t","\u{7f}","\u{F702}","","ab"] {XCTAssertNotNil(KeyBindings.refusal(stroke(key)),"\(Array(key.unicodeScalars))")}
        XCTAssertNil(KeyBindings.refusal(stroke("9")));XCTAssertNil(KeyBindings.refusal(stroke("é")))
        var bindings=KeyBindings();bindings.assign(stroke("h"),to:"preview");bindings.assign(stroke("9"),to:"no such command")
        XCTAssertEqual(bindings,KeyBindings(),"A refused key or an unknown command changes nothing")
    }
    func testChangesAreKeptAndOddDataIsIgnored() throws {
        var bindings=KeyBindings();bindings.assign(stroke("t"),to:"preview");bindings.assign(stroke("9",option:true),to:"deskew")
        XCTAssertEqual(KeyBindings.decode(try bindings.encode()),bindings)
        XCTAssertEqual(KeyBindings.decode(Data("junk".utf8)),KeyBindings());XCTAssertEqual(KeyBindings.decode(nil),KeyBindings())
        // Saved changes that no longer make sense are dropped: an unknown command, a reserved key, two commands on one key.
        let odd=try JSONEncoder().encode(["gone":stroke("9"),"preview":stroke("h"),"split":stroke("q")])
        XCTAssertEqual(KeyBindings.decode(odd),KeyBindings())
    }
    func testTheReferenceShowsTheKeysInUse() {
        let plain=ShortcutReference.sections(with:KeyBindings())
        XCTAssertEqual(plain.map{$0.entries.map{$0.keys}},ShortcutReference.sections.map{$0.entries.map{$0.keys}},"Unchanged keys leave the reference as written")
        var bindings=KeyBindings();bindings.assign(stroke("9"),to:"preview");bindings.assign(stroke("g",option:true),to:"splitLeft")
        let entries=ShortcutReference.sections(with:bindings).flatMap{$0.entries}
        XCTAssertTrue(entries.contains{$0.keys=="9" && $0.action==KeyCommands.named("preview")!.title});XCTAssertFalse(entries.contains{$0.keys=="p"})
        // A row that covered several commands is given one line each once any of them has moved.
        XCTAssertFalse(entries.contains{$0.keys=="y / u"});XCTAssertTrue(entries.contains{$0.keys=="Option g"} && entries.contains{$0.keys=="u"} && entries.contains{$0.keys=="Shift U"})
        // Every command that can be changed is covered by some row, so none can go stale.
        XCTAssertEqual(Set(ShortcutReference.rowCommands.values.flatMap{$0}),Set(KeyCommands.all.map{$0.id}))
        for keys in ShortcutReference.rowCommands.keys {XCTAssertTrue(ShortcutReference.sections.contains{$0.entries.contains{$0.keys==ShortcutReference.shown(keys)}},"No row \(keys)")}
        // The short list in the inspector follows too.
        XCTAssertTrue(ShortcutReference.brief(with:KeyBindings()).contains{$0.keys=="c"} && ShortcutReference.brief(with:bindings).contains{$0.keys=="/"})
        bindings.assign(stroke("0"),to:"copyCrop");XCTAssertTrue(ShortcutReference.brief(with:bindings).contains{$0.keys=="0"})
    }
}
