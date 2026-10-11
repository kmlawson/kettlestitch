import AppKit
import CropCore

extension AppDelegate {
    /// Drives the real window with synthetic events, then quits. Only ever run against a disposable project copy.
    func runSmoke(_ dir:String){
        // Unbuffered so earlier results survive a failed check.
        setvbuf(stdout,nil,_IONBF,0)
        // Start once the first photograph is on screen rather than after a fixed delay.
        let started=Date()
        Timer.scheduledTimer(withTimeInterval:0.25,repeats:true){timer in
            guard (self.canvas.image != nil && Date().timeIntervalSince(started)>1) || Date().timeIntervalSince(started)>30 else{return}
            timer.invalidate()
            self.window.contentView!.layoutSubtreeIfNeeded()
            let view=self.window.contentView!,rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
            view.cacheDisplay(in:view.bounds,to:rep)
            try? rep.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:dir).appendingPathComponent("ui.png"))
            func snapshot(_ view:NSView,_ name:String){
                view.layoutSubtreeIfNeeded()
                guard let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{return}
                view.cacheDisplay(in:view.bounds,to:rep)
                try? rep.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:dir).appendingPathComponent(name))
            }
            snapshot(view.superview ?? view,"window.png")
            snapshot(ExportSheetController(options:self.exportOptions,selectedCount:1,totalCount:self.project.pages.count).panel.contentView!,"export-sheet.png")
            snapshot(SettingsController().window.contentView!,"settings.png")
            // Menu rules as the real window sees them, including while a field is being edited.
            func enabled(_ action:Selector)->Bool {self.validateMenuItem(NSMenuItem(title:"",action:action,keyEquivalent:""))}
            precondition(enabled(#selector(self.removePages)) && enabled(#selector(self.next)) && !enabled(#selector(self.previous)) && !enabled(#selector(self.stop)) && !enabled(#selector(self.undo)))
            let flagItem=NSMenuItem(title:"",action:#selector(self.toggleFlag),keyEquivalent:"");_=self.validateMenuItem(flagItem);precondition(flagItem.title=="Add Flag")
            self.window.makeFirstResponder(self.widthField);precondition(self.editedText != nil && !enabled(#selector(self.removePages)) && !enabled(#selector(self.accept)))
            // A menu shortcut that is a bare letter must leave that letter to the text being typed.
            let bare=NSMenuItem(title:"",action:#selector(self.locatePhotographs),keyEquivalent:"p");bare.keyEquivalentModifierMask=[];bare.target=self
            precondition(!self.validateMenuItem(bare),"A plain-key shortcut is off while a field is edited")
            self.window.makeFirstResponder(self.canvas);precondition(self.validateMenuItem(bare));self.window.makeFirstResponder(self.widthField)
            self.window.makeFirstResponder(self.canvas);precondition(self.editedText==nil && enabled(#selector(self.removePages)))
            self.help();snapshot(self.shortcuts!.window.contentView!,"shortcuts.png");self.shortcuts!.window.close()
            print("MENU_RULES_AND_SHORTCUTS_WINDOW passed")
            // The photograph must actually be visible in the window, not painted over by a neighbouring pane.
            let whole=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:whole)
            let corner=self.canvas.convert(CGPoint(x:6,y:6),to:view),scale=CGFloat(whole.pixelsWide)/view.bounds.width
            let shade=whole.colorAt(x:Int(corner.x*scale),y:Int((view.isFlipped ? corner.y:view.bounds.height-corner.y)*scale))?.usingColorSpace(.deviceGray)?.whiteComponent ?? 1
            precondition(shade<0.25,"The canvas is hidden: its corner shows \(shade) instead of the dark surround")
            print("CANVAS_VISIBLE passed")
            let didLoad=self.original != nil
            let canvas=self.canvas
            func mouse(_ type:NSEvent.EventType,_ point:CGPoint)->NSEvent {
                NSEvent.mouseEvent(with:type,location:canvas.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:self.window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
            }
            let originalQuad=canvas.quad
            let smokeImage=canvas.image
            let cornerPoint=canvas.position(originalQuad.points[0])
            canvas.mouseDown(with:mouse(.leftMouseDown,cornerPoint))
            precondition(canvas.isMagnifierVisible)
            canvas.mouseUp(with:mouse(.leftMouseUp,cornerPoint))
            precondition(!canvas.isMagnifierVisible && !canvas.keyboardSelection)
            let a=canvas.position(originalQuad.points[0]),b=canvas.position(originalQuad.points[1])
            let midpoint=CGPoint(x:(a.x+b.x)/2,y:(a.y+b.y)/2)
            canvas.mouseDown(with:mouse(.leftMouseDown,midpoint))
            precondition(canvas.selectedEdge==0 && !canvas.keyboardSelection)
            let dragged=CGPoint(x:midpoint.x,y:midpoint.y+8)
            canvas.mouseDragged(with:mouse(.leftMouseDragged,dragged))
            precondition(canvas.quad.points[0] != originalQuad.points[0] && canvas.quad.points[1] != originalQuad.points[1])
            precondition(canvas.quad.points[2]==originalQuad.points[2] && canvas.quad.points[3]==originalQuad.points[3])
            canvas.mouseUp(with:mouse(.leftMouseUp,dragged))
            precondition(!canvas.isMagnifierVisible)
            canvas.selectEdge(1);let edgeBefore=canvas.quad;canvas.nudge("a",large:false)
            precondition(canvas.quad.points[1] != edgeBefore.points[1] && canvas.quad.points[2] != edgeBefore.points[2])
            canvas.selectCorner(0);precondition(canvas.isMagnifierVisible);canvas.releaseCorner()
            canvas.quad=originalQuad;self.project.pages[0].quad=originalQuad
            func key(_ chars:String,_ code:UInt16,_ flags:NSEvent.ModifierFlags=[]){
                let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:self.window.windowNumber,context:nil,characters:chars,charactersIgnoringModifiers:chars,isARepeat:false,keyCode:code)!
                precondition(self.handleKey(event))
            }
            for (number,edge) in [("5",0),("6",3),("7",1),("8",2)] {
                key(number,0);precondition(canvas.selectedEdge==edge && canvas.keyboardSelection)
            }
            key("1",0);precondition(canvas.keyboardSelection)
            let click=canvas.position(canvas.quad.points[0])
            canvas.mouseDown(with:mouse(.leftMouseDown,click));canvas.mouseUp(with:mouse(.leftMouseUp,click))
            precondition(!canvas.keyboardSelection)
            let selected=self.project.selected
            key("6",0);let q=canvas.quad
            key("\u{F703}",124)
            precondition(self.project.selected==selected && canvas.quad != q)
            key("\u{1b}",53);precondition(!canvas.hasSelection)
            key("\u{F703}",124);precondition(self.project.selected==selected+1)
            key("c",8);precondition(self.project.pages[1].quad==self.project.pages[0].quad)
            key("c",8);precondition(self.project.pages[1].quad==self.project.pages[0].quad)
            key("'",39);let expanded=self.project.pages[1].quad
            precondition(expanded.area>=self.project.pages[0].quad.area)
            key(";",41);precondition(self.project.pages[1].quad.area<expanded.area)
            let inset=Quad([Point(0.1,0.1),Point(0.9,0.1),Point(0.9,0.9),Point(0.1,0.9)])
            for (letter,edge) in [("h",3),("j",2),("k",0),("l",1)] {
                self.project.pages[1].quad=inset;canvas.quad=inset
                key(letter,0);let moved=self.project.pages[1].quad
                precondition(moved.area>inset.area)
                for index in 0..<4 {precondition((moved.points[index] != inset.points[index]) == (index==edge || index==(edge+1)%4))}
                key(letter,0,.shift);precondition(self.project.pages[1].quad.distance(inset)<1e-10)
            }
            // Rotation in both directions, flags, multi-page settings and structural undo.
            let turned=self.project.pages[1].rotation
            key("r",15);precondition(self.project.pages[1].rotation==(turned+1)%4 && canvas.preview)
            key("r",15,.shift);key("r",15,.shift);precondition(self.project.pages[1].rotation==(turned+3)%4)
            key("r",15);precondition(self.project.pages[1].rotation==turned)
            key("p",35);precondition(!canvas.preview)
            key("m",46);precondition(self.project.pages[1].flagged==true);key("m",46);precondition(self.project.pages[1].flagged==nil)
            self.table.selectRowIndexes(IndexSet([0,1]),byExtendingSelection:false)
            precondition(self.project.selected==1 && self.targetIndexes==[0,1])
            var tone=Adjustments();tone.cleanup = .grayscale;tone.brightness=0.2
            let undoDepth=self.undoStack.count
            self.setAdjustments(tone);tone.brightness=0.4;self.setAdjustments(tone);self.commitAdjustments()
            precondition(self.project.pages[0].adjustments==tone && self.project.pages[1].adjustments==tone && self.undoStack.count==undoDepth+1)
            self.undo();precondition(self.project.pages[0].adjustments==nil && self.project.pages[1].adjustments==nil)
            self.redo();precondition(self.project.pages[1].adjustments==tone)
            self.undo()
            self.project.selected=1;self.selectCurrent()
            self.fitPopup.selectItem(at:2);self.formatChanged(self.fitPopup);precondition(self.project.pages[1].format==PageFormat(fitInto:.a4))
            self.copySettings();self.navigate(-1);self.pasteSettings();precondition(self.project.pages[0].format==PageFormat(fitInto:.a4))
            self.undo();self.navigate(1);self.undo();precondition(self.project.pages[0].format==nil && self.project.pages[1].format==nil)
            let count=self.project.pages.count,firstID=self.project.pages[0].id
            self.reversePages();precondition(self.project.pages.last?.id==firstID)
            // Work done after a reorder survives undoing the reorder.
            let later=self.project.pages.firstIndex{$0.id==firstID}!;self.project.pages[later].reviewNote="written after the reorder"
            self.undo();precondition(self.project.pages[0].id==firstID && self.project.pages[0].reviewNote=="written after the reorder")
            self.project.pages[0].reviewNote=nil
            // Leaving the preview while a photograph is still loading keeps the load.
            self.navigate(1);let loading=self.displayToken;precondition(self.original==nil)
            self.setPreview(true);self.setPreview(false);precondition(self.displayToken==loading);self.navigate(-1)
            // Overlapping work shares the progress bar: finishing one task leaves the other showing.
            self.beginProgress(.review,10);self.beginProgress(.export,2);self.endProgress(.export);precondition(!self.progress.isHidden)
            self.endProgress(.review);precondition(self.progress.isHidden && self.stopButton.isHidden)
            self.project.selected=1;self.selectCurrent();self.removePages();precondition(self.project.pages.count==count-1)
            self.undo();precondition(self.project.pages.count==count && self.project.selected==1)
            print("ROTATE_FLAG_SETTINGS_STRUCTURE passed")
            // Page split: keys, clamping, dragging the line and one end, rotation, removal and undo.
            self.project.selected=1;self.selectCurrent();canvas.image=smokeImage
            self.project.pages[1].quad=inset;self.project.pages[1].rotation=0;self.project.pages[1].split = .centre;self.refreshDetail();canvas.quad=inset
            key(".",47);precondition(abs(self.project.pages[1].split!.top-0.502)<1e-9 && canvas.split==self.project.pages[1].split)
            key(",",43,.shift);precondition(abs(self.project.pages[1].split!.bottom-0.492)<1e-9)
            let ends=canvas.splitEnds!,middle=CGPoint(x:(ends.0.x+ends.1.x)/2,y:(ends.0.y+ends.1.y)/2)
            canvas.mouseDown(with:mouse(.leftMouseDown,middle));precondition(canvas.isDraggingSplit && canvas.selectedEdge==nil)
            canvas.mouseDragged(with:mouse(.leftMouseDragged,CGPoint(x:middle.x+30,y:middle.y)));canvas.mouseUp(with:mouse(.leftMouseUp,CGPoint(x:middle.x+30,y:middle.y)))
            let slid=self.project.pages[1].split!
            precondition(slid.top>0.5 && abs(slid.top-slid.bottom)<1e-9 && self.project.pages[1].quad==inset,"Dragging the line moves both ends and leaves the crop alone")
            snapshot(canvas,"split.png")
            let topEnd=canvas.splitEnds!.0
            canvas.mouseDown(with:mouse(.leftMouseDown,topEnd));canvas.mouseDragged(with:mouse(.leftMouseDragged,CGPoint(x:topEnd.x-40,y:topEnd.y)));canvas.mouseUp(with:mouse(.leftMouseUp,CGPoint(x:topEnd.x-40,y:topEnd.y)))
            precondition(self.project.pages[1].split!.top<slid.top && self.project.pages[1].split!.bottom==slid.bottom,"Dragging an end tilts the line")
            self.undo();precondition(self.project.pages[1].split==slid)
            self.project.pages[1].split=PageSplit(top:0.4,bottom:0.45)
            key("r",15);precondition(self.project.pages[1].split==nil,"A quarter turn drops the split until the fold is found again")
            key("r",15,.shift);self.invalidateWork();key("p",35)
            self.project.pages[1].split=PageSplit(top:0.4,bottom:0.45);self.refreshDetail()
            key("v",9,.shift);precondition(self.project.pages[1].split==nil && canvas.split==nil)
            self.undo();precondition(self.project.pages[1].split != nil)
            key("v",9,.shift)
            self.project.pages[1].split = .centre;key("t",17,.shift);precondition(self.project.pages[1].split==nil,"Shift-T removes the split, as Shift-Command-T does")
            print("PAGE_SPLIT_KEYS_DRAG_ROTATE_REMOVE passed")
            // Deskew, despeckle, picture zones and deviations as the real window drives them.
            self.project.pages[1].deskew=nil;self.project.pages[1].split=nil;self.refreshDetail()
            key(".",47,.option);precondition(self.project.pages[1].deskew==[0.1] && canvas.preview,"Option-. turns the page and shows the result")
            key(",",43,.option);precondition(self.project.pages[1].deskew==nil)
            self.project.pages[1].deskew=[1.5];key("q",12,.shift);precondition(self.project.pages[1].deskew==nil)
            self.undo();precondition(self.project.pages[1].deskew==[1.5]);self.project.pages[1].deskew=nil
            key("p",35);if canvas.preview {key("p",35)}
            canvas.image=smokeImage;self.original=smokeImage
            key("w",13);precondition(canvas.zoneMode)
            let from=canvas.position(Point(0.3,0.3)),to=canvas.position(Point(0.6,0.7))
            canvas.mouseDown(with:mouse(.leftMouseDown,from));canvas.mouseDragged(with:mouse(.leftMouseDragged,to));canvas.mouseUp(with:mouse(.leftMouseUp,to))
            let drawn=self.project.pages[1].pictureZones ?? []
            precondition(drawn.count==1 && !canvas.zoneMode && self.project.pages[1].quad==inset,"One drag draws one zone and leaves the crop alone")
            precondition(abs(drawn[0].minU-0.25)<0.01 && abs(drawn[0].maxV-0.75)<0.01 && canvas.zones==drawn,"The zone is stored in the crop's own coordinates")
            precondition(canvas.zone(at:canvas.position(Point(0.45,0.5)))==0 && canvas.zone(at:canvas.position(Point(0.8,0.8)))==nil)
            snapshot(canvas,"zone.png")
            key("w",13);key("\u{1b}",53);precondition(!canvas.zoneMode && self.project.pages[1].pictureZones?.count==1,"Escape cancels drawing")
            key("w",13,.shift);precondition(self.project.pages[1].pictureZones==nil)
            self.cleanupControl.selectedSegment=1;self.despeckleControl.selectedSegment=2;self.adjustmentChanged(nil);self.commitAdjustments()
            precondition(self.project.pages[1].adjustments?.despeckle==2 && self.despeckleControl.isEnabled)
            self.cleanupControl.selectedSegment=2;self.adjustmentChanged(nil);self.commitAdjustments()
            precondition(self.project.pages[1].adjustments?.despeckle==nil && !self.despeckleControl.isEnabled,"Despeckle only applies to black and white")
            self.resetAdjustments();self.commitAdjustments();key("p",35);if canvas.preview {key("p",35)}
            let usual=self.project.pages[1].quad;self.project.pages[1].quad=Quad([Point(0.4,0.4),Point(0.6,0.4),Point(0.6,0.6),Point(0.4,0.6)]);self.save()
            precondition(self.deviationRows[1].reason=="size")
            self.navigate(-1);key("u",32);precondition(self.project.selected==1,"U goes to the unusual page")
            self.showDeviations();precondition(self.deviations!.rows.first?.index==1,"The deviations window lists the worst page first")
            snapshot(self.deviations!.window.contentView!,"deviations.png");self.deviations!.window.close()
            self.project.pages[1].quad=usual;self.save();canvas.quad=usual
            print("DESKEW_ZONES_DESPECKLE_DEVIATIONS passed")
            // Waiting indicators: status line, progress bar, sidebar rows and inspector note; nothing is sent.
            let batch=[self.project.pages[1],self.project.pages[2]]
            self.beginReview(batch,model:"Haiku 5.5");self.reviewWaiting(for:batch[0],number:1)
            precondition(!self.progress.isHidden && !self.progress.isIndeterminate && self.status.stringValue.hasPrefix("Waiting for Claude Haiku 5.5 · page 1 of 2"))
            let activeCell=self.table.view(atColumn:0,row:1,makeIfNecessary:true) as! PageCell,queuedCell=self.table.view(atColumn:0,row:2,makeIfNecessary:true) as! PageCell
            precondition(activeCell.subtitle.stringValue=="Waiting for Claude…" && queuedCell.subtitle.stringValue=="Queued for Claude" && self.note.stringValue=="Waiting for Claude…" && !self.note.isHidden)
            snapshot(view,"waiting.png")
            self.endReview()
            precondition(self.progress.isHidden && self.reviewPending.isEmpty && (self.table.view(atColumn:0,row:1,makeIfNecessary:true) as! PageCell).subtitle.stringValue != "Waiting for Claude…")
            self.beginReview([batch[0]],model:"Haiku 5.5");precondition(self.progress.isIndeterminate);self.endReview();precondition(!self.progress.isIndeterminate)
            print("CLAUDE_WAITING_INDICATORS passed")
            self.navigate(-1)
            canvas.image=smokeImage
            canvas.quad=originalQuad;self.project.pages[0].quad=originalQuad
            print("ARROW_SELECTION_ESCAPE_EDGE_MAPPING_COPY_SCALE passed")
            print("MOUSE_EDGE_LOUPE_KEYBOARD passed")
            let before=self.project.pages[0].quad
            self.selectCorner(0);self.canvas.nudge("d",large:false)
            precondition(self.project.pages[0].quad != before)
            self.undo();precondition(self.project.pages[0].quad == before)
            self.redo();precondition(self.project.pages[0].quad != before)
            self.accept();precondition(self.project.selected==1 && self.project.pages[0].reviewed)
            self.navigate(-1)
            do{
                try Imaging.export(self.project.pages[0],to:URL(fileURLWithPath:dir).appendingPathComponent("export-check.jpg"))
                var options=ExportOptions();options.searchableText=true
                var styled=self.project.pages[1];var clean=Adjustments();clean.cleanup = .blackAndWhite;styled.adjustments=clean
                let writer=try PDFWriter(url:URL(fileURLWithPath:dir).appendingPathComponent("export-check.pdf"))
                try writer.add(self.project.pages[0],options:options);try writer.add(styled,options:options);try writer.close()
                print("EDIT_UNDO_REDO_REVIEW_EXPORT passed")
            }catch{print("SMOKE_ERROR \(error)")}
            print("UI_SMOKE pages=\(self.project.pages.count) loaded=\(didLoad) canvas=\(self.canvas.bounds)")
            // Preview stays on from one photograph to the next.
            self.project.selected=0;self.selectCurrent();self.setPreview(true);self.navigate(1)
            precondition(canvas.preview && self.project.selected==1,"Moving to another photograph keeps the preview");self.setPreview(false)
            print("PREVIEW_KEPT passed")
            // At the last photograph, asking for the next one reloads nothing and flashes the canvas.
            self.lastPage();let shown=self.displayToken,flashes=canvas.edgeFlashes;self.navigate(1)
            precondition(self.displayToken==shown && canvas.edgeFlashes==flashes+1 && self.project.selected==self.project.pages.count-1,"The last photograph is not reloaded")
            self.firstPage();self.navigate(-1);precondition(canvas.edgeFlashes==flashes+2 && self.project.selected==0)
            print("END_OF_BOOK passed")
            // The smudge brush: a stroke is kept on the page, Undo takes it back, and Escape puts the brush down.
            self.project.selected=0;self.selectCurrent();canvas.image=smokeImage;self.original=smokeImage;let strokes=self.project.pages[0].smudges?.count ?? 0
            key("b",11,.shift);precondition(canvas.smudgeMode && !canvas.preview,"Shift-B picks up the brush")
            canvas.onSmudgeCommit?([Point(0.3,0.3),Point(0.5,0.3)])
            precondition(self.project.pages[0].smudges?.count==strokes+1 && self.project.pages[0].smudges?.last?.strength==self.smudgeStrengthSlider.doubleValue)
            self.undo();precondition((self.project.pages[0].smudges?.count ?? 0)==strokes)
            key("\u{1b}",53);precondition(!canvas.smudgeMode)
            print("SMUDGE passed")
            // The hidden tool for collecting detector mistakes keeps the photograph, its data and a marked-up picture.
            self.project.selected=0;self.selectCurrent();self.saveBadExample()
            let examples=URL(fileURLWithPath:dir).appendingPathComponent("Bad Examples"),saved=(try? FileManager.default.contentsOfDirectory(at:examples,includingPropertiesForKeys:nil)) ?? []
            precondition(saved.count==1 && Set((try? FileManager.default.contentsOfDirectory(atPath:saved[0].path)) ?? [])==["example.json","overlay.jpg",URL(fileURLWithPath:self.project.pages[0].path).lastPathComponent],"A bad example is one folder of three files")
            precondition(self.badExampleItem?.isHidden==true && self.badExampleItem?.keyEquivalentModifierMask==[.command,.option])
            print("BAD_EXAMPLE passed")
            // T again steps through the other places the detector offered, and round to the first; a split moved by hand starts afresh.
            let options=[PageSplit(top:0.47,bottom:0.47),PageSplit(top:0.5,bottom:0.5),PageSplit(top:0.56,bottom:0.56)],cycled=self.project.pages[0]
            self.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
            self.project.pages[0].split=options[0];self.splitOptions[cycled.id]=(options,0,cycled.quad,cycled.rotation)
            key("t",17);precondition(self.project.pages[0].split==options[1]);key("t",17);precondition(self.project.pages[0].split==options[2])
            key("t",17);precondition(self.project.pages[0].split==options[0],"After the last candidate comes the first")
            self.project.pages[0].split=nil;self.splitOptions[cycled.id]=nil;self.refreshDetail()
            print("SPLIT_CANDIDATES passed")
            // A project file is written by Save, not by each edit.
            if self.hasProjectFile {
                func onDisk()->Project? {try? Project.read(self.projectURL)}
                self.saveProject();precondition(!self.unsaved && !self.window.isDocumentEdited)
                self.edit{$0.flagged = $0.flagged==true ? nil:true}
                precondition(self.unsaved && self.window.isDocumentEdited && onDisk()?.pages[self.project.selected].flagged != self.project.pages[self.project.selected].flagged,"An edit waits for Save")
                self.saveProject()
                precondition(!self.unsaved && !self.window.isDocumentEdited && onDisk()?.pages[self.project.selected].flagged==self.project.pages[self.project.selected].flagged,"Save updates the current file")
                print("SAVE passed")
            }
            // terminate normally never returns; if the quit is refused, say so instead of hanging.
            DispatchQueue.main.asyncAfter(deadline:.now()+5){print("TERMINATE_REFUSED");self.write();exit(3)}
            NSApp.terminate(nil)
        }
    }
}

extension AppDelegate {
    /// Checks an ordinary launch: nothing is shown until photographs or a project are handed to the app.
    func runEmptySmoke(_ dir:String,folder:URL,project other:URL){
        setvbuf(stdout,nil,_IONBF,0)
        DispatchQueue.main.asyncAfter(deadline:.now()+1.5){
            let view=self.window.contentView!
            func shade(_ point:CGPoint)->CGFloat {
                let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:rep)
                let p=self.canvas.convert(point,to:view),scale=CGFloat(rep.pixelsWide)/view.bounds.width
                return rep.colorAt(x:Int(p.x*scale),y:Int((view.isFlipped ? p.y:view.bounds.height-p.y)*scale))?.usingColorSpace(.deviceGray)?.whiteComponent ?? 1
            }
            precondition(self.project.pages.isEmpty && self.current==nil && self.table.numberOfRows==0,"Nothing is reopened at launch")
            precondition(self.canvas.image==nil && self.canvas.placeholder==CropCanvas.emptyProjectMessage && self.window.title=="Untitled")
            precondition(shade(CGPoint(x:6,y:6))<0.25,"The empty canvas is visible")
            self.save();precondition(!FileManager.default.fileExists(atPath:self.projectURL.path),"An untouched session writes no file")
            precondition(!self.validateMenuItem(NSMenuItem(title:"",action:#selector(self.exportImages),keyEquivalent:"")) && self.validateMenuItem(NSMenuItem(title:"",action:#selector(self.importImages),keyEquivalent:"")))
            let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:rep)
            try? rep.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:dir).appendingPathComponent("empty.png"))
            print("EMPTY_LAUNCH passed")
            // The same route a drop on the window or on the app's icon takes. The import itself runs off the main thread.
            self.application(NSApp,open:[folder])
            precondition(self.importing && !self.banner.isHidden,"A notice over the canvas says photographs are being imported")
            /// Runs `then` once the import under way has finished.
            func afterImport(_ then:@escaping()->Void){
                let began=Date()
                Timer.scheduledTimer(withTimeInterval:0.05,repeats:true){timer in
                    guard !self.importing || Date().timeIntervalSince(began)>60 else{return}
                    timer.invalidate();precondition(!self.importing && self.banner.isHidden,"The import finishes and its notice goes");then()
                }
            }
            afterImport{
                let count=self.project.pages.count
                precondition(count>0 && self.project.selected==0 && self.table.numberOfRows==count && FileManager.default.fileExists(atPath:self.projectURL.path),"Dropped photographs are added and saved")
                self.receive([folder])
                afterImport{
                    precondition(self.project.pages.count==count,"The same photographs are not added twice")
                    self.undo();precondition(self.project.pages.isEmpty);self.redo();precondition(self.project.pages.count==count)
                    let started=Date()
                    Timer.scheduledTimer(withTimeInterval:0.25,repeats:true){timer in
                        guard (self.canvas.image != nil && !self.detecting) || Date().timeIntervalSince(started)>60 else{return}
                        timer.invalidate()
                        precondition(self.canvas.image != nil,"The first dropped photograph is shown")
                        precondition(!self.project.pages.contains{$0.status=="Pending"},"Crops are proposed for imported photographs without being asked")
                        print("DROP_PHOTOGRAPHS passed")
                        self.receive([other])
                        precondition(self.projectURL==other && self.project.pages.count != count && self.window.title==other.deletingPathExtension().lastPathComponent,"A dropped project file is opened")
                        print("DROP_PROJECT passed")
                        DispatchQueue.main.asyncAfter(deadline:.now()+5){print("TERMINATE_REFUSED");exit(3)}
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }
    /// Times moving through a long project: how long each step holds the main thread, and how long until its
    /// photograph is on screen, near the start, the middle and the end of the list.
    func runBench(){
        let count=project.pages.count;guard count>30 else{print("BENCH needs a long project");exit(2)}
        var plan:[(String,Int)]=[("start",2),("middle",count/2),("end",count-12)],lines:[String]=[]
        func measure(_ label:String,_ from:Int,_ done:@escaping()->Void){
            self.show(from)
            var step=0,held:[Double]=[],shown:[Double]=[]
            func next(){
                guard step<8 else{
                    lines.append(String(format:"BENCH %@ row=%d main_ms=%.1f shown_ms=%.0f",label,from,held.reduce(0,+)/8*1000,shown.reduce(0,+)/8*1000));done();return
                }
                step+=1
                let began=Date();self.navigate(1);held.append(Date().timeIntervalSince(began))
                Timer.scheduledTimer(withTimeInterval:0.005,repeats:true){timer in
                    guard self.canvas.image != nil || Date().timeIntervalSince(began)>10 else{return}
                    timer.invalidate();shown.append(Date().timeIntervalSince(began));next()
                }
            }
            DispatchQueue.main.asyncAfter(deadline:.now()+1.5){next()}
        }
        func run(){
            guard !plan.isEmpty else{lines.forEach{print($0)};self.unsaved=false;exit(0)}
            let (label,row)=plan.removeFirst();measure(label,row,run)
        }
        if CommandLine.arguments.contains("--thumbs") {
            // Sidebar pictures after pages are removed: every visible row should still have one.
            func missing()->[Int] {(0..<min(8,self.project.pages.count)).filter{(self.table.view(atColumn:0,row:$0,makeIfNecessary:true) as? PageCell)?.thumb.image==nil}}
            DispatchQueue.main.asyncAfter(deadline:.now()+(CommandLine.arguments.contains("--early") ? 0.15:4)){
                print("THUMBS before removal, rows without a picture: \(missing())")
                self.table.selectRowIndexes(IndexSet([1,2,3]),byExtendingSelection:false);self.project.selected=1;self.removePages()
                print("THUMBS just after removal: \(missing())")
                DispatchQueue.main.asyncAfter(deadline:.now()+4){print("THUMBS 4 s after removal: \(missing())");self.unsaved=false;exit(0)}
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+2){run()}
    }
}
