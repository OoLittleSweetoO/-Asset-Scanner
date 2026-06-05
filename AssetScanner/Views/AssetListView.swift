import SwiftUI

/// 资产列表视图 — 卡片式 + 渐变空状态
struct AssetListView: View {
    @EnvironmentObject var viewModel: AssetViewModel
    @State private var searchText = ""
    
    var filteredAssets: [Asset] {
        if searchText.isEmpty {
            return viewModel.assets
        }
        return viewModel.assets.filter {
            $0.id.contains(searchText) ||
            $0.assetName.contains(searchText) ||
            $0.brand.contains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.assets.isEmpty {
                    emptyStateView
                } else {
                    assetListView
                }
            }
            .navigationTitle(L("asset_list_title"))
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(String(format: L("asset_count"), filteredAssets.count))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
            }
        }
    }
    
    // MARK: - 资产列表
    
    @ViewBuilder
    private var assetListView: some View {
        List {
            ForEach(filteredAssets) { asset in
                NavigationLink(destination: AssetDetailView(assetId: asset.id)) {
                    AssetRowView(asset: asset)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        viewModel.deleteAsset(asset)
                    } label: {
                        Label(L("delete"), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: L("search_assets"))
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
                    
                    Image(systemName: "tray.full")
                        .font(.system(size: 50))
                        .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                }
                
                VStack(spacing: 8) {
                    Text(L("empty_assets_title"))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(L("empty_assets_hint"))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - 资产行视图

struct AssetRowView: View {
    let asset: Asset
    
    var body: some View {
        HStack(spacing: 14) {
            // 状态指示胶囊
            statusBadge
            
            VStack(alignment: .leading, spacing: 6) {
                Text(asset.assetName)
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(asset.id)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("·")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(asset.brand)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if !asset.location.isEmpty {
                        Text("·")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(asset.location)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(asset.status.displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(statusColor.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var statusColor: Color {
        switch asset.status {
        case .inStock: return Color(red: 0.2, green: 0.7, blue: 0.4)
        case .checkedOut: return Color(red: 1.0, green: 0.55, blue: 0.0)
        case .maintenance: return Color(red: 0.9, green: 0.25, blue: 0.3)
        }
    }
}

#Preview {
    AssetListView()
        .environmentObject(AssetViewModel())
}
