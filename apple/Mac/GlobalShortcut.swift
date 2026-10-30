import AppKit
import SwiftUI
import Carbon

@MainActor
final class MacAppDelegate:NSObject,NSApplicationDelegate {
    private static weak var current:MacAppDelegate?
    private var hotkey:EventHotKeyRef?
    private var handler:EventHandlerRef?
    private var window:NSWindow?
    func applicationDidFinishLaunching(_ notification:Notification) {
        Self.current=self
        TransferService.shared.start()
        var type=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        let status=InstallEventHandler(GetApplicationEventTarget(),{ _,_,_ in
            DispatchQueue.main.async { MacAppDelegate.showClipboard() }
            return noErr
        },1,&type,nil,&handler)
        guard status==noErr else { TransferService.shared.error="快捷键初始化失败：\(status)";return }
        let result=RegisterEventHotKey(UInt32(kVK_ANSI_S),UInt32(optionKey|shiftKey),EventHotKeyID(signature:0x5154524E,id:1),GetApplicationEventTarget(),0,&hotkey)
        if result != noErr { TransferService.shared.error="快捷键注册失败：\(result)" }
    }
    @MainActor static func showClipboard() {
        let service=TransferService.shared;service.paste()
        showMainWindow()
    }
    @MainActor static func showMainWindow() {
        let service=TransferService.shared
        if let window=NSApp.windows.first(where:{$0.title=="快传"}) { window.makeKeyAndOrderFront(nil) }
        else if let delegate=current {
            let window=NSWindow(contentViewController:NSHostingController(rootView:ContentView(service:service)))
            window.title="快传";window.setContentSize(NSSize(width:420,height:540));window.center();window.makeKeyAndOrderFront(nil);delegate.window=window
        }
        NSApp.activate(ignoringOtherApps:true)
    }
    func applicationWillTerminate(_ notification:Notification) {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
