import SwiftUI
import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class TransferService: ObservableObject {
    static let shared = TransferService()
    static let group = "group.com.chongyang.quicktransfer"
    @Published var peers: [Peer] = []
    @Published var selected: String? { didSet { settings.lastPeer = selected; saveSettings() } }
    @Published var text = ""
    @Published var attachments: [URL] = []
    @Published var rows: [TransferRow] = []
    @Published var incoming: Incoming?
    @Published var error: String?
    @Published var ready = false
    @Published var settings: Settings
    @Published var showSettings = false
    @Published var showAddress = false
    @Published var preview: URL?
    let root: URL
    private var timer: Timer?
    private var bonjour: BonjourDiscovery?
    private var hasStarted = false
    private var outgoingDrafts: [String:(String,[URL])] = [:]
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
    func send() {
        guard ready, let selected, peers.contains(where:{$0.id == selected}) else { error = "请选择在线设备"; return }
        guard !text.isEmpty || !attachments.isEmpty else { error = "请选择文件或输入文字"; return }
        let id=UUID().uuidString
        outgoingDrafts[id]=(text,attachments)
        var value: [String:Any] = ["action":"send","peer":selected,"id":id,"paths":attachments.map(\.path)]
        if !text.isEmpty { value["text"] = text }
        command(value)
        text = ""; attachments = []
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
            if rows.count > 30 { rows.removeLast(rows.count - 30) }
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
        case "text":
            rows.insert(TransferRow(id:id,name:value["alias"] as? String ?? "文字",size:0,direction:"receive",state:"已接收",text:value["text"] as? String,finished:true),at:0)
            saveHistory()
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

