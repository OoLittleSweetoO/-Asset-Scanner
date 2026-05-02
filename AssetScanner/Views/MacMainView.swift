import SwiftUI

struct MacMainView: View {
    @EnvironmentObject var assetVM: AssetViewModel
    @EnvironmentObject var syncService: iCloudSyncService
    
    @State private var selectedTab = 0
    @State private var showImportPanel = false
    
    var body: some View {
        NavigationSplitView {
            // Sidebar - 资产列表和来源
            List(selection: $selectedTab) {
                Section("数据管理") {
                    Label("资产列表", systemImage: "list.bullet")
                        .tag(0)
                    Label("操作记录", systemImage: "clock")
                        .tag(1)
                    Label("数据来源", systemImage: "doc")
                        .tag(2)
                }
                
                Section("同步状态") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: syncService.isICloudAvailable ? "icloud" : "icloud.slash")
                            Text(syncService.isICloudAvailable ? "iCloud 已连接" : "iCloud 未连接")
                                .font(.caption)
                        }
                        .foregroundColor(syncService.isICloudAvailable ? .green : .red)
                        
                        if let lastSync = syncService.lastSyncTime {
                            Text("最后同步: \(lastSync, formatter: Self.dateFormatter)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(SidebarListStyle())
        } detail: {
            Group {
                switch selectedTab {
                case 0:
                    AssetListView()
                case 1:
                    OperationHistoryView()
                case 2:
                    AssetSourceListView()
                default:
                    EmptyView()
                }
            }
            .frame(minWidth: 600, minHeight: 400)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: importAssets) {
                    Label("导入数据", systemImage: "square.and.arrow.down")
                }
            }
            
            ToolbarItem {
                Button(action: exportAssets) {
                    Label("导出资产", systemImage: "square.and.arrow.up")
                }
                .disabled(assetVM.assets.isEmpty)
            }
            
            ToolbarItem {
                Button(action: exportRecords) {
                    Label("导出记录", systemImage: "square.and.arrow.up")
                }
                .disabled(assetVM.operationRecords.isEmpty)
            }
            
            ToolbarItem {
                Button(action: {
                    syncService.syncBidirectional(with: assetVM)
                }) {
                    Label("同步", systemImage: "arrow.clockwise")
                }
                .disabled(!syncService.isICloudAvailable)
            }
        }
        .fileImporter(
            isPresented: $showImportPanel,
            allowedContentTypes: [.xlsx, .csv],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
    }
    
    private func importAssets() {
        showImportPanel = true
    }
    
    private func exportAssets() {
        Task {
            if let url = await assetVM.exportAssets() {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
    
    private func exportRecords() {
        Task {
            if let url = await assetVM.exportRecords() {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
    
    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                Task {
                    await assetVM.importAssets(from: url)
                    // 同步到 iCloud
                    syncService.syncToICloud(from: assetVM)
                }
            }
        case .failure(let error):
            assetVM.errorMessage = "导入失败: \(error.localizedDescription)"
        }
    }
    
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - 子视图占位符（复用现有 iOS 视图）

struct AssetListView: View {
    var body: some View {
        Text("资产列表 - 复用现有 iOS 视图逻辑")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OperationHistoryView: View {
    var body: some View {
        Text("操作记录 - 复用现有 iOS 视图逻辑")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AssetSourceListView: View {
    var body: some View {
        Text("数据来源 - 复用现有 iOS 视图逻辑")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}