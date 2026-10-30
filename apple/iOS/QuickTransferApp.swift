import SwiftUI

@main
struct QuickTransferApp:App {
    @StateObject private var service=TransferService.shared
    @Environment(\.scenePhase) private var phase
    var body:some Scene {
        WindowGroup {
            NavigationStack { ContentView(service:service) }
                .onAppear{service.start()}
                .onChange(of:phase) { _,phase in
                    if phase == .active { service.start();service.importShared() }
                    else if phase == .background { service.stop() }
                }
        }
    }
}
