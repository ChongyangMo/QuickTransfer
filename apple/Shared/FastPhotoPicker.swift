#if os(iOS)
import SwiftUI
import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class FastPhotoStore: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var assets: [PHAsset] = []
    private var fetchResult: PHFetchResult<PHAsset>?
    private let imageManager = PHCachingImageManager()
    private let cache = NSCache<NSString, UIImage>()
    private var observing = false

    override init() {
        super.init()
        cache.countLimit = 240
    }

    deinit {
        if observing {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    func prepare() {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        status = current
        switch current {
        case .authorized, .limited:
            startObservingIfNeeded()
            reloadAssets()
        case .notDetermined:
            Task { [weak self] in
                let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                guard let self else { return }
                self.status = granted
                if granted == .authorized || granted == .limited {
                    self.startObservingIfNeeded()
                    self.reloadAssets()
                }
            }
        default:
            break
        }
    }

    func cachedThumbnail(for id: String) -> UIImage? {
        cache.object(forKey: id as NSString)
    }

    func requestThumbnail(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let key = asset.localIdentifier as NSString
        return imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { [weak self] image, _ in
            DispatchQueue.main.async {
                if let image {
                    self?.cache.setObject(image, forKey: key)
                }
                completion(image)
            }
        }
    }

    func cancelRequest(_ requestID: PHImageRequestID) {
        guard requestID != PHInvalidImageRequestID else { return }
        imageManager.cancelImageRequest(requestID)
    }

    private func startObservingIfNeeded() {
        guard !observing else { return }
        observing = true
        PHPhotoLibrary.shared().register(self)
    }

    private func reloadAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        applyFetchResult(result)
    }

    private func applyFetchResult(_ result: PHFetchResult<PHAsset>) {
        fetchResult = result
        var list: [PHAsset] = []
        list.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            list.append(asset)
        }
        assets = list
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let current = self.fetchResult else {
                self.reloadAssets()
                return
            }
            if let details = changeInstance.changeDetails(for: current) {
                self.applyFetchResult(details.fetchResultAfterChanges)
            }
        }
    }
}

struct FastPhotoPickerSheet: View {
    @ObservedObject var service: TransferService
    let onUseSystemPicker: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = FastPhotoStore()
    @State private var selectedIDs: [String] = []
    private let maxSelection = 100
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    private var canSendDirectly: Bool {
        service.canSendToSelectedPeer
    }

