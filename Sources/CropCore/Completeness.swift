import Foundation

/// Whether a photograph's file holds the whole picture. ImageIO opens a file that was cut short, reports it
/// complete and fills what is missing with gray or black, so the file's own structure is read instead: each format
/// says where it ends, and a file that stops before that is refused.
///
/// With thanks to @anhphong.bsky.social, who pointed out that `CGImageSourceGetStatus` reports a truncated file as
/// complete, so that a half-decoded page can walk straight into an exported PDF.
extension Imaging {
    private static let completenessLock=NSLock()
    private static var completeness:[String:(size: UInt64, modified: Date?, problem: String?)]=[:]
    /// Forgets what has been found about files, for tests that rewrite one in place within the same moment.
    static func forgetCompleteness() {completenessLock.lock();completeness=[:];completenessLock.unlock()}
    /// Why the file cannot be used, when it ends before its picture does; nil for a whole file, and for anything
    /// that is not there or is not a picture this check knows, which the ordinary reading then reports.
    public static func incomplete(_ url: URL) -> String? {
        guard let attributes=try? FileManager.default.attributesOfItem(atPath:url.path),let size=(attributes[.size] as? NSNumber)?.uint64Value else {return nil}
        let modified=attributes[.modificationDate] as? Date
        completenessLock.lock();let known=completeness[url.path];completenessLock.unlock()
        if let known,known.size == size,known.modified == modified {return known.problem}
        var problem:String?
        if let data=try? Data(contentsOf:url,options:.alwaysMapped),endsEarly(data) {
            problem="“\(url.lastPathComponent)” is incomplete: the file ends before the picture does. It was probably cut short while being copied or downloaded; copy it again from where it came."
        }
        completenessLock.lock();if completeness.count>4000 {completeness=[:]};completeness[url.path]=(size,modified,problem);completenessLock.unlock()
        return problem
    }
    /// True only when the file is of a known format and certainly stops short. Anything unrecognised or oddly made is not judged.
    static func endsEarly(_ data: Data) -> Bool {
        data.withUnsafeBytes{(raw: UnsafeRawBufferPointer) -> Bool in
            let bytes=raw.bindMemory(to:UInt8.self),count=bytes.count
            guard count>=12 else {return false}
            func big(_ at: Int, _ length: Int) -> UInt64 {(0..<length).reduce(UInt64(0)){($0<<8)|UInt64(bytes[at+$1])}}
            func tag(_ at: Int) -> String {String(decoding:UnsafeRawBufferPointer(rebasing:raw[at..<at+4]),as:UTF8.self)}
            if bytes[0] == 0xFF,bytes[1] == 0xD8 {
                // JPEG: segments each give their length; after a start of scan the picture's data runs to the next
                // marker. The file is whole when the end-of-image marker of the outermost picture is reached.
                var at=2
                while true {
                    guard at+1<count else {return true}
                    guard bytes[at] == 0xFF else {return false}
                    while at+1<count,bytes[at+1] == 0xFF {at+=1}
                    guard at+1<count else {return true}
                    let marker=bytes[at+1];at+=2
                    if marker == 0xD9 {return false}
                    if marker == 0x01 || (0xD0...0xD7).contains(marker) {continue}
                    guard at+2<=count else {return true}
                    let length=Int(big(at,2));guard length>=2 else {return false}
                    guard at+length<=count else {return true}
                    at+=length
                    if marker == 0xDA {
                        // In picture data a marker's FF is never followed by 00 or a restart number.
                        while true {
                            guard let found=memchr(raw.baseAddress!+at,0xFF,count-at) else {return true}
                            at=raw.baseAddress!.distance(to:UnsafeRawPointer(found))
                            guard at+1<count else {return true}
                            let next=bytes[at+1]
                            if next == 0x00 || (0xD0...0xD7).contains(next) {at+=2;continue}
                            if next == 0xFF {at+=1;continue}
                            break
                        }
                    }
                }
            }
            if big(0,8) == 0x89504E470D0A1A0A {
                // PNG: chunks of stated length, the last of them IEND.
                var at=8
                while true {
                    guard at+12<=count else {return true}
                    let length=Int(big(at,4)),type=tag(at+4);at+=12+length
                    guard at<=count else {return true}
                    if type == "IEND" {return false}
                }
            }
            if tag(4) == "ftyp" {
                // HEIC and its relations: boxes of stated size, one after another, none reaching past the end of the file.
                var at=0
                while at+8<=count {
                    var size=big(at,4)
                    if size == 0 {return false}
                    if size == 1 {guard at+16<=count else {return true};size=big(at+8,8)}
                    guard size>=8 else {return false}
                    guard UInt64(at)+size<=UInt64(count) else {return true}
                    at+=Int(size)
                }
                return at != count
            }
            if bytes[0] == 0x42,bytes[1] == 0x4D {
                // BMP: its header says how long the file is, least significant byte first.
                let stated=(0..<4).reduce(0){$0|(Int(bytes[2+$1])<<(8*$1))}
                return stated>count
            }
            return false
        }
    }
}
