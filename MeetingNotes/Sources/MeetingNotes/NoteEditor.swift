import SwiftUI
import AppKit

/// A document-style editor that grows with its text, instead of a stack of
/// independently scrolling boxes. The surrounding document owns scrolling.
struct NoteEditor:NSViewRepresentable {
    @Binding var text:String
    var minimumHeight:CGFloat=28
    var label="Meeting notes"
    var formatting:NoteFormatting?=nil
    func makeNSView(context:Context)->NSTextView {
        let view=NSTextView()
        view.isRichText=false;view.importsGraphics=false;view.isAutomaticQuoteSubstitutionEnabled=false
        view.isAutomaticDashSubstitutionEnabled=false;view.isAutomaticTextReplacementEnabled=false
        view.isVerticallyResizable=false;view.isHorizontallyResizable=false
        view.textContainer?.widthTracksTextView=true
        view.textContainer?.lineFragmentPadding=0
        view.textContainerInset=NSSize(width:0,height:3)
        view.drawsBackground=false;view.font=NSFont(name:"Georgia",size:17)
        view.textColor=NSColor.labelColor;view.insertionPointColor=NSColor.labelColor
        view.allowsUndo=true;view.delegate=context.coordinator
        view.setAccessibilityLabel(label)
        formatting?.view=view
        return view
    }
    func updateNSView(_ view:NSTextView,context:Context){
        context.coordinator.parent=self
        formatting?.view=view
        if view.string != text{view.string=text;view.invalidateIntrinsicContentSize()}
    }
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:NSTextView,context:Context)->CGSize? {
        let width=max(80,proposal.width ?? 500)
        // Measure independently of the live text container: during resizing it
        // still has the previous frame width and can report a stale height.
        let storage=NSTextStorage(string:text.isEmpty ? " ":text,attributes:[.font:NSFont(name:"Georgia",size:17) ?? NSFont.systemFont(ofSize:17)])
        let manager=NSLayoutManager(),container=NSTextContainer(size:NSSize(width:width,height:CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding=0;manager.addTextContainer(container);storage.addLayoutManager(manager)
        manager.ensureLayout(for:container)
        let height=ceil(manager.usedRect(for:container).height)+10
        return CGSize(width:width,height:max(minimumHeight,height))
    }
    func makeCoordinator()->Coordinator{Coordinator(self)}
    final class Coordinator:NSObject,NSTextViewDelegate {
        var parent:NoteEditor
        init(_ parent:NoteEditor){self.parent=parent}
        func textDidChange(_ notification:Notification){guard let view=notification.object as? NSTextView else{return};parent.text=view.string;view.invalidateIntrinsicContentSize()}
    }
}
