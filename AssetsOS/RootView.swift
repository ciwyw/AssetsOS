import Observation
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var coordinator = AppCoordinator()
    @State private var backupManager = BackupManager()

    var body: some View {
        @Bindable var coordinator = coordinator
        let tabSelection = Binding<AppTab>(
            get: { coordinator.selectedTab },
            set: { coordinator.handleTabSelection($0) }
        )

        TabView(selection: tabSelection) {
            NavigationStack {
                OverviewScreen()
            }
            .tabItem {
                Label(AppTab.overview.title, systemImage: AppTab.overview.systemImage)
            }
            .tag(AppTab.overview)

            NavigationStack {
                AccountsScreen()
            }
            .tabItem {
                Label(AppTab.accounts.title, systemImage: AppTab.accounts.systemImage)
            }
            .tag(AppTab.accounts)

            NavigationStack {
                FixedTermsScreen()
            }
            .tabItem {
                Label(AppTab.fixedTerms.title, systemImage: AppTab.fixedTerms.systemImage)
            }
            .tag(AppTab.fixedTerms)
        }
        .environment(coordinator)
        .environment(backupManager)
        .tint(AppTheme.accent)
        .task {
            backupManager.startObserving(modelContext)
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .background else { return }
            Task { await backupManager.flushWhenEnteringBackground(context: modelContext) }
        }
    }
}
