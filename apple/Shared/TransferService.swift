import SwiftUI
import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif
#if os(iOS)
import Photos
import PhotosUI
#endif

@MainActor
final class TransferService: ObservableObject {
    static let shared = TransferService()
    static let group = "group.com.chongyang.quicktransfer"
    @Published var peers: [Peer] = []
    @Published private var cachedPeers: [Peer] = []
    @Published var selected: String? { didSet { settings.lastPeer = selected; saveSettings() } }
    @Published var text = ""
    @Published var attachments: [URL] = []
    @Published private(set) var importingPhotos = false
    @Published private(set) var importingPhotoCount = 0
    @Published private(set) var pendingAutoSend = false
    @Published private(set) var cacheSizeBytes: Int64 = 0
    @Published private(set) var cacheItemCount = 0
    @Published var rows: [TransferRow] = []
    @Published var incoming: Incoming?
    @Published var error: String?
    @Published var ready = false
    @Published var settings: Settings
    @Published var showSettings = false
    @Published var showAddress = false
    @Published var preview: URL?
    /// 收到文件或文字时回调（名称或发送方，文字内容），iOS 用于后台通知。
    var onReceive: ((String,String?)->Void)?
    let root: URL
    private var timer: Timer?
    private var bonjour: BonjourDiscovery?
    private var hasStarted = false
    private var outgoingDrafts: [String:(String,[URL])] = [:]
    private var peerGraceTask: Task<Void, Never>?
    #if os(iOS)
    private var photoImportBatches = 0
    #endif
    #if DEBUG
    private lazy var verification = NativeVerification(service:self)
    #endif

