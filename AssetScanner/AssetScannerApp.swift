import SwiftUI

@main
struct AssetScannerApp: App {
    @StateObject private var assetVM = AssetViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(assetVM)
        }
    }
}
