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
                            DragSelectPhotoGrid(
                                assets: store.assets,
                                store: store,
                                selectedIDs: $selectedIDs,
                                maxSelection: maxSelection
                            )
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
                    Button { Haptics.shared.play(.tap); dismiss() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("取消")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.shared.play(.tap)
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
        HStack(spacing: 10) {
            Button {
                Haptics.shared.play(.tap)
                selectedIDs.removeAll()
            } label: {
                Text("取消选中")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
            if canSendDirectly {
                Button {
                    Haptics.shared.play(.tap)
                    commit(autoSend: false)
                } label: {
                    Text("仅添加")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                Button("发送 (\(selectedIDs.count))") {
                    Haptics.shared.play(.action)
                    commit(autoSend: true)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("添加 (\(selectedIDs.count))") {
                    Haptics.shared.play(.tap)
                    commit(autoSend: false)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func commit(autoSend: Bool) {
        let picked = selectedAssets
        guard !picked.isEmpty else { return }
        dismiss()
        service.stagePhotoAssets(picked, autoSend: autoSend)
    }
}

private struct DragSelectPhotoGrid: UIViewRepresentable {
    let assets: [PHAsset]
    let store: FastPhotoStore
    @Binding var selectedIDs: [String]
    let maxSelection: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, selectedIDs: $selectedIDs, maxSelection: maxSelection)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        let collectionView = PhotoGridCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(PhotoAssetCell.self, forCellWithReuseIdentifier: PhotoAssetCell.reuseID)
        context.coordinator.attach(to: collectionView)
        return collectionView
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        context.coordinator.selectedIDsBinding = $selectedIDs
        context.coordinator.update(assets: assets, selectedIDs: selectedIDs, in: uiView)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate {
        let store: FastPhotoStore
        var selectedIDsBinding: Binding<[String]>
        let maxSelection: Int

        private weak var collectionView: UICollectionView?
        private var assets: [PHAsset] = []
        private var assetIDs: [String] = []
        private var selectedIDs: [String] = []
        private var selectionOrderMap: [String: Int] = [:]

        private var dragStartIndex: Int?
        private var dragBaseSelection: [String] = []
        private var dragSelectMode = true
        private var lastDragIndex: Int?
        private var dragPointInViewport: CGPoint = .zero
        private var autoScrollLink: CADisplayLink?

        init(store: FastPhotoStore, selectedIDs: Binding<[String]>, maxSelection: Int) {
            self.store = store
            self.selectedIDsBinding = selectedIDs
            self.maxSelection = maxSelection
        }

        deinit {
            autoScrollLink?.invalidate()
        }

        func attach(to collectionView: UICollectionView) {
            self.collectionView = collectionView
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDragSelect(_:)))
            pan.delegate = self
            pan.maximumNumberOfTouches = 1
            collectionView.addGestureRecognizer(pan)
            collectionView.panGestureRecognizer.require(toFail: pan)
        }

        func update(assets newAssets: [PHAsset], selectedIDs newSelection: [String], in collectionView: UICollectionView) {
            let newIDs = newAssets.map(\.localIdentifier)
            let assetsChanged = newIDs != assetIDs
            let selectionChanged = newSelection != selectedIDs
            assets = newAssets
            assetIDs = newIDs
            selectedIDs = newSelection
            rebuildOrderMap()

            if assetsChanged {
                collectionView.reloadData()
            } else if selectionChanged {
                refreshVisibleBadges(in: collectionView)
            }
        }

        private func rebuildOrderMap() {
            var map: [String: Int] = [:]
            map.reserveCapacity(selectedIDs.count)
            for (index, id) in selectedIDs.enumerated() {
                map[id] = index + 1
            }
            selectionOrderMap = map
        }

        private func refreshVisibleBadges(in collectionView: UICollectionView) {
            for cell in collectionView.visibleCells {
                guard let photoCell = cell as? PhotoAssetCell,
                      let indexPath = collectionView.indexPath(for: cell),
                      indexPath.item < assets.count else { continue }
                let id = assets[indexPath.item].localIdentifier
                photoCell.updateSelection(order: selectionOrderMap[id])
            }
        }

        private func commitSelection(_ updated: [String]) {
            guard updated != selectedIDs else { return }
            selectedIDs = updated
            rebuildOrderMap()
            if let collectionView {
                refreshVisibleBadges(in: collectionView)
            }
            selectedIDsBinding.wrappedValue = updated
        }

        // MARK: - UICollectionViewDataSource / Delegate

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            assets.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoAssetCell.reuseID, for: indexPath) as! PhotoAssetCell
            let asset = assets[indexPath.item]
            cell.configure(asset: asset, store: store, selectionOrder: selectionOrderMap[asset.localIdentifier])
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard indexPath.item < assets.count else { return }
            let id = assets[indexPath.item].localIdentifier
            var updated = selectedIDs
            if let idx = updated.firstIndex(of: id) {
                updated.remove(at: idx)
            } else if updated.count < maxSelection {
                updated.append(id)
            }
            Haptics.shared.play(.selection)
            commitSelection(updated)
        }

        // MARK: - Drag Multi-Select (Horizontal start, then free 2D drag + edge auto-scroll)

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let collectionView else { return false }
            let velocity = pan.velocity(in: collectionView)
            // 横向起手触发滑动多选，纵向起手交给 UICollectionView 正常上下滚动
            guard abs(velocity.x) > abs(velocity.y) * 1.05, abs(velocity.x) > 20 else {
                return false
            }
            let location = pan.location(in: collectionView)
            return collectionView.indexPathForItem(at: location) != nil
        }

        @objc private func handleDragSelect(_ pan: UIPanGestureRecognizer) {
            guard let collectionView else { return }
            let contentPoint = pan.location(in: collectionView)
            dragPointInViewport = CGPoint(
                x: contentPoint.x - collectionView.contentOffset.x,
                y: contentPoint.y - collectionView.contentOffset.y
            )

            switch pan.state {
            case .began:
                guard let indexPath = collectionView.indexPathForItem(at: contentPoint),
                      indexPath.item < assets.count else { return }
                let startID = assets[indexPath.item].localIdentifier
                dragStartIndex = indexPath.item
                dragBaseSelection = selectedIDs
                dragSelectMode = selectionOrderMap[startID] == nil
                lastDragIndex = nil
                applyDragRange(to: indexPath.item)
                startAutoScrollIfNeeded()

            case .changed:
                if let index = nearestItemIndex(at: contentPoint, in: collectionView) {
                    applyDragRange(to: index)
                }
                startAutoScrollIfNeeded()

            default:
                stopAutoScroll()
                dragStartIndex = nil
                dragBaseSelection = []
                lastDragIndex = nil
            }
        }

        private func nearestItemIndex(at point: CGPoint, in collectionView: UICollectionView) -> Int? {
            guard !assets.isEmpty else { return nil }
            if let indexPath = collectionView.indexPathForItem(at: point) {
                return indexPath.item
            }
            // 手指落在格子 2pt 间隙或左右边缘时，找最近的有效格子
            let clampedX = min(max(point.x, 4), max(4, collectionView.bounds.width - 4))
            let clampedY = min(max(point.y, 4), max(4, collectionView.contentSize.height - 4))
            let probes: [CGPoint] = [
                CGPoint(x: clampedX, y: clampedY),
                CGPoint(x: clampedX + 4, y: clampedY),
                CGPoint(x: clampedX - 4, y: clampedY),
                CGPoint(x: clampedX, y: clampedY + 4),
                CGPoint(x: clampedX, y: clampedY - 4),
            ]
            for probe in probes {
                if let indexPath = collectionView.indexPathForItem(at: probe) {
                    return indexPath.item
                }
            }
            return nil
        }

        private func applyDragRange(to currentIndex: Int) {
            guard let startIndex = dragStartIndex, currentIndex != lastDragIndex else { return }
            lastDragIndex = currentIndex

            let indices: [Int]
            if currentIndex >= startIndex {
                indices = Array(startIndex...currentIndex)
            } else {
                indices = Array((currentIndex...startIndex).reversed())
            }

            var updated: [String]
            if dragSelectMode {
                updated = dragBaseSelection
                var existing = Set(updated)
                for idx in indices where idx >= 0 && idx < assets.count {
                    guard updated.count < maxSelection else { break }
                    let id = assets[idx].localIdentifier
                    if existing.insert(id).inserted {
                        updated.append(id)
                    }
                }
            } else {
                var toRemove = Set<String>()
                for idx in indices where idx >= 0 && idx < assets.count {
                    toRemove.insert(assets[idx].localIdentifier)
                }
                updated = dragBaseSelection.filter { !toRemove.contains($0) }
            }

            if updated != selectedIDs {
                Haptics.shared.play(.selection)
                commitSelection(updated)
            }
        }

        private func startAutoScrollIfNeeded() {
            guard autoScrollLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(stepAutoScroll))
            link.add(to: .main, forMode: .common)
            autoScrollLink = link
        }

        private func stopAutoScroll() {
            autoScrollLink?.invalidate()
            autoScrollLink = nil
        }

        @objc private func stepAutoScroll() {
            guard dragStartIndex != nil, let collectionView else {
                stopAutoScroll()
                return
            }
            let edgeZone: CGFloat = 56
            let maxSpeed: CGFloat = 14
            let visibleHeight = collectionView.bounds.height
            let minY = -collectionView.adjustedContentInset.top
            let maxY = max(minY, collectionView.contentSize.height - visibleHeight + collectionView.adjustedContentInset.bottom)

            var delta: CGFloat = 0
            if dragPointInViewport.y < edgeZone {
                let factor = max(0, min(1, (edgeZone - dragPointInViewport.y) / edgeZone))
                delta = -maxSpeed * factor
            } else if dragPointInViewport.y > visibleHeight - edgeZone {
                let factor = max(0, min(1, (dragPointInViewport.y - (visibleHeight - edgeZone)) / edgeZone))
                delta = maxSpeed * factor
            }
            guard abs(delta) > 0.2 else { return }

            let nextY = min(maxY, max(minY, collectionView.contentOffset.y + delta))
            guard abs(nextY - collectionView.contentOffset.y) > 0.1 else { return }

            collectionView.contentOffset.y = nextY
            let contentPoint = CGPoint(
                x: dragPointInViewport.x + collectionView.contentOffset.x,
                y: dragPointInViewport.y + collectionView.contentOffset.y
            )
            if let index = nearestItemIndex(at: contentPoint, in: collectionView) {
                applyDragRange(to: index)
            }
        }
    }
}

