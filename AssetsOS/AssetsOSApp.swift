import SwiftData
import SwiftUI

@main
struct AssetsOSApp: App {
    private let container = PersistenceController.makeSharedContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
