import SwiftUI

@main
struct AssetManagerApp: App {
    @StateObject private var syncService = iCloudSyncService()
    @StateObject private var assetVM = AssetViewModel()
    
    var body: some Scene {
        WindowGroup("资产管家") {
            MacMainView()
                .environmentObject(assetVM)
                .environmentObject(syncService)
                .onAppear { syncService.syncFromICloud(to: &assetVM.assets, records: &assetVM.operationRecords, sources: &assetVM.sources) }
        }
        #if DEBUG
        MenuBarExtra("资产管家", systemImage: "barcode") {
            VStack {
                Text(assetVM.syncStatus).font(.caption)
                
                if let lastSync = syncService.lastSyncTime {
                    Text("最后同步: \(lastSync, formatter: Self.dateFormatter)").font(.caption)
                }
                if let lastImport = syncService.lastImportTime {
                    Text("最后导入: \(lastImport, formatter: Self.dateFormatter)").font(.caption)
                }
                
                Divider()
                
                Button("同步数据") {
                    syncService.syncBidirectional(assets: &assetVM.assets, records: &assetVM.operationRecords, sources: &assetVM.sources)
                }
                
                Button("从 iCloud 导入 CSV") {
                    assetVM.importCSVFromICloud()
                }
                
                Button("保存当前列表到 iCloud") {
                    assetVM.saveCSVToICloud()
                }
            }.padding(8)
        }
        #endif
    }
    static let dateFormatter: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f }()
}