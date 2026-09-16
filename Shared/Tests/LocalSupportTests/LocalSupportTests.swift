import Foundation
import LocalSupport

// Foundation-only checks work with Command Line Tools; XCTest requires full Xcode here.
@main
enum Checks {
    @MainActor static func main() async throws {
        if CommandLine.arguments.contains("--check-antigravity-live") {
            var settings = try AISettings.load()
            settings.provider = .gemini
            let answer = try await Task.detached {
                try AIClient.ask("Reply exactly: connection ready. Do not use tools.", settings: settings, timeout: 60)
            }.value
            print("Connection-test reply: " + answer.prefix(500))
            guard answer.lowercased().contains("connection ready") else {
                throw LocalAIError("Connection returned an unexpected answer.")
            }
            print("PASS live Antigravity answer through the apps' shared AI client")
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            print("\(ok ? "PASS" : "FAIL")  \(name)")
            if !ok { failures += 1 }
        }
        let old = directory.appendingPathComponent("old.md"), new = directory.appendingPathComponent("new.md")
        try "original note".write(to: old, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        var threw = false
        do { try LocalFiles.replace("edited note", at: new, retiring: old) } catch { threw = true }
        check("failed replacement reports an error", threw)
        check("failed replacement preserves original", try String(contentsOf: old) == "original note")
        try FileManager.default.removeItem(at: new)
        let text = "# Note\nUnicode: λ\n\\frac{x}{y}\n"
        try LocalFiles.replace(text, at: new, retiring: old)
        check("rename preserves exact content", try String(contentsOf: new) == text)
        check("successful rename retires original", !FileManager.default.fileExists(atPath: old.path))
        try LocalFiles.replace("second", at: new, retiring: new)
        check("same filename update", try String(contentsOf: new) == "second")
        let alias = directory.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        try LocalFiles.replace("saved via alias", at: new, retiring: alias.appendingPathComponent("new.md"))
        check("an aliased path cannot retire the file just saved", try String(contentsOf: new) == "saved via alias")
        let name = LocalFiles.safeName("../../private:note.md")
        check("imported filename cannot escape directory", !name.contains("/") &&
              directory.appendingPathComponent(name).deletingLastPathComponent().path == directory.path)
        let config = directory.appendingPathComponent("config.json")
        try Data("{\"dataRoot\":\"/tmp/from-file\",\"claudePath\":\"/missing/tool\"}".utf8).write(to: config)
        withEnvironment(["LOCAL_APPS_CONFIG": config.path, "LOCAL_APPS_DATA_ROOT": nil, "LOCAL_APPS_CLAUDE": nil]) {
            check("JSON data directory", LocalConfig.dataDirectory("Jot").path == "/tmp/from-file/Jot")
            check("invalid executable never silently falls back", LocalConfig.executable("claudePath", environment: "LOCAL_APPS_CLAUDE", name: "sh") == nil)
            withEnvironment(["LOCAL_APPS_DATA_ROOT": "/tmp/override"]) {
                check("environment overrides JSON", LocalConfig.dataDirectory("Jot").path == "/tmp/override/Jot")
            }
        }
        withEnvironment(["LOCAL_APPS_CLAUDE": "relative/tool"]) {
            check("relative executable path is rejected", LocalConfig.executable("claudePath", environment: "LOCAL_APPS_CLAUDE", name: "sh") == nil)
        }
        setenv("LOCAL_APPS_DATA_ROOT", directory.path, 1)
        let fake = directory.appendingPathComponent("fake-claude")
        let captured = directory.appendingPathComponent("request.txt")
        try "#!/bin/sh\ncat > '\(captured.path)'\nprintf 'A careful answer with $x^2$.'\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
        var aiConfig = AISettings(); aiConfig.executablePath = fake.path; aiConfig.claudeModel = "test-alpha"
        let first = AIConversation(app: "Checks", id: "first-paper")
        first.draft = "Does this assumption hold?"
        await first.send(first.draft, source: { "SOURCE ALPHA" }, settings: { aiConfig })
        check("discussion saves question and provider answer", first.messages.count == 2 && first.lastAnswer?.contains("$x^2$") == true)
        aiConfig.claudeModel = "test-beta"
        var sawActiveModel = false
        await first.send("What if the sample is biased?", source: {
            sawActiveModel = first.activeConfiguration?.model == "test-beta"
            aiConfig.claudeModel = "future-choice"
            return "SOURCE ALPHA"
        }, settings: { aiConfig })
        check("in-flight request keeps its model when settings change", sawActiveModel && first.messages.last?.model == "test-beta" && first.activeConfiguration == nil)
        let request = try String(contentsOf: captured)
        check("follow-up includes previous exchange and scoped source", request.contains("Does this assumption hold?") && request.contains("A careful answer") && request.contains("SOURCE ALPHA") && request.contains("sample is biased"))
        let restored = AIConversation(app: "Checks", id: "first-paper")
        check("saved answers preserve the model used for each turn", restored.messages.filter { $0.role == "assistant" }.map { $0.model ?? "" } == ["test-alpha", "test-beta"] && restored.markdown.contains("Claude · test-alpha"))
        let other = AIConversation(app: "Checks", id: "second-paper")
        check("conversations persist and remain separated by paper", restored.messages.count == 4 && other.messages.isEmpty)
        var bad = aiConfig; bad.executablePath = "/missing/ai"
        restored.draft = "Preserve my question"
        await restored.send(restored.draft, source: { "" }, settings: { bad })
        check("provider failure keeps question and existing history", restored.error != nil && restored.draft == "Preserve my question" && restored.messages.count == 4)
        restored.clear()
        check("clear removes saved discussion only", AIConversation(app: "Checks", id: "first-paper").messages.isEmpty)
        let draftChat = AIConversation(app: "Checks", id: "draft-paper")
        draftChat.draft = "My unfinished understanding"
        check("question draft survives reopening", AIConversation(app: "Checks", id: "draft-paper").draft == draftChat.draft)
        await draftChat.send(draftChat.draft, source: {
            draftChat.draft = "A follow-up typed while waiting"
            return "SOURCE ALPHA"
        }, settings: { aiConfig })
        check("answer does not erase a newer question draft", draftChat.draft == "A follow-up typed while waiting" && AIConversation(app: "Checks", id: "draft-paper").draft == draftChat.draft)
        try "#!/bin/sh\ncat >/dev/null\nexit 1\n".write(to: fake, atomically: true, encoding: .utf8)
        let failing = AIConversation(app: "Checks", id: "retry-paper")
        failing.draft = "Please check this interpretation"
        await failing.send(failing.draft, source: { "SOURCE" }, settings: { aiConfig })
        let interrupted = AIConversation(app: "Checks", id: "retry-paper")
        check("failed request retains its submitted question on disk", interrupted.messages.count == 1 && interrupted.draft == failing.draft)
        try "#!/bin/sh\ncat >/dev/null\nprintf 'Recovered answer'\n".write(to: fake, atomically: true, encoding: .utf8)
        await interrupted.send(interrupted.draft, source: { "SOURCE" }, settings: { aiConfig })
        check("retry of a failed request does not duplicate the question", interrupted.messages.count == 2 && interrupted.lastAnswer == "Recovered answer")
        // Force a save failure after the submitted question has been written.
        let unsaved = AIConversation(app: "Checks", id: "unsaved-answer")
        unsaved.draft = "Keep the answer if saving fails"
        let folder = LocalConfig.dataDirectory("Checks").appendingPathComponent("conversations")
        let beforeFiles = Set(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))
        let blocker = directory.appendingPathComponent("block-save")
        try "#!/bin/sh\ncat >/dev/null\nfor f in '\(folder.path)'/*.json; do if [ \"${f##*.}\" = json ] && /usr/bin/grep -q 'Keep the answer if saving fails' \"$f\"; then case \"$f\" in *.draft.json) ;; *) /bin/rm \"$f\"; /bin/mkdir \"$f\" ;; esac; fi; done\nprintf 'An answer worth keeping'\n".write(to: blocker, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocker.path)
        var blockedSettings = aiConfig; blockedSettings.executablePath = blocker.path
        await unsaved.send(unsaved.draft, source: { "SOURCE" }, settings: { blockedSettings })
        check("failed answer save stays visible with retry", unsaved.lastAnswer == "An answer worth keeping" && unsaved.saveError != nil)
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) where !beforeFiles.contains(file) {
            if (try file.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true { try FileManager.default.removeItem(at: file) }
        }
        unsaved.retrySave()
        check("retry save recovers the answer without another AI call", unsaved.saveError == nil && AIConversation(app: "Checks", id: "unsaved-answer").lastAnswer == "An answer worth keeping")
        try "#!/bin/sh\ncat > '\(captured.path)'\nprintf '%s\\n' '{\"event\":\"init\"}' '{\"event\":\"result\",\"result\":{\"status\":\"SUCCESS\",\"response\":\"Gemini answer\"}}'\n".write(to: fake, atomically: true, encoding: .utf8)
        var gemini = AISettings(); gemini.provider = .gemini; gemini.geminiExecutablePath = fake.path
        check("Antigravity final streamed response is parsed", try AIClient.ask("Connection test", settings: gemini, timeout: 5) == "Gemini answer")
        let sent = try JSONSerialization.jsonObject(with: Data(contentsOf: captured)) as? [String: Any]
        check("Antigravity request uses one stdin turn", sent?["event"] as? String == "user" && (sent?["message"] as? [String: Any])?["content"] as? String == "Connection test")
        check("Antigravity keeps permission checks and disables command expansion", gemini.arguments().contains("--sandbox") && gemini.arguments().contains("plan") && gemini.arguments().contains("--disable-slash-commands") && !gemini.arguments().contains("--dangerously-skip-permissions"))
        do { _ = try AIClient.antigravityResponse(Data(#"{"event":"result","result":{"status":"ERROR","response":"partial text"}}"#.utf8)); check("Antigravity failure cannot become a successful answer", false) }
        catch { check("Antigravity failure cannot become a successful answer", true) }
        let completed = #"{"event":"result","result":{"status":"SUCCESS","error":null,"response":"A completed write-up with $x^2$."}}"#
        check("Antigravity accepts explicit null error from current CLI", try AIClient.antigravityResponse(Data(completed.utf8)) == "A completed write-up with $x^2$.")
        for (name, record) in [
            ("real error despite success status", #"{"event":"result","result":{"status":"SUCCESS","error":"failed","response":"partial"}}"#),
            ("missing final result", #"{"event":"step_update","step_update":{"text_delta":"partial"}}"#),
            ("empty completed answer", #"{"event":"result","result":{"status":"SUCCESS","error":null,"response":"  "}}"#),
            ("interrupted response", #"{"event":"result","result":{"status":"INTERRUPTED","error":null,"response":"partial"}}"#),
            ("waiting response", #"{"event":"result","result":{"status":"WAITING","error":null,"response":"partial"}}"#)
        ] {
            do { _ = try AIClient.antigravityResponse(Data(record.utf8)); check("Antigravity rejects " + name, false) }
            catch { check("Antigravity rejects " + name + " without blaming sign-in", !error.localizedDescription.contains("Sign in")) }
        }
        let oldJSON = Data(#"{"provider":"claude","claudeModel":"","codexModel":"","serverModel":"","endpoint":"","executablePath":"","codexExecutablePath":""}"#.utf8)
        let retryCLI=directory.appendingPathComponent("agy"),marker=directory.appendingPathComponent("retried")
        try """
        #!/bin/sh
        cat >/dev/null
        if [ ! -f '\(marker.path)' ]; then
          touch '\(marker.path)'
          printf '%s\\n' '{"event":"result","result":{"status":"ERROR","response":"","error":"UNAVAILABLE code 503: No capacity available"}}'
          exit 1
        fi
        printf '%s\\n' '{"event":"result","result":{"status":"SUCCESS","response":"Recovered answer","error":null}}'
        """.write(to:retryCLI,atomically:true,encoding:.utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:retryCLI.path)
        gemini.geminiExecutablePath=retryCLI.path
        check("temporary nonzero Antigravity capacity failure retries to completion",try AIClient.ask("Test",settings:gemini,timeout:15)=="Recovered answer")
        for (message,expected,retryable) in [("RESOURCE_EXHAUSTED quota 429","usage or rate limit",false),("invalid model selection","does not recognize",false),("No capacity available 503","server capacity",true)] {
            let data=try JSONSerialization.data(withJSONObject:["event":"result","result":["status":"ERROR","error":message,"response":"private partial source"]])
            do{_=try AIClient.antigravityResponse(data);check("classified provider error",false)}
            catch let error as LocalAIError{check("provider error classified: "+expected,error.localizedDescription.contains(expected) && error.retryable==retryable && !error.localizedDescription.contains("private partial source"))}
        }
        let oldSettings = try JSONDecoder().decode(AISettings.self, from: oldJSON)
        check("existing provider settings decode without Gemini migration", oldSettings.provider == .claude && oldSettings.geminiModel == nil)
        exit(failures == 0 ? 0 : 1)
    }
    private static func withEnvironment(_ values: [String: String?], run: () -> Void) {
        let previous = values.keys.map { ($0, ProcessInfo.processInfo.environment[$0]) }
        defer { for (key, value) in previous { if let value { setenv(key, value, 1) } else { unsetenv(key) } } }
        for (key, value) in values { if let value { setenv(key, value, 1) } else { unsetenv(key) } }
        run()
    }
}
