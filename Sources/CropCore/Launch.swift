import Foundation

public enum LaunchPolicy {
    /// The project to open at launch. The app starts empty unless one is asked for explicitly:
    /// by `--project`, or by a test folder holding a prepared `Recovery.kettlestitch`.
    public static func projectToOpen(arguments: [String], testDirectory: String?) -> URL? {
        if let flag=arguments.firstIndex(of:"--project"),arguments.count>flag+1 {return URL(fileURLWithPath:arguments[flag+1])}
        return testDirectory.map{URL(fileURLWithPath:$0).appendingPathComponent("Recovery.kettlestitch")}
    }
    /// A new name per session, so work that was never given a name is not overwritten by the next launch.
    /// `unique` tells apart two sessions begun in the same second.
    public static func untitledName(_ date: Date, unique: String? = nil) -> String {
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="yyyy-MM-dd HH.mm.ss"
        return "Untitled "+formatter.string(from:date)+(unique.map{" "+$0} ?? "")+".kettlestitch"
    }
    /// A session file that was never given a name: one with such a name in the app's own folder. A project the
    /// user saved elsewhere under a name beginning "Untitled" is a project file like any other.
    public static func isUntitled(_ url: URL, in support: URL) -> Bool {
        isUntitled(url) && url.deletingLastPathComponent().standardizedFileURL.path == support.standardizedFileURL.path
    }
    /// A session file that was never given a name. It is a recovery copy, not a project file the user saves to.
    public static func isUntitled(_ url: URL) -> Bool {url.deletingPathExtension().lastPathComponent.hasPrefix("Untitled ")}
    public static let autosaveInterval: TimeInterval = 300
    public static func shouldAutosave(enabled: Bool, hasProjectFile: Bool, unsaved: Bool) -> Bool {enabled && hasProjectFile && unsaved}
    /// What to do about the project when the app is about to quit or its window to close.
    public enum QuitAction: Equatable {
        /// Nothing is at stake.
        case nothing
        /// A project file has changes and auto-save is on: write them without asking.
        case saveQuietly
        /// A project file has changes and auto-save is off: ask whether to save them.
        case askToSave
        /// The work was never given a file: ask where to save it.
        case askToName
    }
    public static func onQuit(hasProjectFile: Bool, unsaved: Bool, untitledChanged: Bool, pageCount: Int, autosave: Bool) -> QuitAction {
        if hasProjectFile {return unsaved ? (autosave ? .saveQuietly:.askToSave):.nothing}
        return untitledChanged && pageCount>0 ? .askToName:.nothing
    }
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
    /// Where a missing photograph might be inside `folder`: inside up to three of the folders that used to enclose
    /// it, so a parent of several moved folders can be chosen at once, and last under its own name alone. The
    /// fullest match comes first, since a bare name is the likeliest to belong to some other photograph.
    public static func candidates(for path: String, in folder: URL) -> [URL] {
        let parts=URL(fileURLWithPath:path).pathComponents.filter{$0 != "/"}
        guard !parts.isEmpty else {return []}
        return (1...min(4,parts.count)).reversed().map{count in parts.suffix(count).reduce(folder){$0.appendingPathComponent($1)}}
    }
    /// For each missing page, the photograph in `folder` it would be pointed at, and whether that can be trusted:
    /// not when pages that had different photographs would end up sharing one, or sharing with a page that is not missing.
    static func matches(_ pages: [Page], in folder: URL, exists: (String) -> Bool) -> [(index: Int, path: String, sure: Bool)] {
        let present=Set(pages.map{$0.path}.filter(exists))
        let found=pages.indices.filter{!present.contains(pages[$0].path)}.compactMap{i in candidates(for:pages[i].path,in:folder).first{exists($0.path)}.map{(i,$0.path)}}
        let claims=Dictionary(grouping:found,by:{$0.1}).mapValues{Set($0.map{pages[$0.0].path})}
        return found.map{(index:$0.0,path:$0.1,sure:claims[$0.1]!.count == 1 && !present.contains($0.1))}
    }
    /// Points each missing page at its photograph in `folder` when it is there and is certainly its own. Returns how many were found.
    @discardableResult public static func relink(_ pages: inout [Page], in folder: URL, exists: (String) -> Bool) -> Int {
        let sure=matches(pages,in:folder,exists:exists).filter{$0.sure}
        for match in sure {pages[match.index].path=match.path}
        return sure.count
    }
    /// How many missing pages have a photograph of their name in `folder` that could as well be another page's.
    public static func ambiguous(_ pages: [Page], in folder: URL, exists: (String) -> Bool) -> Int {matches(pages,in:folder,exists:exists).filter{!$0.sure}.count}
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
/// Asks GitHub which release of the app is the latest. This happens only when the user chooses Check for Updates;
/// the request carries no key, no identifier and nothing about the user's work.
public enum UpdateCheck {
    public static let latestRelease = "https://api.github.com/repos/kmlawson/kettlestitch/releases/latest"
    public static let releasesPage = "https://github.com/kmlawson/kettlestitch/releases/latest"
    public struct Release: Equatable {
        public var version: String
        public var page: URL
    }
    public static func request() -> URLRequest {
        var request=URLRequest(url:URL(string:latestRelease)!,timeoutInterval:20)
        request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
        request.setValue(ReviewAPI.userAgent,forHTTPHeaderField:"User-Agent")
        return request
    }
    /// The numbers of a version such as "v0.4.6", or nil if it is not one.
    static func numbers(_ version: String) -> [Int]? {
        let text=version.hasPrefix("v") ? String(version.dropFirst()):version
        let parts=text.split(separator:".",omittingEmptySubsequences:false).map{Int($0)}
        guard !parts.isEmpty,parts.allSatisfy({$0 != nil && $0! >= 0}) else {return nil}
        return parts.map{$0!}
    }
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let new=numbers(candidate),let old=numbers(current) else {return false}
        for i in 0..<max(new.count,old.count) {
            let a=i<new.count ? new[i]:0,b=i<old.count ? old[i]:0
            if a != b {return a>b}
        }
        return false
    }
    /// The latest release named in GitHub's reply. The page to open is the release's own when it is on the
    /// project's part of github.com, and otherwise the project's releases page.
    public static func latest(from data: Data) -> Release? {
        guard let reply=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let tag=reply["tag_name"] as? String,numbers(tag) != nil else {return nil}
        let stated=(reply["html_url"] as? String).flatMap(URL.init(string:))
        let own=stated.flatMap{$0.scheme == "https" && $0.host == "github.com" && $0.path.hasPrefix("/kmlawson/kettlestitch/") ? $0:nil}
        return Release(version:tag.hasPrefix("v") ? String(tag.dropFirst()):tag,page:own ?? URL(string:releasesPage)!)
    }
}
