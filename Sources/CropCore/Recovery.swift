import Foundation

/// A copy of a named project's unsaved state, kept in the app's support folder so that a crash or a power cut does
/// not lose the changes made since the last Save. It is written a moment after each run of edits and removed when
/// the project is saved or its changes are knowingly discarded. It is never written over the project's own file.
public struct RecoverySnapshot: Codable {
    public var version = 1
    /// Names the session that wrote the copy, and the copy's file.
    public var id: UUID
    /// The project file these changes belong to.
    public var originalPath: String?
    public var written: Date
    public var project: Project
    public init(id: UUID, originalPath: String?, written: Date, project: Project) {
        self.id=id;self.originalPath=originalPath;self.written=written;self.project=project
    }
    public static let folderName = "Recovery", fileExtension = "kettlestitch-recovery"
    public static func folder(in support: URL) -> URL {support.appendingPathComponent(folderName,isDirectory:true)}
    public static func url(_ id: UUID, in support: URL) -> URL {folder(in:support).appendingPathComponent(id.uuidString).appendingPathExtension(fileExtension)}
    /// Writes the copy whole or not at all, replacing this session's earlier one.
    public func write(in support: URL) throws {
        try FileManager.default.createDirectory(at:Self.folder(in:support),withIntermediateDirectories:true)
        try JSONEncoder().encode(self).write(to:Self.url(id,in:support),options:.atomic)
    }
    public static func read(_ url: URL) throws -> RecoverySnapshot {
        var snapshot=try JSONDecoder().decode(RecoverySnapshot.self,from:Data(contentsOf:url))
        guard snapshot.version == 1 else {throw CropError.message("This recovery copy was written by a newer version of KettleStitch")}
        snapshot.project=try snapshot.project.checked()
        return snapshot
    }
    public static func remove(_ id: UUID, in support: URL) {try? FileManager.default.removeItem(at:url(id,in:support))}
}
/// What there is to recover: copies of named projects' unsaved changes, and sessions that were never given a name.
public enum RecoveryList {
    public enum Reason: Equatable {
        /// A named project has changes that never reached its file.
        case unsavedChanges
        /// The project file the changes belong to is no longer there.
        case originalMissing
        /// The session was never saved to a file of its own.
        case neverNamed
        /// The project file has been saved since the copy was written.
        case savedSince
        /// The copy itself cannot be read.
        case damaged
        public var explanation: String {
            switch self {
            case .unsavedChanges:return "Changes that were not saved to the project"
            case .originalMissing:return "The project file is no longer there"
            case .neverNamed:return "Never saved to a project file"
            case .savedSince:return "Older than the saved project"
            case .damaged:return "Damaged: it cannot be opened"
            }
        }
        /// True for work that exists nowhere else, which is worth raising when the app opens.
        public var needsAttention: Bool {self == .unsavedChanges || self == .originalMissing || self == .damaged}
    }
    public struct Entry: Equatable {
        /// The copy's own file.
        public var file: URL
        public var name: String
        public var pageCount: Int
        /// How many of its photographs are not where it expects them.
        public var missing: Int
        public var written: Date
        public var originalPath: String?
        public var reason: Reason
        /// The copy's session, or nil for an untitled session's file.
        public var snapshot: UUID?
    }
    /// Copies and untitled sessions that are there but cannot be read. They are listed, not passed over in silence:
    /// the user should know that something was kept and lost, and be able to remove it.
    public static func damaged(in support: URL, exceptFile: URL? = nil, modified: (String) -> Date?) -> [Entry] {
        var found:[Entry]=[]
        for file in (try? FileManager.default.contentsOfDirectory(at:RecoverySnapshot.folder(in:support),includingPropertiesForKeys:nil)) ?? [] where file.pathExtension == RecoverySnapshot.fileExtension {
            guard (try? RecoverySnapshot.read(file)) == nil else {continue}
            // What can still be made out of it says whose it was.
            let loose=(try? Data(contentsOf:file)).flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}
            let original=loose?["originalPath"] as? String
            found.append(Entry(file:file,name:original.map{URL(fileURLWithPath:$0).deletingPathExtension().lastPathComponent} ?? "Recovery copy",pageCount:0,missing:0,written:modified(file.path) ?? .distantPast,originalPath:original,reason:.damaged,snapshot:nil))
        }
        for file in (try? FileManager.default.contentsOfDirectory(at:support,includingPropertiesForKeys:nil)) ?? [] where LaunchPolicy.isUntitled(file) && ImportPolicy.isProject(file) {
            guard file.standardizedFileURL != exceptFile?.standardizedFileURL,(try? Project.read(file)) == nil else {continue}
            found.append(Entry(file:file,name:file.deletingPathExtension().lastPathComponent,pageCount:0,missing:0,written:modified(file.path) ?? .distantPast,originalPath:nil,reason:.damaged,snapshot:nil))
        }
        return found.sorted{$0.written != $1.written ? $0.written>$1.written:$0.name<$1.name}
    }
    /// Everything recoverable in the support folder, newest first. `except` and `exceptFile` leave out the session
    /// that is open now. `exists` and `modified` answer for a path; a copy that cannot be read is left out.
    public static func entries(in support: URL, except: UUID? = nil, exceptFile: URL? = nil, exists: (String) -> Bool, modified: (String) -> Date?) -> [Entry] {
        var found:[Entry]=[]
        func missing(_ project: Project) -> Int {project.pages.filter{!exists($0.path)}.count}
        for file in (try? FileManager.default.contentsOfDirectory(at:RecoverySnapshot.folder(in:support),includingPropertiesForKeys:nil)) ?? [] where file.pathExtension == RecoverySnapshot.fileExtension {
            guard let snapshot=try? RecoverySnapshot.read(file),snapshot.id != except else {continue}
            let original=snapshot.originalPath
            let reason:Reason
            if let original,exists(original) {reason=(modified(original) ?? .distantPast)>snapshot.written ? .savedSince:.unsavedChanges} else {reason = .originalMissing}
            let name=original.map{URL(fileURLWithPath:$0).deletingPathExtension().lastPathComponent} ?? "Untitled"
            found.append(Entry(file:file,name:name,pageCount:snapshot.project.pages.count,missing:missing(snapshot.project),written:snapshot.written,originalPath:original,reason:reason,snapshot:snapshot.id))
        }
        for file in (try? FileManager.default.contentsOfDirectory(at:support,includingPropertiesForKeys:nil)) ?? [] where LaunchPolicy.isUntitled(file) && ImportPolicy.isProject(file) {
            guard file.standardizedFileURL != exceptFile?.standardizedFileURL,let project=try? Project.read(file) else {continue}
            found.append(Entry(file:file,name:file.deletingPathExtension().lastPathComponent,pageCount:project.pages.count,missing:missing(project),written:modified(file.path) ?? .distantPast,originalPath:nil,reason:.neverNamed,snapshot:nil))
        }
        return found.sorted{$0.written != $1.written ? $0.written>$1.written:$0.name<$1.name}
    }
}