private final class PhotoGridCollectionView: UICollectionView {
    private var lastLayoutWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0, abs(width - lastLayoutWidth) > 0.5,
              let flow = collectionViewLayout as? UICollectionViewFlowLayout else { return }
        lastLayoutWidth = width
        let spacing: CGFloat = 2
        let side = floor((width - spacing * 3) / 4)
        flow.itemSize = CGSize(width: side, height: side)
        flow.invalidateLayout()
    }
}

private final class PhotoAssetCell: UICollectionViewCell {
    static let reuseID = "PhotoAssetCell"

    private let imageView = UIImageView()
    private let dimView = UIView()
    private let badgeLabel = UILabel()
    private weak var store: FastPhotoStore?
    private var representedAssetID: String?
    private var requestID: PHImageRequestID = PHInvalidImageRequestID

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = UIColor.secondarySystemFill
        contentView.clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        dimView.isHidden = true
        dimView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dimView)

        badgeLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        badgeLabel.textAlignment = .center
        badgeLabel.textColor = .white
        badgeLabel.layer.cornerRadius = 11
        badgeLabel.layer.masksToBounds = true
        badgeLabel.layer.borderWidth = 1.5
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            dimView.topAnchor.constraint(equalTo: contentView.topAnchor),
            dimView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            dimView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            badgeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            badgeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            badgeLabel.widthAnchor.constraint(equalToConstant: 22),
            badgeLabel.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if requestID != PHInvalidImageRequestID {
            store?.cancelRequest(requestID)
            requestID = PHInvalidImageRequestID
        }
        representedAssetID = nil
        imageView.image = nil
        updateSelection(order: nil)
    }

    func configure(asset: PHAsset, store: FastPhotoStore, selectionOrder: Int?) {
        self.store = store
        let id = asset.localIdentifier
        updateSelection(order: selectionOrder)

        if representedAssetID == id, imageView.image != nil {
            return
        }
        if requestID != PHInvalidImageRequestID {
            store.cancelRequest(requestID)
            requestID = PHInvalidImageRequestID
        }
        representedAssetID = id

        if let cached = store.cachedThumbnail(for: id) {
            imageView.image = cached
            return
        }
        imageView.image = nil
        requestID = store.requestThumbnail(for: asset, targetSize: CGSize(width: 280, height: 280)) { [weak self] loaded in
            guard let self, self.representedAssetID == id, let loaded else { return }
            self.imageView.image = loaded
        }
    }

    func updateSelection(order: Int?) {
        if let order {
            dimView.isHidden = false
            badgeLabel.text = "\(order)"
            badgeLabel.backgroundColor = tintColor
            badgeLabel.layer.borderColor = UIColor.white.cgColor
        } else {
            dimView.isHidden = true
            badgeLabel.text = nil
            badgeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.25)
            badgeLabel.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
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
