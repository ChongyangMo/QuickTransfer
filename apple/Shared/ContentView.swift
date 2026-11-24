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
    @State private var isPullRefreshingHeader = false
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
                    Button { Haptics.shared.play(.tap); service.error=nil } label: { Image(systemName:"xmark").font(.caption.bold()).foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("关闭错误")
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
                        .swipeActions(edge:.leading,allowsFullSwipe:true) {
                            Button {
                                Haptics.shared.play(.pin)
                                withAnimation(.snappy(duration:0.25)) {
                                    service.togglePinRow(row.id)
                                }
                            } label: {
                                Label(row.pinned ? "取消置顶" : "置顶",systemImage:row.pinned ? "pin.slash.fill" : "pin.fill")
                            }
                            .tint(row.pinned ? .gray : .orange)
                        }
                        .swipeActions(edge:.trailing,allowsFullSwipe:true) {
                            Button(role:.destructive) {
                                Haptics.shared.play(.warning)
                                withAnimation(.snappy(duration:0.25)) {
                                    service.deleteRow(row.id)
                                }
                            } label: {
                                Label("删除",systemImage:"trash")
                            }
                            if let text = row.text {
                                Button {
                                    service.copy(text)
                                    Haptics.shared.play(.complete)
                                } label: {
                                    Label("复制",systemImage:"doc.on.doc")
                                }
                                .tint(.blue)
                            } else if !row.fileURLs.isEmpty {
                                Button {
                                    Haptics.shared.play(.action)
                                    service.stageExistingRowFiles(row)
                                } label: {
                                    Label("重发",systemImage:"paperplane")
                                }
                                .tint(.blue)
                            }
                        }
                }
                .listStyle(.plain)
                .refreshable { await service.pullRefresh() }
                .ignoresSafeArea(.keyboard,edges:.bottom)
            } else if !service.rows.isEmpty {
                Divider()
                ForEach(service.rows.filter{!$0.finished}.prefix(1)) { row in
                    TransferRowView(row:row,service:service).padding(.horizontal,16)
                }
            } else if !shareMode {
                ScrollView {
                    VStack(spacing:6) {
                        #if os(iOS)
                        Text("下拉刷新附近设备")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top,32)
                        #else
                        Text("暂无传输记录")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top,32)
                        #endif
                    }
                    .frame(maxWidth:.infinity)
                }
                .refreshable { await service.pullRefresh() }
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

                #if os(macOS)
                Button { service.refresh() } label: {
                    Image(systemName:"arrow.clockwise")
                }
                .help("刷新设备")
                .accessibilityLabel("刷新设备")
                .keyboardShortcut("r",modifiers:.command)
                #endif

                if shareMode {
                    Button { Haptics.shared.play(.expand); service.showAddress=true } label:{ Image(systemName:"plus") }.help("添加设备").accessibilityLabel("添加设备")
                } else {
                    Button { Haptics.shared.play(.expand); service.showSettings=true } label:{ Image(systemName:"gearshape") }.help("设置").accessibilityLabel("设置")
                }
            }
        }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.item],allowsMultipleSelection:true) { result in
            switch result { case .success(let urls):service.stage(urls);case .failure(let error):service.error="选择文件失败：\(error.localizedDescription)" }
        }
        .sheet(item:$service.incoming) { incoming in ReceiveSheet(incoming:incoming,service:service) }
        .sheet(isPresented:$service.showSettings) { SettingsView(service:service) }
        .sheet(isPresented:$service.showAddress) {
            NavigationStack {
                AddressView(service:service,isSheet:true)
            }
            .frame(minWidth:320,minHeight:260)
        }
        .quickLookPreview($service.preview)
        .onDrop(of:[UTType.fileURL,UTType.image],isTargeted:nil) { service.importDropped($0) }
        .overlay(alignment:.bottom) {
            if let toast = service.toast {
                HStack(spacing:8) {
                    Image(systemName:toast.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(toast.success ? .green : .red)
                    Text(toast.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                .padding(.horizontal,16)
                .padding(.vertical,10)
                .background(.ultraThinMaterial,in:Capsule())
                .overlay(Capsule().stroke(toast.success ? Color.green.opacity(0.28) : Color.red.opacity(0.28),lineWidth:0.8))
                .shadow(color:.black.opacity(0.12),radius:10,y:4)
                .padding(.horizontal,20)
                .padding(.bottom,18)
                .transition(.move(edge:.bottom).combined(with:.opacity))
                .onTapGesture { Haptics.shared.play(.collapse); service.dismissToast() }
            }
        }
        .animation(.snappy(duration:0.25),value:service.toast)
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
        let visiblePeers = service.displayPeers
        VStack(spacing:0) {
            if isPullRefreshingHeader {
                HStack(spacing:6) {
                    ProgressView().controlSize(.mini)
                    Text("正在刷新附近设备…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top,8)
                .transition(.opacity.combined(with:.move(edge:.top)))
            }
            if visiblePeers.isEmpty {
                HStack(spacing:8) {
                    Spacer()
                    if !service.ready { ProgressView().controlSize(.small) }
                    #if os(iOS)
                    Text(service.ready ? "未发现附近设备，下拉刷新" : "正在连接…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    #else
                    Text(service.ready ? "未发现附近设备" : "正在连接…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    #endif
                    Spacer()
                }
                .padding(.vertical,20)
            } else {
                let listContent = VStack(spacing:6) {
                    ForEach(visiblePeers) { peer in
                        let isSelected = service.selected == peer.id
                        let isOnline = service.isPeerOnline(peer.id)
                        Button {
                            if service.selected != peer.id {
                                Haptics.shared.play(.deviceSwitch)
                                service.selected = peer.id
                            } else {
                                Haptics.shared.play(.tap)
                            }
                        } label: {
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
                                        .opacity(isOnline ? 1 : 0.45)
                                }
                            }
                            .opacity(isOnline ? 1 : 0.65)
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
                .animation(.easeInOut(duration:0.2),value:visiblePeers.map(\.id))

                if visiblePeers.count > 3 {
                    ScrollView { listContent }
                        .frame(maxHeight:184)
                        .refreshable { await service.pullRefresh() }
                } else {
                    listContent
                }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance:28)
                .onEnded { value in
                    #if os(iOS)
                    guard !isPullRefreshingHeader,
                          value.translation.height > 44,
                          abs(value.translation.height) > abs(value.translation.width) * 1.4 else { return }
                    triggerHeaderPullRefresh()
                    #endif
                }
        )
        .animation(.snappy(duration:0.22),value:isPullRefreshingHeader)
    }

    private func triggerHeaderPullRefresh() {
        isPullRefreshingHeader = true
        Task {
            await service.pullRefresh()
            isPullRefreshingHeader = false
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
                        Button("清空") { Haptics.shared.play(.tap); service.text = "" }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                    }
                    Spacer()
                    Button { Haptics.shared.play(.collapse); closeTextComposer() } label: {
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
                    Button { Haptics.shared.play(.expand); showFastPhotoPicker = true } label: {
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

                Button { Haptics.shared.play(.tap); importing = true } label: {
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
            Haptics.shared.play(.tap)
        }
        #else
        service.paste()
        #endif
    }

    private func toggleTextComposer() {
        if showTextComposer {
            Haptics.shared.play(.collapse)
            closeTextComposer()
        } else {
            Haptics.shared.play(.expand)
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
                    if row.pinned {
                        Image(systemName:"pin.fill")
                            .font(.system(size:10))
                            .foregroundStyle(.orange)
                    }
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
                Button { Haptics.shared.play(.warning); service.command(["action":"cancel","id":row.id]) } label: {
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
            Button {
                Haptics.shared.play(.pin)
                withAnimation(.snappy(duration:0.25)) {
                    service.togglePinRow(row.id)
                }
            } label: {
                Label(row.pinned ? "取消置顶" : "置顶",systemImage:row.pinned ? "pin.slash" : "pin")
            }
            if let text = row.text {
                Button {
                    copyWithFeedback(text)
                } label: {
                    Label("复制文字",systemImage:"doc.on.doc")
                }
            } else if let url = existingFileURLs.first {
                Button {
                    Haptics.shared.play(.tap)
                    service.preview = url
                } label: {
                    Label("预览",systemImage:"eye")
                }
                Button {
                    Haptics.shared.play(.action)
                    service.stageExistingRowFiles(row)
                } label: {
                    Label("重新发送",systemImage:"paperplane")
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
            Divider()
            Button(role:.destructive) {
                Haptics.shared.play(.warning)
                withAnimation(.snappy(duration:0.25)) {
                    service.deleteRow(row.id)
                }
            } label: {
                Label("删除",systemImage:"trash")
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
            Haptics.shared.play(.tap)
            service.preview = url
        }
    }

    private func copyWithFeedback(_ text: String) {
        service.copy(text)
        Haptics.shared.play(.complete)
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
                .onChange(of:remember) { _,_ in Haptics.shared.play(.selection) }
            HStack { Button("拒绝",role:.cancel) { Haptics.shared.play(.warning); service.answer(accept:false,remember:false) };Spacer();Button("接收") { Haptics.shared.play(.action); service.answer(accept:true,remember:remember) }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(minWidth:300).interactiveDismissDisabled()
    }
}

struct SettingsView:View {
    @ObservedObject var service:TransferService
    @Environment(\.dismiss) private var dismiss
    @State private var showClearCacheConfirm = false
    @State private var showManualAdd = false
    @State private var initialAlias = ""
    @State private var initialPort: UInt16 = 53317
    @State private var lastSliderHapticBucket = -1
    private let presetDays = [3, 7, 30, 365]

    private var retentionDaysBinding: Binding<Double> {
        Binding(
            get: { Double(service.settings.cacheRetentionDays) },
            set: {
                let next = Settings.clampedRetentionDays(Int($0.rounded()))
                if next != service.settings.cacheRetentionDays {
                    service.settings.cacheRetentionDays = next
                    let bucket = next / 5
                    if bucket != lastSliderHapticBucket {
                        lastSliderHapticBucket = bucket
                        Haptics.shared.play(.selection)
                    }
                }
            }
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
                    Button {
                        Haptics.shared.play(.tap)
                        showManualAdd = true
                    } label: {
                        HStack {
                            Label("手动添加设备",systemImage:"network")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName:"chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
                            in:Double(Settings.minCacheRetentionDays)...Double(Settings.maxCacheRetentionDays)
                        )
                        .labelsHidden()
                        HStack(spacing:8) {
                            ForEach(presetDays, id:\.self) { days in
                                let selected = service.settings.cacheRetentionDays == days
                                Button {
                                    Haptics.shared.play(.selection)
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
                            Haptics.shared.play(.warning)
                            showClearCacheConfirm = true
                        }
                        .buttonStyle(.borderless)
                        .disabled(service.cacheItemCount == 0)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationDestination(isPresented:$showManualAdd) {
                AddressView(service:service,onConnected:{ dismiss() })
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
                Button("取消",role:.cancel) { Haptics.shared.play(.tap) }
                Button("清除缓存和记录",role:.destructive) {
                    Haptics.shared.play(.confirm)
                    service.clearOutboxCacheNow()
                }
            } message: {
                Text("清除缓存会同时删除对应的发送历史记录，且无法恢复。")
            }
            .onAppear {
                initialAlias = service.settings.alias
                initialPort = service.settings.port
                lastSliderHapticBucket = service.settings.cacheRetentionDays / 5
                service.refreshCacheStats()
            }
        }.frame(minWidth:340,minHeight:360)
    }

    private func saveAndDismiss(forceRestart: Bool) {
        Haptics.shared.play(forceRestart || connectionChanged ? .confirm : .collapse)
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
    var isSheet = false
    var onConnected: (() -> Void)? = nil
    @State private var host = ""
    @State private var port: UInt16 = 53317
    @State private var showPort = false
    @FocusState private var hostFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmedHost: String {
        host.trimmingCharacters(in:.whitespacesAndNewlines)
    }

    var body:some View {
        Form {
            Section {
                LabeledContent("IP 地址") {
                    TextField("例如 192.168.1.100",text:$host)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .focused($hostFocused)
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                DisclosureGroup("自定义端口（默认 \(String(port))）",isExpanded:$showPort) {
                    LabeledContent("端口") {
                        TextField("53317",value:$port,format:.number.grouping(.never))
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }
                .onChange(of:showPort) { _,expanded in
                    Haptics.shared.play(expanded ? .expand : .collapse)
                }
            } header: {
                Text("目标设备")
            } footer: {
                Text("仅在局域网自动发现搜不到对方设备时，通过 IP 手动直连。")
            }

            Section {
                Button {
                    service.probeDevice(host:trimmedHost,port:port)
                    if let onConnected {
                        onConnected()
                    } else {
                        dismiss()
                    }
                } label: {
                    Text("连接设备")
                        .font(.body.weight(.medium))
                        .frame(maxWidth:.infinity,alignment:.center)
                }
                .disabled(trimmedHost.isEmpty)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("手动添加设备")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if isSheet {
                ToolbarItem(placement:.cancellationAction) {
                    Button("取消") { Haptics.shared.play(.collapse); dismiss() }
                }
            }
        }
        .onAppear {
            hostFocused = true
        }
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
