import Foundation

public enum LaunchPolicy {
    /// The project to open at launch. The app starts empty unless one is asked for explicitly:
    /// by `--project`, or by a test folder holding a prepared `Recovery.kettlestitch`.
    public static func projectToOpen(arguments: [String], testDirectory: String?) -> URL? {
        if let flag=arguments.firstIndex(of:"--project"),arguments.count>flag+1 {return URL(fileURLWithPath:arguments[flag+1])}
        return testDirectory.map{URL(fileURLWithPath:$0).appendingPathComponent("Recovery.kettlestitch")}
    }
    /// A new name per session, so work that was never given a name is not overwritten by the next launch.
    public static func untitledName(_ date: Date) -> String {
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="yyyy-MM-dd HH.mm.ss"
        return "Untitled "+formatter.string(from:date)+".kettlestitch"
    }
    /// A session file that was never given a name. It is a recovery copy, not a project file the user saves to.
    public static func isUntitled(_ url: URL) -> Bool {url.deletingPathExtension().lastPathComponent.hasPrefix("Untitled ")}
    public static let autosaveInterval: TimeInterval = 300
    public static func shouldAutosave(enabled: Bool, hasProjectFile: Bool, unsaved: Bool) -> Bool {enabled && hasProjectFile && unsaved}
    public static func shouldWrite(pageCount: Int, fileExists: Bool) -> Bool {pageCount>0 || fileExists}
}
public enum ImportPolicy {
    public static let extensions: Set<String> = ["jpg","jpeg","png","tif","tiff","heic","heif","bmp"]
    public static func isPhotograph(_ url: URL) -> Bool {extensions.contains(url.pathExtension.lowercased())}
    /// The extension new projects are saved with.
    public static let projectExtension = "kettlestitch"
    /// Every extension that opens as a project, including those used under the app's earlier names.
    public static let projectExtensions = [projectExtension,"scanseamstress","pagecrop"]
    public static func isProject(_ url: URL) -> Bool {projectExtensions.contains(url.pathExtension.lowercased())}
    public struct Incoming {
        public var project: URL?
        public var photographs: [URL]
    }
    /// Sorts files and folders handed to the app into a project to open and photographs to add.
    /// `contents` lists a folder, or returns nil for anything that is not one; subfolders are not followed.
    public static func sort(_ urls: [URL], existing: Set<String>, contents: (URL) -> [URL]?) -> Incoming {
        var seen=existing,photographs:[URL]=[],project:URL?
        for url in urls {
            if isProject(url) {if project == nil {project=url};continue}
            for candidate in contents(url) ?? [url] where isPhotograph(candidate) && !candidate.lastPathComponent.hasPrefix(".") && !seen.contains(candidate.path) {
                seen.insert(candidate.path);photographs.append(candidate)
            }
        }
        photographs.sort{$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending}
        return Incoming(project:project,photographs:photographs)
    }
}
/// Finds photographs again after they, or the project, were moved. A project stores each photograph's full path.
public enum Relink {
    public static func missing(_ pages: [Page], exists: (String) -> Bool) -> [Int] {pages.indices.filter{!exists(pages[$0].path)}}
    /// Where a missing photograph might be inside `folder`: under its own name, then inside up to three of
    /// the folders that used to enclose it, so a parent of several moved folders can be chosen at once.
    public static func candidates(for path: String, in folder: URL) -> [URL] {
        let parts=URL(fileURLWithPath:path).pathComponents.filter{$0 != "/"}
        guard !parts.isEmpty else {return []}
        return (1...min(4,parts.count)).map{count in parts.suffix(count).reduce(folder){$0.appendingPathComponent($1)}}
    }
    /// Points each missing page at its photograph in `folder` when it is there. Returns how many were found.
    @discardableResult public static func relink(_ pages: inout [Page], in folder: URL, exists: (String) -> Bool) -> Int {
        var found=0
        for i in pages.indices where !exists(pages[i].path) {
            if let match=candidates(for:pages[i].path,in:folder).first(where:{exists($0.path)}) {pages[i].path=match.path;found+=1}
        }
        return found
    }
}
/// The app was called PageCrop, then briefly ScanSeamstress, before KettleStitch. Sessions, preferences and the
/// stored API key saved under an earlier name are carried over once. Each list has the most recent name first.
public enum LegacyNames {
    public static let supportFolders = ["ScanSeamstress","PageCrop"]
    public static let keychainServices = ["local.scanseamstress.app.anthropic","local.pagecrop.app.anthropic"]
    public static let preferencesDomains = ["local.scanseamstress.app","local.pagecrop.app"]
    public static func shouldCarryOver(oldExists: Bool, newExists: Bool) -> Bool {oldExists && !newExists}
    public static func firstExisting(_ names: [String], where exists: (String) -> Bool) -> String? {names.first(where:exists)}
}
