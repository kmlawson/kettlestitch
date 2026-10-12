import Foundation

/// A note of what the app is doing, kept in its support folder while it runs and removed when it quits properly.
/// One found at launch means the last run ended in a crash or was killed, and says what was under way: which
/// project was open, whether an export was half done, and which photographs were being read at that moment.
public struct CrashJournal: Codable, Equatable {
    /// The project file that was open, if it had one.
    public var project: String?
    /// What was being done, in words for the user: "Exporting", "Proposing crops".
    public var activity: String?
    /// The unfinished PDF an export was writing, to be removed.
    public var partialExport: String?
    /// Where the export was going: the PDF, or the folder of images.
    public var exportDestination: String?
    /// The photographs being read when the note was last written.
    public var reading: [String] = []
    public init() {}
    public static let fileName = "session.json"
    static func url(in support: URL) -> URL {support.appendingPathComponent(fileName)}
    /// The journal the last run left behind, or nil if it quit properly. One torn by the crash still counts.
    public static func read(in support: URL) -> CrashJournal? {
        guard let data=try? Data(contentsOf:url(in:support)) else {return nil}
        return (try? JSONDecoder().decode(CrashJournal.self,from:data)) ?? CrashJournal()
    }
    public func write(in support: URL) throws {try JSONEncoder().encode(self).write(to:Self.url(in:support),options:.atomic)}
    public static func clear(in support: URL) {try? FileManager.default.removeItem(at:url(in:support))}
    /// The photographs to set aside: one of them may be what brought the app down, and reading it again at once
    /// would bring it down again.
    public var suspects: [String] {Array(Set(reading)).sorted()}
    /// What to tell the user, a sentence to a line. `recoverable` is how many copies of unsaved work were kept.
    public func account(recoverable: Int) -> [String] {
        var lines:[String]=[]
        func name(_ path: String) -> String {URL(fileURLWithPath:path).lastPathComponent}
        if let project,recoverable>0 {lines.append("Unsaved changes to “\(URL(fileURLWithPath:project).deletingPathExtension().lastPathComponent)” were kept. They are in the Recovery window.")}
        else if recoverable>0 {lines.append("Unsaved work was kept. It is in the Recovery window.")}
        if let destination=exportDestination {
            lines.append(partialExport != nil ? "The export to “\(name(destination))” did not finish. Nothing was left there, and a PDF of that name that was there before is untouched."
                :"The export to the folder “\(name(destination))” did not finish: it holds only some of the pages.")
        } else if let activity {lines.append("It was in the middle of this: \(activity). Pages it had not reached are as they were; ask for it again.")}
        let held=suspects
        if !held.isEmpty {
            let listed=held.prefix(4).map(name).joined(separator:", ")+(held.count>4 ? " and \(held.count-4) more":"")
            lines.append("It was reading \(held.count == 1 ? "this photograph":"these photographs") at the time: \(listed). In case \(held.count == 1 ? "it was":"one of them was") the cause, \(held.count == 1 ? "it has":"they have") been set aside and will not be read until you choose File ▸ Try Set-Aside Photographs Again.")
        }
        return lines
    }
}
extension Imaging {
    private static let watchLock=NSLock()
    private static var heldPaths=Set<String>()
    private static var inFlight:[String:Int]=[:]
    /// Called with the photographs being read, each time one is begun or done. Set once by the app, to keep its journal.
    public static var readingChanged: (([String]) -> Void)?
    /// Sets photographs aside: reading one fails until `release`.
    public static func hold(_ paths: [String]) {watchLock.lock();heldPaths.formUnion(paths);watchLock.unlock()}
    public static func release() {watchLock.lock();heldPaths=[];watchLock.unlock()}
    public static func isHeld(_ path: String) -> Bool {watchLock.lock();defer {watchLock.unlock()};return heldPaths.contains(path)}
    public static var heldCount: Int {watchLock.lock();defer {watchLock.unlock()};return heldPaths.count}
    /// Notes that a photograph is being read, or is done with. The note is passed on while the lock is held, so
    /// that what is written down is never behind what is happening.
    static func noteReading(_ path: String, begun: Bool) {
        watchLock.lock();defer {watchLock.unlock()}
        if begun {inFlight[path,default:0]+=1} else if let count=inFlight[path] {inFlight[path]=count>1 ? count-1:nil}
        readingChanged?(inFlight.keys.sorted())
    }
}
