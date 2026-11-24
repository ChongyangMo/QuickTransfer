import SwiftUI

@main
struct QuickTransferApp:App {
    @StateObject private var service=TransferService.shared
    @Environment(\.scenePhase) private var phase
    private let keeper=BackgroundKeeper.shared
    var body:some Scene {
        WindowGroup {
            NavigationStack { ContentView(service:service) }
                .onAppear{service.start();keeper.prepare();Haptics.shared.prepare()}
                .onChange(of:phase) { _,phase in
                    if phase == .active { Haptics.shared.prepare();keeper.enterForeground();service.start();service.importShared();service.cleanExpiredOutbox() }
                    else { Haptics.shared.suspend();keeper.enterBackground() }
                }
        }
    }
}
