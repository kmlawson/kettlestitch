import AppKit
import CropCore

/// The export options sheet. Its choices are remembered.
final class ExportSheetController: NSObject {
    let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:560,height:420),styleMask:[.titled],backing:.buffered,defer:false)
    let allPages=NSButton(radioButtonWithTitle:"All Pages",target:nil,action:nil)
    let selectedPages=NSButton(radioButtonWithTitle:"Selected Page(s)",target:nil,action:nil)
    let format=NSPopUpButton()
    let language=NSPopUpButton()
    let quality=NSSlider(value:85,minValue:10,maxValue:100,target:nil,action:nil)
    let qualityField=NSTextField()
    let maxDPI=NSPopUpButton()
    let splits=NSPopUpButton()
    /// One menu for the kind of file: a PDF comes plain or with its text recognised, then the image formats.
    static let ocrTitle="PDF with Apple Vision OCR"
    let kinds:[(title:String,format:ExportOptions.Format,searchable:Bool)]=[("PDF",.pdf,false),(ExportSheetController.ocrTitle,.pdf,true)]+ExportOptions.Format.allCases.filter{$0 != .pdf}.map{($0.title,$0,false)}
    let limits:[Double?]=[nil,600,400,300,200,150,100,72]
    let languages=Exporter.textLanguages
    var completion:((ExportOptions?,Bool)->Void)?

    init(options:ExportOptions,selectedCount:Int,totalCount:Int){
        super.init()
        allPages.title="All Pages (\(totalCount))";selectedPages.title="Selected Page\(selectedCount==1 ? "":"s") (\(selectedCount))"
        allPages.state = .on
        format.addItems(withTitles:kinds.map{$0.title})
        format.selectItem(at:kinds.firstIndex{$0.format==options.format && $0.searchable==(options.format == .pdf && options.searchableText)} ?? 0)
        language.addItem(withTitle:"Automatic")
        language.addItems(withTitles:languages.map{Locale.current.localizedString(forIdentifier:$0) ?? $0})
        if let chosen=options.textLanguage,let index=languages.firstIndex(of:chosen) {language.selectItem(at:index+1)}
        quality.doubleValue=(options.jpegQuality*100).rounded();quality.isContinuous=true
        maxDPI.addItems(withTitles:limits.map{$0.map{"\(Int($0)) DPI"} ?? "Off"});maxDPI.selectItem(at:limits.firstIndex(of:options.maxDPI) ?? 0)
        splits.addItems(withTitles:SplitOrder.allCases.map{$0.title});splits.selectItem(at:SplitOrder.allCases.firstIndex(of:options.splitOrder ?? .leftFirst) ?? 0)
        splits.toolTip="Pages with a split are exported as two pages. Choose which comes first, or export them whole."
        qualityField.alignment = .right;qualityField.widthAnchor.constraint(equalToConstant:54).isActive=true
        for control in [allPages,selectedPages,format,language,quality,qualityField,maxDPI] as [NSControl] {control.target=self;control.action=#selector(changed(_:))}

        func label(_ text:String)->NSTextField {let l=NSTextField(labelWithString:text);l.alignment = .right;return l}
        func help(_ text:String)->NSTextField {let l=NSTextField(wrappingLabelWithString:text);l.font = .systemFont(ofSize:11);l.textColor = .secondaryLabelColor;l.preferredMaxLayoutWidth=340;return l}
        func row(_ views:[NSView])->NSStackView {let s=NSStackView(views:views);s.spacing=8;return s}
        let include=NSStackView(views:[allPages,selectedPages]);include.orientation = .vertical;include.alignment = .leading;include.spacing=6
        let divider=NSBox();divider.boxType = .separator
        let empty=NSGridCell.emptyContentView
        let grid=NSGridView(views:[
            [label("Include:"),include],
            [label("Format:"),format],
            [label("Text Language:"),language],
            [label("Split Pages:"),splits],
            [divider],
            [label("JPEG Quality:"),row([quality,qualityField])],
            [label("Maximum DPI:"),maxDPI]])
        grid.rowSpacing=10;grid.columnSpacing=10;grid.column(at:0).xPlacement = .trailing;grid.column(at:1).xPlacement = .leading
        grid.mergeCells(inHorizontalRange:NSRange(location:0,length:2),verticalRange:NSRange(location:4,length:1));grid.cell(for:divider)?.xPlacement = .fill
        grid.row(at:0).yPlacement = .top
        language.toolTip="The language Apple Vision reads the text in, for a PDF with OCR"
        maxDPI.toolTip="Limit the resolution of exported pages for a smaller file"
        for popup in [format,splits,language,maxDPI] {popup.widthAnchor.constraint(equalToConstant:340).isActive=true}
        quality.widthAnchor.constraint(equalToConstant:278).isActive=true

        let cancel=NSButton(title:"Cancel",target:self,action:#selector(cancel(_:)));cancel.keyEquivalent="\u{1b}"
        let export=NSButton(title:"Export…",target:self,action:#selector(export(_:)));export.keyEquivalent="\r"
        let buttons=NSStackView(views:[cancel,NSView(),export])
        let content=NSView()
        for v in [grid,buttons] as [NSView] {v.translatesAutoresizingMaskIntoConstraints=false;content.addSubview(v)}
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo:content.topAnchor,constant:24),grid.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:28),grid.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-28),
            buttons.topAnchor.constraint(equalTo:grid.bottomAnchor,constant:24),buttons.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:20),buttons.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-20),buttons.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-20),
            cancel.widthAnchor.constraint(greaterThanOrEqualToConstant:90),export.widthAnchor.constraint(greaterThanOrEqualToConstant:110)])
        panel.contentView=content;panel.setContentSize(content.fittingSize)
        selectedPages.isEnabled=selectedCount<totalCount || selectedCount>1
        changed(nil)
    }
    var chosen:(title:String,format:ExportOptions.Format,searchable:Bool) {kinds[max(0,format.indexOfSelectedItem)]}
    @objc func changed(_ sender:Any?){
        if (sender as? NSTextField)===qualityField {quality.doubleValue=min(100,max(10,Double(qualityField.stringValue.filter{$0.isNumber}) ?? quality.doubleValue))}
        qualityField.stringValue="\(Int(quality.doubleValue.rounded()))%"
        language.isEnabled=chosen.searchable
        let lossy=chosen.format == .pdf || chosen.format == .jpeg
        quality.isEnabled=lossy;qualityField.isEnabled=lossy
    }
    func begin(on window:NSWindow,completion:@escaping(ExportOptions?,Bool)->Void){self.completion=completion;window.beginSheet(panel)}
    func finish(_ options:ExportOptions?){
        let selectedOnly=selectedPages.state == .on,done=completion;completion=nil
        panel.sheetParent?.endSheet(panel);done?(options,selectedOnly)
    }
    @objc func cancel(_ sender:Any?){finish(nil)}
    @objc func export(_ sender:Any?){
        var options=ExportOptions()
        options.format=chosen.format;options.searchableText=chosen.searchable
        options.textLanguage=language.indexOfSelectedItem>0 ? languages[language.indexOfSelectedItem-1]:nil
        options.splitOrder=SplitOrder.allCases[splits.indexOfSelectedItem]
        options.jpegQuality=quality.doubleValue/100;options.maxDPI=limits[maxDPI.indexOfSelectedItem]
        finish(options)
    }
}
