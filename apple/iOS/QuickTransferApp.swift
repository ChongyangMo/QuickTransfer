import SwiftUI

@main
struct QuickTransferApp:App {
    @StateObject private var service=TransferService.shared
    @Environment(\.scenePhase) private var phase
    private let keeper=BackgroundKeeper.shared
    var body:some Scene {
        WindowGroup {
            NavigationStack { ContentView(service:service) }
                .onAppear{service.start();keeper.prepare()}
                .onChange(of:phase) { _,phase in
                    if phase == .active { keeper.enterForeground();service.start();service.importShared() }
                    else { keeper.enterBackground() }
                }
        }
    }
}
