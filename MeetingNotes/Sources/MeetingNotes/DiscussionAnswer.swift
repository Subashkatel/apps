import AppKit
import SwiftUI

/// NSTextView delegates handle links directly, including when text selection is enabled.
/// This avoids handing private citation URLs to macOS or an external browser.
struct DiscussionAnswer:NSViewRepresentable {
    let message:DiscussionMessage
    var openSource:(DiscussionSource)->Void
    func makeNSView(context:Context)->NSTextView {
        let view=NSTextView()
        view.isEditable=false;view.isSelectable=true;view.drawsBackground=false
        view.isVerticallyResizable=false;view.isHorizontallyResizable=false
        view.textContainer?.widthTracksTextView=true;view.textContainer?.lineFragmentPadding=0
        view.textContainerInset = .zero
        view.linkTextAttributes=[.foregroundColor:NSColor(Palette.accent),.underlineStyle:NSUnderlineStyle.single.rawValue]
        view.delegate=context.coordinator
        view.setAccessibilityLabel("AI answer with source links")
        return view
    }
    func updateNSView(_ view:NSTextView,context:Context) {
        context.coordinator.parent=self
        let value=rendered
        if !view.attributedString().isEqual(to:value){view.textStorage?.setAttributedString(value);view.invalidateIntrinsicContentSize()}
    }
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:NSTextView,context:Context)->CGSize? {
        let width=max(80,proposal.width ?? 314)
        let storage=NSTextStorage(attributedString:rendered),manager=NSLayoutManager()
        let container=NSTextContainer(size:NSSize(width:width,height:.greatestFiniteMagnitude));container.lineFragmentPadding=0
        manager.addTextContainer(container);storage.addLayoutManager(manager);manager.ensureLayout(for:container)
        return CGSize(width:width,height:ceil(manager.usedRect(for:container).height)+4)
    }
    private var rendered:NSAttributedString {
        let output=NSMutableAttributedString()
        let lines=message.linkedText.components(separatedBy:"\n")
        for (index,line) in lines.enumerated() {
            var content=line
            var font=NSFont(name:"Georgia",size:17) ?? NSFont.systemFont(ofSize:17)
            if content.hasPrefix("## "){content=String(content.dropFirst(3));font=NSFont(name:"Georgia-Bold",size:20) ?? font}
            else if content.hasPrefix("# "){content=String(content.dropFirst(2));font=NSFont(name:"Georgia-Bold",size:24) ?? font}
            else if content.hasPrefix("- "){content="• "+content.dropFirst(2)}
            let parsed=(try? AttributedString(markdown:content,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(content)
            let styled=NSMutableAttributedString()
            for run in parsed.runs {
                var runFont=font
                if let intent=run.inlinePresentationIntent {
                    if intent.contains(.stronglyEmphasized){runFont=NSFontManager.shared.convert(runFont,toHaveTrait:.boldFontMask)}
                    if intent.contains(.emphasized){runFont=NSFontManager.shared.convert(runFont,toHaveTrait:.italicFontMask)}
                    if intent.contains(.code){runFont=NSFont.monospacedSystemFont(ofSize:14,weight:.regular)}
                }
                var attributes:[NSAttributedString.Key:Any]=[.font:runFont,.foregroundColor:NSColor(Palette.ink)]
                if let link=run.link{attributes[.link]=link}
                styled.append(NSAttributedString(string:String(parsed[run.range].characters),attributes:attributes))
            }
            let paragraph=NSMutableParagraphStyle();paragraph.lineSpacing=3;paragraph.paragraphSpacing=6
            styled.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:styled.length))
            output.append(styled)
            if index<lines.count-1{output.append(NSAttributedString(string:"\n",attributes:[.font:font,.foregroundColor:NSColor(Palette.ink),.paragraphStyle:paragraph]))}
        }
        return output
    }
    func makeCoordinator()->Coordinator{Coordinator(self)}
    final class Coordinator:NSObject,NSTextViewDelegate {
        var parent:DiscussionAnswer
        init(_ parent:DiscussionAnswer){self.parent=parent}
        func textView(_ textView:NSTextView,clickedOnLink link:Any,at charIndex:Int)->Bool {
            let url=(link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            if let url,url.scheme=="meeting-source",let id=url.host,
               let source=parent.message.sources.first(where:{$0.id.lowercased()==id.lowercased()}) {
                parent.openSource(source)
            }
            // Never launch unverified AI-generated links or custom URI handlers.
            return true
        }
    }
}
