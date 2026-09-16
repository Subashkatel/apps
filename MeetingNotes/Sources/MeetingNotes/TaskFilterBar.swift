import SwiftUI

/// Compact controls shared by the task inbox and each project's task list.
struct TaskFilterBar: View {
    @ObservedObject var store: MeetingStore
    let project: MeetingProject?
    @Binding var query: TaskQuery
    @Binding var grouping: String
    let count: Int

    private var projectTitle: String {
        query.project == "all" ? "All projects" : query.project == "unfiled" ? "Unfiled" : store.projects.first{$0.id == query.project}?.name ?? "Project unavailable"
    }
    private var meetingTitle: String {
        query.meeting == "all" ? "All meetings" : query.meeting == "none" ? "No meeting" : store.meetings.first{$0.id == query.meeting}?.title ?? "Meeting unavailable"
    }
    private var statusTitle: String { query.status == "open" ? "Open" : query.status == "done" ? "Completed" : "All statuses" }
    private var dueTitle: String { ["all":"Any date","today":"Today","overdue":"Overdue","none":"No date"][query.deadline] ?? "Any date" }
    private var filtered: Bool { !query.search.isEmpty || (project == nil && query.project != "all") || query.meeting != "all" || query.status != "open" || query.deadline != "all" }

    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:8) {
                Image(systemName:"magnifyingglass").foregroundStyle(Palette.secondary).accessibilityHidden(true)
                TextField("Search tasks or owners",text:$query.search)
                    .textFieldStyle(.plain).accessibilityIdentifier("tasks.search")
                if !query.search.isEmpty {
                    Button { query.search="" } label: { Image(systemName:"xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Palette.secondary).help("Clear search").accessibilityLabel("Clear search")
                }
            }.font(.system(size:13)).padding(.horizontal,11).padding(.vertical,10)
                .background(Palette.panel.opacity(0.55),in:RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Palette.secondary.opacity(0.16)))

            TaskFilterFlow(spacing:8) {
                if project == nil {
                    filterMenu("Project",title:projectTitle,active:query.project != "all") {
                        Picker("Project",selection:$query.project) {
                            Text("All projects").tag("all");Text("Unfiled").tag("unfiled")
                            ForEach(store.projects) { Text($0.name).tag($0.id) }
                        }.labelsHidden().pickerStyle(.inline)
                    }
                }
                filterMenu("Meeting",title:meetingTitle,active:query.meeting != "all") {
                    Picker("Meeting",selection:$query.meeting) {
                        Text("All meetings").tag("all");Text("No meeting").tag("none")
                        ForEach(store.meetings.filter{project == nil || $0.projectID == project?.id}) {
                            Text($0.title+($0.deletedAt != nil ? " · in Trash":"")).tag($0.id)
                        }
                    }.labelsHidden().pickerStyle(.inline)
                }
                filterMenu("Status",title:statusTitle,active:query.status != "open") {
                    Picker("Status",selection:$query.status) {
                        Text("Open").tag("open");Text("Completed").tag("done");Text("All statuses").tag("all")
                    }.labelsHidden().pickerStyle(.inline)
                }
                filterMenu("Due",title:dueTitle,active:query.deadline != "all") {
                    Picker("Due",selection:$query.deadline) {
                        Text("Any date").tag("all");Text("Today").tag("today");Text("Overdue").tag("overdue");Text("No date").tag("none")
                    }.labelsHidden().pickerStyle(.inline)
                }
            }

            HStack(spacing:12) {
                Text("\(count) \(count == 1 ? "task":"tasks")").foregroundStyle(Palette.secondary)
                if filtered {
                    Button("Clear filters") {
                        let sort=query.sort;query=TaskQuery();query.sort=sort
                    }.buttonStyle(.plain).foregroundStyle(Palette.accent).accessibilityIdentifier("tasks.clear-filters")
                }
                Spacer(minLength:8)
                Menu {
                    Picker("Sort by",selection:$query.sort) {
                        Text("Due date").tag("due");Text("Newest").tag("newest");Text("Title").tag("title")
                    }
                    Divider()
                    Picker("Group by",selection:$grouping) {
                        Text("None").tag("none");Text("Project").tag("project");Text("Meeting").tag("meeting");Text("Due date").tag("due")
                    }
                } label: {
                    HStack(spacing:6) { Image(systemName:"slider.horizontal.3");Text("View");Image(systemName:"chevron.down").font(.system(size:9,weight:.medium)) }
                        .padding(.vertical,5).contentShape(Rectangle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .foregroundStyle(Palette.secondary).help("Sort and group tasks")
                    .accessibilityLabel("View options: sort and group tasks").accessibilityIdentifier("tasks.view-options")
            }.font(.system(size:12))
            Divider().overlay(Palette.secondary.opacity(0.1))
        }
    }

    private func filterMenu<Content: View>(_ name:String,title:String,active:Bool,@ViewBuilder content:()->Content)->some View {
        Menu(content:content) { Text(title).lineLimit(1).truncationMode(.tail) }
            .menuStyle(.borderlessButton)
            .font(.system(size:12,weight:.medium))
            .foregroundStyle(active ? Palette.accent:Palette.ink)
            .frame(maxWidth:170).fixedSize(horizontal:true,vertical:true)
            .padding(.horizontal,10).frame(height:30)
            .background(active ? Palette.accent.opacity(0.13):Palette.panel.opacity(0.5),in:RoundedRectangle(cornerRadius:6))
            .overlay(RoundedRectangle(cornerRadius:6).strokeBorder(active ? Palette.accent.opacity(0.35):Palette.secondary.opacity(0.16)))
            .help(name+": "+title).accessibilityLabel(name+": "+title)
            .accessibilityIdentifier("tasks.filter."+name.lowercased())
    }
}

/// Wrap intrinsic-width controls without stretching popups to fill a row.
private struct TaskFilterFlow: Layout {
    let spacing: CGFloat
    private func positions(_ subviews:Subviews,width:CGFloat)->(points:[CGPoint],size:CGSize) {
        var points:[CGPoint]=[],x:CGFloat=0,y:CGFloat=0,rowHeight:CGFloat=0,used:CGFloat=0
        for view in subviews {
            let size=view.sizeThatFits(ProposedViewSize(width:min(190,width),height:nil))
            if x>0 && x+size.width>width { x=0;y+=rowHeight+spacing;rowHeight=0 }
            points.append(CGPoint(x:x,y:y));used=max(used,x+size.width)
            x+=size.width+spacing;rowHeight=max(rowHeight,size.height)
        }
        return (points,CGSize(width:used,height:y+rowHeight))
    }
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        positions(subviews,width:proposal.width ?? .infinity).size
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let layout=positions(subviews,width:bounds.width)
        for (index,view) in subviews.enumerated() {
            view.place(at:CGPoint(x:bounds.minX+layout.points[index].x,y:bounds.minY+layout.points[index].y),proposal:ProposedViewSize(width:min(190,bounds.width),height:nil))
        }
    }
}
