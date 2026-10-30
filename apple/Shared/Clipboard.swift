import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension TransferService {
    func copy(_ text:String) {
        #if os(macOS)
        NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string)
        #else
        UIPasteboard.general.string=text
        #endif
    }
    #if os(macOS)
    func paste() {
        let clipboard=NSPasteboard.general
        if let urls=clipboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL], !urls.isEmpty { stage(urls);return }
        if let text=clipboard.string(forType:.string),!text.isEmpty { self.text=text;return }
        if let data=clipboard.data(forType:.png) {
            do {
                let dir=root.appendingPathComponent("outbox").appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
                let url=dir.appendingPathComponent("截图.png");try data.write(to:url);attachments.append(url)
            } catch { self.error="读取剪贴板图片失败：\(error.localizedDescription)" }
            return
        }
        error="剪贴板中没有文字或文件"
    }
    #endif
}
