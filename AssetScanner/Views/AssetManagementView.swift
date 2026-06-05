import SwiftUI
import UniformTypeIdentifiers

/// 资产管理视图 — 显示所有导入的文件来源，支持删除和管理
struct AssetManagementView: View {
    @EnvironmentObject var viewModel: AssetViewModel

    private var checkedOutAssetCount: Int {
        viewModel.assets.filter { $0.status == .checkedOut }.count
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 统计卡片
                    statsCard
                    
                    // iCloud 同步卡片
                    SyncSectionView()
                    
                    // 来源列表卡片
                    if viewModel.sources.isEmpty {
                        emptyStateCard
                    } else {
                        VStack(spacing: 12) {
                            ForEach(viewModel.sources) { source in
                                SourceRowView(source: source)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(Color(.systemBackground))
                                            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
                                    )
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            viewModel.deleteSource(source)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L("management_title"))
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    // MARK: - 统计卡片
    
    private var statsCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                statItem(
                    icon: "doc.fill",
                    value: "\(viewModel.sources.count)",
                    label: L("stat_file_sources"),
                    color: Color.blue
                )
                
                statItem(
                    icon: "cube.box.fill",
                    value: "\(viewModel.assets.count)",
                    label: L("stat_total_assets"),
                    color: Color.green
                )
                
                statItem(
                    icon: "arrow.up.circle.fill",
                    value: "\(checkedOutAssetCount)",
                    label: "出库数量",
                    color: Color.orange
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
        )
    }
    
    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text(L("empty_management_title"))
                .font(.headline)
            
            Text(L("empty_management_hint"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
        )
    }
    
    @ViewBuilder
    private func statItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - iCloud 同步区域

struct SyncSectionView: View {
    @EnvironmentObject var viewModel: AssetViewModel
    @State private var showFeishuConfigImporter = false
    
    var body: some View {
        VStack(spacing: 16) {
            // 标题
            HStack {
                Image(systemName: "icloud.fill")
                    .font(.title3)
                    .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                
                Text("iCloud 文件同步")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if let url = viewModel.selectedFolderURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            // 4 个独立的功能按钮
            VStack(spacing: 12) {
                // 按钮 1: 选择文件夹
                Button {
                    viewModel.selectSyncFolder()
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                            .font(.title3)
                        Text("选择文件夹")
                            .font(.headline)
                        Spacer()
                        if viewModel.selectedFolderURL != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                // 按钮 2: 导入
                Button {
                    Task {
                        await viewModel.syncFromiCloud()
                    }
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title3)
                        Text("导入")
                            .font(.headline)
                        Spacer()
                        if viewModel.isSyncInProgress {
                            ProgressView()
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .foregroundColor(.orange)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSyncInProgress || viewModel.selectedFolderURL == nil)
                
                // 按钮 3: 导出
                Button {
                    Task {
                        await viewModel.syncToiCloud()
                    }
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                        Text("导出")
                            .font(.headline)
                        Spacer()
                        if viewModel.isSyncInProgress {
                            ProgressView()
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSyncInProgress || viewModel.selectedFolderURL == nil)
                
                // 按钮 4: 双向同步
                Button {
                    Task {
                        await viewModel.bidirectionalSync()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.title3)
                        Text("双向同步")
                            .font(.headline)
                        Spacer()
                        if viewModel.isSyncInProgress {
                            ProgressView()
                        }
                    }
                    .padding()
                    .background(Color.purple.opacity(0.1))
                    .foregroundColor(.purple)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSyncInProgress || viewModel.selectedFolderURL == nil)

                Button {
                    showFeishuConfigImporter = true
                } label: {
                    HStack {
                        Image(systemName: "link.badge.plus")
                            .font(.title3)
                        Text("导入 AssetManager 配置")
                            .font(.headline)
                        Spacer()
                        if viewModel.hasFeishuConfig {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .padding()
                    .background(Color.teal.opacity(0.1))
                    .foregroundColor(.teal)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            
            // 状态显示
            if viewModel.syncStatus != "就绪" {
                HStack {
                    if viewModel.isSyncInProgress {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(viewModel.syncStatus)
                        .font(.caption)
                        .foregroundColor(viewModel.syncStatus.contains("失败") || viewModel.syncStatus.contains("错误") ? .red : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 10) {
                HStack {
                    Image(systemName: viewModel.hasFeishuConfig ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(viewModel.hasFeishuConfig ? .green : .orange)
                    Text(viewModel.feishuConfigStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                if viewModel.hasFeishuConfig {
                    configRow(title: "App ID", value: viewModel.importedFeishuAppID)
                    configRow(title: "资产表 ID", value: viewModel.importedFeishuAssetTableID)
                    configRow(title: "记录表 ID", value: viewModel.importedFeishuRecordTableID)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
        )
        .fileImporter(
            isPresented: $showFeishuConfigImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await viewModel.importAssetManagerFeishuConfig(from: url) }
            case .failure(let error):
                viewModel.errorMessage = "选择配置文件失败: \(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private func configRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value.isEmpty ? "-" : value)
                .font(.caption.monospaced())
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }
}

// MARK: - 来源行视图

struct SourceRowView: View {
    let source: AssetSource
    
    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // 文件图标
            Image(systemName: "doc.fill")
                .font(.title3)
                .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color(red: 0.2, green: 0.4, blue: 0.8).opacity(0.1))
                )
            
            // 文件信息
            VStack(alignment: .leading, spacing: 4) {
                Text(source.fileName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(dateFormatter.string(from: source.importDate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(String(format: L("source_assets_count"), source.assetCount))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 箭头
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 预览

#Preview {
    AssetManagementView()
        .environmentObject(AssetViewModel())
}
