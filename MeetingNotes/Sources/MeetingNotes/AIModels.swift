import Foundation
import LocalSupport

struct AvailableAIModel:Identifiable,Equatable {
    var id:String
    var title:String
    static func parse(_ output:String)->[Self] {
        var seen=Set<String>()
        return output.split(separator:"\n").compactMap{line in
            let parts=line.split(separator:"\t",maxSplits:1).map(String.init)
            guard parts.count==2,!parts[0].isEmpty,!parts[1].isEmpty,
                  parts[0].allSatisfy({$0.isASCII && ($0.isLetter || $0.isNumber || "-_.:/".contains($0))}),seen.insert(parts[0]).inserted else{return nil}
            return Self(id:parts[0],title:parts[1])
        }
    }
    static func load(_ settings:AISettings)throws->[Self] {
        guard settings.provider == .gemini,let executable=settings.executable else{throw MeetingError("Choose the Antigravity executable first.")}
        var env=ProcessInfo.processInfo.environment;env["AGY_CLI_DISABLE_AUTO_UPDATE"]="true"
        let output=try LocalProcess.run(executable,arguments:["models"],directory:FileManager.default.temporaryDirectory,timeout:30,environment:env)
        let models=parse(String(decoding:output,as:UTF8.self))
        guard !models.isEmpty else{throw MeetingError("No models were returned. Check Antigravity sign-in, or enter a model ID manually.")}
        return models
    }
}

struct DiscussionModelCatalog {
    struct CodexModel:Decodable {var slug:String;var display_name:String?;var supported_reasoning_levels:[Effort]?;struct Effort:Decodable{var effort:String}}
    static func codex()->[CodexModel] {
        let root=ProcessInfo.processInfo.environment["CODEX_HOME"].map{URL(fileURLWithPath:$0)} ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        struct Cache:Decodable{var models:[CodexModel]}
        guard let data=try? Data(contentsOf:root.appendingPathComponent("models_cache.json")),let cache=try? JSONDecoder().decode(Cache.self,from:data) else{return []}
        return cache.models.filter{!$0.slug.contains("review")}
    }
    static func load(_ settings:AISettings)throws->[AvailableAIModel] {
        switch settings.provider {
        case .gemini:return try AvailableAIModel.load(settings)
        case .codex:return codex().map{AvailableAIModel(id:$0.slug,title:$0.display_name ?? $0.slug)}
        case .claude:return ["fable","opus","sonnet","haiku"].map{AvailableAIModel(id:$0,title:$0.capitalized+" (latest alias)")}
        case .server:return []
        }
    }
    static func efforts(provider:AIProvider,model:String)->[String] {
        switch provider {
        case .server:return [""]
        case .gemini:return ["","low","medium","high"]
        case .codex:return [""] + (codex().first{$0.slug==model}?.supported_reasoning_levels?.map(\.effort).filter{$0 != "ultra"} ?? ["low","medium","high"])
        case .claude:return model.contains("haiku") ? [""]:["","low","medium","high","xhigh","max"]
        }
    }
}
