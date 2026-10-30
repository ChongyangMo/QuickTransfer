import SwiftUI
import UniformTypeIdentifiers
import QuickLook
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import PhotosUI
#endif

struct ContentView: View {
    @ObservedObject var service: TransferService
    var shareMode = false
    @State private var importing = false
    #if os(iOS)
    @State private var photos: [PhotosPickerItem] = []
    #endif
    var body: some View {
        VStack(spacing:0) {
            if let error = service.error {
                HStack(alignment:.top) {
                    Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    Spacer(minLength:8)
                    Button { service.error=nil } label: { Image(systemName:"xmark") }.buttonStyle(.plain).accessibilityLabel("关闭错误")
                }.padding(12)
                Divider()
            }
            List {
                if service.peers.isEmpty {
                    HStack { Spacer(); Text(service.ready ? "未发现设备":"正在连接").foregroundStyle(.secondary); Spacer() }.padding(.vertical,24)
                }
                ForEach(service.peers) { peer in
                    Button { service.selected=peer.id } label: {
                        HStack(spacing:12) {
                            Image(systemName:peer.mobile ? "iphone":"desktopcomputer").font(.title2).frame(width:30)
                            Text(peer.alias).foregroundStyle(.primary).lineLimit(1)
                            Spacer()
                            if peer.trusted { Image(systemName:"lock.fill").font(.caption).foregroundStyle(.secondary).accessibilityLabel("已记住") }
                            if service.selected==peer.id { Image(systemName:"checkmark.circle.fill").foregroundStyle(.tint) }
                        }.frame(minHeight:38).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(peer.alias).accessibilityAddTraits(service.selected==peer.id ? .isSelected:[])
                }
            }.listStyle(.plain).frame(minHeight:110,maxHeight:190)
            Divider()
            VStack(alignment:.leading,spacing:12) {
                TextField("输入文字",text:$service.text,axis:.vertical).lineLimit(2...5).textFieldStyle(.plain).accessibilityLabel("发送文字")
                if !service.attachments.isEmpty {
                    FileStrip(urls:service.attachments,service:service,removable:true)
                }
                HStack(spacing:16) {
                    Button { importing=true } label:{ Label("文件",systemImage:"paperclip") }.buttonStyle(.borderless)
                    #if os(iOS)
                    if !shareMode {
                        PhotosPicker(selection:$photos,maxSelectionCount:100,matching:.images,preferredItemEncoding:.current) { Label("照片",systemImage:"photo") }.buttonStyle(.borderless)
                        PasteButton(payloadType:String.self) { strings in service.text=strings.joined(separator:"\n") }.labelStyle(.iconOnly).accessibilityLabel("粘贴文字")
                    }
                    #else
                    Button { service.paste() } label:{ Label("粘贴",systemImage:"doc.on.clipboard") }.buttonStyle(.borderless).keyboardShortcut("v",modifiers:.command)
                    #endif
                    Spacer(minLength:0)
                    Button("发送") { service.send() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!service.ready || service.selected==nil || (service.text.isEmpty && service.attachments.isEmpty)).keyboardShortcut(.return,modifiers:.command)
                }
            }.padding(16)
            if !shareMode && !service.rows.isEmpty {
                Divider()
                List(service.rows) { row in TransferRowView(row:row,service:service) }.listStyle(.plain)
            } else if !service.rows.isEmpty {
                ForEach(service.rows.filter{!$0.finished}.prefix(1)) { row in TransferRowView(row:row,service:service).padding(.horizontal) }
            }
        }
        .navigationTitle("快传")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement:.primaryAction) {
                Button { service.refresh() } label:{ Image(systemName:"arrow.clockwise") }.help("刷新设备").accessibilityLabel("刷新设备")
                Button { service.showAddress=true } label:{ Image(systemName:"plus") }.help("添加设备").accessibilityLabel("添加设备")
                if !shareMode { Button { service.showSettings=true } label:{ Image(systemName:"gearshape") }.help("设置").accessibilityLabel("设置") }
            }
        }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.item],allowsMultipleSelection:true) { result in
            switch result { case .success(let urls):service.stage(urls);case .failure(let error):service.error="选择文件失败：\(error.localizedDescription)" }
        }
        .sheet(item:$service.incoming) { incoming in ReceiveSheet(incoming:incoming,service:service) }
        .sheet(isPresented:$service.showSettings) { SettingsView(service:service) }
        .sheet(isPresented:$service.showAddress) { AddressView(service:service) }
        .quickLookPreview($service.preview)
        .onDrop(of:[UTType.fileURL,UTType.image],isTargeted:nil) { service.importDropped($0) }
        #if os(macOS)
        .frame(minWidth:370,minHeight:420)
        #else
        .onChange(of:photos) { _,items in
            Task {
                do {
                    for item in items {
                        guard let photo = try await item.loadTransferable(type:ImportedPhoto.self) else { throw CocoaError(.fileReadUnknown) }
                        service.attachments.append(photo.url)
                    }
                    photos=[]
                } catch { service.error="读取照片失败：\(error.localizedDescription)" }
            }
        }
        #endif
    }
}

