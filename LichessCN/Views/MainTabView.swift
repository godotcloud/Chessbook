import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppStateViewModel
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            StudyBrowserView()
                .tabItem {
                    Label("研习翻译", systemImage: "book.pages.fill")
                }
                .tag(0)

            PuzzleTrainingView()
                .tabItem {
                    Label("战术谜题", systemImage: "puzzlepiece.extension.fill")
                }
                .tag(1)

            OnlinePlayView()
                .tabItem {
                    Label("在线对局", systemImage: "checkerboard.rectangle")
                }
                .tag(2)

            EngineAnalysisView()
                .tabItem {
                    Label("引擎分析", systemImage: "cpu.fill")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("设置与翻译源", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .task {
            await appState.verifyTokenIfPresent()
        }
    }
}
