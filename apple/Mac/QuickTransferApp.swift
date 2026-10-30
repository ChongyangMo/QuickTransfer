import SwiftUI
import AppKit

@main
struct QuickTransferApp:App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var delegate
    @StateObject private var service=TransferService.shared
    var body:some Scene {
        WindowGroup("快传",id:"main") {
            ContentView(service:service).onAppear{service.start()}
        }.defaultSize(width:420,height:540)
        MenuBarExtra("快传",systemImage:"arrow.up.arrow.down") {
            MenuContents(service:service)
        }
        SwiftUI.Settings { SettingsView(service:service) }
    }
}
struct MenuContents:View {
    @ObservedObject var service:TransferService
    @Environment(\.openWindow) private var openWindow
    var body:some View {
        Button("打开快传") { openWindow(id:"main");NSApp.activate(ignoringOtherApps:true) }
        Button("发送剪贴板") { service.paste();openWindow(id:"main");NSApp.activate(ignoringOtherApps:true) }.keyboardShortcut("s",modifiers:[.option,.shift])
        Divider()
        Button("退出") { service.stop();NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
