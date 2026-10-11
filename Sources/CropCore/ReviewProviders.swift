import Foundation

/// A service that can be asked for a second opinion on a crop. Each is reached directly over HTTPS with the
/// user's own key; nothing else needs to be installed.
public enum ReviewProvider: String, CaseIterable, Codable {
    case anthropic, openai, gemini
    /// What the assistant is called in commands and notes: "Send to Claude", "Gemini's fix selected".
    public var name: String {
        switch self {case .anthropic:return "Claude";case .openai:return "OpenAI";case .gemini:return "Gemini"}
    }
    public var company: String {
        switch self {case .anthropic:return "Anthropic";case .openai:return "OpenAI";case .gemini:return "Google"}
    }
    /// How a key from this service usually begins, shown in the empty key field.
    public var keyHint: String {
        switch self {case .anthropic:return "sk-ant-…";case .openai:return "sk-…";case .gemini:return "AIza…"}
    }
}
/// One model of a provider. Prices are US dollars per million tokens at list price, where they are known,
/// and only serve to estimate what a request cost.
public struct ReviewModel: Equatable {
    public let provider: ReviewProvider
    public let id: String
    public let title: String
    public let inputPerMillion: Double?
    public let outputPerMillion: Double?
    public init(_ provider: ReviewProvider, _ id: String, _ title: String, _ input: Double? = nil, _ output: Double? = nil) {
        self.provider=provider;self.id=id;self.title=title;inputPerMillion=input;outputPerMillion=output
    }
    /// The models offered, cheapest first within each provider. Checked against each provider's model list on 2026-10-11.
    public static let all: [ReviewModel] = [
        ReviewModel(.anthropic,"claude-haiku-5-5","Haiku 5.5",0.10,0.50),
        ReviewModel(.anthropic,"claude-sonnet-5-5","Sonnet 5.5",2,10),
        ReviewModel(.anthropic,"claude-opus-5-5","Opus 5.5",4,20),
        ReviewModel(.openai,"gpt-6-luna","GPT-6 Luna",0.10,0.50),
        ReviewModel(.openai,"gpt-6.1-sol","GPT-6.1 Sol",2,10),
        ReviewModel(.openai,"gpt-6-astra","GPT-6 Astra",10,50),
        ReviewModel(.gemini,"gemini-3.5-flash-lite","Gemini 3.5 Flash-Lite"),
        ReviewModel(.gemini,"gemini-3.8-flash","Gemini 3.8 Flash"),
        ReviewModel(.gemini,"gemini-3.1-pro-preview","Gemini 3.1 Pro (preview)"),
    ]
    public static func models(for provider: ReviewProvider) -> [ReviewModel] {all.filter{$0.provider == provider}}
    /// The saved choice if it is still offered, otherwise the provider's first model.
    public static func chosen(_ id: String?, for provider: ReviewProvider) -> ReviewModel {
        let offered=models(for:provider)
        return offered.first{$0.id == id} ?? offered[0]
    }
    /// What the request cost at list price, when the prices are known.
    public func cost(_ usage: ReviewUsage) -> Double? {
        guard let inputPerMillion,let outputPerMillion else {return nil}
        return (Double(usage.inputTokens)*inputPerMillion+Double(usage.outputTokens)*outputPerMillion)/1_000_000
    }
}
/// The text a provider answered with, and what the request used.
public struct ReviewAnswer: Equatable {
    public var text: String
    public var usage: ReviewUsage?
}
/// Builds the request each provider expects and reads its reply. The three differ in shape, not in substance:
/// two JPEG images, a prompt, and a JSON schema the answer must follow.
public enum ReviewAPI {
    /// The connection every request is made over. It keeps nothing on disk (no cache, no cookies), and it refuses
    /// to be redirected, so a request and the key in its header go to the provider's own address or nowhere.
    public static let session=URLSession(configuration:.ephemeral,delegate:NoRedirects(),delegateQueue:nil)
    final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    /// Says what is calling without identifying the user or the Mac.
    public static let userAgent = "KettleStitch (book page cropper)"

