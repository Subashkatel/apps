import Foundation

/// Local, explicit handoff. URL events contain only an inbox identifier, never
/// document contents or arbitrary paths. Both apps can remain usable alone.
public struct ReadingHandoff: Codable {
    public var id: String
    public var materialID: String
    public var title: String
    public var origin: String
    public var originalPath: String
    public var annotationID: String
    public var page: Int
    public var quote: String
    public var note: String
    public init(materialID: String, title: String, origin: String, originalPath: String,
                annotationID: String, page: Int, quote: String, note: String) {
        id = UUID().uuidString; self.materialID = materialID; self.title = title; self.origin = origin
        self.originalPath = originalPath; self.annotationID = annotationID; self.page = page
        self.quote = quote; self.note = note
    }
    public static var inbox: URL { LocalConfig.dataDirectory("Reading Bridge").appendingPathComponent("inbox") }
    public var sourceURL: URL {
        var parts = URLComponents(); parts.scheme = "frontier"; parts.host = "source"; parts.path = "/" + materialID
        parts.queryItems = [.init(name: "page", value: String(page)), .init(name: "annotation", value: annotationID)]
        return parts.url!
    }
    public func write(to folder: URL = Self.inbox) throws -> URL {
        try validate()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent(id + ".json")
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return URL(string: "papernotes://handoff/" + id)!
    }
    public static func read(_ url: URL, from folder: URL = Self.inbox) throws -> Self {
        let id = url.lastPathComponent
        guard url.scheme == "papernotes", url.host == "handoff", UUID(uuidString: id) != nil else { throw CocoaError(.fileReadCorruptFile) }
        let data = try Data(contentsOf: folder.appendingPathComponent(id + ".json"))
        guard data.count < 2_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let packet = try JSONDecoder().decode(Self.self, from: data)
        guard packet.id == id else { throw CocoaError(.fileReadCorruptFile) }
        try packet.validate(); return packet
    }
    public func validate() throws {
        guard UUID(uuidString: id) != nil, !materialID.isEmpty,
              materialID == URL(fileURLWithPath: materialID).lastPathComponent,
              materialID != ".", materialID != "..", page > 0,
              originalPath.hasPrefix("/"), originalPath.lowercased().hasSuffix(".pdf"),
              note.count + quote.count < 500_000 else { throw CocoaError(.fileReadCorruptFile) }
    }
}
