import SwiftUI

// MARK: - 可复用资产管理模块
// 任何 macOS 项目只需传入数据和回调即可使用，零耦合

// MARK: - 来源行

public struct SourceRowData: Identifiable, Hashable {
    public let id: UUID
    public let fileName: String
    public let importDate: Date
    public let assetCount: Int

    public init(id: UUID = UUID(), fileName: String, importDate: Date = Date(), assetCount: Int) {
        self.id = id
        self.fileName = fileName
        self.importDate = importDate
        self.assetCount = assetCount
    }
}

// MARK: - 资产行（用于来源详情页）

public struct AssetRowData: Identifiable, Hashable {
    public let id: String
    public let assetName: String
    public let brand: String
    public let location: String
    public let statusDisplayName: String
    public let statusState: AssetStatusState

    public init(id: String, assetName: String, brand: String, location: String,
                statusDisplayName: String, statusState: AssetStatusState) {
        self.id = id
        self.assetName = assetName
        self.brand = brand
        self.location = location
        self.statusDisplayName = statusDisplayName
        self.statusState = statusState
    }
}

public enum AssetStatusState: String, Codable, CaseIterable {
    case inStock, checkedOut, maintenance, scrapped
}

// MARK: - 主题色

public struct ManagementTheme {
    public var blue: Color
    public var green: Color
    public var orange: Color
    public var red: Color

    public static var `default` = ManagementTheme(
        blue: Color(red: 0.2, green: 0.4, blue: 0.8),
        green: Color(red: 0.2, green: 0.7, blue: 0.4),
        orange: Color(red: 1.0, green: 0.55, blue: 0.0),
        red: Color(red: 0.9, green: 0.25, blue: 0.3)
    )
}

// MARK: - 主视图：资产管理（含统计 + 同步 + 来源列表）

public struct AssetManagementModule: View {
    // 数据
    private let sources: [SourceRowData]
    private let totalAssets: Int
    private let checkOutCount: Int
    @Binding private var syncPath: String
    @Binding private var syncStatus: String

    // 回调
    private let onSelectDirectory: () -> Void
    private let onImport: () -> Void
    private let onExport: () -> Void
    private let onBidirectionalSync: () -> Void
    private let onUpdateSource: (SourceRowData) -> Void
    private let onRenameSource: (SourceRowData) -> Void
    private let onDeleteSource: (SourceRowData) -> Void
    private let onSourceTap: ((SourceRowData) -> Void)?

    // 外观
    private var theme: ManagementTheme

    @State private var searchText = ""

    /// 初始化 — 传入数据和 Binding
    public init(
        sources: [SourceRowData],
        totalAssets: Int = 0,
        checkOutCount: Int = 0,
        syncPath: Binding<String>,
        syncStatus: Binding<String>,
        onSelectDirectory: @escaping () -> Void,
        onImport: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onBidirectionalSync: @escaping () -> Void,
        onUpdateSource: @escaping (SourceRowData) -> Void,
        onRenameSource: @escaping (SourceRowData) -> Void,
        onDeleteSource: @escaping (SourceRowData) -> Void,
        onSourceTap: ((SourceRowData) -> Void)? = nil,
        theme: ManagementTheme = .default
    ) {
        self.sources = sources
        self.totalAssets = totalAssets
        self.checkOutCount = checkOutCount
        self._syncPath = syncPath
        self._syncStatus = syncStatus
        self.onSelectDirectory = onSelectDirectory
        self.onImport = onImport
        self.onExport = onExport
        self.onBidirectionalSync = onBidirectionalSync
        self.onUpdateSource = onUpdateSource
        self.onRenameSource = onRenameSource
        self.onDeleteSource = onDeleteSource
        self.onSourceTap = onSourceTap
        self.theme = theme
    }

    private var filteredSources: [SourceRowData] {
        if searchText.isEmpty { return sources }
        return sources.filter { $0.fileName.contains(searchText) }
    }

    public var body: some View {
        List {
            // 统计卡片
            statsCard
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

            // iCloud 同步区域
            syncSection
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

            // 来源列表
            if !filteredSources.isEmpty {
                ForEach(filteredSources) { source in
                    sourceRow(source)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded { onSourceTap?(source) },
                            including: .all
                        )
                        .contextMenu {
                            Button("更新 CSV") { onUpdateSource(source) }
                            Button("编辑来源名称") { onRenameSource(source) }
                            Divider()
                            Button("删除", role: .destructive) { onDeleteSource(source) }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("更新") { onUpdateSource(source) }
                                .tint(theme.blue)
                            Button("重命名") { onRenameSource(source) }
                                .tint(.gray)
                            Button("删除") { onDeleteSource(source) }
                                .tint(theme.red)
                        }
                }
            } else {
                emptyStateRow
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "搜索文件来源")
    }

    // MARK: - 统计卡片

