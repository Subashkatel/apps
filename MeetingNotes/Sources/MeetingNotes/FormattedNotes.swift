import SwiftUI
import AppKit

/// Markdown keeps personal notes portable in exports and independent backups.
@MainActor final class NoteFormatting:ObservableObject {
    weak var view:NSTextView?
    func apply(_ prefix:String,_ suffix:String="") {
        guard let view else{return}
        let range=view.selectedRange(),source=view.string as NSString
        guard range.location != NSNotFound,NSMaxRange(range)<=source.length else{return}
        let selected=source.substring(with:range)
        let replacement=prefix+selected+suffix
        guard view.shouldChangeText(in:range,replacementString:replacement) else{return}
        view.textStorage?.replaceCharacters(in:range,with:replacement);view.didChangeText()
        view.window?.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location:range.location+(prefix as NSString).length,length:(selected as NSString).length))
    }
}
struct FormattedNotes:View {
    @Binding var text:String
    @StateObject private var formatting=NoteFormatting()
    @State private var preview=false
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            HStack(spacing:16){
                if !preview {
                    Button{formatting.apply("**","**")}label:{Image(systemName:"bold")}.help("Bold selection")
                    Button{formatting.apply("*","*")}label:{Image(systemName:"italic")}.help("Italic selection")
                    Button{formatting.apply("\n## ")}label:{Text("H")}.help("Heading")
                    Button{formatting.apply("\n- ")}label:{Image(systemName:"list.bullet")}.help("Bullet")
                    Button{formatting.apply("\n- [ ] ")}label:{Image(systemName:"checklist")}.help("Checklist")
                }
                Spacer()
                Button(preview ? "Edit":"Preview"){preview.toggle()}.help("Preview Markdown formatting")
            }.font(.system(size:12)).buttonStyle(.plain).foregroundStyle(Palette.secondary)
            if preview {MarkdownNotes(text:text).frame(maxWidth:.infinity,alignment:.leading)}
            else {NoteEditor(text:$text,minimumHeight:85,label:"My meeting notes",formatting:formatting)}
        }
    }
}
struct MarkdownNotes:View {
    let text:String
    var body:some View {
        VStack(alignment:.leading,spacing:7){
            if text.isEmpty {Text("Your notes will appear here.").foregroundStyle(Palette.secondary)}
            ForEach(Array(text.components(separatedBy:"\n").enumerated()),id:\.offset){_,line in
                if line.hasPrefix("## "){Text(inline(String(line.dropFirst(3)))).font(.custom("Georgia-Bold",size:20)).padding(.top,8)}
                else if line.hasPrefix("# "){Text(inline(String(line.dropFirst(2)))).font(.custom("Georgia-Bold",size:24)).padding(.top,8)}
                else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] "){HStack(alignment:.firstTextBaseline){Image(systemName:line.hasPrefix("- [x]") ? "checkmark.square":"square");Text(inline(String(line.dropFirst(6))))}}
                else if line.hasPrefix("- "){HStack(alignment:.firstTextBaseline){Text("•");Text(inline(String(line.dropFirst(2))))}}
                else {Text(line.isEmpty ? AttributedString(" "):inline(line))}
            }
        }.font(.custom("Georgia",size:17)).foregroundStyle(Palette.ink).textSelection(.enabled)
    }
    private func inline(_ value:String)->AttributedString{(try? AttributedString(markdown:value,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(value)}
}