    init() {
        #if os(macOS)
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QuickTransfer", isDirectory: true)
        let alias = Host.current().localizedName ?? "Mac"
        #else
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.group) else {
            fatalError("共享容器不可用，请检查开发签名")
        }
        let previous=container.appendingPathComponent("QuickTransfer",isDirectory:true)
        let location=container.appendingPathComponent("Library/Application Support/QuickTransfer",isDirectory:true)
        do {
            if FileManager.default.fileExists(atPath:previous.path),!FileManager.default.fileExists(atPath:location.path) {
                try FileManager.default.createDirectory(at:location.deletingLastPathComponent(),withIntermediateDirectories:true)
                try FileManager.default.moveItem(at:previous,to:location)
            }
        } catch { fatalError("迁移存储失败：\(error.localizedDescription)") }
        root=location
        let alias = Self.defaultDeviceAlias()
        #endif
        let config = root.appendingPathComponent("settings.json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: config.path) {
                settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: config))
                #if os(iOS)
                let trimmed = settings.alias.trimmingCharacters(in: .whitespacesAndNewlines)
                if (trimmed.isEmpty || trimmed == UIDevice.current.model) && alias != trimmed {
                    settings.alias = alias
                    try? JSONEncoder().encode(settings).write(to: config, options: .atomic)
                }
                #endif
            } else { settings = Settings(alias: alias) }
        } catch {
            settings = Settings(alias: alias)
            self.error = "配置读取失败：\(error.localizedDescription)"
        }
        selected = settings.lastPeer
        let cachedPeersFile = root.appendingPathComponent("last_peers.json")
        if let data = try? Data(contentsOf: cachedPeersFile),
           let loaded = try? JSONDecoder().decode([Peer].self, from: data) {
            cachedPeers = loaded
        }
        let history = root.appendingPathComponent("history.json")
        if FileManager.default.fileExists(atPath: history.path) {
            do {
                rows = try JSONDecoder().decode([TransferRow].self, from: Data(contentsOf: history))
                #if os(iOS)
                for index in rows.indices {
                    if let path=rows[index].path,path.hasPrefix(previous.path+"/") { rows[index].path=location.path+path.dropFirst(previous.path.count) }
                }
                #endif
                sortRows()
            }
            catch { self.error = "接收记录读取失败：\(error.localizedDescription)" }
        }
        timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer!,forMode:.common)
        cleanExpiredOutbox()
    }
    var displayPeers: [Peer] {
        guard !cachedPeers.isEmpty else { return peers }
        var merged: [String: Peer] = [:]
        for peer in cachedPeers { merged[peer.id] = peer }
        for peer in peers { merged[peer.id] = peer }
        return merged.values.sorted { $0.alias.localizedStandardCompare($1.alias) == .orderedAscending }
    }
    func isPeerOnline(_ id: String) -> Bool {
        ready && peers.contains(where: { $0.id == id })
    }
    func start(portOverride: UInt16? = nil) {
        guard !hasStarted else { return }
        guard error == nil else { return }
        hasStarted = true
        if !cachedPeers.isEmpty {
            schedulePeerGraceTimeout()
        }
        #if os(macOS)
        let mobile = false
        let model = "Mac"
        #else
        let mobile = true
        let model = UIDevice.current.model
        #endif
        sendJSON(["root":root.path,"alias":settings.alias,"model":model,"mobile":mobile,"port":portOverride ?? settings.port,"multicast": !mobile], to: qt_start)
    }
    func stop() {
        if !peers.isEmpty {
            cachedPeers = peers
            saveCachedPeers(peers)
        }
        peerGraceTask?.cancel()
        peerGraceTask = nil
        bonjour?.stop(); bonjour = nil
        qt_stop(); ready = false; hasStarted = false; peers = []
    }
    private func schedulePeerGraceTimeout() {
        peerGraceTask?.cancel()
        peerGraceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.cachedPeers = []
            self.peerGraceTask = nil
        }
    }
    private func saveCachedPeers(_ list: [Peer]) {
        guard !list.isEmpty else { return }
        let file = root.appendingPathComponent("last_peers.json")
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: file, options: .atomic)
        }
    }
    func restart() { error = nil; stop(); start() }
    func refresh() { if ready { command(["action":"refresh"]); bonjour?.refresh() } else { restart() } }
    func command(_ value: [String:Any]) { sendJSON(value, to: qt_command) }
    private func sendJSON(_ value: [String:Any], to call: (UnsafePointer<CChar>?) -> Void) {
        do {
            let data = try JSONSerialization.data(withJSONObject: value)
            guard let json = String(data:data,encoding:.utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            json.withCString { call($0) }
        } catch { self.error = "操作失败：\(error.localizedDescription)" }
    }
    var canSendToSelectedPeer: Bool {
        ready && selected != nil && peers.contains(where: { $0.id == selected })
    }
    func send() {
        guard ready, let selected, peers.contains(where:{$0.id == selected}) else { error = "请选择在线设备"; return }
        if importingPhotos {
            pendingAutoSend = true
            return
        }
        guard !text.isEmpty || !attachments.isEmpty else { error = "请选择文件或输入文字"; return }
        pendingAutoSend = false
        let id=UUID().uuidString
        outgoingDrafts[id]=(text,attachments)
        var value: [String:Any] = ["action":"send","peer":selected,"id":id,"paths":attachments.map(\.path)]
        if !text.isEmpty { value["text"] = text }
        command(value)
        text = ""; attachments = []
    }
    func removeAttachment(_ url: URL) {
        attachments.removeAll { $0 == url }
        if !importingPhotos && text.isEmpty && attachments.isEmpty {
            pendingAutoSend = false
        }
        if !isURLReferenced(url) {
            let root = self.root
            Task.detached(priority: .utility) {
                Self.deleteOutboxEntryIfOwned(url, root: root)
            }
        }
    }
    func answer(accept: Bool, remember: Bool) {
        guard let incoming else { return }
        command(["action":accept ? "accept":"decline","id":incoming.id,"remember":remember])
        self.incoming = nil
    }
    func stage(_ urls: [URL]) {
        #if os(macOS)
        attachments.append(contentsOf:urls)
        #else
        let root=self.root
        Task {
            do {
                let copied=try await Task.detached(priority:.userInitiated) {
                    try urls.map { url in
                        let scoped=url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        return try Self.copyToOutbox(url,root:root)
                    }
                }.value
                attachments.append(contentsOf:copied)
            } catch { self.error="添加文件失败：\(error.localizedDescription)" }
        }
        #endif
    }
    #if os(iOS)
    private enum PhotoImportResult: Sendable {
        case success(URL)
        case failure(String)
    }

    func stagePhotoAssets(_ assets: [PHAsset], autoSend: Bool = false) {
        guard !assets.isEmpty else { return }
        photoImportBatches += 1
        importingPhotoCount += assets.count
        importingPhotos = true
        if autoSend { pendingAutoSend = true }
        let root = self.root
        Task { [weak self] in
            guard let self else { return }
            var hadFailure = false
            var orderedResults: [Int: URL] = [:]
            await withTaskGroup(of: (Int, PhotoImportResult).self) { group in
                var nextIndex = 0
                let concurrentLimit = min(4, assets.count)
                for _ in 0..<concurrentLimit {
                    let index = nextIndex
                    let asset = assets[index]
                    nextIndex += 1
                    group.addTask {
                        do {
                            let url = try await PhotoAssetExporter.exportOriginal(asset, root: root)
                            return (index, .success(url))
                        } catch {
                            return (index, .failure(error.localizedDescription))
                        }
                    }
                }
                while let (index, result) = await group.next() {
                    self.importingPhotoCount = max(0, self.importingPhotoCount - 1)
                    switch result {
                    case .success(let url):
                        if autoSend {
                            orderedResults[index] = url
                        } else {
                            self.attachments.append(url)
                        }
                    case .failure(let message):
                        hadFailure = true
                        self.error = "读取照片失败：\(message)"
                    }
                    if nextIndex < assets.count {
                        let next = nextIndex
                        let asset = assets[next]
                        nextIndex += 1
                        group.addTask {
                            do {
                                let url = try await PhotoAssetExporter.exportOriginal(asset, root: root)
                                return (next, .success(url))
                            } catch {
                                return (next, .failure(error.localizedDescription))
                            }
                        }
                    }
                }
            }
            if autoSend && !orderedResults.isEmpty {
                let ordered = orderedResults.keys.sorted().compactMap { orderedResults[$0] }
                attachments.append(contentsOf: ordered)
            }
            finishPhotoImportBatch(hadFailure: hadFailure)
        }
    }

    func stagePhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoImportBatches += 1
        importingPhotoCount += items.count
        importingPhotos = true
        let root = self.root
        let authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let canUsePhotoKit = authStatus == .authorized || authStatus == .limited
        Task { [weak self] in
            guard let self else { return }
            var hadFailure = false
            await withTaskGroup(of: PhotoImportResult.self) { group in
                var nextIndex = 0
                let concurrentLimit = min(4, items.count)
                for _ in 0..<concurrentLimit {
                    let item = items[nextIndex]
                    nextIndex += 1
                    group.addTask { await Self.importPhoto(item, root: root, canUsePhotoKit: canUsePhotoKit) }
                }
                while let result = await group.next() {
                    self.importingPhotoCount = max(0, self.importingPhotoCount - 1)
                    switch result {
                    case .success(let url):
                        self.attachments.append(url)
                    case .failure(let message):
                        hadFailure = true
                        self.error = "读取照片失败：\(message)"
                    }
                    if nextIndex < items.count {
                        let item = items[nextIndex]
                        nextIndex += 1
                        group.addTask { await Self.importPhoto(item, root: root, canUsePhotoKit: canUsePhotoKit) }
                    }
                }
            }
            finishPhotoImportBatch(hadFailure: hadFailure)
        }
    }

    private func finishPhotoImportBatch(hadFailure: Bool) {
        if hadFailure {
            pendingAutoSend = false
        }
        photoImportBatches = max(0, photoImportBatches - 1)
        importingPhotos = photoImportBatches > 0
        if !importingPhotos {
            importingPhotoCount = 0
            if pendingAutoSend {
                pendingAutoSend = false
                if canSendToSelectedPeer && (!text.isEmpty || !attachments.isEmpty) {
                    send()
                }
            }
        }
    }

    private nonisolated static func importPhoto(_ item: PhotosPickerItem, root: URL, canUsePhotoKit: Bool) async -> PhotoImportResult {
        if canUsePhotoKit, let id = item.itemIdentifier {
            if let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
                if let url = try? await PhotoAssetExporter.exportOriginal(asset, root: root) {
                    return .success(url)
                }
            }
        }
        do {
            guard let photo = try await item.loadTransferable(type: ImportedPhoto.self) else {
                return .failure("照片内容不可用")
            }
            return .success(photo.url)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
    #endif
    private func isURLReferenced(_ url: URL) -> Bool {
        let target = url.standardizedFileURL.path
        if attachments.contains(where: { $0.standardizedFileURL.path == target }) { return true }
        if outgoingDrafts.values.contains(where: { $0.1.contains(where: { $0.standardizedFileURL.path == target }) }) { return true }
        if rows.contains(where: { $0.fileURLs.contains(where: { $0.standardizedFileURL.path == target }) }) { return true }
        return false
    }
    private func activeOutboxFolders(includePinned: Bool = false) -> Set<String> {
        let outboxRoot = root.appendingPathComponent("outbox", isDirectory: true).standardizedFileURL
        let prefix = outboxRoot.path + "/"
        var keptFolders = Set<String>()
        let collect: (URL) -> Void = { url in
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { return }
            let remainder = path.dropFirst(prefix.count)
            if let folder = remainder.split(separator: "/").first {
                keptFolders.insert(String(folder))
            }
        }
        attachments.forEach(collect)
        outgoingDrafts.values.forEach { $0.1.forEach(collect) }
        if includePinned {
            rows.filter(\.pinned).forEach { $0.fileURLs.forEach(collect) }
        }
        return keptFolders
    }
    func refreshCacheStats() {
        let outboxRoot = root.appendingPathComponent("outbox", isDirectory: true).standardizedFileURL
        let active = activeOutboxFolders()
        Task { [weak self] in
            let stats = await Task.detached(priority: .utility) {
                Self.measureOutbox(at: outboxRoot, excluding: active)
            }.value
            self?.cacheItemCount = stats.count
            self?.cacheSizeBytes = stats.bytes
        }
    }
    func cleanExpiredOutbox() {
        let days = Settings.clampedRetentionDays(settings.cacheRetentionDays)
        let cutoff = Date().addingTimeInterval(-TimeInterval(days) * 86_400)
        let outboxRoot = root.appendingPathComponent("outbox", isDirectory: true).standardizedFileURL
        let active = activeOutboxFolders(includePinned: true)
        let snapshotRows = rows
        Task { [weak self] in
            let (stats, deadRowIDs) = await Task.detached(priority: .utility) {
                let fm = FileManager.default
                let keys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey]
                if let entries = try? fm.contentsOfDirectory(at: outboxRoot, includingPropertiesForKeys: Array(keys)) {
                    for entry in entries where !active.contains(entry.lastPathComponent) {
                        let values = try? entry.resourceValues(forKeys: keys)
                        let modified = values?.contentModificationDate ?? values?.creationDate
                        if let modified, modified < cutoff {
                            try? fm.removeItem(at: entry)
                        }
                    }
                }
                let measured = Self.measureOutbox(at: outboxRoot, excluding: active)
                let dead = Self.findDeadFileRowIDs(in: snapshotRows)
                return (measured, dead)
            }.value
            guard let self else { return }
            self.cacheItemCount = stats.count
            self.cacheSizeBytes = stats.bytes
            self.removeRows(withIDs: deadRowIDs)
        }
    }
    func clearOutboxCacheNow() {
        let outboxRoot = root.appendingPathComponent("outbox", isDirectory: true).standardizedFileURL
        let active = activeOutboxFolders(includePinned: false)
        let snapshotRows = rows
        Task { [weak self] in
            let (stats, deadRowIDs) = await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                if let entries = try? fm.contentsOfDirectory(at: outboxRoot, includingPropertiesForKeys: nil) {
                    for entry in entries where !active.contains(entry.lastPathComponent) {
                        try? fm.removeItem(at: entry)
                    }
                }
                let measured = Self.measureOutbox(at: outboxRoot, excluding: active)
                let dead = Self.findDeadFileRowIDs(in: snapshotRows)
                return (measured, dead)
            }.value
            guard let self else { return }
            self.cacheItemCount = stats.count
            self.cacheSizeBytes = stats.bytes
            self.removeRows(withIDs: deadRowIDs)
        }
    }
    func togglePinRow(_ id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].pinned.toggle()
        sortRows()
        saveHistory()
    }
    func deleteRow(_ id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let removed = rows.remove(at: index)
        if !removed.finished && removed.direction == "send" {
            command(["action":"cancel","id":id])
        }
        saveHistory()
        let root = self.root
        let orphaned = removed.fileURLs.filter { !isURLReferenced($0) }
        if !orphaned.isEmpty {
            Task { [weak self] in
                await Task.detached(priority: .utility) {
                    for url in orphaned {
                        Self.deleteOutboxEntryIfOwned(url, root: root)
                    }
                }.value
                self?.refreshCacheStats()
            }
        }
    }
    func stageExistingRowFiles(_ row: TransferRow) {
        let alive = row.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !alive.isEmpty else { return }
        let existing = Set(attachments.map { $0.standardizedFileURL.path })
        let toAdd = alive.filter { !existing.contains($0.standardizedFileURL.path) }
        if !toAdd.isEmpty {
            attachments.append(contentsOf: toAdd)
        }
    }
    private func sortRows() {
        rows.sort { a, b in
            if a.pinned != b.pinned { return a.pinned && !b.pinned }
            return a.started > b.started
        }
    }
    private func trimRowsIfNeeded() {
        guard rows.count > 30 else { return }
        while rows.count > 30 {
            if let lastUnpinned = rows.lastIndex(where: { !$0.pinned }) {
                rows.remove(at: lastUnpinned)
            } else {
                rows.removeLast()
            }
        }
        cleanExpiredOutbox()
    }
    private func removeRows(withIDs ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let before = rows.count
        rows.removeAll { ids.contains($0.id) }
        if rows.count != before {
            saveHistory()
        }
    }
    private nonisolated static func findDeadFileRowIDs(in rows: [TransferRow]) -> Set<String> {
        let fm = FileManager.default
        var dead = Set<String>()
        for row in rows {
            guard row.finished, row.text == nil else { continue }
            let urls = row.fileURLs
            guard !urls.isEmpty else { continue }
            let hasAnyAlive = urls.contains { fm.fileExists(atPath: $0.path) }
            if !hasAnyAlive {
                dead.insert(row.id)
            }
        }
        return dead
    }
    private nonisolated static func measureOutbox(at outboxRoot: URL, excluding active: Set<String>) -> (count: Int, bytes: Int64) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: outboxRoot, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) else {
            return (0, 0)
        }
        var count = 0
        var total: Int64 = 0
        for entry in entries where !active.contains(entry.lastPathComponent) {
            count += 1
            if let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory, isDir {
                if let enumerator = fm.enumerator(at: entry, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
                    for case let file as URL in enumerator {
                        let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                        if values?.isRegularFile == true {
                            total += Int64(values?.fileSize ?? 0)
                        }
                    }
                }
            } else {
                let size = (try? entry.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                total += Int64(size)
            }
        }
        return (count, total)
    }
    private nonisolated static func deleteOutboxEntryIfOwned(_ url: URL, root: URL) {
        let outboxRoot = root.appendingPathComponent("outbox", isDirectory: true).standardizedFileURL
        let prefix = outboxRoot.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(prefix) else { return }
        let remainder = path.dropFirst(prefix.count)
        guard let folder = remainder.split(separator: "/").first else { return }
        try? FileManager.default.removeItem(at: outboxRoot.appendingPathComponent(String(folder), isDirectory: true))
    }
    nonisolated static func copyToOutbox(_ source: URL, root: URL) throws -> URL {
        let dir = root.appendingPathComponent("outbox").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at:source,to:destination)
        return destination
    }
    func importShared() {
        let manifest = root.appendingPathComponent("share.json")
        guard FileManager.default.fileExists(atPath:manifest.path) else { return }
        do {
            let value = try JSONSerialization.jsonObject(with:Data(contentsOf:manifest)) as? [String:Any]
            guard let value else { throw CocoaError(.fileReadCorruptFile) }
            text = value["text"] as? String ?? ""
            attachments = (value["paths"] as? [String] ?? []).map { URL(fileURLWithPath:$0) }
            try FileManager.default.removeItem(at:manifest)
        } catch { self.error = "读取分享内容失败：\(error.localizedDescription)" }
    }
    func saveSettings() {
        do { try JSONEncoder().encode(settings).write(to:root.appendingPathComponent("settings.json"),options:.atomic) }
        catch { self.error = "保存配置失败：\(error.localizedDescription)" }
    }
    private func poll() {
        for _ in 0..<64 {
            guard let pointer = qt_poll() else { break }
            let data = Data(String(cString:pointer).utf8)
            qt_free(pointer)
            do {
                guard let value = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw CocoaError(.fileReadCorruptFile) }
                consume(value)
            } catch { self.error = "读取传输状态失败：\(error.localizedDescription)" }
        }
    }
    private func consume(_ value: [String:Any]) {
        let type = value["type"] as? String ?? ""
        let id = value["id"] as? String ?? ""
        switch type {
        case "ready":
            ready = true
            let port = (value["port"] as? NSNumber)?.uint16Value ?? settings.port
            bonjour = BonjourDiscovery(alias:settings.alias,port:port) { [weak self] host, port in
                self?.command(["action":"probe","host":host,"port":port])
            }
            bonjour?.start()
            importShared()
        case "devices":
            do {
                let data = try JSONSerialization.data(withJSONObject:value["devices"] ?? [])
                peers = try JSONDecoder().decode([Peer].self,from:data).sorted { $0.alias.localizedStandardCompare($1.alias) == .orderedAscending }
                if !peers.isEmpty {
                    saveCachedPeers(peers)
                    let onlineIDs = Set(peers.map(\.id))
                    if !cachedPeers.isEmpty && cachedPeers.allSatisfy({ onlineIDs.contains($0.id) }) {
                        cachedPeers = []
                        peerGraceTask?.cancel()
                        peerGraceTask = nil
                    }
                }
                if selected == nil, displayPeers.count == 1 { selected = displayPeers[0].id }
            } catch { self.error = "读取设备失败：\(error.localizedDescription)" }
        case "offline": peers.removeAll { $0.id == id }
        case "incoming":
            incoming = Incoming(id:id,alias:value["alias"] as? String ?? "",count:value["count"] as? Int ?? 0,size:(value["size"] as? NSNumber)?.int64Value ?? 0,text:value["text"] as? String)
            #if os(macOS)
            MacAppDelegate.showMainWindow()
            #endif
        case "dismiss": if incoming?.id == id { incoming = nil }
        case "transfer":
            rows.insert(TransferRow(id:id,name:value["name"] as? String ?? "",size:(value["size"] as? NSNumber)?.int64Value ?? 0,direction:value["direction"] as? String ?? "send",paths:value["paths"] as? [String]),at:0)
            sortRows()
            trimRowsIfNeeded()
        case "progress":
            if let index = rows.firstIndex(where:{$0.id == id}), !rows[index].finished { rows[index].bytes = (value["bytes"] as? NSNumber)?.int64Value ?? 0 }
        case "sent", "received":
            if type == "sent" { outgoingDrafts.removeValue(forKey:id) }
            if let index = rows.firstIndex(where:{$0.id == id}) {
                rows[index].finished = true; rows[index].bytes = rows[index].size
                rows[index].state = type == "sent" ? "已发送":"已接收"
                rows[index].path = value["path"] as? String
                saveHistory()
            }
            if type == "received" { onReceive?(value["name"] as? String ?? "",nil) }
        case "text":
            rows.insert(TransferRow(id:id,name:value["alias"] as? String ?? "文字",size:0,direction:"receive",state:"已接收",text:value["text"] as? String,finished:true),at:0)
            sortRows()
            trimRowsIfNeeded()
            saveHistory()
            onReceive?(value["alias"] as? String ?? "",value["text"] as? String ?? "")
        case "failed", "cancelled":
            if let draft=outgoingDrafts.removeValue(forKey:id),text.isEmpty,attachments.isEmpty { text=draft.0;attachments=draft.1 }
            if let index = rows.firstIndex(where:{$0.id == id}) { rows[index].finished = true; rows[index].state = value["message"] as? String ?? "已取消" }
            if type == "failed" { error = value["message"] as? String }
        case "error": error = value["message"] as? String
        default: break
        }
        #if DEBUG
        verification.event(value)
        #endif
    }
    #if os(iOS)
    private static func defaultDeviceAlias() -> String {
        let systemName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let genericModel = UIDevice.current.model
        // 若应用已获得 user-assigned-device-name 权限，UIDevice.current.name 会直接返回用户自定义名称
        if !systemName.isEmpty && systemName != genericModel {
            return systemName
        }
        return hardwareMarketingName() ?? (systemName.isEmpty ? genericModel : systemName)
    }

    private static func hardwareMarketingName() -> String? {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let table: [String: String] = [
            "iPhone18,1": "iPhone 17 Pro",
            "iPhone18,2": "iPhone 17 Pro Max",
            "iPhone18,3": "iPhone 17",
            "iPhone18,4": "iPhone Air",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,5": "iPhone 16e",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            "iPad11,3": "iPad Air",
            "iPad11,4": "iPad Air",
            "iPad13,1": "iPad Air",
            "iPad13,2": "iPad Air",
            "iPad13,16": "iPad Air",
            "iPad13,17": "iPad Air",
            "iPad14,8": "iPad Air 11\"",
            "iPad14,9": "iPad Air 11\"",
            "iPad14,10": "iPad Air 13\"",
            "iPad14,11": "iPad Air 13\"",
            "iPad16,3": "iPad Pro 11\"",
            "iPad16,4": "iPad Pro 11\"",
            "iPad16,5": "iPad Pro 13\"",
            "iPad16,6": "iPad Pro 13\"",
        ]
        return table[identifier]
    }
    #endif
    private func saveHistory() {
        do { try JSONEncoder().encode(rows.filter(\.finished)).write(to:root.appendingPathComponent("history.json"),options:.atomic) }
        catch { self.error = "保存接收记录失败：\(error.localizedDescription)" }
    }
}

