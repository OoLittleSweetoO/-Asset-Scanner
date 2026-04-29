import SwiftUI

/// 主内容视图 - TabView 导航
struct ContentView: View {
    @EnvironmentObject var viewModel: AssetViewModel
    
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    init() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        tabBarAppearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        UITabBar.appearance().tintColor = UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
    }
    
    var body: some View {
        TabView {
            NavigationStack {
                ScanView()
            }
            .tabItem {
                Label(L("tab_scan"), systemImage: "camera.viewfinder")
            }
            
            AssetListView()
                .tabItem {
                    Label(L("tab_assets"), systemImage: "list.bullet")
                }
            
            AssetManagementView()
                .tabItem {
                    Label(L("tab_management"), systemImage: "folder.badge.gearshape")
                }
            
            HistoryView()
                .tabItem {
                    Label(L("tab_history"), systemImage: "clock.arrow.circlepath")
                }
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if let error = newValue {
                errorMessage = error
                showingErrorAlert = true
            }
        }
        .alert(L("error_title"), isPresented: $showingErrorAlert) {
            Button(L("confirm")) {
                viewModel.errorMessage = nil
                errorMessage = ""
            }
        } message: {
            Text(errorMessage)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AssetViewModel())
}
