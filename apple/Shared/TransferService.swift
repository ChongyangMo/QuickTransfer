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
    @Published var selected: String? { didSet { settings.lastPeer = selected; saveSettings() } }
    @Published var text = ""
    @Published var attachments: [URL] = []
    @Published private(set) var importingPhotos = false
    @Published private(set) var importingPhotoCount = 0
    @Published private(set) var pendingAutoSend = false
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
        let alias = UIDevice.current.name
        #endif
        let config = root.appendingPathComponent("settings.json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: config.path) {
                settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: config))
            } else { settings = Settings(alias: alias) }
        } catch {
            settings = Settings(alias: alias)
            self.error = "配置读取失败：\(error.localizedDescription)"
        }
        selected = settings.lastPeer
        let history = root.appendingPathComponent("history.json")
        if FileManager.default.fileExists(atPath: history.path) {
            do {
                rows = try JSONDecoder().decode([TransferRow].self, from: Data(contentsOf: history))
                #if os(iOS)
                for index in rows.indices {
                    if let path=rows[index].path,path.hasPrefix(previous.path+"/") { rows[index].path=location.path+path.dropFirst(previous.path.count) }
                }
                #endif
            }
            catch { self.error = "接收记录读取失败：\(error.localizedDescription)" }
        }
        timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer!,forMode:.common)
        pruneUnusedOutbox()
    }
    func start(portOverride: UInt16? = nil) {
        guard !hasStarted else { return }
        guard error == nil else { return }
        hasStarted = true
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
        bonjour?.stop(); bonjour = nil
        qt_stop(); ready = false; hasStarted = false; peers = []
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
    private func pruneUnusedOutbox() {
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
        rows.forEach { $0.fileURLs.forEach(collect) }
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let entries = try? fm.contentsOfDirectory(at: outboxRoot, includingPropertiesForKeys: nil) else { return }
            for entry in entries {
                if !keptFolders.contains(entry.lastPathComponent) {
                    try? fm.removeItem(at: entry)
                }
            }
        }
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
                if selected == nil, peers.count == 1 { selected = peers[0].id }
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
            if rows.count > 30 {
                rows.removeLast(rows.count - 30)
                pruneUnusedOutbox()
            }
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
    private func saveHistory() {
        do { try JSONEncoder().encode(rows.filter(\.finished)).write(to:root.appendingPathComponent("history.json"),options:.atomic) }
        catch { self.error = "保存接收记录失败：\(error.localizedDescription)" }
    }
}