struct TransferRowView: View {
    let row: TransferRow
    @ObservedObject var service: TransferService
    var body: some View {
        HStack(alignment:.top,spacing:10) {
            Image(systemName:row.text != nil ? "text.bubble":row.direction=="send" ? "arrow.up.right":"arrow.down.left").foregroundStyle(.secondary).padding(.top,3)
            VStack(alignment:.leading,spacing:5) {
                Text(row.text ?? row.name).lineLimit(row.text != nil ? 4:1).textSelection(.enabled)
                if !row.finished { ProgressView(value:row.progress) }
                Text(row.state).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if !row.fileURLs.isEmpty { FileStrip(urls:row.fileURLs,service:service) }
            }
            Spacer(minLength:6)
            if let text=row.text {
                Button { service.copy(text) } label:{ Image(systemName:"doc.on.doc").frame(minWidth:44,minHeight:44) }.buttonStyle(.borderless).accessibilityLabel("复制文字")
            } else if let url=row.fileURLs.first {
                Button { service.preview=url } label:{ Image(systemName:"eye").frame(minWidth:44,minHeight:44) }.buttonStyle(.borderless).accessibilityLabel("预览")
                ShareLink(item:url) { Image(systemName:"square.and.arrow.up").frame(minWidth:44,minHeight:44) }.buttonStyle(.borderless).accessibilityIdentifier("share-received-file")
                #if os(macOS)
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label:{ Image(systemName:"folder") }.buttonStyle(.borderless).accessibilityLabel("在访达显示")
                #endif
            }
            if !row.finished && row.direction=="send" {
                Button { service.command(["action":"cancel","id":row.id]) } label:{ Image(systemName:"xmark.circle") }.buttonStyle(.borderless).accessibilityLabel("取消传输")
            }
        }.padding(.vertical,6)
    }
}

struct ReceiveSheet: View {
    let incoming: Incoming
    @ObservedObject var service:TransferService
    @State private var remember=false
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            Text(incoming.alias).font(.title3.bold())
            Text(incoming.text.map{String($0.prefix(250))} ?? "\(incoming.count) 个文件 · \(ByteCountFormatter.string(fromByteCount:incoming.size,countStyle:.file))").lineLimit(6)
            Toggle("记住此设备，自动接收",isOn:$remember)
            HStack { Button("拒绝",role:.cancel) { service.answer(accept:false,remember:false) };Spacer();Button("接收") { service.answer(accept:true,remember:remember) }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(minWidth:300).interactiveDismissDisabled()
    }
}

struct SettingsView:View {
    @ObservedObject var service:TransferService
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            Form {
                TextField("设备名称",text:$service.settings.alias)
                TextField("端口",value:$service.settings.port,format:.number.grouping(.never))
                Button("保存并重新连接") { service.saveSettings();service.restart();dismiss() }
            }.padding().navigationTitle("设置").toolbar { Button("完成") { dismiss() } }
        }.frame(minWidth:320,minHeight:220)
    }
}
struct AddressView:View {
    @ObservedObject var service:TransferService
    @State private var host=""
    @State private var port:UInt16=53317
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            Form {
                TextField("IP 地址",text:$host).autocorrectionDisabled()
                TextField("端口",value:$port,format:.number.grouping(.never))
                Button("连接") { service.command(["action":"probe","host":host.trimmingCharacters(in:.whitespaces),"port":port]);dismiss() }.disabled(host.trimmingCharacters(in:.whitespaces).isEmpty)
            }.padding().navigationTitle("添加设备").toolbar { Button("取消") { dismiss() } }
        }.frame(minWidth:320,minHeight:220)
    }
}

#if os(iOS)
struct ImportedPhoto: Transferable {
    let url:URL
    static var transferRepresentation:some TransferRepresentation {
        FileRepresentation(importedContentType:.image) { file in
            guard let container=FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:TransferService.group) else { throw CocoaError(.fileNoSuchFile) }
            let url=try TransferService.copyToOutbox(file.file,root:container.appendingPathComponent("Library/Application Support/QuickTransfer"))
            return ImportedPhoto(url:url)
        }
    }
}
#endif