    static func json(_ string: String) -> [String:Any] {(try? JSONSerialization.jsonObject(with:Data(string.utf8)) as? [String:Any]) ?? [:]}
    /// Gemini's `responseSchema` is an OpenAPI subset: type names in capitals, no `additionalProperties`.
    static func geminiSchema(_ schema: [String:Any]) -> [String:Any] {
        var result:[String:Any]=[:]
        for (key,value) in schema where key != "additionalProperties" {
            if key == "type",let type=value as? String {result[key]=type.uppercased()}
            else if key == "properties",let properties=value as? [String:Any] {
                result[key]=properties.mapValues{($0 as? [String:Any]).map(geminiSchema) ?? $0}
            } else {result[key]=value}
        }
        return result
    }
    public static func request(model: ReviewModel, apiKey: String, prompt: String, photo: Data, overlay: Data, split: Bool, timeout: TimeInterval = 240) throws -> URLRequest {
        let schema=json(ClaudeReview.schema(split:split))
        let images=[photo,overlay].map{$0.base64EncodedString()}
        var headers=["Content-Type":"application/json","User-Agent":userAgent]
        let url:String,body:[String:Any]
        switch model.provider {
        case .anthropic:
            url="https://api.anthropic.com/v1/messages"
            headers["x-api-key"]=apiKey;headers["anthropic-version"]="2023-06-01"
            let pictures:[[String:Any]]=images.map{["type":"image","source":["type":"base64","media_type":"image/jpeg","data":$0]]}
            var message:[String:Any]=[
                "model":model.id,"max_tokens":16000,
                "messages":[["role":"user","content":pictures+[["type":"text","text":prompt]]]],
                // These models think by default; effort is their one control, and medium suits a careful look at a page.
                "output_config":["effort":"medium","format":["type":"json_schema","schema":schema]],
            ]
            // Sonnet 5.5 and Opus 5.5 can decline a request on a safety classifier's say-so. With this the service
            // retries a declined request on another of its models itself; Haiku 5.5 has no such option.
            if ["claude-sonnet-5-5","claude-opus-5-5"].contains(model.id) {
                message["fallbacks"]="default";headers["anthropic-beta"]="server-side-fallback-2026-07-01"
            }
            body=message
        case .openai:
            url="https://api.openai.com/v1/responses"
            headers["Authorization"]="Bearer "+apiKey
            let pictures:[[String:Any]]=images.map{["type":"input_image","image_url":"data:image/jpeg;base64,"+$0]}
            body=[
                "model":model.id,
                "input":[["role":"user","content":pictures+[["type":"input_text","text":prompt]]]],
                "text":["format":["type":"json_schema","name":"crop_review","schema":schema,"strict":true]],
            ]
        case .gemini:
            url="https://generativelanguage.googleapis.com/v1beta/models/\(model.id):generateContent"
            // In a header, not the address, so the key is not written into logs along the way.
            headers["x-goog-api-key"]=apiKey
            let pictures:[[String:Any]]=images.map{["inlineData":["mimeType":"image/jpeg","data":$0]]}
            body=[
                "contents":[["role":"user","parts":pictures+[["text":prompt]]]],
                "generationConfig":["responseMimeType":"application/json","responseSchema":geminiSchema(schema)],
            ]
        }
        guard let address=URL(string:url) else {throw CropError.message("Cannot reach \(model.provider.name): bad address")}
        var request=URLRequest(url:address,timeoutInterval:timeout)
        request.httpMethod="POST";request.httpBody=try JSONSerialization.data(withJSONObject:body)
        for (name,value) in headers {request.setValue(value,forHTTPHeaderField:name)}
        return request
    }
    /// True for a failure worth trying again after a pause: too many requests, or trouble at the service's end.
    public static func isTemporary(status: Int) -> Bool {status == 429 || status == 408 || status >= 500}
    /// Reads a reply. A refusal, a cut-off answer or an error the service reports is thrown with its own words.
    public static func answer(_ data: Data, status: Int, provider: ReviewProvider) throws -> ReviewAnswer {
        let root=try? JSONSerialization.jsonObject(with:data) as? [String:Any]
        let name=provider.name
        guard (200..<300).contains(status) else {
            let said=((root?["error"] as? [String:Any])?["message"] as? String) ?? String(decoding:data.prefix(300),as:UTF8.self)
            switch status {
            case 401,403:throw CropError.message("\(name) rejected the API key. Check it in Settings.\n\n\(said)")
            case 429:throw CropError.message("\(name) is receiving too many requests, or the account is out of credit.\n\n\(said)")
            default:throw CropError.message("\(name) reported an error (\(status)).\n\n\(said)")
            }
        }
        guard let root else {throw CropError.message("\(name) returned an unreadable reply: "+String(decoding:data.prefix(300),as:UTF8.self))}
        func count(_ source: [String:Any]?, _ keys: String...) -> Int {keys.reduce(0){$0+((source?[$1] as? NSNumber)?.intValue ?? 0)}}
        switch provider {
        case .anthropic:
            if root["type"] as? String == "error" {throw CropError.message("\(name) reported an error: "+(((root["error"] as? [String:Any])?["message"] as? String) ?? "no details"))}
            let stop=root["stop_reason"] as? String
            if stop == "refusal" {throw CropError.message("\(name) declined to look at this page.")}
            if stop == "max_tokens" {throw CropError.message("\(name)'s answer was cut off before it finished.")}
            let blocks=root["content"] as? [[String:Any]] ?? []
            guard let text=blocks.first(where:{$0["type"] as? String == "text"})?["text"] as? String else {throw CropError.message("\(name) returned no answer.")}
            let usage=root["usage"] as? [String:Any]
            return ReviewAnswer(text:text,usage:usage.map{_ in ReviewUsage(inputTokens:count(usage,"input_tokens","cache_creation_input_tokens","cache_read_input_tokens"),outputTokens:count(usage,"output_tokens"))})
        case .openai:
            if root["status"] as? String == "incomplete" {
                throw CropError.message("\(name)'s answer was cut off: "+(((root["incomplete_details"] as? [String:Any])?["reason"] as? String) ?? "no reason given"))
            }
            let parts=(root["output"] as? [[String:Any]] ?? []).filter{$0["type"] as? String == "message"}.flatMap{$0["content"] as? [[String:Any]] ?? []}
            if let refusal=parts.first(where:{$0["type"] as? String == "refusal"}) {throw CropError.message("\(name) declined to look at this page: "+((refusal["refusal"] as? String) ?? ""))}
            guard let text=parts.first(where:{$0["type"] as? String == "output_text"})?["text"] as? String else {throw CropError.message("\(name) returned no answer.")}
            let usage=root["usage"] as? [String:Any]
            return ReviewAnswer(text:text,usage:usage.map{_ in ReviewUsage(inputTokens:count(usage,"input_tokens"),outputTokens:count(usage,"output_tokens"))})
        case .gemini:
            if let blocked=(root["promptFeedback"] as? [String:Any])?["blockReason"] as? String {throw CropError.message("\(name) declined to look at this page (\(blocked)).")}
            let candidate=(root["candidates"] as? [[String:Any]])?.first
            let parts=((candidate?["content"] as? [String:Any])?["parts"] as? [[String:Any]] ?? []).filter{$0["thought"] as? Bool != true}
            let text=parts.compactMap{$0["text"] as? String}.joined()
            guard !text.isEmpty else {throw CropError.message("\(name) returned no answer"+((candidate?["finishReason"] as? String).map{" (\($0))."} ?? "."))}
            let usage=root["usageMetadata"] as? [String:Any]
            return ReviewAnswer(text:text,usage:usage.map{_ in ReviewUsage(inputTokens:count(usage,"promptTokenCount"),outputTokens:count(usage,"candidatesTokenCount","thoughtsTokenCount"))})
        }
    }
}
