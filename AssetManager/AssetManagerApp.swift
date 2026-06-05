import SwiftUI

@main
struct AssetManagerApp: App {
    
    @StateObject private var assetVM = AssetViewModel()
    
    var body: some Scene {
        WindowGroup("资产管家") {
            MacMainView()
                .environmentObject(assetVM)
                .onAppear { assetVM.syncService.syncFromICloud(to: &assetVM.assets, records: &assetVM.operationRecords, sources: &assetVM.sources) }
        }
        .commands {
            CommandGroup(after: .saveItem) {
                Divider()
                Button("保存当前配置...") {
                    assetVM.saveCurrentConfigurationToFile()
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

                Button("读取配置...") {
                    assetVM.loadConfigurationFromFile()
                }
                .keyboardShortcut("o", modifiers: [.command, .option])
            }

            CommandGroup(after: .help) {
                Divider()
                Button("打开 AssetManager 使用说明") {
                    HelpPageService.openAssetManagerHelpPage()
                }
                .keyboardShortcut("/", modifiers: [.command, .option])
            }
        }
        #if DEBUG
        MenuBarExtra("资产管家", systemImage: "barcode") {
            VStack {
                Text(assetVM.syncStatus).font(.caption)
                
                if let lastSync = assetVM.syncService.lastSyncTime {
                    Text("最后同步: \(lastSync, formatter: Self.dateFormatter)").font(.caption)
                }
                if let lastImport = assetVM.syncService.lastImportTime {
                    Text("最后导入: \(lastImport, formatter: Self.dateFormatter)").font(.caption)
                }
                
                Divider()
                
                Button("同步数据") {
                    assetVM.syncService.syncBidirectional(assets: &assetVM.assets, records: &assetVM.operationRecords, sources: &assetVM.sources)
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
