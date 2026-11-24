import SwiftUI
import UniformTypeIdentifiers
import QuickLook
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import PhotosUI
import UIKit
#endif

struct ContentView: View {
    @ObservedObject var service: TransferService
    var shareMode = false
    @State private var importing = false
    @State private var showTextComposer = false
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
                }
                .padding(.horizontal,16)
                .padding(.top,10)
                .padding(.bottom,4)

                List(service.rows) { row in
                    TransferRowView(row:row,service:service)
                        .listRowInsets(EdgeInsets(top:6,leading:16,bottom:6,trailing:16))
                }
                .listStyle(.plain)
                .ignoresSafeArea(.keyboard,edges:.bottom)
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
        VStack(alignment:.leading,spacing:0) {
            // 常驻轻量输入容器，平滑插值高度与透明度，避免首次挂载 TextField 卡顿
            VStack(alignment:.leading,spacing:8) {
                TextField("输入要发送的文字…",text:$service.text,axis:.vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.plain)
                    .focused($textFocused)
                    .accessibilityLabel("发送文字")
                HStack(spacing:10) {
                    Button { pasteText() } label: {
                        Label("粘贴",systemImage:"doc.on.clipboard")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal,10)
                            .padding(.vertical,5)
                            .background(Color.secondary.opacity(0.14),in:Capsule())
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
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
            .frame(height:showTextComposer ? nil : 0,alignment:.top)
            .opacity(showTextComposer ? 1 : 0)
            .clipped()
            .allowsHitTesting(showTextComposer)
            .padding(.bottom,showTextComposer ? 10 : 0)

            if !service.attachments.isEmpty {
                FileStrip(urls:service.attachments,service:service,removable:true)
                    .padding(.bottom,10)
            }

            if service.importingPhotos {
                HStack(spacing:8) {
                    ProgressView().controlSize(.small)
                    Text(service.pendingAutoSend ? "正在准备原图，完成后自动发送…" : "正在读取原图（剩余 \(max(1, service.importingPhotoCount)) 张）…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom,10)
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
                    .transition(.opacity.combined(with:.scale(scale:0.92)))
                }
            }
        }
        .padding(.horizontal,14)
        .padding(.vertical,12)
    }

    private func pasteText() {
        #if os(iOS)
        if let pasted = UIPasteboard.general.string, !pasted.isEmpty {
            service.text = pasted
        }
        #else
        service.paste()
        #endif
    }

    private func toggleTextComposer() {
        if showTextComposer {
            closeTextComposer()
        } else {
            openTextComposer(focus:true)
        }
    }

    private func openTextComposer(focus: Bool) {
        withAnimation(.spring(response:0.32,dampingFraction:0.9)) {
            showTextComposer = true
        }
        if focus {
            textFocused = true
        }
    }

    private func closeTextComposer() {
        textFocused = false
        withAnimation(.spring(response:0.28,dampingFraction:0.92)) {
            showTextComposer = false
        }
    }
}

struct TransferRowView: View {
    let row: TransferRow
    @ObservedObject var service: TransferService
    @State private var existingFileURLs: [URL] = []
    @State private var checkedFiles = false
    @State private var copiedFeedback = false

    private var isInteractive: Bool {
        row.text != nil || !existingFileURLs.isEmpty
    }

    private var directionIcon: String {
        row.direction == "send" ? "arrow.up.right" : "arrow.down.left"
    }

    private var directionColor: Color {
        if row.text != nil { return .purple }
        return row.direction == "send" ? .accentColor : .green
    }

    private var subtitleText: String {
        var parts = [copiedFeedback ? "已复制到剪贴板" : row.state]
        if row.size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount:row.size,countStyle:.file))
        }
        return parts.joined(separator:" · ")
    }

    var body: some View {
        HStack(alignment:.center,spacing:12) {
            leadingThumbnail

            VStack(alignment:.leading,spacing:4) {
                HStack(alignment:.firstTextBaseline,spacing:6) {
                    Text(row.text ?? row.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(row.text != nil ? 2 : 1)
                    Spacer(minLength:4)
                    Text(row.started,style:.time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !row.finished {
                    ProgressView(value:row.progress)
                        .padding(.vertical,1)
                }

                HStack(spacing:4) {
                    Image(systemName:directionIcon)
                        .font(.system(size:10,weight:.bold))
                        .foregroundStyle(directionColor)
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(copiedFeedback ? Color.accentColor : Color.secondary)
                        .lineLimit(1)
                }
            }

            if !row.finished && row.direction == "send" {
                Button { service.command(["action":"cancel","id":row.id]) } label: {
                    Image(systemName:"xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width:30,height:30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消传输")
            }
        }
        .padding(.vertical,2)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .contextMenu {
            if let text = row.text {
                Button {
                    copyWithFeedback(text)
                } label: {
                    Label("复制文字",systemImage:"doc.on.doc")
                }
            } else if let url = existingFileURLs.first {
                Button {
                    service.preview = url
                } label: {
                    Label("预览",systemImage:"eye")
                }
                ShareLink(item:url) {
                    Label("分享",systemImage:"square.and.arrow.up")
                }
                #if os(macOS)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("在访达显示",systemImage:"folder")
                }
                #endif
            }
        }
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

    @ViewBuilder
    private var leadingThumbnail: some View {
        ZStack(alignment:.bottomTrailing) {
            if let firstURL = existingFileURLs.first {
                FileThumbnail(url:firstURL)
                    .frame(width:52,height:52)
                    .background(Color.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:10))
                    .clipShape(RoundedRectangle(cornerRadius:10))
                    .overlay(RoundedRectangle(cornerRadius:10).stroke(.primary.opacity(0.06),lineWidth:0.5))
            } else if row.text != nil {
                Image(systemName:"text.bubble.fill")
                    .font(.title3)
                    .foregroundStyle(.purple)
                    .frame(width:52,height:52)
                    .background(Color.purple.opacity(0.11),in:RoundedRectangle(cornerRadius:10))
            } else {
                Image(systemName:row.fileURLs.isEmpty ? directionIcon : "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width:52,height:52)
                    .background(Color.secondary.opacity(0.1),in:RoundedRectangle(cornerRadius:10))
            }

            if existingFileURLs.count > 1 {
                Text("\(existingFileURLs.count)")
                    .font(.system(size:10,weight:.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal,5)
                    .padding(.vertical,1.5)
                    .background(.black.opacity(0.65),in:Capsule())
                    .padding(3)
            }
        }
    }

    private func handleTap() {
        if let text = row.text {
            copyWithFeedback(text)
        } else if let url = existingFileURLs.first {
            service.preview = url
        }
    }

    private func copyWithFeedback(_ text: String) {
        service.copy(text)
        withAnimation(.easeInOut(duration:0.15)) {
            copiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+1.5) {
            withAnimation(.easeInOut(duration:0.2)) {
                copiedFeedback = false
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
    @State private var showClearCacheConfirm = false
    @State private var initialAlias = ""
    @State private var initialPort: UInt16 = 53317
    private let presetDays = [3, 7, 30, 365]

    private var retentionDaysBinding: Binding<Double> {
        Binding(
            get: { Double(service.settings.cacheRetentionDays) },
            set: { service.settings.cacheRetentionDays = Settings.clampedRetentionDays(Int($0.rounded())) }
        )
    }

    private var connectionChanged: Bool {
        service.settings.alias != initialAlias || service.settings.port != initialPort
    }

    var body:some View {
        NavigationStack {
            Form {
                Section("本机信息") {
                    LabeledContent("设备名称") {
                        TextField("例如：我的 iPhone",text:$service.settings.alias)
                            .multilineTextAlignment(.trailing)
                    }
                    if connectionChanged {
                        Button("应用更改并重新连接") {
                            saveAndDismiss(forceRestart:true)
                        }
                        .frame(maxWidth:.infinity,alignment:.center)
                    }
                }
                Section("发送缓存") {
                    VStack(alignment:.leading,spacing:12) {
                        HStack {
                            Text("自动保留时间")
                            Spacer()
                            Text("\(service.settings.cacheRetentionDays) 天")
                                .font(.body.weight(.medium))
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
                                let selected = service.settings.cacheRetentionDays == days
                                Button {
                                    service.settings.cacheRetentionDays = days
                                } label: {
                                    Text("\(days)天")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                        .frame(maxWidth:.infinity)
                                        .padding(.vertical,6)
                                        .background(
                                            selected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.1),
                                            in:Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical,4)

                    HStack {
                        VStack(alignment:.leading,spacing:2) {
                            Text("当前缓存")
                            Text("\(service.cacheItemCount) 项 · \(ByteCountFormatter.string(fromByteCount:service.cacheSizeBytes,countStyle:.file))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("立即清理",role:.destructive) {
                            showClearCacheConfirm = true
                        }
                        .buttonStyle(.borderless)
                        .disabled(service.cacheItemCount == 0)
                    }
                }
            }
            .navigationTitle("设置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement:.confirmationAction) {
                    Button("完成") {
                        saveAndDismiss(forceRestart:false)
                    }
                }
            }
            .alert("清除发送缓存？",isPresented:$showClearCacheConfirm) {
                Button("取消",role:.cancel) {}
                Button("清除缓存和记录",role:.destructive) {
                    service.clearOutboxCacheNow()
                }
            } message: {
                Text("清除缓存会同时删除对应的发送历史记录，且无法恢复。")
            }
            .onAppear {
                initialAlias = service.settings.alias
                initialPort = service.settings.port
                service.refreshCacheStats()
            }
        }.frame(minWidth:340,minHeight:360)
    }

    private func saveAndDismiss(forceRestart: Bool) {
        service.settings.cacheRetentionDays = Settings.clampedRetentionDays(service.settings.cacheRetentionDays)
        service.saveSettings()
        service.cleanExpiredOutbox()
        if forceRestart || connectionChanged {
            service.restart()
        }
        dismiss()
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
