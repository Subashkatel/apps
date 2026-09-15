import Foundation

@MainActor enum RemovalTests {
    static func run(_ check: (String, Bool, String) -> Void) {
        guard ProcessInfo.processInfo.environment["LOCAL_APPS_TESTING"] == "1", ProcessInfo.processInfo.environment["LOCAL_APPS_DATA_ROOT"] != nil else { return }
        do {
            var exclusive = Concept(id: "removal-exclusive", title: "Exclusive lesson"); exclusive.courses = ["Removal A"]
            var shared = Concept(id: "removal-shared", title: "Shared lesson"); shared.courses = ["Removal A", "Removal B"]
            let path = Store.shared.save(exclusive); Store.shared.save(shared)
            let before = try Data(contentsOf: path)
            let model = Model(); model.load()
            let item = model.materials.first { $0.courseName == "Removal A" }!
            try model.removeMaterial(item)
            check("removal hides material and exclusive lessons, keeps shared lessons", !model.materials.contains { $0.id == item.id } && !model.concepts.contains { $0.id == exclusive.id } && model.concepts.contains { $0.id == shared.id }, "")
            check("removal preserves original lesson files for recovery", try Data(contentsOf: path) == before, "")
            model.restoreMaterial(item.id)
            check("restore brings removed course and lessons back", model.materials.contains { $0.id == item.id } && model.concepts.contains { $0.id == exclusive.id }, "")
        } catch { check("material removal and restore", false, error.localizedDescription) }
    }
}
