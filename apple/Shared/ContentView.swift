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
    @State private var showTextComposer = false
    @State private var pasteControlReady = false
    @FocusState private var textFocused: Bool
    #if os(iOS)
    @State private var photos: [PhotosPickerItem] = []
    @State private var showFastPhotoPicker = false
    @State private var showSystemPhotoPicker = false
    #endif

    private var hasPendingContent: Bool {
        !service.text.isEmpty || !service.attachments.isEmpty || service.importingPhotos
    }

    var body: some View {
        VStack(spacing:0) {
            if let error = service.error {
                HStack(alignment:.top,spacing:8) {
                    Image(systemName:"exclamationmark.circle.fill").foregroundStyle(.red).padding(.top,2)
                    Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    Spacer(minLength:8)
                    Button { service.error=nil } label: { Image(systemName:"xmark").font(.caption.bold()).foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("关闭错误")
                }
                .padding(.horizontal,16)
                .padding(.vertical,10)
                .background(Color.red.opacity(0.08))
                Divider()
            }

            deviceSection

            Divider()

            composerSection

            if !shareMode && !service.rows.isEmpty {
                Divider()
                HStack {
                    Text("传输记录")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(service.rows.count) 条")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal,16)
                .padding(.top,10)
                .padding(.bottom,4)

                List(service.rows) { row in
                    TransferRowView(row:row,service:service)
                        .listRowInsets(EdgeInsets(top:4,leading:16,bottom:4,trailing:16))
                }
                .listStyle(.plain)
            } else if !service.rows.isEmpty {
                Divider()
                ForEach(service.rows.filter{!$0.finished}.prefix(1)) { row in
                    TransferRowView(row:row,service:service).padding(.horizontal,16)
                }
            } else {
                Spacer(minLength:0)
            }
        }
        .navigationTitle("快传")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement:.primaryAction) {
                Button { toggleTextComposer() } label: {
                    Image(systemName:"character.zh")
                        .foregroundStyle((showTextComposer || !service.text.isEmpty) ? Color.accentColor : Color.primary)
                }
                .help(showTextComposer ? "收起文字输入" : "输入文字")
                .accessibilityLabel("输入文字")

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
        .onAppear {
            if !service.text.isEmpty {
                showTextComposer = true
                pasteControlReady = true
            }
        }
        .onChange(of:service.text) { oldValue,value in
            if oldValue.isEmpty && !value.isEmpty && !showTextComposer {
                openTextComposer(focus:false)
            }
        }
        #if os(macOS)
        .frame(minWidth:370,minHeight:420)
        #else
        .sheet(isPresented:$showFastPhotoPicker) {
            FastPhotoPickerSheet(service:service) {
                DispatchQueue.main.asyncAfter(deadline:.now()+0.35) {
                    showSystemPhotoPicker=true
                }
            }
            .presentationDetents([.fraction(0.64)])
            .presentationContentInteraction(.scrolls)
            .presentationBackgroundInteraction(.enabled(upThrough:.fraction(0.64)))
        }
        .photosPicker(isPresented:$showSystemPhotoPicker,selection:$photos,maxSelectionCount:100,matching:.images,preferredItemEncoding:.current,photoLibrary:.shared())
        .onChange(of:photos) { _,items in
            guard !items.isEmpty else { return }
            photos=[]
            service.stagePhotos(items)
        }
        #endif
    }

    @ViewBuilder
    private var deviceSection: some View {
        if service.peers.isEmpty {
            HStack(spacing:8) {
                Spacer()
                if !service.ready { ProgressView().controlSize(.small) }
                Text(service.ready ? "未发现附近设备" : "正在连接…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical,20)
        } else {
            let listContent = VStack(spacing:6) {
                ForEach(service.peers) { peer in
                    let isSelected = service.selected == peer.id
                    Button { service.selected = peer.id } label: {
                        HStack(spacing:12) {
                            Image(systemName:peer.mobile ? "iphone":"desktopcomputer")
                                .font(.title3)
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                .frame(width:28)
                            Text(peer.alias)
                                .font(.body.weight(isSelected ? .medium : .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            if peer.trusted {
                                Image(systemName:"lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("已记住")
                            }
                            if isSelected {
                                Image(systemName:"checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(.horizontal,12)
                        .padding(.vertical,10)
                        .background(
                            RoundedRectangle(cornerRadius:12)
                                .fill(isSelected ? Color.accentColor.opacity(0.11) : Color.secondary.opacity(0.06))
                        )
                        .contentShape(RoundedRectangle(cornerRadius:12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(peer.alias)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal,14)
            .padding(.vertical,10)

            if service.peers.count > 3 {
                ScrollView { listContent }
                    .frame(maxHeight:184)
            } else {
                listContent
            }
        }
    }

    private var composerSection: some View {
        VStack(alignment:.leading,spacing:10) {
            if showTextComposer {
                VStack(alignment:.leading,spacing:8) {
                    TextField("输入要发送的文字…",text:$service.text,axis:.vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.plain)
                        .focused($textFocused)
                        .accessibilityLabel("发送文字")
                    HStack(spacing:10) {
                        #if os(iOS)
                        ZStack(alignment:.leading) {
                            if pasteControlReady {
                                PasteButton(payloadType:String.self) { strings in
                                    let pasted = strings.joined(separator:"\n")
                                    if !pasted.isEmpty { service.text = pasted }
                                }
                                .labelStyle(.titleAndIcon)
                                .buttonBorderShape(.capsule)
                                .controlSize(.small)
                                .transition(.opacity)
                            }
                        }
                        .frame(minHeight:28)
                        #else
                        Button { service.paste() } label: {
                            Label("粘贴",systemImage:"doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .keyboardShortcut("v",modifiers:.command)
                        #endif
                        if !service.text.isEmpty {
                            Button("清空") { service.text = "" }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .buttonStyle(.plain)
                        }
                        Spacer()
                        Button { closeTextComposer() } label: {
                            Text("收起")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
                .transition(.opacity)
            }

            if !service.attachments.isEmpty {
                FileStrip(urls:service.attachments,service:service,removable:true)
            }

            if service.importingPhotos {
                HStack(spacing:8) {
                    ProgressView().controlSize(.small)
                    Text(service.pendingAutoSend ? "正在准备原图，完成后自动发送…" : "正在读取原图（剩余 \(max(1, service.importingPhotoCount)) 张）…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing:10) {
                #if os(iOS)
                if !shareMode {
                    Button { showFastPhotoPicker = true } label: {
                        Label("照片",systemImage:"photo")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal,14)
                            .padding(.vertical,9)
                            .background(Color.secondary.opacity(0.12),in:Capsule())
                    }
                    .buttonStyle(.plain)
                }
                #endif

                Button { importing = true } label: {
                    Label("文件",systemImage:"paperclip")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal,14)
                        .padding(.vertical,9)
                        .background(Color.secondary.opacity(0.12),in:Capsule())
                }
                .buttonStyle(.plain)

                #if os(macOS)
                Button { service.paste() } label: {
                    Label("粘贴",systemImage:"doc.on.clipboard")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal,12)
                        .padding(.vertical,9)
                        .background(Color.secondary.opacity(0.12),in:Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("v",modifiers:.command)
                #endif

                Spacer(minLength:0)

                if hasPendingContent || showTextComposer {
                    Button(service.pendingAutoSend ? "等待发送" : "发送") {
                        textFocused = false
                        service.send()
                        if service.text.isEmpty { closeTextComposer() }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)
                    .disabled(!service.canSendToSelectedPeer || service.pendingAutoSend || (!service.importingPhotos && service.text.isEmpty && service.attachments.isEmpty))
                    .keyboardShortcut(.return,modifiers:.command)
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal,14)
        .padding(.vertical,12)
        .clipped()
    }

    private func toggleTextComposer() {
        if showTextComposer {
            closeTextComposer()
        } else {
            openTextComposer(focus:true)
        }
    }

    private func openTextComposer(focus: Bool) {
        pasteControlReady = false
        withAnimation(.snappy(duration:0.24,extraBounce:0)) {
            showTextComposer = true
        }
        if focus {
            Task { @MainActor in
                textFocused = true
            }
        }
        // 延后挂载跨进程 PasteButton，避免首帧 XPC 初始化拖卡展开动画
        DispatchQueue.main.asyncAfter(deadline:.now()+0.22) {
            guard showTextComposer else { return }
            withAnimation(.easeIn(duration:0.12)) {
                pasteControlReady = true
            }
        }
    }

    private func closeTextComposer() {
        textFocused = false
        pasteControlReady = false
        withAnimation(.snappy(duration:0.22,extraBounce:0)) {
            showTextComposer = false
        }
    }
}

struct TransferRowView: View {
    let row: TransferRow
    @ObservedObject var service: TransferService
    @State private var existingFileURLs: [URL] = []
    @State private var checkedFiles = false

    private var iconName: String {
        if row.text != nil { return "text.bubble.fill" }
        return row.direction == "send" ? "arrow.up.right" : "arrow.down.left"
    }

    private var iconColor: Color {
        if row.text != nil { return .purple }
        return row.direction == "send" ? .accentColor : .green
    }

    private var subtitleText: String {
        var parts = [row.state]
        if row.size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount:row.size,countStyle:.file))
        }
        if checkedFiles && row.text == nil && !row.fileURLs.isEmpty && existingFileURLs.isEmpty && row.finished {
            parts.append("缓存已清理")
        }
        return parts.joined(separator:" · ")
    }

    var body: some View {
        HStack(alignment:.top,spacing:10) {
            Image(systemName:iconName)
                .font(.caption.bold())
                .foregroundStyle(iconColor)
                .frame(width:28,height:28)
                .background(iconColor.opacity(0.12),in:Circle())
                .padding(.top,2)

            VStack(alignment:.leading,spacing:5) {
                HStack(alignment:.firstTextBaseline,spacing:6) {
                    Text(row.text ?? row.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(row.text != nil ? 4 : 1)
                        .textSelection(.enabled)
                    Spacer(minLength:4)
                    Text(row.started,style:.time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !row.finished { ProgressView(value:row.progress) }
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !existingFileURLs.isEmpty {
                    FileStrip(urls:existingFileURLs,service:service)
                        .padding(.top,2)
                }
            }

            if let text = row.text {
                Button { service.copy(text) } label: {
                    Image(systemName:"doc.on.doc")
                        .font(.subheadline)
                        .frame(width:34,height:34)
                        .background(Color.secondary.opacity(0.1),in:Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制文字")
            } else if let url = existingFileURLs.first {
                HStack(spacing:6) {
                    Button { service.preview = url } label: {
                        Image(systemName:"eye")
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                            .frame(width:34,height:34)
                            .background(Color.accentColor.opacity(0.1),in:Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("预览")

                    ShareLink(item:url) {
                        Image(systemName:"square.and.arrow.up")
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                            .frame(width:34,height:34)
                            .background(Color.accentColor.opacity(0.1),in:Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("share-received-file")

                    #if os(macOS)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                        Image(systemName:"folder")
                            .font(.subheadline)
                            .frame(width:34,height:34)
                            .background(Color.secondary.opacity(0.1),in:Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("在访达显示")
                    #endif
                }
            }
            if !row.finished && row.direction == "send" {
                Button { service.command(["action":"cancel","id":row.id]) } label: {
                    Image(systemName:"xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width:32,height:32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消传输")
            }
        }
        .padding(.vertical,6)
        .task(id:"\(row.id)-\(row.finished)-\(service.cacheItemCount)") {
            let candidates = row.fileURLs
            guard !candidates.isEmpty else {
                existingFileURLs = []
                checkedFiles = true
                return
            }
            let alive = await Task.detached(priority:.utility) {
                candidates.filter { FileManager.default.fileExists(atPath:$0.path) }
            }.value
            if !Task.isCancelled {
                existingFileURLs = alive
                checkedFiles = true
            }
        }
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
    private let presetDays = [3, 7, 30, 365]

    private var retentionDaysBinding: Binding<Double> {
        Binding(
            get: { Double(service.settings.cacheRetentionDays) },
            set: { service.settings.cacheRetentionDays = Settings.clampedRetentionDays(Int($0.rounded())) }
        )
    }

    var body:some View {
        NavigationStack {
            Form {
                Section("设备连接") {
                    TextField("设备名称",text:$service.settings.alias)
                    TextField("端口",value:$service.settings.port,format:.number.grouping(.never))
                    Button("保存并重新连接") {
                        service.settings.cacheRetentionDays = Settings.clampedRetentionDays(service.settings.cacheRetentionDays)
                        service.saveSettings()
                        service.cleanExpiredOutbox()
                        service.restart()
                        dismiss()
                    }
                }
                Section("发送缓存清理") {
                    VStack(alignment:.leading,spacing:10) {
                        HStack {
                            Text("缓存保留时间")
                            Spacer()
                            Text("\(service.settings.cacheRetentionDays) 天")
                                .foregroundStyle(.tint)
                                .monospacedDigit()
                        }
                        Slider(
                            value:retentionDaysBinding,
                            in:Double(Settings.minCacheRetentionDays)...Double(Settings.maxCacheRetentionDays),
                            step:1
                        )
                        HStack(spacing:8) {
                            ForEach(presetDays, id:\.self) { days in
                                Button("\(days)天") {
                                    service.settings.cacheRetentionDays = days
                                }
                                .buttonStyle(.bordered)
                                .tint(service.settings.cacheRetentionDays == days ? .accentColor : .secondary)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.vertical,4)
                    HStack {
                        Text("当前缓存：\(service.cacheItemCount) 项 · \(ByteCountFormatter.string(fromByteCount:service.cacheSizeBytes,countStyle:.file))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("立即清理",role:.destructive) {
                            service.clearOutboxCacheNow()
                        }
                        .buttonStyle(.borderless)
                        .disabled(service.cacheItemCount == 0)
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                Button("完成") {
                    service.settings.cacheRetentionDays = Settings.clampedRetentionDays(service.settings.cacheRetentionDays)
                    service.saveSettings()
                    service.cleanExpiredOutbox()
                    dismiss()
                }
            }
            .onAppear { service.refreshCacheStats() }
        }.frame(minWidth:340,minHeight:360)
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
