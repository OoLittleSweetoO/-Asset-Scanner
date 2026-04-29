import SwiftUI

/// 资产管理视图 — 显示所有导入的文件来源，支持删除和管理
struct AssetManagementView: View {
    @EnvironmentObject var viewModel: AssetViewModel
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.sources.isEmpty {
                    emptyStateView
                } else {
                    sourceListView
                }
            }
            .navigationTitle(L("management_title"))
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    // MARK: - 来源列表
    
    @ViewBuilder
    private var sourceListView: some View {
        List {
            // 统计信息
            VStack(spacing: 12) {
                statsCard
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            
            // 来源列表
            ForEach(viewModel.sources) { source in
                NavigationLink(destination: SourceAssetListView(sourceId: source.id)) {
                    SourceRowView(source: source)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
            }
            .onDelete { offsets in
                for index in offsets {
                    let source = viewModel.sources[index]
                    viewModel.deleteSource(source)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    

    // MARK: - 统计卡片
    
    @ViewBuilder
    private var statsCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                statItem(
                    icon: "doc.fill",
                    value: "\(viewModel.sources.count)",
                    label: L("stat_file_sources"),
                    color: Color(red: 0.2, green: 0.4, blue: 0.8)
                )
                
                statItem(
                    icon: "cube.box.fill",
                    value: "\(viewModel.assets.count)",
                    label: L("stat_total_assets"),
                    color: Color(red: 0.2, green: 0.7, blue: 0.4)
                )
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.2, green: 0.4, blue: 0.8).opacity(0.06),
                    Color(red: 0.2, green: 0.4, blue: 0.8).opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(14)
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
                .foregroundColor(.primary)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 空状态
    
    @ViewBuilder
    private var emptyStateView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.2, green: 0.4, blue: 0.8).opacity(0.08),
                    Color(red: 0.2, green: 0.4, blue: 0.8).opacity(0.02)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.2, green: 0.4, blue: 0.8).opacity(0.15), Color(red: 0.2, green: 0.4, blue: 0.8).opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 50))
                        .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                }
                
                VStack(spacing: 8) {
                    Text(L("empty_management_title"))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(L("empty_management_hint"))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
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
                .background(Color(red: 0.2, green: 0.4, blue: 0.8).opacity(0.1))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(source.fileName)
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(source.importDate, formatter: dateFormatter)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("·")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(String(format: L("source_assets_count"), source.assetCount))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 来源资产列表

struct SourceAssetListView: View {
    let sourceId: UUID
    @EnvironmentObject var viewModel: AssetViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    var source: AssetSource? {
        viewModel.sources.first(where: { $0.id == sourceId })
    }
    
    var filteredAssets: [Asset] {
        let assets = viewModel.assets(for: sourceId)
        if searchText.isEmpty {
            return assets
        }
        return assets.filter {
            $0.id.contains(searchText) ||
            $0.assetName.contains(searchText) ||
            $0.brand.contains(searchText)
        }
    }
    
    var body: some View {
        List {
            // 来源信息
            if let source = source {
                HStack(spacing: 12) {
                    Image(systemName: "doc.fill")
                        .font(.title3)
                        .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.fileName)
                            .font(.headline)
                        
                        Text(String(format: L("source_assets_count"), source.assetCount))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            
            // 资产列表
            ForEach(filteredAssets) { asset in
                NavigationLink(destination: AssetDetailView(assetId: asset.id)) {
                    AssetRowView(asset: asset)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(source?.fileName ?? L("asset_list_title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: L("search_assets"))
    }
}

#Preview {
    AssetManagementView()
        .environmentObject(AssetViewModel())
}
