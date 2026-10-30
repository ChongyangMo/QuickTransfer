import Foundation

struct Peer: Codable, Identifiable, Hashable {
    var id: String
    var alias: String
    var host: String
    var port: UInt16
    var `protocol`: String
    var mobile: Bool
    var trusted: Bool
}
struct TransferRow: Identifiable, Codable {
    var id: String
    var name: String
    var size: Int64
    var bytes: Int64 = 0
    var direction: String
    var state: String = "传输中"
    var path: String?
    var paths: [String]?
    var text: String?
    var started: Date = Date()
    var finished: Bool = false
    var progress: Double { size > 0 ? min(1, Double(bytes) / Double(size)) : 0 }
    var fileURLs: [URL] { (paths ?? path.map { [$0] } ?? []).map { URL(fileURLWithPath:$0) } }
}
struct Incoming: Identifiable {
    var id: String
    var alias: String
    var count: Int
    var size: Int64
    var text: String?
}
struct Settings: Codable {
    var alias: String
    var port: UInt16 = 53317
    var lastPeer: String?
}

