import AppKit
import Foundation

enum ResourceFiles {
    static let extensions = ["pdf", "epub", "tex", "latex", "md", "markdown", "txt", "html", "htm", "xhtml", "docx", "rtf"]
    static let formatDescription = "PDF, EPUB, LaTeX (.tex), Markdown, text, HTML, DOCX, or RTF"
    static let maxBytes = 20_000_000

    static func read(_ url: URL, nameOverride: String? = nil) throws -> Resource.Loaded {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) <= 100_000_000 else { throw FrontierError("Choose a document smaller than 100 MB.") }
        let name = nameOverride ?? url.deletingPathExtension().lastPathComponent
        var sections: [Resource.Section]
        switch url.pathExtension.lowercased() {
        case "epub": return try epub(url, nameOverride: nameOverride)
        case "docx":
            let archive = try BookArchive(url)
            let xml = try TextXML(data: archive.read("word/document.xml"), mode: .word)
            sections = Resource.markdownSections(xml.text)
        case "rtf":
            let data = try boundedData(url)
            let value = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            sections = [Resource.Section(title: name, text: value.string)]
        case "tex", "latex":
            var visiting = Set<URL>(), total = 0
            let source = try latex(url, root: url.deletingLastPathComponent().resolvingSymlinksInPath(), visiting: &visiting, total: &total)
            let re = try NSRegularExpression(pattern: #"\\(?:chapter|section|subsection)\*?(?:\[[^\]]*\])?\{([^{}]+)\}"#)
            let marked = re.stringByReplacingMatches(in: source, range: NSRange(source.startIndex..., in: source), withTemplate: "\n# $1\n")
            sections = Resource.markdownSections(marked)
        case "md", "markdown":
            let text = try decode(boundedData(url))
            let heading = text.contains("\n# ") || text.hasPrefix("# ") ? "# " : "## "
            sections = Resource.markdownSections(text, heading: heading)
        case "txt": sections = [Resource.Section(title: name, text: try decode(boundedData(url)))]
        case "html", "htm", "xhtml": sections = html(try decode(boundedData(url)), name: name)
        default: throw FrontierError("Unsupported file format. Choose \(formatDescription).")
        }
        sections = sections.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !sections.isEmpty else { throw FrontierError("No readable text was found in this document.") }
        return Resource.Loaded(name: name, origin: url.path, sections: sections)
    }

    static func boundedData(_ url: URL) throws -> Data {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maxBytes else { throw FrontierError("The document text is larger than 20 MB. Import it in smaller parts.") }
        return data
    }
    static func decode(_ data: Data) throws -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]), let text = String(data: data, encoding: .utf16) { return text }
        throw FrontierError("Could not decode the text. Save it as UTF-8 or UTF-16 and try again.")
    }
    static func html(_ source: String, name: String) -> [Resource.Section] {
        let sections = Resource.htmlSections(source)
        if !sections.isEmpty { return sections }
        let clean = source.replacingOccurrences(of: #"<(script|style|nav|header|footer)\b[^>]*>[\s\S]*?</\1>"#, with: "", options: [.regularExpression, .caseInsensitive])
        return [.init(title: Resource.pageTitle(source) ?? name, text: Resource.plainText(clean))]
    }

    /// Includes are read only within the selected source folder. TeX is never executed.
    static func latex(_ url: URL, root: URL, visiting: inout Set<URL>, total: inout Int) throws -> String {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.path.hasPrefix(root.path + "/"), visiting.count < 16,
              visiting.insert(canonical).inserted else { throw FrontierError("LaTeX includes must stay inside the selected file's folder and must not form a cycle.") }
        defer { visiting.remove(canonical) }
        let bytes = try boundedData(canonical); total += bytes.count
        guard total <= maxBytes else { throw FrontierError("The combined LaTeX source exceeds 20 MB.") }
        let raw = try decode(bytes)
        // Ignore comments when looking for include directives, while preserving escaped percent signs.
        let text = raw.replacingOccurrences(of: #"(?m)(?<!\\)%[^\n]*"#, with: "", options: .regularExpression)
        let re = try NSRegularExpression(pattern: #"\\(?:input|include)\s*\{([^{}]+)\}"#)
        var result = text
        for match in re.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: result), let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[nameRange])
            guard !name.hasPrefix("/"), !name.contains("\\") else { throw FrontierError("LaTeX includes must use relative filenames.") }
            var included = canonical.deletingLastPathComponent().appendingPathComponent(name)
            if included.pathExtension.isEmpty { included.appendPathExtension("tex") }
            let expansion = try latex(included, root: root, visiting: &visiting, total: &total)
            result.replaceSubrange(whole, with: "\n" + expansion + "\n")
        }
        return result
    }

    static func epub(_ url: URL, nameOverride: String?) throws -> Resource.Loaded {
        let archive = try BookArchive(url)
        let container = try TextXML(data: archive.read("META-INF/container.xml"), mode: .container)
        guard let path = container.packagePath else { throw FrontierError("This EPUB has no package document.") }
        let package = try TextXML(data: archive.read(path), mode: .package)
        let name = nameOverride ?? (package.title.isEmpty ? url.deletingPathExtension().lastPathComponent : package.title)
        guard !package.spine.isEmpty else { throw FrontierError("This EPUB has no reading order.") }
        var sections: [Resource.Section] = [], total = 0
        for id in package.spine {
            guard let item = package.manifest[id], ["application/xhtml+xml", "text/html"].contains(item.type) else {
                throw FrontierError("This EPUB contains a chapter format Frontier cannot read. Use an EPUB with text chapters.")
            }
            let chapter = try archive.resolve(item.href, relativeTo: path)
            let bytes = try archive.read(chapter); total += bytes.count
            guard total <= maxBytes else { throw FrontierError("The EPUB text exceeds 20 MB. Import smaller parts.") }
            sections += html(try decode(bytes), name: "Chapter \(sections.count + 1)")
        }
        sections = sections.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !sections.isEmpty else { throw FrontierError("No readable EPUB text was found. DRM-protected or image-only books are not supported.") }
        return Resource.Loaded(name: name, origin: url.path, sections: sections)
    }
}

