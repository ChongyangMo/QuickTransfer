import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct FileStrip: View {
    let urls: [URL]
    @ObservedObject var service: TransferService
    var removable = false
    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing:8) {
                ForEach(Array(urls.enumerated()),id:\.offset) { _,url in
                    Button { service.preview=url } label: {
                        FileThumbnail(url:url)
                            .frame(width:76,height:76)
                            .background(.quaternary.opacity(0.6),in:RoundedRectangle(cornerRadius:10))
                            .clipShape(RoundedRectangle(cornerRadius:10))
                            .overlay(RoundedRectangle(cornerRadius:10).stroke(.primary.opacity(0.06),lineWidth:0.5))
                            .contentShape(RoundedRectangle(cornerRadius:10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("预览 \(url.lastPathComponent)")
                    .help(url.lastPathComponent)
                    .onDrag { NSItemProvider(contentsOf:url) ?? NSItemProvider(object:url as NSURL) }
                    .overlay(alignment:.topTrailing) {
                        if removable {
                            Button { service.removeAttachment(url) } label:{
                                Image(systemName:"xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white,.black.opacity(0.65)).frame(width:28,height:28)
                            }.buttonStyle(.plain).accessibilityLabel("移除 \(url.lastPathComponent)")
                        }
                    }
                }
            }.frame(height:80)
        }.scrollIndicators(.hidden).frame(height:80)
    }
}

struct FileThumbnail: View {
    let url: URL
    @State private var thumbnail: CGImage?
    private var isImage: Bool { UTType(filenameExtension:url.pathExtension)?.conforms(to:.image) == true }
    var body: some View {
        Group {
            if let thumbnail {
                Image(decorative:thumbnail,scale:1)
                    .resizable()
                    .scaledToFill()
            } else if isImage {
                Image(systemName:"photo").font(.title3).foregroundStyle(.secondary)
            } else {
                VStack(spacing:4) {
                    Image(systemName:"doc.fill").font(.title3).foregroundStyle(.secondary)
                    Text(url.lastPathComponent).font(.caption2).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
                }
                .padding(6)
            }
        }
        .task(id:url) {
            thumbnail=nil
            guard isImage else { return }
            let sourceURL=url
            let decoded=await Task.detached(priority:.userInitiated) {
                guard let source=CGImageSourceCreateWithURL(sourceURL as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary) else { return nil as CGImage? }
                return CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageIfAbsent:true,kCGImageSourceThumbnailMaxPixelSize:256,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary)
            }.value
            if !Task.isCancelled { thumbnail=decoded }
        }
    }
}

extension TransferService {
    func importDropped(_ providers: [NSItemProvider]) -> Bool {
        let destination=root
        for provider in providers {
            if provider.canLoadObject(ofClass:URL.self) {
                _=provider.loadObject(ofClass:URL.self) { url,error in
                    guard let url else { Task { @MainActor in self.error="添加文件失败：\(error?.localizedDescription ?? "文件不可用")" };return }
                    #if os(macOS)
                    Task { @MainActor in self.stage([url]) }
                    #else
                    let scoped=url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do { let copied=try Self.copyToOutbox(url,root:destination);Task { @MainActor in self.attachments.append(copied) } }
                    catch { Task { @MainActor in self.error="添加文件失败：\(error.localizedDescription)" } }
                    #endif
                }
            } else {
                provider.loadFileRepresentation(forTypeIdentifier:UTType.image.identifier) { url,error in
                    do {
                        guard let url else { throw error ?? CocoaError(.fileReadUnknown) }
                        let copied=try Self.copyToOutbox(url,root:destination)
                        Task { @MainActor in self.attachments.append(copied) }
                    }catch { Task { @MainActor in self.error="添加图片失败：\(error.localizedDescription)" } }
                }
            }
        }
        return !providers.isEmpty
    }
}