    private var selectedAssets: [PHAsset] {
        guard !selectedIDs.isEmpty else { return [] }
        let lookup = Dictionary(uniqueKeysWithValues: store.assets.map { ($0.localIdentifier, $0) })
        return selectedIDs.compactMap { lookup[$0] }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch store.status {
                case .authorized, .limited:
                    VStack(spacing: 0) {
                        if store.status == .limited {
                            limitedAccessBanner
                        }
                        if store.assets.isEmpty {
                            ContentUnavailableView("暂无照片", systemImage: "photo.on.rectangle.angled")
                        } else {
                            ScrollView {
                                LazyVGrid(columns: columns, spacing: 2) {
                                    ForEach(store.assets, id: \.localIdentifier) { asset in
                                        let order = selectedIDs.firstIndex(of: asset.localIdentifier).map { $0 + 1 }
                                        PhotoGridCell(asset: asset, store: store, selectionOrder: order) {
                                            toggleSelection(asset.localIdentifier)
                                        }
                                    }
                                }
                            }
                        }
                        if !selectedIDs.isEmpty {
                            Divider()
                            actionBar
                        }
                    }
                case .notDetermined:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在请求相册权限…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    VStack(spacing: 16) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("开启相册权限后可极速直发原图")
                            .font(.headline)
                        Text("允许快传访问照片后，无需等待系统导出，拍完即可直接发送原图。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                        Button("前往系统设置") {
                            if let url = URL(string: "app-settings:") {
                                openURL(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("改用系统相册选择") {
                            dismiss()
                            onUseSystemPicker()
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("选择原图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("取消")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                        onUseSystemPicker()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel("系统相册")
                }
            }
            .onAppear { store.prepare() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.prepare() }
            }
        }
    }

    private var limitedAccessBanner: some View {
        HStack(spacing: 8) {
            Text("当前仅允许访问部分照片")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("开启全部") {
                if let url = URL(string: "app-settings:") {
                    openURL(url)
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Text("已选 \(selectedIDs.count) 张原图")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if canSendDirectly {
                Button("仅添加") {
                    commit(autoSend: false)
                }
                .buttonStyle(.bordered)
                Button("发送 (\(selectedIDs.count))") {
                    commit(autoSend: true)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("添加 (\(selectedIDs.count))") {
                    commit(autoSend: false)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func toggleSelection(_ id: String) {
        if let index = selectedIDs.firstIndex(of: id) {
            selectedIDs.remove(at: index)
        } else if selectedIDs.count < maxSelection {
            selectedIDs.append(id)
        }
    }

    private func commit(autoSend: Bool) {
        let picked = selectedAssets
        guard !picked.isEmpty else { return }
        dismiss()
        service.stagePhotoAssets(picked, autoSend: autoSend)
    }
}

private struct PhotoGridCell: View {
    let asset: PHAsset
    let store: FastPhotoStore
    let selectionOrder: Int?
    let onTap: () -> Void
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID

    var body: some View {
        Button(action: onTap) {
            Color.secondary.opacity(0.12)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipped()
                .overlay {
                    if selectionOrder != nil {
                        Color.black.opacity(0.18)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    selectionBadge
                        .padding(5)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { loadThumbnail() }
        .onDisappear {
            store.cancelRequest(requestID)
            requestID = PHInvalidImageRequestID
        }
    }

    @ViewBuilder
    private var selectionBadge: some View {
        if let selectionOrder {
            Text("\(selectionOrder)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
        } else {
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 1.5)
                .background(Circle().fill(.black.opacity(0.25)))
                .frame(width: 22, height: 22)
        }
    }

    private func loadThumbnail() {
        if let cached = store.cachedThumbnail(for: asset.localIdentifier) {
            image = cached
            return
        }
        requestID = store.requestThumbnail(for: asset, targetSize: CGSize(width: 280, height: 280)) { loaded in
            if let loaded {
                image = loaded
            }
        }
    }
}

enum PhotoAssetExporter {
    nonisolated static func exportOriginal(_ asset: PHAsset, root: URL) async throws -> URL {
        let resources = PHAssetResource.assetResources(for: asset)
        if let resource = preferredImageResource(from: resources) {
            do {
                return try await writeResource(resource, root: root)
            } catch {
                // 极端情况下（刚按快门资源尚未就绪）回退到 PHImageManager 原始数据流
                return try await exportViaImageManager(asset, preferredName: resourceFilename(resource), root: root)
            }
        }
        return try await exportViaImageManager(asset, preferredName: nil, root: root)
    }

    private nonisolated static func preferredImageResource(from resources: [PHAssetResource]) -> PHAssetResource? {
        let order: [PHAssetResourceType] = [.fullSizePhoto, .photo, .alternatePhoto, .photoProxy]
        for type in order {
            if let matched = resources.first(where: { $0.type == type }) {
                return matched
            }
        }
        return resources.first
    }

    private nonisolated static func writeResource(_ resource: PHAssetResource, root: URL) async throws -> URL {
        let dir = root.appendingPathComponent("outbox").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(resourceFilename(resource))
        try? FileManager.default.removeItem(at: destination)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        return try await withCheckedThrowingContinuation { continuation in
            PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options) { error in
                if let error {
                    try? FileManager.default.removeItem(at: dir)
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: destination)
                }
            }
        }
    }

    private nonisolated static func exportViaImageManager(_ asset: PHAsset, preferredName: String?, root: URL) async throws -> URL {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let (data, dataUTI): (Data, String?) = try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var resumed = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, info in
                lock.lock()
                if resumed {
                    lock.unlock()
                    return
                }
                resumed = true
                lock.unlock()
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, !data.isEmpty else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    return
                }
                continuation.resume(returning: (data, uti))
            }
        }
        let dir = root.appendingPathComponent("outbox").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name: String
        if let preferredName, !preferredName.isEmpty {
            name = preferredName
        } else {
            let ext = dataUTI.flatMap { UTType($0)?.preferredFilenameExtension } ?? "heic"
            name = "IMG_\(UUID().uuidString.prefix(8)).\(ext)"
        }
        let destination = dir.appendingPathComponent(name)
        do {
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
    }

    private nonisolated static func resourceContentType(_ resource: PHAssetResource) -> UTType? {
        if #available(iOS 26, *) {
            return resource.contentType
        }
        return UTType(resource.uniformTypeIdentifier)
    }

    private nonisolated static func resourceFilename(_ resource: PHAssetResource) -> String {
        let raw: String
        if #available(iOS 27, *) {
            raw = resource.filename ?? ""
        } else {
            raw = resource.originalFilename
        }
        let cleaned = URL(fileURLWithPath: raw).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty, cleaned != ".", cleaned != "/" {
            return cleaned
        }
        let ext = resourceContentType(resource)?.preferredFilenameExtension ?? "heic"
        return "IMG_\(UUID().uuidString.prefix(8)).\(ext)"
    }
}
#endif
