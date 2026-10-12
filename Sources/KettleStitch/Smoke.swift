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
            key("r",15);precondition(self.project.pages[1].rotation==(turned+1)%4 && !canvas.preview,"Turning the page leaves the view on the photograph")
            key("r",15,.shift);key("r",15,.shift);precondition(self.project.pages[1].rotation==(turned+3)%4)
            key("r",15);precondition(self.project.pages[1].rotation==turned)
            precondition(!canvas.preview)
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
            key("u",32);precondition(abs(self.project.pages[1].split!.top-0.502)<1e-9 && canvas.split==self.project.pages[1].split)
            key("y",16,.shift);precondition(abs(self.project.pages[1].split!.bottom-0.492)<1e-9)
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
            key("t",17,.shift);precondition(self.project.pages[1].split==nil && canvas.split==nil)
            self.undo();precondition(self.project.pages[1].split != nil)
            key("t",17,.shift)
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
            self.navigate(-1);key(".",47);precondition(self.project.selected==1,"Period goes to the unusual page")
            self.showDeviations();precondition(self.deviations!.rows.first?.index==1,"The deviations window lists the worst page first")
            snapshot(self.deviations!.window.contentView!,"deviations.png");self.deviations!.window.close()
            self.project.pages[1].quad=usual;self.save();canvas.quad=usual
            print("DESKEW_ZONES_DESPECKLE_DEVIATIONS passed")
            // Waiting indicators: status line, progress bar, sidebar rows and inspector note; nothing is sent.
            let batch=[self.project.pages[1],self.project.pages[2]]
            self.beginReview(batch,model:"Claude Haiku 5.5");self.reviewWaiting(for:batch[0],number:1)
            precondition(!self.progress.isHidden && !self.progress.isIndeterminate && self.status.stringValue.hasPrefix("Waiting for Claude Haiku 5.5 · page 1 of 2"))
            let activeCell=self.table.view(atColumn:0,row:1,makeIfNecessary:true) as! PageCell,queuedCell=self.table.view(atColumn:0,row:2,makeIfNecessary:true) as! PageCell
            precondition(activeCell.subtitle.stringValue=="Waiting for an answer…" && queuedCell.subtitle.stringValue=="Queued for review" && self.note.stringValue=="Waiting for an answer…" && !self.note.isHidden)
            snapshot(view,"waiting.png")
            self.endReview()
            precondition(self.progress.isHidden && self.reviewPending.isEmpty && (self.table.view(atColumn:0,row:1,makeIfNecessary:true) as! PageCell).subtitle.stringValue != "Waiting for an answer…")
            self.beginReview([batch[0]],model:"Claude Haiku 5.5");precondition(self.progress.isIndeterminate);self.endReview();precondition(!self.progress.isIndeterminate)
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
            key("z",6,.shift);precondition(self.project.pages[0].quad != before,"Shift-Z redoes")
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
            precondition(self.smudgeRows.count==2 && self.smudgeRows.allSatisfy{$0.isHidden} && self.smudgeButton.state == .off,"The brush's width and strength are out of sight until it is picked up")
            precondition(!self.clearSmudgeButton.isEnabled || strokes>0,"Nothing to erase, so the crossed-out button is off")
            key("b",11,.shift);precondition(canvas.smudgeMode && !canvas.preview,"Shift-B picks up the brush")
            precondition(self.smudgeRows.allSatisfy{!$0.isHidden} && self.smudgeButton.state == .on)
            snapshot(self.window.contentView!,"smudge-on.png")
            canvas.onSmudgeCommit?([Point(0.3,0.3),Point(0.5,0.3)])
            precondition(self.project.pages[0].smudges?.count==strokes+1 && self.project.pages[0].smudges?.last?.strength==self.smudgeStrengthSlider.doubleValue)
            precondition(self.clearSmudgeButton.isEnabled,"With a smudge on the page it can be erased")
            self.undo();precondition((self.project.pages[0].smudges?.count ?? 0)==strokes)
            key("\u{1b}",53);precondition(!canvas.smudgeMode && self.smudgeRows.allSatisfy{$0.isHidden} && self.smudgeButton.state == .off)
            // The grain a stroke gets is what its slider says.
            self.smudgeGrainSlider.doubleValue=0.8;self.smudgeBrushChanged(nil);key("b",11,.shift);canvas.onSmudgeCommit?([Point(0.3,0.3),Point(0.5,0.3)])
            precondition(self.project.pages[0].smudges?.last?.grain==0.8 && self.smudgeGrainValue.stringValue=="80");self.undo();key("\u{1b}",53)
            self.smudgeGrainSlider.doubleValue=Imaging.smudgeGrain;self.smudgeBrushChanged(nil)
            // The clone brush: its own button, the shared width, a source chosen first, strokes that Undo takes back.
            key("c",8,.shift);precondition(canvas.cloneMode && !canvas.smudgeMode && self.cloneButton.state == .on && self.smudgeButton.state == .off,"Shift-C picks up the clone brush")
            precondition(self.brushRow?.isHidden==false && self.smudgeRows.allSatisfy{$0.isHidden},"Only the width belongs to the clone brush")
            precondition(!self.clearCloneButton.isEnabled,"Nothing cloned yet, so nothing to remove")
            canvas.onCloneCommit?([Point(0.2,0.2),Point(0.3,0.2)],Point(0.4,0.1))
            precondition(self.project.pages[0].clones==[CloneStroke(points:[Point(0.2,0.2),Point(0.3,0.2)],radius:self.smudgeSizeSlider.doubleValue,offset:Point(0.4,0.1))] && self.clearCloneButton.isEnabled)
            snapshot(self.window.contentView!,"clone-on.png")
            self.removeClones();precondition(self.project.pages[0].clones==nil);self.undo();precondition(self.project.pages[0].clones?.count==1);self.undo();precondition(self.project.pages[0].clones==nil)
            key("b",11,.shift);precondition(canvas.smudgeMode && !canvas.cloneMode,"Picking up one brush puts the other down");key("\u{1b}",53)
            precondition(!canvas.smudgeMode && !canvas.cloneMode && self.brushRow?.isHidden==true)
            // A sidebar picture of a turned page is turned too.
            let wide=NSImage(size:NSSize(width:120,height:90),flipped:false){rect in NSColor.gray.setFill();rect.fill();return true}
            let upright=ThumbnailPolicy.turned(wide,by:ViewTurn(1));precondition(upright.size.width<upright.size.height && ThumbnailPolicy.turned(wide,by:ViewTurn(2)).size.width>90)
            print("SMUDGE passed")
            // The hidden tool for collecting detector mistakes keeps the photograph, its data and a marked-up picture.
            self.project.selected=0;self.selectCurrent();self.saveBadExample()
            let examples=URL(fileURLWithPath:dir).appendingPathComponent("Bad Examples"),saved=(try? FileManager.default.contentsOfDirectory(at:examples,includingPropertiesForKeys:nil)) ?? []
            precondition(saved.count==1 && Set((try? FileManager.default.contentsOfDirectory(atPath:saved[0].path)) ?? [])==["example.json","overlay.jpg",URL(fileURLWithPath:self.project.pages[0].path).lastPathComponent],"A bad example is one folder of three files")
            precondition(self.badExampleItem?.isHidden==true && self.badExampleItem?.keyEquivalentModifierMask==[.command,.option])
            // Its shortcut works through the menu bar although the item is hidden, also while a text field is being edited.
            func kept()->Int {((try? FileManager.default.contentsOfDirectory(atPath:examples.path)) ?? []).count}
            let shortcut=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command,.option],timestamp:0,windowNumber:self.window.windowNumber,context:nil,characters:"∫",charactersIgnoringModifiers:"b",isARepeat:false,keyCode:11)!
            Thread.sleep(forTimeInterval:1.1)
            precondition(NSApp.mainMenu!.performKeyEquivalent(with:shortcut) && kept()==2,"Option-Command-B saves an example")
            self.window.makeFirstResponder(self.widthField);Thread.sleep(forTimeInterval:1.1)
            precondition(NSApp.mainMenu!.performKeyEquivalent(with:shortcut) && kept()==3,"and does so while a field is edited");self.window.makeFirstResponder(self.canvas)
            print("BAD_EXAMPLE passed")
            // T again steps through the other places the detector offered, and round to the first; a split moved by hand starts afresh.
            let options=[PageSplit(top:0.47,bottom:0.47),PageSplit(top:0.5,bottom:0.5),PageSplit(top:0.56,bottom:0.56)],cycled=self.project.pages[0]
            self.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
            self.project.pages[0].split=options[0];self.splitOptions[cycled.id]=(options,0,cycled.quad,cycled.rotation)
            key("t",17);precondition(self.project.pages[0].split==options[1]);key("t",17);precondition(self.project.pages[0].split==options[2])
            key("t",17);precondition(self.project.pages[0].split==options[0],"After the last candidate comes the first")
            self.project.pages[0].split=nil;self.splitOptions[cycled.id]=nil;self.refreshDetail()
            // Option-t asks for a split on every page without one, and leaves those that have one alone.
            self.project.pages[1].split=PageSplit(top:0.31,bottom:0.31)
            let asked=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.option,timestamp:0,windowNumber:self.window.windowNumber,context:nil,characters:"†",charactersIgnoringModifiers:"t",isARepeat:false,keyCode:17)!
            precondition(self.handleKey(asked) && self.tracker.isRunning(.split),"Option-t starts proposing splits through the book")
            precondition(self.project.pages[1].split==PageSplit(top:0.31,bottom:0.31),"A page that already has a split keeps it")
            self.stop();self.project.pages[1].split=nil;for i in self.project.pages.indices {self.project.pages[i].split=nil};self.refreshDetail()
            print("SPLIT_CANDIDATES passed")
            // V brings over the previous page's image settings and turns the preview on to show them.
            var borrowed=Adjustments();borrowed.cleanup = .grayscale;borrowed.brightness=0.25;borrowed.sharpness=0.4
            self.project.pages[0].adjustments=borrowed;self.project.pages[1].adjustments=nil
            self.project.selected=1;self.selectCurrent();canvas.image=smokeImage;self.original=smokeImage;self.setPreview(false)
            key("v",9);precondition(self.project.pages[1].adjustments==borrowed && canvas.preview,"V copies the adjustments and shows the preview")
            self.undo();precondition(self.project.pages[1].adjustments==nil);self.project.pages[0].adjustments=nil;self.setPreview(false)
            print("COPY_ADJUSTMENTS passed")
            // A preset keeps a page's image settings under a name and gives them to the selected pages in one change.
            do {
                let kept=self.presets,first=self.project.pages[0],second=self.project.pages[1]
                self.project.selected=0;self.selectCurrent();self.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
                var wanted=Adjustments();wanted.cleanup = .grayscale;wanted.brightness=0.2;wanted.sharpness=0.4
                self.edit{$0.adjustments=wanted;$0.format=PageFormat(fitInto:.a5)}
                precondition(self.savePreset(named:" Smoke text ",includeFormat:false) && self.presets.last?.name=="Smoke text" && self.presets.last?.format==nil)
                precondition(self.presetPopup.menu!.items.contains{$0.title=="Smoke text" && $0.toolTip?.contains("Grayscale")==true} && self.presetPopup.menu!.items.contains{$0.title=="Delete Preset"})
                self.table.selectRowIndexes(IndexSet([0,1]),byExtendingSelection:false);self.edit([0,1],geometry:false){$0.adjustments=nil;$0.format=nil}
                self.applyPreset(named:"Smoke text")
                precondition(self.project.pages[0].adjustments==wanted && self.project.pages[1].adjustments==wanted && self.project.pages[1].format==nil && self.canvas.preview,"Both selected pages take the preset; their format is left alone")
                self.undo();precondition(self.project.pages[1].adjustments==nil,"One Undo takes the preset off both")
                // Tools lists the presets, and the one applied most often is first in line for ⌘1.
                self.savePreset(named:"Smoke other",includeFormat:false)
                func shortcut(_ name:String)->String? {self.toolsPresetMenu.items.first{$0.title==name}?.keyEquivalent}
                precondition(self.toolsPresetMenu.items.map{$0.title}.suffix(2)==["Smoke text","Smoke other"] && self.toolsPresetMenu.supermenu?.title=="Tools")
                self.applyPreset(named:"Smoke other");self.applyPreset(named:"Smoke other");self.undo();self.undo()
                precondition(self.presetUses["Smoke other"]==2 && self.presetUses["Smoke text"]==1 && PresetStore.mostUsed(self.presets.filter{$0.name.hasPrefix("Smoke")},uses:self.presetUses)==["Smoke other","Smoke text"])
                if self.presets.count==2 {precondition(shortcut("Smoke other")=="1" && shortcut("Smoke text")=="2","\(String(describing:shortcut("Smoke other")))")}
                snapshot(self.window.contentView!,"preset.png")
                self.keepPresets(kept);precondition(!self.presets.contains{$0.name=="Smoke text"})
                self.undo();self.undo();self.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
                precondition(self.project.pages[0].adjustments==first.adjustments && self.project.pages[1].adjustments==second.adjustments)
                print("PRESETS passed")
            }
            // The sidebar's two layouts: compact rows, and large pictures with only the number, name and type beneath.
            self.project.selected=1;self.selectCurrent()
            let compactCell=self.table.view(atColumn:0,row:1,makeIfNecessary:true) as! PageCell
            precondition(!compactCell.large && !compactCell.subtitle.isHidden && self.table.rowHeight==58)
            self.toggleSidebarLayout()
            let largeCell=self.table.view(atColumn:0,row:1,makeIfNecessary:true) as! PageCell;largeCell.layoutSubtreeIfNeeded()
            precondition(largeCell.large && largeCell.subtitle.isHidden && self.table.rowHeight>150 && largeCell.thumb.frame.width>largeCell.bounds.width*0.8,"The large layout gives the picture the row's width")
            precondition(largeCell.title.frame.maxY<largeCell.thumb.frame.minY+1 || largeCell.title.frame.minY>largeCell.thumb.frame.maxY-1,"with the name outside the picture")
            precondition(self.table.selectedRow==1 && self.project.selected==1 && self.sidebarLayoutMenuItem?.state == .on,"The page on screen stays selected")
            snapshot(view.superview ?? view,"sidebar-large.png")
            self.toggleSidebarLayout();precondition(!ThumbnailPolicy.large && self.table.rowHeight==58)
            print("SIDEBAR_LAYOUT passed")
            // Turning the page turns the photograph on screen too, so the crop is adjusted the way round it comes out.
            self.project.selected=0;self.selectCurrent();canvas.image=smokeImage;self.original=smokeImage;self.setPreview(false)
            let level=canvas.imageRect,turnedBefore=self.project.pages[0].rotation
            key("r",15)
            precondition(!canvas.preview && self.project.pages[0].rotation==(turnedBefore+1)%4 && canvas.turn.quarterTurns==(turnedBefore+1)%4,"The view stays on the photograph, turned")
            precondition((canvas.imageRect.width>canvas.imageRect.height) != (level.width>level.height),"A quarter turn stands the picture on its side")
            // The crop's corners are where they are seen: the handle drawn top-left is the one key 1 selects.
            let handles=self.project.pages[0].quad.points.map(canvas.position)
            key("1",18);let chosen=canvas.selectedCorner!
            precondition(handles.indices.allSatisfy{handles[chosen].x+handles[chosen].y<=handles[$0].x+handles[$0].y+0.5},"1 takes the corner seen top-left")
            snapshot(self.window.contentView!,"turned.png")
            key("\u{1b}",53)
            // h still pushes out the side seen on the left.
            let leftBefore=self.project.pages[0].quad.points.map(canvas.position).map{$0.x}.min()!
            key("h",4,.shift);let leftAfter=self.project.pages[0].quad.points.map(canvas.position).map{$0.x}.min()!
            precondition(leftAfter>leftBefore,"Shift-H pulls in the side seen on the left");self.undo()
            self.setPreview(true);snapshot(self.window.contentView!,"turned-preview.png");self.setPreview(false)
            key("r",15,.shift);precondition(self.project.pages[0].rotation==turnedBefore)
            // With several pages selected, one turn turns them all and one Undo turns them all back.
            let turns=self.project.pages.prefix(3).map{$0.rotation}
            self.project.selected=0;self.selectCurrent();self.table.selectRowIndexes(IndexSet([0,1,2]),byExtendingSelection:false)
            key("r",15);precondition(Array(self.project.pages.prefix(3).map{$0.rotation})==turns.map{($0+1)%4} && self.project.pages[3].rotation==0,"r turns every selected page, and no other")
            self.undo();precondition(Array(self.project.pages.prefix(3).map{$0.rotation})==turns,"One Undo turns them all back")
            self.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
            // A rotation is copied from one page and pasted to others, apart from the other settings.
            self.project.pages[0].rotation=2;self.project.selected=0;self.selectCurrent();self.copyRotation()
            self.table.selectRowIndexes(IndexSet([1,2]),byExtendingSelection:false);self.project.selected=1
            let formats=self.project.pages[1].format,settings=self.project.pages[1].adjustments
            self.pasteRotation()
            precondition(self.project.pages[1].rotation==2 && self.project.pages[2].rotation==2 && self.project.pages[1].format==formats && self.project.pages[1].adjustments==settings,"Paste Rotation changes the rotation and nothing else")
            self.undo();precondition(self.project.pages[1].rotation==0 && self.project.pages[2].rotation==0)
            self.project.pages[0].rotation=0;self.project.selected=0;self.selectCurrent();self.refreshDetail()
            print("TURNED_VIEW passed")
            // On a split spread the deskew turns can act on one page; the choice shows only when there is a split.
            self.project.selected=0;self.selectCurrent();self.edit{$0.split=nil;$0.deskew=nil}
            precondition(self.deskewHalfRow?.isHidden==true && self.deskewPart==nil,"No choice of half without a split")
            self.edit{$0.split=PageSplit(top:0.5,bottom:0.5)};precondition(self.deskewHalfRow?.isHidden==false)
            self.turnDeskew(0.1);precondition(self.project.pages[0].deskew==[0.1,0.1],"Both pages by default")
            key("/",44,.option);precondition(self.deskewHalf.selectedSegment==1 && self.deskewPart==0,"Option-/ steps to the left page")
            self.turnDeskew(0.1);precondition(self.project.pages[0].deskew==[0.2,0.1])
            key("/",44,.option);self.turnDeskew(-0.3);precondition(self.project.pages[0].deskew==[0.2,-0.2],"then the right")
            self.removeDeskew();precondition(self.project.pages[0].deskew==[0.2,0],"Reset levels only the chosen page")
            key("/",44,.option);precondition(self.deskewPart==nil);self.removeDeskew();precondition(self.project.pages[0].deskew==nil)
            for _ in 0..<7 {self.undo()};self.setPreview(false)
            print("DESKEW_HALF passed")
            // A key given to another command in Settings takes effect at once, in the keys, the menus and the lists.
            do {
                precondition(self.keyBindings==KeyBindings(),"The smoke run starts from the default keys")
                func menuKey(_ action:Selector)->String? {
                    func find(_ menu:NSMenu)->NSMenuItem? {for item in menu.items {if item.action==action && item.target === self {return item};if let sub=item.submenu,let found=find(sub) {return found}};return nil}
                    return find(NSApp.mainMenu!)?.keyEquivalent
                }
                self.showSettings();let pane=self.settings!.keys
                self.settings!.tabs.selectTabViewItem(at:1);snapshot(self.settings!.window.contentView!,"shortcut-settings.png")
                let was=canvas.preview
                precondition(pane.assign(KeyStroke(key:"9"),to:"preview"){_,_ in preconditionFailure("9 is free")} && self.keyBindings.stroke(for:"preview")==KeyStroke(key:"9") && menuKey(#selector(AppDelegate.togglePreview))=="9")
                key("9",25);precondition(canvas.preview != was,"9 now toggles the preview")
                let freed=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:self.window.windowNumber,context:nil,characters:"p",charactersIgnoringModifiers:"p",isARepeat:false,keyCode:35)!
                precondition(!self.handleKey(freed) && canvas.preview != was,"and p no longer does anything")
                key("9",25);precondition(canvas.preview==was)
                // A key in use is exchanged, once the user agrees.
                precondition(!pane.assign(KeyStroke(key:"c"),to:"preview"){other,_ in other.id=="copyCrop" ? false:true} && self.keyBindings.stroke(for:"preview")==KeyStroke(key:"9"),"Declined, nothing changes")
                precondition(pane.assign(KeyStroke(key:"c"),to:"preview"){_,_ in true} && self.keyBindings.stroke(for:"copyCrop")==KeyStroke(key:"9") && self.shortcutKeyLabels[1].0.stringValue=="9","The inspector's list follows")
                precondition(!pane.assign(KeyStroke(key:"h"),to:"preview"){_,_ in true} && pane.note.stringValue.contains("h, j, k and l"),"A reserved key is refused with the reason")
                pane.resetAll();precondition(self.keyBindings==KeyBindings() && menuKey(#selector(AppDelegate.togglePreview))=="p" && self.shortcutKeyLabels[1].0.stringValue=="c")
                key("p",35);precondition(canvas.preview != was);key("p",35)
                self.settings!.tabs.selectTabViewItem(at:0);self.settings!.window.close()
                print("KEY_BINDINGS passed")
            }
            // A measurement that finishes late does not undo what the user did while it ran (review R01, R02, R14).
            do {
                func settle(){let end=Date()+30;while self.splitQueue.operationCount>0 && Date()<end {RunLoop.current.run(until:Date()+0.05)};RunLoop.current.run(until:Date()+0.4)}
                self.project.selected=0;self.selectCurrent();self.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
                let kept=self.project.pages[0]
                self.edit{$0.split=PageSplit(top:0.5,bottom:0.5);$0.splitByHand=nil;$0.deskew=nil}
                self.proposeSplits([0],record:true);self.moveSplit(0.01)
                let mine=self.project.pages[0].split;precondition(mine != PageSplit(top:0.5,bottom:0.5) && self.project.pages[0].splitByHand==true)
                settle();precondition(self.project.pages[0].split==mine && self.project.pages[0].splitByHand==true,"The line the user moved stays where it was put: \(String(describing:self.project.pages[0].split))")
                precondition(self.status.stringValue.contains("nothing was applied"),self.status.stringValue)
                self.edit{$0.deskew=[0.3,0.3]};self.deskew();self.turnDeskew(0.1)
                settle();precondition(self.project.pages[0].deskew==[0.4,0.4],"A turn by hand is not replaced by a measurement begun before it: \(String(describing:self.project.pages[0].deskew))")
                self.removeSplit();precondition(self.project.pages[0].deskew==nil,"Two pages' tilts do not outlive the split")
                // A slider change waiting to be recorded is recorded when the selection moves (R09).
                self.project.pages[0]=kept;self.unsaved=false;self.loadCurrent()
                var brighter=self.project.pages[0].adjustments ?? Adjustments();brighter.brightness=0.15;self.setAdjustments(brighter);precondition(self.adjusting && !self.unsaved)
                self.table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
                precondition(!self.adjusting && self.unsaved,"Moving to another page records the change")
                self.undo();precondition(self.project.pages[0].adjustments==kept.adjustments,"and one Undo takes it back")
                self.project.pages[0]=kept;self.undoStack.removeAll();self.redoStack.removeAll();self.setPreview(false)
                self.project.selected=0;self.selectCurrent();self.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
                print("LATE_RESULTS passed")
            }
            // A drag inside the crop moves the crop; with the space bar down it moves the picture instead.
            do {
                self.project.selected=0;self.selectCurrent();self.setPreview(false);canvas.fit()
                let kept=self.project.pages[0]
                let inner=Quad([Point(0.3,0.3),Point(0.7,0.3),Point(0.7,0.7),Point(0.3,0.7)]);self.edit{$0.setManualCrop(inner)}
                let centre=canvas.position(Point(0.5,0.5)),away=CGPoint(x:centre.x+20,y:centre.y+10),pan=canvas.pan
                precondition(canvas.cropContains(centre) && !canvas.cropContains(canvas.position(Point(0.1,0.1))))
                canvas.mouseDown(with:mouse(.leftMouseDown,centre));precondition(canvas.isMovingCrop);canvas.mouseDragged(with:mouse(.leftMouseDragged,away));canvas.mouseUp(with:mouse(.leftMouseUp,away))
                let moved=self.project.pages[0].quad
                precondition(moved != inner && canvas.pan==pan && abs((moved.points[1].x-moved.points[0].x)-0.4)<1e-9 && !canvas.isMovingCrop,"The crop moved whole and the picture stayed")
                canvas.spaceHeld=true;canvas.mouseDown(with:mouse(.leftMouseDown,centre));canvas.mouseDragged(with:mouse(.leftMouseDragged,away));canvas.mouseUp(with:mouse(.leftMouseUp,away));canvas.spaceHeld=false
                precondition(self.project.pages[0].quad==moved && canvas.pan != pan,"With the space bar the picture moves and the crop stays")
                let outside=canvas.position(Point(0.1,0.1));let before=canvas.pan
                canvas.mouseDown(with:mouse(.leftMouseDown,outside));canvas.mouseDragged(with:mouse(.leftMouseDragged,CGPoint(x:outside.x+15,y:outside.y)));canvas.mouseUp(with:mouse(.leftMouseUp,CGPoint(x:outside.x+15,y:outside.y)))
                precondition(self.project.pages[0].quad==moved && canvas.pan != before,"Outside the crop a drag still moves the picture")
                self.project.pages[0]=kept;self.undoStack.removeAll();self.redoStack.removeAll();self.loadCurrent();canvas.fit()
                print("DRAG_CROP passed")
            }
            // A page with a smudge and a cloned area shows them in every mode, in the preview and in the sidebar.
            do {
                func settle(_ done:()->Bool){let end=Date()+30;while !done() && Date()<end {RunLoop.current.run(until:Date()+0.05)};RunLoop.current.run(until:Date()+0.3)}
                self.project.selected=0;self.selectCurrent();self.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);self.setPreview(false)
                let kept=self.project.pages[0]
                self.edit{$0.adjustments=nil;$0.smudges=nil;$0.clones=nil}
                key("c",8,.shift);canvas.onCloneCommit?([Point(0.3,0.6),Point(0.6,0.6)],Point(0,0.15))
                key("b",11,.shift);canvas.onSmudgeCommit?([Point(0.3,0.3),Point(0.6,0.3)])
                settle{canvas.image != nil && canvas.image !== self.original};precondition(canvas.image !== self.original && !canvas.preview,"The photograph is shown retouched")
                for (segment,mode) in Cleanup.allCases.enumerated().reversed() {
                    canvas.showOutput(self.original!);let stand=canvas.image
                    self.cleanupControl.selectedSegment=segment;self.adjustmentChanged(self.cleanupControl)
                    precondition(canvas.preview && !canvas.smudgeMode && !canvas.cloneMode,"Choosing a mode shows the preview")
                    settle{canvas.image !== stand}
                    precondition(canvas.image !== stand && canvas.outputShown && self.window.attachedSheet==nil,"The preview arrives in \(mode.title)")
                    precondition((self.project.pages[0].adjustments?.cleanup ?? Cleanup.none)==mode && self.project.pages[0].smudges?.count==1 && self.project.pages[0].clones?.count==1,"The retouching stays through \(mode.title)")
                    snapshot(self.window.contentView!,"retouch-\(mode.rawValue).png")
                }
                self.commitAdjustments();self.project.pages[0]=kept;self.undoStack.removeAll();self.redoStack.removeAll();self.setPreview(false);self.loadCurrent()
                print("RETOUCH_MODES passed")
            }
            // Pages are reordered by moving their rows; the page on screen stays on screen and Undo puts them back.
            let order=self.project.pages.map{$0.id}
            self.project.selected=0;self.selectCurrent();self.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
            precondition(self.movePages(IndexSet([0]),to:3) && self.project.pages.map{$0.id}==[order[1],order[2],order[0]]+order[3...] && self.project.selected==2 && self.table.selectedRow==2,"The first page dropped before the fourth becomes the third")
            self.movePagesUp();precondition(self.project.pages[1].id==order[0] && self.project.selected==1)
            self.undo();self.undo();precondition(self.project.pages.map{$0.id}==order,"Two Undos restore the order")
            precondition(!self.movePages(IndexSet([2]),to:2),"Dropping a page where it is changes nothing")
            print("REORDER passed")
            // A project file is written by Save, not by each edit.
            if self.hasProjectFile {
                func onDisk()->Project? {try? Project.read(self.projectURL)}
                self.saveProject();precondition(!self.unsaved && !self.window.isDocumentEdited)
                self.edit{$0.flagged = $0.flagged==true ? nil:true}
                precondition(self.unsaved && self.window.isDocumentEdited && onDisk()?.pages[self.project.selected].flagged != self.project.pages[self.project.selected].flagged,"An edit waits for Save")
                self.saveProject()
                precondition(!self.unsaved && !self.window.isDocumentEdited && onDisk()?.pages[self.project.selected].flagged==self.project.pages[self.project.selected].flagged,"Save updates the current file")
                // Unsaved changes to a named project are also kept aside, until they are saved or let go.
                let copy=RecoverySnapshot.url(self.sessionID,in:self.supportURL)
                precondition(!FileManager.default.fileExists(atPath:copy.path),"Nothing is kept aside for a saved project")
                self.edit{$0.flagged = $0.flagged==true ? nil:true};self.writeRecoveryCopy()
                let kept=try? RecoverySnapshot.read(copy)
                precondition(kept?.originalPath==self.projectURL.path && kept?.project.pages[self.project.selected].flagged==self.project.pages[self.project.selected].flagged && onDisk()?.pages[self.project.selected].flagged != self.project.pages[self.project.selected].flagged,"The copy holds what the file does not yet")
                // Another session finds it, and opening it leaves the project file as it was until Save.
                let own=self.sessionID,before=try? Data(contentsOf:self.projectURL);self.sessionID=UUID()
                let found=self.recoveryEntries().first{$0.snapshot==own}
                precondition(found?.reason == .unsavedChanges && found?.pageCount==self.project.pages.count,"\(String(describing:found))")
                self.unsaved=false;self.recover(found!,saveAs:false)
                precondition(self.sessionID==own && self.unsaved && self.window.isDocumentEdited && (try? Data(contentsOf:self.projectURL))==before && FileManager.default.fileExists(atPath:copy.path))
                self.showRecovery();precondition(self.recovery!.rows.allSatisfy{$0.snapshot != own},"The open session is not offered to itself");snapshot(self.recovery!.window.contentView!,"recovery.png");self.recovery!.window.close()
                self.saveProject();precondition(!self.unsaved && !FileManager.default.fileExists(atPath:copy.path),"Saving makes the copy unnecessary")
                print("RECOVERY passed")
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
                        // A photograph whose file was cut short is named at import, marked, and kept out of any export.
                        if let short=self.project.pages.first(where:{$0.path.hasSuffix("cut-short.jpg")}) {
                            precondition(self.incompleteNames==["zz-cut-short.jpg"] && short.status==AppDelegate.detectionError && self.status.stringValue.contains("incomplete"),"\(self.incompleteNames) \(short.status) \(self.status.stringValue)")
                            var options=ExportOptions();options.format = .png
                            precondition((try? Exporter.render(short,options:options)) == nil,"An incomplete photograph is not exported")
                            print("INCOMPLETE_IMPORT passed")
                        }
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
        if CommandLine.arguments.contains("--large-sidebar"),let dir=testDirectory {
            // A picture of the large sidebar layout once its pictures have loaded, to look at.
            DispatchQueue.main.asyncAfter(deadline:.now()+2){
                self.setSidebarLarge(true)
                DispatchQueue.main.asyncAfter(deadline:.now()+5){
                    let whole=self.window.contentView!,rep=whole.bitmapImageRepForCachingDisplay(in:whole.bounds)!;whole.cacheDisplay(in:whole.bounds,to:rep)
                    try? rep.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:dir).appendingPathComponent("sidebar-large.png"))
                    self.setSidebarLarge(false);self.unsaved=false;exit(0)
                }
            }
            return
        }
        if CommandLine.arguments.contains("--thumbs") {
            // Sidebar pictures through the things that used to lose them: removing pages, the preview with
            // black-and-white cleanup, a photograph that is missing, a picture or a request that goes astray.
            setvbuf(stdout,nil,_IONBF,0)
            func cell(_ row:Int)->PageCell? {self.table.view(atColumn:0,row:row,makeIfNecessary:true) as? PageCell}
            func blank()->[Int] {(0..<min(8,self.project.pages.count)).filter{cell($0)?.thumb.image==nil}}
            /// The share of a picture's pixels that are darker than light gray: near zero for a blank white one.
            func ink(_ image:NSImage?)->Double {
                guard let cg=image?.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return -1}
                let w=cg.width,h=cg.height;var gray=[UInt8](repeating:0,count:w*h)
                gray.withUnsafeMutableBytes{b in CGContext(data:b.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0)?.draw(cg,in:CGRect(x:0,y:0,width:w,height:h))}
                return Double(gray.filter{$0<200}.count)/Double(max(1,w*h))
            }
            func after(_ seconds:Double,_ work:@escaping()->Void){DispatchQueue.main.asyncAfter(deadline:.now()+seconds,execute:work)}
            after(CommandLine.arguments.contains("--early") ? 0.15:4){
                print("THUMBS rows without a picture before removal: \(blank())")
                self.table.selectRowIndexes(IndexSet([1,2,3]),byExtendingSelection:false);self.project.selected=1;self.removePages()
                after(4){
                    precondition(blank().isEmpty,"Every row has its picture again after pages are removed");print("THUMBS after removal: all rows have pictures")
                    // Preview with black-and-white cleanup: the picture must still show the page, not a white blank.
                    var bw=Adjustments();bw.cleanup = .blackAndWhite
                    for i in 0..<min(8,self.project.pages.count) {self.project.pages[i].adjustments=bw}
                    self.project.selected=0;self.selectCurrent();self.setPreview(true)
                    after(6){
                        let shares=(0..<4).map{ink(cell($0)?.thumb.image)}
                        print("THUMBS preview with black and white, dark share of rows 0-3: \(shares.map{String(format:"%.3f",$0)})")
                        precondition(shares.allSatisfy{$0>0.02},"A black-and-white preview picture still shows the page")
                        // Image settings changed on every page at once, twice in quick succession, with the selection
                        // moving on before either change is recorded: every picture must end up showing the latest settings.
                        let all=IndexSet(integersIn:0..<self.project.pages.count)
                        var gray=Adjustments();gray.cleanup = .grayscale;gray.brightness=0.25
                        self.table.selectRowIndexes(all,byExtendingSelection:false);self.setAdjustments(gray)
                        self.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
                        gray.contrast=0.2
                        self.table.selectRowIndexes(all,byExtendingSelection:false);self.setAdjustments(gray)
                        self.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
                        precondition(self.project.pages.allSatisfy{$0.adjustments==gray})
                        after(12){
                        let rows=self.table.rows(in:self.table.visibleRect)
                        let stale=(rows.location..<NSMaxRange(rows)).filter{row in
                            guard self.project.pages.indices.contains(row),self.thumbs[self.project.pages[row].path] != nil else{return false}
                            let page=self.project.pages[row],made=self.previewThumbs[page.id]
                            return made?.look != PreviewThumbnail.look(page) || cell(row)?.thumb.image !== made?.image
                        }
                        print("THUMBS after settings changed on \(self.project.pages.count) pages: \(rows.length) rows on screen, stale \(stale)")
                        precondition(stale.isEmpty,"Every picture on screen shows the settings its page has now")
                        // A picture that was missed is noticed by the regular check.
                        let missed=self.project.pages[1].id,noticed=self.thumbnailRecoveries
                        self.project.pages[1].adjustments?.brightness = -0.3
                        after(7){
                        precondition(self.previewThumbs[missed]?.look==PreviewThumbnail.look(self.project.pages[1]) && cell(1)?.thumb.image === self.previewThumbs[missed]?.image && self.thumbnailRecoveries>noticed,"A picture left behind is noticed and remade")
                        print("THUMBS a stale picture was noticed and remade")
                        self.setPreview(false)
                        // A picture lost from memory, and a request that never came back, are both put right by the regular check.
                        let lost=self.project.pages[0].path,stuck=self.project.pages[1].path,before=self.thumbnailRecoveries
                        self.thumbs[lost]=nil;cell(0)?.thumb.image=nil
                        self.thumbs[stuck]=nil;cell(1)?.thumb.image=nil;self.thumbnailPending[stuck]=Date(timeIntervalSinceNow:-60)
                        // A photograph that is not there is marked as such, not left blank.
                        self.project.pages[2].path="/nowhere/missing-photograph.jpg";self.table.reloadData(forRowIndexes:IndexSet(integer:2),columnIndexes:IndexSet(integer:0))
                        after(7){
                            precondition(cell(0)?.thumb.image != nil && cell(1)?.thumb.image != nil && self.thumbs[lost] != nil && self.thumbs[stuck] != nil,"The check restores a lost picture and retries a request that went astray")
                            precondition(self.thumbnailRecoveries>before,"and counts that it had to")
                            precondition(cell(2)?.unreadable==true && cell(2)?.thumb.image != nil,"A missing photograph shows a mark")
                            print("THUMBS check restored \(self.thumbnailRecoveries-before) blank rows; the missing photograph is marked");self.unsaved=false;exit(0)
                        }
                        }
                        }
                    }
                }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+2){run()}
    }
}