/// Read selected ZIP members without extracting paths onto the filesystem.
struct BookArchive {
    let url: URL
    let entries: Set<String>
    init(_ url: URL) throws {
        self.url = url
        let listing = try LocalProcess.run(URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-Z1", url.path], limit: 1_000_000)
        entries = Set(try ResourceFiles.decode(listing).split(separator: "\n").map(String.init))
        guard entries.count <= 10_000 else { throw FrontierError("This archive contains too many files.") }
    }
    func read(_ path: String) throws -> Data {
        guard entries.contains(path), !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
              !path.contains(where: { "*?[]\\".contains($0) }) else { throw FrontierError("The book contains an invalid chapter path.") }
        return try LocalProcess.run(URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-p", url.path, path], limit: ResourceFiles.maxBytes)
    }
    func resolve(_ href: String, relativeTo package: String) throws -> String {
        guard let decoded = href.removingPercentEncoding, !decoded.contains(":"), !decoded.hasPrefix("/") else { throw FrontierError("The EPUB refers to a chapter outside the book.") }
        let base = URL(fileURLWithPath: "/epub-root/" + package).deletingLastPathComponent()
        let resolved = base.appendingPathComponent(decoded.components(separatedBy: "#")[0]).standardizedFileURL.path
        guard resolved.hasPrefix("/epub-root/") else { throw FrontierError("The EPUB chapter path leaves the book.") }
        return String(resolved.dropFirst("/epub-root/".count))
    }
}

final class TextXML: NSObject, XMLParserDelegate {
    enum Mode { case container, package, word }
    let mode: Mode
    var packagePath: String?
    var title = "", text = ""
    var manifest: [String: (href: String, type: String)] = [:]
    var spine: [String] = []
    var coverID: String?
    private var inTitle = false, inText = false
    init(data: Data, mode: Mode) throws {
        self.mode = mode
        super.init()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        guard parser.parse() else { throw FrontierError("The document contains invalid XML.") }
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes a: [String: String]) {
        let tag = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if mode == .container, tag == "rootfile", packagePath == nil { packagePath = a["full-path"] }
        if mode == .package {
            if tag == "title" { inTitle = true }
            if tag == "meta", a["name"] == "cover" { coverID = a["content"] }
            if tag == "item", (a["properties"] ?? "").split(separator: " ").contains("cover-image") { coverID = a["id"] }
            if tag == "item", let id = a["id"], let href = a["href"] { manifest[id] = (href, a["media-type"] ?? "") }
            if tag == "itemref", a["linear"] != "no", let id = a["idref"] { spine.append(id) }
        }
        if mode == .word {
            if tag == "t" { inText = true }
            if tag == "tab" { text += "\t" }
            if tag == "br" { text += "\n" }
            if tag == "pStyle", (a["w:val"] ?? "").lowercased().hasPrefix("heading") { text += "# " }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTitle { title += string }
        if inText { text += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let tag = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if tag == "title" { inTitle = false }
        if tag == "t" { inText = false }
        if mode == .word, tag == "p" { text += "\n\n" }
    }
}
