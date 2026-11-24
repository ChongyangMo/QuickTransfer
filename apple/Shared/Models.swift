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
    static let defaultCacheRetentionDays = 7
    static let minCacheRetentionDays = 1
    static let maxCacheRetentionDays = 365

    var alias: String
    var port: UInt16 = 53317
    var lastPeer: String?
    var cacheRetentionDays: Int = Settings.defaultCacheRetentionDays

    enum CodingKeys: String, CodingKey {
        case alias, port, lastPeer, cacheRetentionDays
    }

    init(alias: String, port: UInt16 = 53317, lastPeer: String? = nil, cacheRetentionDays: Int = Settings.defaultCacheRetentionDays) {
        self.alias = alias
        self.port = port
        self.lastPeer = lastPeer
        self.cacheRetentionDays = Self.clampedRetentionDays(cacheRetentionDays)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        alias = try container.decode(String.self, forKey: .alias)
        port = try container.decodeIfPresent(UInt16.self, forKey: .port) ?? 53317
        lastPeer = try container.decodeIfPresent(String.self, forKey: .lastPeer)
        let days = try container.decodeIfPresent(Int.self, forKey: .cacheRetentionDays) ?? Self.defaultCacheRetentionDays
        cacheRetentionDays = Self.clampedRetentionDays(days)
    }

    static func clampedRetentionDays(_ value: Int) -> Int {
        min(maxCacheRetentionDays, max(minCacheRetentionDays, value))
    }
}

