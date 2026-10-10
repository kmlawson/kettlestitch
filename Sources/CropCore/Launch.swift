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
/// The app was called PageCrop, then briefly ScanSeamstress, before KettleStitch. Sessions, preferences and the
/// stored API key saved under an earlier name are carried over once. Each list has the most recent name first.
public enum LegacyNames {
    public static let supportFolders = ["ScanSeamstress","PageCrop"]
    public static let keychainServices = ["local.scanseamstress.app.anthropic","local.pagecrop.app.anthropic"]
    public static let preferencesDomains = ["local.scanseamstress.app","local.pagecrop.app"]
    public static func shouldCarryOver(oldExists: Bool, newExists: Bool) -> Bool {oldExists && !newExists}
    public static func firstExisting(_ names: [String], where exists: (String) -> Bool) -> String? {names.first(where:exists)}
}
