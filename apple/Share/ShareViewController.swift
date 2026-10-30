import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController:UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize=CGSize(width:0,height:460)
        let service=TransferService.shared
        let initialRows=Set(service.rows.map(\.id))
        let controller=UIHostingController(rootView:NavigationStack {
            ContentView(service:service,shareMode:true)
                .onReceive(service.$rows) { [weak self] rows in
                    if let row=rows.first,!initialRows.contains(row.id),row.direction=="send",row.state=="已发送" {
                        DispatchQueue.main.asyncAfter(deadline:.now()+0.15) { service.stop();self?.extensionContext?.completeRequest(returningItems:nil) }
                    }
                }
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("完成") { [weak self] in
                    service.stop();self?.extensionContext?.completeRequest(returningItems:nil)
                } } }
        })
        addChild(controller);view.addSubview(controller.view);controller.view.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([controller.view.leadingAnchor.constraint(equalTo:view.leadingAnchor),controller.view.trailingAnchor.constraint(equalTo:view.trailingAnchor),controller.view.topAnchor.constraint(equalTo:view.topAnchor),controller.view.bottomAnchor.constraint(equalTo:view.bottomAnchor)])
        controller.didMove(toParent:self)
        importItems(service)
    }
    private func importItems(_ service:TransferService) {
        let providers=(extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap{$0.attachments ?? []}
        guard !providers.isEmpty else { service.error="没有可以发送的内容";return }
        let group=DispatchGroup()
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) || provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                guard let type=provider.registeredTypeIdentifiers.first(where:{UTType($0)?.conforms(to:.data)==true && $0 != UTType.plainText.identifier}) else { service.error="不支持此文件类型";return }
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier:type) { url,error in
                    do {
                        if let error { throw error }
                        guard let url else { throw CocoaError(.fileReadUnknown) }
                        let copied=try TransferService.copyToOutbox(url,root:service.root)
                        DispatchQueue.main.async { service.attachments.append(copied);group.leave() }
                    } catch { DispatchQueue.main.async { service.error="读取分享文件失败：\(error.localizedDescription)";group.leave() } }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier:UTType.url.identifier) { value,error in
                    DispatchQueue.main.async {
                        if let error { service.error="读取链接失败：\(error.localizedDescription)" }
                        else if let url=value as? URL { service.text += (service.text.isEmpty ? "":"\n")+url.absoluteString }
                        else { service.error="无法读取分享的链接" }
                        group.leave()
                    }
                }
            } else if provider.canLoadObject(ofClass:NSString.self) {
                group.enter()
                _=provider.loadObject(ofClass:NSString.self) { value,error in
                    DispatchQueue.main.async {
                        if let error { service.error="读取文字失败：\(error.localizedDescription)" }
                        else if let text=value as? String { service.text += (service.text.isEmpty ? "":"\n")+text }
                        else { service.error="无法读取分享的文字" }
                        group.leave()
                    }
                }
            } else { service.error="不支持此分享内容";return }
        }
        group.notify(queue:.main) { if service.error==nil { service.start(portOverride:0) } }
    }
}
