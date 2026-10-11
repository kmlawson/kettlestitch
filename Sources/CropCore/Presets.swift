import Foundation

/// A named set of image settings, and optionally a page format, that the user keeps to apply again. Presets belong
/// to the app on this Mac, not to a project; applying one copies its values into the pages.
public struct SettingsPreset: Codable, Equatable {
    public var name: String
    public var adjustments: Adjustments
    /// Nil when the preset leaves a page's format as it is.
    public var format: PageFormat?
    public init(name: String, adjustments: Adjustments, format: PageFormat?) {self.name=name;self.adjustments=adjustments;self.format=format}
    public func apply(to page: inout Page) {
        page.adjustments=adjustments.isIdentity ? nil:adjustments
        if let format {page.format=format}
    }
    /// What the preset holds, in a line: the mode, each value that is not neutral, and the format if it has one.
    public var summary: String {
        func signed(_ value: Double) -> String {let n=Int((value*100).rounded());return n>0 ? "+\(n)":n<0 ? "−\(-n)":"0"}
        var parts=[adjustments.cleanup == .none ? "No mode":adjustments.cleanup.title]
        if let exposure=adjustments.exposure,exposure != 0 {parts.append("exposure "+signed(exposure))}
        if adjustments.brightness != 0 {parts.append("brightness "+signed(adjustments.brightness))}
        if adjustments.contrast != 0 {parts.append("contrast "+signed(adjustments.contrast))}
        if let sharpness=adjustments.sharpness,sharpness != 0 {parts.append("sharpness \(Int((sharpness*100).rounded()))")}
        if let despeckle=adjustments.despeckle {parts.append("despeckle \(despeckle)")}
        if let paper=format?.fitInto {parts.append("fits "+paper.title)} else if let width=format?.widthCM {parts.append(String(format:"%g cm wide",width))}
        return parts.joined(separator:", ")
    }
}
public enum PresetStore {
    /// Where the app keeps the list in its preferences.
    public static let key = "settingsPresets"
    static func same(_ a: String, _ b: String) -> Bool {a.compare(b,options:[.caseInsensitive,.diacriticInsensitive]) == .orderedSame}
    public static func isTaken(_ name: String, in list: [SettingsPreset]) -> Bool {
        let wanted=name.trimmingCharacters(in:.whitespacesAndNewlines);return list.contains{same($0.name,wanted)}
    }
    /// The list with `preset` added at the end, or put in place of the one that has its name.
    public static func adding(_ preset: SettingsPreset, to list: [SettingsPreset]) -> [SettingsPreset] {
        var preset=preset;preset.name=preset.name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !preset.name.isEmpty else {return list}
        var list=list
        if let i=list.firstIndex(where:{same($0.name,preset.name)}) {list[i]=preset} else {list.append(preset)}
        return list
    }
    public static func removing(_ name: String, from list: [SettingsPreset]) -> [SettingsPreset] {list.filter{!same($0.name,name)}}
    public static func encode(_ list: [SettingsPreset]) throws -> Data {try JSONEncoder().encode(list)}
    public static func decode(_ data: Data?) -> [SettingsPreset] {data.flatMap{try? JSONDecoder().decode([SettingsPreset].self,from:$0)} ?? []}
}
