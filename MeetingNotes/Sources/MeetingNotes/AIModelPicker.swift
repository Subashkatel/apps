import SwiftUI
import LocalSupport

/// The same model control is used for summary defaults and per-discussion choices.
struct AIModelPicker:View {
    let settings:AISettings
    @Binding var model:String
    @State private var models:[AvailableAIModel]=[]
    @State private var loading=false
    @State private var error:String?
    @State private var requestID=UUID()
    private var custom:Bool{!model.isEmpty && !models.contains{$0.id==model}}
    var body:some View {
        VStack(alignment:.leading,spacing:10){
            if settings.provider == .server {
                TextField("Server model ID",text:$model)
                Text("Use the model name exposed by your configured server.").font(.caption).foregroundStyle(Palette.secondary)
            }else{
                HStack{
                    Picker("Model",selection:$model){
                        Text("Automatic · CLI default").tag("")
                        if custom{Text(model+" (custom ID)").tag(model)}
                        ForEach(models){Text($0.title).tag($0.id)}
                    }.accessibilityIdentifier("ai.model-picker")
                    Button(loading ? "Loading…":"Refresh models"){Task{await load()}}.disabled(loading).accessibilityIdentifier("ai.refresh-models")
                }
                if let error{Text(error).font(.caption).foregroundStyle(.orange)}
                if !loading && custom{Text("This custom ID is not in the model list. Choose a listed model, or check the ID with your provider.").font(.caption).foregroundStyle(Palette.secondary)}
                DisclosureGroup("Enter a model ID manually"){
                    TextField("Exact model ID",text:$model).accessibilityIdentifier("ai.custom-model")
                }.font(.caption)
            }
        }.task(id:settings.provider){await load()}
    }
    private func load()async {
        let id=UUID();requestID=id;models=[];error=nil
        guard settings.provider != .server else{loading=false;return}
        let config=settings;loading=true
        let result=await Task.detached{Result{try DiscussionModelCatalog.load(config)}}.value
        guard requestID==id,!Task.isCancelled else{return}
        loading=false
        switch result {
        case .success(let list):
            models=list
            if list.isEmpty{error="No model list is available yet. Open \(config.provider.title) once, then refresh, or enter a model ID below."}
        case .failure(let failure):error=failure.localizedDescription
        }
    }
}
