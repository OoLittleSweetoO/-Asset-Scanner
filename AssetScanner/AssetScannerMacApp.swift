import SwiftUI

@main
struct AssetScannerMacApp: App {
    @StateObject private var assetVM = AssetViewModel()
    @StateObject private var syncService = iCloudSyncService()
    
    var body: some Scene {
        WindowGroup("AssetScanner") {
            MacMainView()
                .environmentObject(assetVM)
                .environmentObject(syncService)
        }
        #if DEBUG
        // 开发模式下显示同步状态
        MenuBarExtra("AssetScanner", systemImage: "barcode") {
            VStack {
                if let lastSync = syncService.lastSyncTime {
                    Text("最后同步: \(lastSync, formatter: Self.dateFormatter)")
                        .font(.caption)
                } else {
                    Text("未同步")
                        .font(.caption)
                }
                
                if syncService.syncError != nil {
                    Text("同步错误: \(syncService.syncError ?? "")")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Divider()
                Button("手动同步") {
                    syncService.syncBidirectional(with: assetVM)
                }
                .disabled(!syncService.isICloudAvailable)
            }
            .padding(8)
        }
        #endif
    }
    
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}