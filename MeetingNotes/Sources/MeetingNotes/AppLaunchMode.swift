import Foundation

enum AppLaunchMode {
    static func isPreview(bundleID:String?,arguments:[String])->Bool {
        // Finder and UI automation reopen bundles without their original CLI
        // arguments. A QA bundle must remain isolated even in that case.
        let testBundle=bundleID?.hasPrefix("local.meetingnotes.") == true
        let testArguments=["--ui-check","--ui-inspect","--discussion-ui-inspect"]
        return testBundle || arguments.contains{testArguments.contains($0)}
    }
}