    private var statsCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                statItem(icon: "doc.fill", value: "\(sources.count)", label: "文件来源", color: theme.blue)
                statItem(icon: "cube.box.fill", value: "\(totalAssets)", label: "资产总数", color: theme.green)
                statItem(icon: "arrow.up.circle.fill", value: "\(checkOutCount)", label: "出库数量", color: theme.orange)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [theme.blue.opacity(0.06), theme.blue.opacity(0.02)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .cornerRadius(14)
    }

    private func statItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundColor(color)
            Text(value).font(.title2).fontWeight(.bold).foregroundColor(.primary)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 同步区域

    private var syncSection: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "icloud.fill").font(.title3).foregroundColor(theme.blue)
                Text("iCloud 文件同步").font(.headline).fontWeight(.medium)
                Spacer()
                if !syncPath.isEmpty {
                    Text(syncPath)
                        .font(.caption2).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }

            VStack(spacing: 10) {
                syncButton(icon: "folder.badge.plus", title: "选择文件夹", color: theme.blue,
                           trailing: syncPath.isEmpty ? nil : "checkmark.circle.fill",
                           action: onSelectDirectory)

                syncButton(icon: "square.and.arrow.down", title: "导入", color: theme.orange,
                           action: onImport)
                .disabled(syncPath.isEmpty)

                syncButton(icon: "square.and.arrow.up", title: "导出", color: theme.green,
                           action: onExport)
                .disabled(syncPath.isEmpty)

                syncButton(icon: "arrow.triangle.2.circlepath", title: "双向同步", color: .purple,
                           action: onBidirectionalSync)
                .disabled(syncPath.isEmpty)
            }

            if syncStatus != "就绪" {
                HStack {
                    Text(syncStatus)
                        .font(.caption)
                        .foregroundColor(syncStatus.contains("失败") || syncStatus.contains("错误") ? theme.red : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
        )
    }

    private func syncButton(icon: String, title: String, color: Color, trailing: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).font(.title3)
                Text(title).font(.headline)
                Spacer()
                if let trailing = trailing { Image(systemName: trailing) }
            }
            .padding()
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 来源行

    private func sourceRow(_ source: SourceRowData) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.fill")
                .font(.title3).foregroundColor(theme.blue)
                .frame(width: 40, height: 40)
                .background(theme.blue.opacity(0.1))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                Text(source.fileName).font(.headline).fontWeight(.medium).lineLimit(1)
                HStack(spacing: 6) {
                    Text(source.importDate, style: .date).font(.caption2).foregroundColor(.secondary)
                    Text("·").font(.caption2).foregroundColor(.secondary)
                    Text("\(source.assetCount) 个资产").font(.caption2).foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption).foregroundColor(.secondary.opacity(0.6))
                .padding(8).contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded { onSourceTap?(source) })
        }
        .padding(.vertical, 8)
    }

    private var emptyStateRow: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
            Text("暂无导入记录").font(.headline).foregroundColor(.secondary)
            Text("点击上方按钮导入 CSV 文件来管理资产")
                .font(.caption).foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 30)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }
}

// MARK: - 来源资产列表（通用）

public struct ModuleSourceAssetListView: View {
    public let sourceName: String
    public let assets: [AssetRowData]
    public var theme: ManagementTheme

    @State private var searchText = ""

    public init(sourceName: String, assets: [AssetRowData], theme: ManagementTheme = .default) {
        self.sourceName = sourceName
        self.assets = assets
        self.theme = theme
    }

    private var filteredAssets: [AssetRowData] {
        if searchText.isEmpty { return assets }
        return assets.filter { $0.id.contains(searchText) || $0.assetName.contains(searchText) || $0.brand.contains(searchText) }
    }

    public var body: some View {
        List {
            HStack(spacing: 12) {
                Image(systemName: "doc.fill").font(.title3).foregroundColor(theme.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(sourceName).font(.headline)
                    Text("\(assets.count) 个资产").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)

            ForEach(filteredAssets) { asset in
                HStack(spacing: 12) {
                    Circle().fill(statusColor(asset.statusState)).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.assetName).font(.body).fontWeight(.medium)
                        HStack(spacing: 4) {
                            Text(asset.id).font(.caption2).foregroundColor(.secondary)
                            if !asset.brand.isEmpty {
                                Text("·").font(.caption2).foregroundColor(.secondary)
                                Text(asset.brand).font(.caption2).foregroundColor(.secondary)
                            }
                            if !asset.location.isEmpty {
                                Text("·").font(.caption2).foregroundColor(.secondary)
                                Text(asset.location).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    Spacer()
                    Text(asset.statusDisplayName)
                        .font(.caption2).foregroundColor(statusColor(asset.statusState))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(statusColor(asset.statusState).opacity(0.1))
                        .cornerRadius(8)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(sourceName)
        .searchable(text: $searchText, prompt: "搜索资产")
    }

    private func statusColor(_ state: AssetStatusState) -> Color {
        switch state {
        case .inStock: return theme.green
        case .checkedOut: return theme.orange
        case .maintenance: return theme.red
        case .scrapped: return .gray
        }
    }
}
