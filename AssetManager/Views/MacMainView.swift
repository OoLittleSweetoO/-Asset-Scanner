import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

// MARK: - 主题色

struct AppTheme {
    static let blue = Color(red: 0.2, green: 0.4, blue: 0.8)
    static let green = Color(red: 0.2, green: 0.7, blue: 0.4)
    static let orange = Color(red: 1.0, green: 0.55, blue: 0.0)
    static let red = Color(red: 0.9, green: 0.25, blue: 0.3)

    static let blueGradient = LinearGradient(colors: [blue, Color(red: 0.15, green: 0.35, blue: 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let greenGradient = LinearGradient(colors: [green, Color(red: 0.15, green: 0.6, blue: 0.35)], startPoint: .leading, endPoint: .trailing)
    static let orangeGradient = LinearGradient(colors: [orange, Color(red: 0.9, green: 0.45, blue: 0.0)], startPoint: .leading, endPoint: .trailing)
}

// MARK: - 主视图

struct MacMainView: View {
    @EnvironmentObject var assetVM: AssetViewModel
    @State private var showImportPanel = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                AssetListView(assetVM: assetVM)
            }
            .tabItem {
                Label("资产列表", systemImage: "list.bullet")
            }
            .tag(0)

            NavigationStack {
                AssetManagementView(assetVM: assetVM)
            }
            .tabItem {
                Label("资产管理", systemImage: "folder.badge.gearshape")
            }
            .tag(1)

            NavigationStack {
                OperationHistoryView(assetVM: assetVM)
            }
            .tabItem {
                Label("历史记录", systemImage: "clock.arrow.circlepath")
            }
            .tag(2)
        }
        .environmentObject(assetVM)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("导入文件", systemImage: "square.and.arrow.down") { showImportPanel = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("帮助", systemImage: "questionmark.circle") {
                    HelpPageService.openAssetManagerHelpPage()
                }
                .help("打开 AssetManager 使用说明")
            }
            ToolbarItem(placement: .primaryAction) {
                syncBadge
            }
        }
        .fileImporter(
            isPresented: $showImportPanel,
            allowedContentTypes: [
                .commaSeparatedText,
                .plainText,
                .text,
                UTType(filenameExtension: "xlsx") ?? .data,
                UTType(mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") ?? .data
            ],
            onCompletion: handleImport
        )
        .alert("操作结果", isPresented: Binding(
            get: { assetVM.errorMessage != nil },
            set: { if !$0 { assetVM.errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(assetVM.errorMessage ?? "")
        }
        .frame(minWidth: 800, minHeight: 550)
    }

    private var syncBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: assetVM.syncStatus.contains("✅") ? "icloud" : assetVM.syncStatus.contains("❌") ? "icloud.slash" : "arrow.clockwise")
                .font(.system(size: 14, weight: .semibold))
            Text(assetVM.syncStatus)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            assetVM.syncStatus.contains("✅") ? AppTheme.green.opacity(0.15) :
            assetVM.syncStatus.contains("❌") ? AppTheme.red.opacity(0.15) :
            Color.gray.opacity(0.1)
        )
        .cornerRadius(8)
        .foregroundColor(
            assetVM.syncStatus.contains("✅") ? AppTheme.green :
            assetVM.syncStatus.contains("❌") ? AppTheme.red :
            .secondary
        )
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task { await assetVM.importAssets(from: url) }
        case .failure(let error):
            assetVM.errorMessage = "导入失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - 资产列表视图

struct AssetListView: View {
    @ObservedObject var assetVM: AssetViewModel
    @EnvironmentObject var vm: AssetViewModel
    @State private var showAddSheet = false
    @State private var showBulkCheckOutSheet = false
    @State private var searchText = ""
    @State private var selection = Set<String>()
    @State private var navigateToAsset: macOS_Asset?  // 用于导航
    @State private var bulkOperatorName = ""
    @State private var bulkNote = ""
    @State private var bulkEstimatedReturnDate = Date()
    @State private var selectedAssetForSheet: macOS_Asset?
    @State private var assetsPendingDeletion: [macOS_Asset] = []
    @State private var bulkCheckOutTargets: [macOS_Asset] = []

    private var selectedAssets: [macOS_Asset] {
        assetVM.assets.filter { selection.contains($0.id) }
    }

    private var selectedAsset: macOS_Asset? {
        selectedAssets.first
    }

    private var filteredAssets: [macOS_Asset] {
        if searchText.isEmpty { return assetVM.assets }
        return assetVM.assets.filter {
            $0.id.contains(searchText) ||
            $0.assetName.contains(searchText) ||
            $0.modelName.contains(searchText) ||
            $0.brand.contains(searchText)
        }
    }

    private var bulkCheckOutAssets: [macOS_Asset] {
        assetVM.assets.filter { $0.status == .inStock }
    }

    private var selectedAssetCount: Int {
        selectedAssets.count
    }

    private var canBatchCheckIn: Bool {
        !selectedAssets.isEmpty && selectedAssets.contains { $0.status != .inStock }
    }

    private var canBatchCheckOut: Bool {
        !selectedAssets.isEmpty && selectedAssets.allSatisfy { $0.status == .inStock }
    }

    private var canBatchMaintenance: Bool {
        !selectedAssets.isEmpty && selectedAssets.contains { $0.status != .maintenance }
    }

    private var canBatchScrap: Bool {
        !selectedAssets.isEmpty && selectedAssets.contains { $0.status != .scrapped }
    }

    var body: some View {
        Group {
            if assetVM.assets.isEmpty {
                emptyStateView(
                    icon: "tray.full",
                    title: "暂无资产",
                    hint: "点击右下角按钮导入 CSV 文件开始管理"
                )
            } else {
                assetListView
            }
        }
        .navigationTitle("资产列表")
        // toolbarBackground removed for macOS
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("\(filteredAssets.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            }
            ToolbarItem(placement: .automatic) {
                Button("一键全部出库", systemImage: "arrow.up.circle") {
                    bulkOperatorName = ""
                    bulkNote = ""
                    bulkEstimatedReturnDate = Date()
                    bulkCheckOutTargets = bulkCheckOutAssets
                    showBulkCheckOutSheet = true
                }
                .disabled(bulkCheckOutAssets.isEmpty)
            }
            ToolbarItemGroup(placement: .automatic) {
                Button("归还", systemImage: "arrow.down.circle") {
                    guard let selectedAsset else { return }
                    assetVM.restoreToInStock(asset: selectedAsset)
                }
                .disabled(selectedAsset == nil || selectedAsset?.status == .inStock)

                Button("送修", systemImage: "wrench.and.screwdriver") {
                    guard let selectedAsset else { return }
                    assetVM.markForMaintenance(asset: selectedAsset)
                }
                .disabled(selectedAsset == nil || selectedAsset?.status == .maintenance)

                Button("报废", systemImage: "trash.slash") {
                    guard let selectedAsset else { return }
                    assetVM.markAsScrapped(asset: selectedAsset)
                }
                .disabled(selectedAsset == nil || selectedAsset?.status == .scrapped)

                Button("出库", systemImage: "arrow.up.circle.fill") {
                    guard selectedAsset != nil else { return }
                    showBulkCheckOutSheet = false
                    operatorNameForSelectedAsset()
                }
                .disabled(selectedAsset == nil || selectedAsset?.status != .inStock)
            }
            ToolbarItem(placement: .automatic) {
                Button("添加", systemImage: "plus") { showAddSheet = true }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                AddAssetView(assetVM: assetVM)
            }
        }
        .sheet(isPresented: $showBulkCheckOutSheet) {
            BulkCheckOutSheetView(
                assets: bulkCheckOutTargets,
                operatorName: $bulkOperatorName,
                note: $bulkNote,
                estimatedReturnDate: $bulkEstimatedReturnDate
            ) {
                let targetIDs = Set(bulkCheckOutTargets.map(\.id))
                assetVM.updateAssets(
                    withIDs: targetIDs,
                    to: .checkedOut,
                    operatorName: bulkOperatorName,
                    note: bulkNote.isEmpty ? nil : bulkNote,
                    estimatedReturnDate: bulkEstimatedReturnDate
                )
            }
        }
        .sheet(item: Binding(
            get: { selectedAssetForSheet },
            set: { _ in selectedAssetForSheet = nil }
        )) { asset in
            CheckOutSheetView(
                asset: asset,
                operatorName: $bulkOperatorName,
                note: $bulkNote,
                estimatedReturnDate: $bulkEstimatedReturnDate
            ) {
                assetVM.checkOut(
                    asset: asset,
                    operatorName: bulkOperatorName,
                    note: bulkNote.isEmpty ? nil : bulkNote,
                    estimatedReturnDate: bulkEstimatedReturnDate
                )
            }
        }
        .confirmationDialog(
            deletionDialogTitle,
            isPresented: Binding(
                get: { !assetsPendingDeletion.isEmpty },
                set: { if !$0 { assetsPendingDeletion = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除设备", role: .destructive) {
                assetVM.deleteAssets(withIDs: Set(assetsPendingDeletion.map(\.id)))
                selection.subtract(assetsPendingDeletion.map(\.id))
                assetsPendingDeletion = []
            }
            Button("取消", role: .cancel) {
                assetsPendingDeletion = []
            }
        } message: {
            Text(deletionDialogMessage)
        }
    }

    private func operatorNameForSelectedAsset() {
        guard let selectedAsset else { return }
        bulkOperatorName = ""
        bulkNote = ""
        bulkEstimatedReturnDate = Date()
        selectedAssetForSheet = selectedAsset
    }

    private func prepareBatchCheckOut() {
        bulkOperatorName = ""
        bulkNote = ""
        bulkEstimatedReturnDate = Date()
        bulkCheckOutTargets = selectedAssets.filter { $0.status == .inStock }
        showBulkCheckOutSheet = true
    }

    private func requestDelete(_ assets: [macOS_Asset]) {
        assetsPendingDeletion = assets
    }

    private var deletionDialogTitle: String {
        assetsPendingDeletion.count == 1 ? "删除这个设备条目？" : "删除选中的设备条目？"
    }

    private var deletionDialogMessage: String {
        "删除后会同时清理对应的历史记录与来源关联，无法撤销。"
    }

    @ViewBuilder
    private var assetListView: some View {
        List(selection: $selection) {
            ForEach(filteredAssets) { asset in
                AssetRowView(asset: asset, sourceName: assetVM.sourceName(for: asset), onChevronTap: {
                    navigateToAsset = asset
                })
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .tag(asset.id)
                .contextMenu {
                    assetStatusMenu(for: asset)
                }
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            navigateToAsset = asset
                        },
                    including: .all
                )
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "搜索外编号、名称、型号、品牌")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if selectedAssetCount > 0 {
                    Text("已选 \(selectedAssetCount)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            ToolbarItem(placement: .automatic) {
                Menu("批量状态", systemImage: "square.stack.3d.up") {
                    Button("批量入库", systemImage: "arrow.down.circle") {
                        assetVM.updateAssets(withIDs: selection, to: .inStock)
                    }
                    .disabled(!canBatchCheckIn)

                    Button("批量出库", systemImage: "arrow.up.circle.fill") {
                        prepareBatchCheckOut()
                    }
                    .disabled(!canBatchCheckOut)

                    Button("批量送修", systemImage: "wrench.and.screwdriver") {
                        assetVM.updateAssets(withIDs: selection, to: .maintenance)
                    }
                    .disabled(!canBatchMaintenance)

                    Button("批量报废", systemImage: "trash.slash") {
                        assetVM.updateAssets(withIDs: selection, to: .scrapped)
                    }
                    .disabled(!canBatchScrap)
                }
                .disabled(selectedAssetCount == 0)
            }
            ToolbarItem(placement: .automatic) {
                Button("删除", systemImage: "trash") {
                    requestDelete(selectedAssets)
                }
                .disabled(selectedAssetCount == 0)
            }
        }
        .navigationDestination(item: $navigateToAsset) { asset in
            AssetDetailView(asset: asset)
        }
    }

    @ViewBuilder
    private func assetStatusMenu(for asset: macOS_Asset) -> some View {
        Button("归还", systemImage: "arrow.down.circle") {
            assetVM.restoreToInStock(asset: asset)
        }
        .disabled(asset.status == .inStock)

        Button("送修", systemImage: "wrench.and.screwdriver") {
            assetVM.markForMaintenance(asset: asset)
        }
        .disabled(asset.status == .maintenance)

        Button("报废", systemImage: "trash.slash") {
            assetVM.markAsScrapped(asset: asset)
        }
        .disabled(asset.status == .scrapped)

        Button("出库", systemImage: "arrow.up.circle.fill") {
            bulkOperatorName = ""
            bulkNote = ""
            bulkEstimatedReturnDate = Date()
            selectedAssetForSheet = asset
        }
        .disabled(asset.status != .inStock)

        Divider()

        Button("查看详情", systemImage: "chevron.right") {
            navigateToAsset = asset
        }

        Button("删除设备", systemImage: "trash", role: .destructive) {
            requestDelete([asset])
        }
    }

    @ViewBuilder
    private func emptyStateView(icon: String, title: String, hint: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.blue.opacity(0.08), AppTheme.blue.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.blue.opacity(0.15), AppTheme.blue.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)

                    Image(systemName: icon)
                        .font(.system(size: 50))
                        .foregroundColor(AppTheme.blue)
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(hint)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}

// MARK: - 资产行视图

struct AssetRowView: View {
    let asset: macOS_Asset
    let sourceName: String?
    var onChevronTap: (() -> Void)? = nil

    private var detailText: String {
        let detailValues: [String] = [
            asset.id,
            asset.internalCode,
            asset.brand,
            asset.modelName,
            noteValue(for: "保管科室"),
            noteValue(for: "使用人"),
            noteValue(for: "二级状态"),
            noteValue(for: "二级存放地"),
            noteValue(for: "其他附件"),
            sourceName.map { "来源：\($0)" } ?? ""
        ]

        return detailValues
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "  ·  ")
    }
    
    var body: some View {
        HStack(spacing: 14) {
            statusBadge

            VStack(alignment: .leading, spacing: 6) {
                Text(asset.assetName)
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(detailText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
                .padding(8)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    TapGesture()
                        .onEnded {
                            onChevronTap?()
                        }
                )
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
        case .inStock: return AppTheme.green
        case .checkedOut: return AppTheme.orange
        case .maintenance: return AppTheme.red
        case .scrapped: return .gray
        }
    }

    private func noteValue(for label: String) -> String {
        guard let note = asset.note else { return "" }
        let prefix = "\(label)："
        for line in note.components(separatedBy: .newlines) {
            guard line.hasPrefix(prefix) else { continue }
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
}

// MARK: - 资产管理视图（薄适配层 → AssetManagementModule）

struct AssetManagementView: View {
    @ObservedObject var assetVM: AssetViewModel
    @State private var navigateToSource: macOS_AssetSource?
    @State private var showSettings = false
    @State private var sourcePendingDeletion: macOS_AssetSource?
    @State private var sourcePendingRename: macOS_AssetSource?
    @State private var sourceRenameDraft = ""
    @State private var pendingSourceUpdate: SourceUpdatePreview?

    var body: some View {
        AssetManagementModule(
            sources: assetVM.sources.map {
                SourceRowData(id: $0.id, fileName: $0.fileName, importDate: $0.importDate, assetCount: $0.assetCount)
            },
            totalAssets: assetVM.assets.count,
            checkOutCount: assetVM.checkedOutAssetCount,
            syncPath: Binding(
                get: { assetVM.syncService.syncPath },
                set: { assetVM.syncService.setSyncPath($0) }
            ),
            syncStatus: $assetVM.syncStatus,
            onSelectDirectory: {
                let panel = NSOpenPanel()
                panel.title = "选择同步目录"
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.canCreateDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                    assetVM.syncService.setSyncDirectoryURL(url)
                }
            },
            onImport: { assetVM.importFromSync() },
            onExport: { assetVM.exportToSync() },
            onBidirectionalSync: { assetVM.bidirectionalSync() },
            onUpdateSource: { row in
                guard let source = assetVM.sources.first(where: { $0.id == row.id }) else { return }

                let panel = NSOpenPanel()
                panel.title = "选择用于更新的 CSV / XLSX 文件"
                panel.allowedContentTypes = [
                    .commaSeparatedText,
                    .plainText,
                    .text,
                    UTType(filenameExtension: "xlsx") ?? .data,
                    UTType(mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") ?? .data
                ]
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false

                if panel.runModal() == .OK, let url = panel.url {
                    Task {
                        guard let preview = await assetVM.prepareSourceUpdate(source, from: url) else { return }
                        if preview.removedAssetIDs.isEmpty {
                            assetVM.applySourceUpdate(preview)
                        } else {
                            pendingSourceUpdate = preview
                        }
                    }
                }
            },
            onRenameSource: { row in
                guard let source = assetVM.sources.first(where: { $0.id == row.id }) else { return }
                sourceRenameDraft = source.fileName
                sourcePendingRename = source
            },
            onDeleteSource: { row in
                if let source = assetVM.sources.first(where: { $0.id == row.id }) {
                    sourcePendingDeletion = source
                }
            },
            onSourceTap: { row in
                if let source = assetVM.sources.first(where: { $0.id == row.id }) {
                    navigateToSource = source
                }
            },
            theme: ManagementTheme(
                blue: AppTheme.blue,
                green: AppTheme.green,
                orange: AppTheme.orange,
                red: AppTheme.red
            )
        )
        .navigationTitle("资产管理")
        .navigationDestination(item: $navigateToSource) { source in
            SourceAssetDetailListView(source: source, assetVM: assetVM)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("设置", systemImage: "gearshape") {
                    showSettings = true
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SyncSettingsView(assetVM: assetVM)
                .frame(minWidth: 600, minHeight: 500)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") {
                            showSettings = false
                        }
                    }
                }
        }
        .alert(
            "删除来源「\(sourcePendingDeletion?.fileName ?? "")」？",
            isPresented: Binding(
                get: { sourcePendingDeletion != nil },
                set: { if !$0 { sourcePendingDeletion = nil } }
            ),
            presenting: sourcePendingDeletion
        ) { source in
            Button("删除", role: .destructive) {
                assetVM.deleteSource(source)
                sourcePendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                sourcePendingDeletion = nil
            }
        } message: { source in
            Text("会同时删除该来源下的 \(source.assetCount) 个资产及相关历史记录，无法撤销。")
        }
        .sheet(item: $sourcePendingRename) { source in
            RenameSourceSheet(
                title: "编辑来源名称",
                initialName: sourceRenameDraft,
                onCancel: { sourcePendingRename = nil },
                onSave: { newName in
                    assetVM.renameSource(source, to: newName)
                    sourcePendingRename = nil
                }
            )
        }
        .sheet(item: $pendingSourceUpdate) { preview in
            SourceUpdateConfirmationSheet(
                preview: preview,
                onCancel: { pendingSourceUpdate = nil },
                onConfirm: {
                    assetVM.applySourceUpdate(preview)
                    pendingSourceUpdate = nil
                }
            )
        }
    }
}

// MARK: - 来源行视图

struct SourceRowView: View {
    let source: macOS_AssetSource
    var onChevronTap: (() -> Void)? = nil

    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.fill")
                .font(.title3)
                .foregroundColor(AppTheme.blue)
                .frame(width: 40, height: 40)
                .background(AppTheme.blue.opacity(0.1))
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

                    Text("\(source.assetCount) 个资产")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
                .padding(8)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    TapGesture()
                        .onEnded {
                            onChevronTap?()
                        }
                )
        }
        .padding(.vertical, 8)
    }
}

struct RenameSourceSheet: View {
    let title: String
    let initialName: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var draftName: String

    init(title: String, initialName: String, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.title = title
        self.initialName = initialName
        self.onCancel = onCancel
        self.onSave = onSave
        _draftName = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            TextField("来源名称", text: $draftName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("取消") { onCancel() }
                Button("保存") { onSave(draftName) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }
}

struct SourceUpdateConfirmationSheet: View {
    let preview: SourceUpdatePreview
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("确认更新来源")
                .font(.title3)
                .fontWeight(.semibold)

            Text("将按外编码优先比对并保留已命中条目的当前出入库状态。以下条目在新 CSV 中已消失，确认后会批量删除：")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                statusPill(title: "新增", value: "\(preview.addedCount)", color: AppTheme.green)
                statusPill(title: "保持/更新", value: "\(preview.updatedCount)", color: AppTheme.blue)
                statusPill(title: "待删除", value: "\(preview.removedAssetIDs.count)", color: AppTheme.red)
            }

            List(preview.removedAssets) { asset in
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.assetName)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(asset.externalCode)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(asset.statusDisplayName)
                            .font(.caption)
                            .foregroundColor(statusColor(for: asset.statusDisplayName))
                    }
                }
            }
            .frame(minHeight: 220)

            HStack {
                Spacer()
                Button("取消") { onCancel() }
                Button("确认批量删除并更新") { onConfirm() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420)
    }

    @ViewBuilder
    private func statusPill(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .cornerRadius(10)
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "在库":
            return AppTheme.green
        case "已出库":
            return AppTheme.orange
        case "送修":
            return AppTheme.red
        case "待报废":
            return .gray
        default:
            return .secondary
        }
    }
}

// MARK: - 来源资产列表

struct SourceAssetDetailListView: View {
    let source: macOS_AssetSource
    @ObservedObject var assetVM: AssetViewModel
    @State private var searchText = ""
    @State private var selection: macOS_Asset?        // 用于高亮
    @State private var navigateToAsset: macOS_Asset?  // 用于导航

    private var filteredAssets: [macOS_Asset] {
        let sourceAssetIDs = Set(source.assetIds)
        let assets = assetVM.assets.filter { $0.sourceId == source.id || ($0.sourceId == nil && sourceAssetIDs.contains($0.id)) }
        if searchText.isEmpty { return assets }
        return assets.filter {
            $0.id.contains(searchText) ||
            $0.assetName.contains(searchText) ||
            $0.brand.contains(searchText)
        }
    }

    var body: some View {
        List(selection: $selection) {
            // 来源信息
            HStack(spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.title3)
                    .foregroundColor(AppTheme.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(source.fileName)
                        .font(.headline)

                    Text("\(source.assetCount) 个资产")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)

            // 资产列表
            ForEach(filteredAssets) { asset in
                AssetRowView(asset: asset, sourceName: assetVM.sourceName(for: asset), onChevronTap: {
                    navigateToAsset = asset
                })
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .tag(asset)
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            navigateToAsset = asset
                        },
                    including: .all
                )
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(source.fileName)
        .searchable(text: $searchText, prompt: "搜索资产")
        .navigationDestination(item: $navigateToAsset) { asset in
            AssetDetailView(asset: asset)
        }
    }
}

// MARK: - 历史记录视图

struct OperationHistoryView: View {
    @ObservedObject var assetVM: AssetViewModel
    @StateObject private var remindersService = RemindersService()
    @State private var showSyncAlert = false
    @State private var showClearAllConfirmation = false
    @State private var editingRecord: macOS_OperationRecord?
    @State private var selectedRecordIds: Set<UUID> = []
    @State private var isSyncingSelected = false
    @State private var searchText = ""

    private var filteredRecords: [macOS_OperationRecord] {
        if searchText.isEmpty { return assetVM.operationRecords }
        return assetVM.operationRecords.filter {
            $0.assetId.contains(searchText) ||
            $0.assetName.contains(searchText) ||
            $0.operatorName.contains(searchText)
        }
    }

    private var selectedSyncableRecords: [macOS_OperationRecord] {
        assetVM.operationRecords.filter {
            selectedRecordIds.contains($0.id) &&
            $0.type == .checkOut &&
            $0.estimatedReturnDate != nil
        }
    }

    var body: some View {
        Group {
            if assetVM.operationRecords.isEmpty {
                emptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "暂无操作记录",
                    hint: "出库或归还资产后,这里将显示操作历史"
                )
            } else {
                recordListView
            }
        }
        .navigationTitle("历史记录")
        // toolbarBackground removed for macOS
        .confirmationDialog("清空全部历史记录？", isPresented: $showClearAllConfirmation, titleVisibility: .visible) {
            Button("清空全部记录", role: .destructive) {
                assetVM.clearOperationRecords()
                selectedRecordIds.removeAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除当前所有出入库历史记录。")
        }
    }

    @ViewBuilder
    private var recordListView: some View {
        List {
            ForEach(filteredRecords) { record in
                HStack {
                    Image(systemName: selectedRecordIds.contains(record.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedRecordIds.contains(record.id) ? AppTheme.blue : Color.secondary)
                        .onTapGesture {
                            if selectedRecordIds.contains(record.id) {
                                selectedRecordIds.remove(record.id)
                            } else {
                                selectedRecordIds.insert(record.id)
                            }
                        }

                    RecordRowView(record: record)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .contextMenu {
                    Button {
                        editingRecord = record
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }

                    Divider()

                    Button(role: .destructive) {
                        assetVM.deleteRecord(record)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        assetVM.deleteRecord(record)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    let record = filteredRecords[index]
                    assetVM.deleteRecord(record)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "搜索条码、名称、操作人")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if !assetVM.operationRecords.isEmpty {
                    Button(selectedRecordIds.count == filteredRecords.count && !filteredRecords.isEmpty ? "取消全选" : "全选") {
                        if selectedRecordIds.count == filteredRecords.count && !filteredRecords.isEmpty {
                            selectedRecordIds.subtract(filteredRecords.map(\.id))
                        } else {
                            selectedRecordIds.formUnion(filteredRecords.map(\.id))
                        }
                    }
                }
            }
            ToolbarItem(placement: .automatic) {
                if !selectedRecordIds.isEmpty {
                    Button("删除选中") {
                        assetVM.deleteRecords(withIDs: selectedRecordIds)
                        selectedRecordIds.removeAll()
                    }
                }
            }
            ToolbarItem(placement: .automatic) {
                if !selectedRecordIds.isEmpty {
                    Button("同步选中") {
                        Task { await syncSelectedRecords() }
                    }
                    .disabled(isSyncingSelected || selectedSyncableRecords.isEmpty)
                }
            }
            ToolbarItem(placement: .automatic) {
                if !assetVM.operationRecords.isEmpty {
                    Button(action: {
                        Task {
                            let syncedIds = await remindersService.syncCheckOutRecords(assetVM.operationRecords)
                            for recordId in syncedIds {
                                if let idx = assetVM.operationRecords.firstIndex(where: { $0.id == recordId }) {
                                    var updated = assetVM.operationRecords[idx]
                                    updated.isSyncedToReminders = true
                                    assetVM.operationRecords[idx] = updated
                                    assetVM.saveToStorage()
                                }
                            }
                            showSyncAlert = true
                        }
                    }) {
                        if remindersService.isSyncing {
                            ProgressView()
                        } else {
                            Label("同步 Reminder", systemImage: "arrow.clockwise.circle")
                        }
                    }
                    .disabled(remindersService.isSyncing)
                }
            }
            ToolbarItem(placement: .automatic) {
                if !assetVM.operationRecords.isEmpty {
                    Button("清空历史") {
                        showClearAllConfirmation = true
                    }
                }
            }
        }
        .alert("同步提醒事项", isPresented: $showSyncAlert) {
            Button("确定") {}
        } message: {
            Text(remindersService.syncMessage ?? "同步完成")
        }
        .sheet(item: $editingRecord) { record in
            EditOperationRecordSheetView(
                assetVM: assetVM,
                record: record
            )
        }
    }

    @ViewBuilder
    private func emptyStateView(icon: String, title: String, hint: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.blue.opacity(0.08), AppTheme.blue.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.blue.opacity(0.15), AppTheme.blue.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)

                    Image(systemName: icon)
                        .font(.system(size: 50))
                        .foregroundColor(AppTheme.blue)
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(hint)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func syncSelectedRecords() async {
        isSyncingSelected = true
        var successCount = 0

        for record in selectedSyncableRecords {
            let synced = await remindersService.syncRecordToReminders(record)
            if synced {
                if let idx = assetVM.operationRecords.firstIndex(where: { $0.id == record.id }) {
                    var updated = assetVM.operationRecords[idx]
                    updated.isSyncedToReminders = true
                    assetVM.operationRecords[idx] = updated
                    assetVM.saveToStorage()
                }
                successCount += 1
            }
        }

        selectedRecordIds.removeAll()

        if successCount > 0 {
            remindersService.syncMessage = "已同步 \(successCount) 条记录到提醒事项"
            showSyncAlert = true
        }

        isSyncingSelected = false
    }
}

struct EditOperationRecordSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var assetVM: AssetViewModel
    let record: macOS_OperationRecord

    @State private var operatorName: String
    @State private var note: String
    @State private var hasEstimatedReturnDate: Bool
    @State private var estimatedReturnDate: Date

    init(assetVM: AssetViewModel, record: macOS_OperationRecord) {
        self.assetVM = assetVM
        self.record = record
        _operatorName = State(initialValue: record.operatorName)
        _note = State(initialValue: record.note ?? "")
        _hasEstimatedReturnDate = State(initialValue: record.estimatedReturnDate != nil)
        _estimatedReturnDate = State(initialValue: record.estimatedReturnDate ?? Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("编辑历史记录")
                    .font(.title3.weight(.semibold))
                Text("\(record.assetName) · \(record.type.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)

            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("操作信息")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("操作人")
                                .font(.subheadline.weight(.medium))
                            TextField("输入操作人", text: $operatorName)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("备注")
                                .font(.subheadline.weight(.medium))
                            TextEditor(text: $note)
                                .frame(minHeight: 88)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(NSColor.textBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                )
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(NSColor.windowBackgroundColor))
                    )

                    if record.type == .checkOut {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("预计归还")
                                .font(.headline)

                            Toggle("设置预计归还时间", isOn: $hasEstimatedReturnDate)
                                .toggleStyle(.switch)

                            if hasEstimatedReturnDate {
                                DatePicker(
                                    "归还时间",
                                    selection: $estimatedReturnDate,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .datePickerStyle(.compact)
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(NSColor.windowBackgroundColor))
                        )
                    }
                }
                .padding(24)
            }
            .background(Color(NSColor.controlBackgroundColor))

            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("保存") {
                    assetVM.updateRecord(
                        record.id,
                        operatorName: operatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "当前用户" : operatorName.trimmingCharacters(in: .whitespacesAndNewlines),
                        note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines),
                        estimatedReturnDate: hasEstimatedReturnDate ? estimatedReturnDate : nil
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.bar)
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

// MARK: - 记录行视图

struct RecordRowView: View {
    let record: macOS_OperationRecord

    var typeIcon: String {
        switch record.type {
        case .checkIn: return "arrow.down.circle.fill"
        case .checkOut: return "arrow.up.circle.fill"
        case .repair: return "wrench.and.screwdriver.fill"
        case .scrap: return "trash.slash.fill"
        }
    }

    var typeColor: Color {
        switch record.type {
        case .checkIn: return AppTheme.green
        case .checkOut: return AppTheme.orange
        case .repair: return AppTheme.red
        case .scrap: return .gray
        }
    }

    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: typeIcon)
                .foregroundColor(.white)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(typeColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(record.assetName)
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(record.type.displayName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(typeColor)
                        .cornerRadius(8)

                    Text(record.operatorName)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if record.type == .checkOut && record.estimatedReturnDate != nil {
                        if record.isSyncedToReminders {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Text(dateFormatter.string(from: record.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if record.type == .checkOut, let returnDate = record.estimatedReturnDate {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundColor(AppTheme.blue)
                        Text("预计归还")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(returnDate, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if let note = record.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 添加资产视图

struct AddAssetView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var assetVM: AssetViewModel
    @State private var asset: macOS_Asset

    init(assetVM: AssetViewModel) {
        self.assetVM = assetVM
        _asset = State(initialValue: macOS_Asset(
            id: "", assetName: "", modelName: "", brand: "",
            status: .inStock, internalCode: "", location: ""
        ))
    }

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("外编号", text: $asset.id)
                TextField("名称", text: $asset.assetName)
                TextField("型号", text: $asset.modelName)
                TextField("品牌", text: $asset.brand)
                TextField("内编号", text: $asset.internalCode)
                TextField("存放地", text: $asset.location)
            }

            Section("状态") {
                Picker("状态", selection: $asset.status) {
                    ForEach(macOS_AssetStatus.allCases, id: \.self) { status in
                        Text(status.displayName).tag(status)
                    }
                }

                TextField("采购日期 (yyyy-MM-dd)", text: Binding(
                    get: { asset.purchaseDate?.toString() ?? "" },
                    set: { if !$0.isEmpty { asset.purchaseDate = parseDate($0) } }
                ))
            }

            Section("备注") {
                TextEditor(text: Binding(
                    get: { asset.note ?? "" },
                    set: { asset.note = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 60)
            }
        }
        .navigationTitle("添加资产")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(asset.id.isEmpty || asset.assetName.isEmpty)
            }
        }
    }

    private func save() {
        if asset.id.isEmpty {
            assetVM.errorMessage = "外编号不能为空"
            return
        }
        assetVM.assets.append(asset)
        assetVM.saveToStorage()
        assetVM.errorMessage = "添加成功"
        dismiss()
    }

    private func parseDate(_ string: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: string)
    }
}

struct BulkCheckOutSheetView: View {
    let assets: [macOS_Asset]
    @Binding var operatorName: String
    @Binding var note: String
    @Binding var estimatedReturnDate: Date
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var canSubmit: Bool {
        !assets.isEmpty && !operatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var previewNames: String {
        assets.prefix(3).map(\.assetName).joined(separator: "、")
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 18) {
                    summaryCard
                    formCard
                }
                .padding(20)
            }

            actionBar
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 480, idealHeight: 540)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppTheme.orange.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(AppTheme.orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("批量办理出库")
                    .font(.title2.weight(.semibold))
                Text("将对 \(assets.count) 个选中设备执行出库")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.75))
    }

    private var summaryCard: some View {
        VStack(spacing: 0) {
            detailRow(label: "处理数量", value: "\(assets.count) 个")
            Divider().padding(.leading, 16)
            detailRow(label: "处理范围", value: "当前选中的设备")
            Divider().padding(.leading, 16)
            detailRow(
                label: "示例资产",
                value: assets.isEmpty ? "-" : "\(previewNames)\(assets.count > 3 ? " 等" : "")",
                accent: AppTheme.orange
            )
        }
        .background(panelBackground)
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("出库信息")
                .font(.headline)

            labeledField(title: "操作人") {
                TextField("填写借用人或经手人", text: $operatorName)
                    .textFieldStyle(.roundedBorder)
            }

            labeledField(title: "预计归还时间") {
                DatePicker(
                    "",
                    selection: $estimatedReturnDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("备注")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)

                TextEditor(text: $note)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 110)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            }
        }
        .padding(18)
        .background(panelBackground)
    }

    private var actionBar: some View {
        HStack {
            Button("取消") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("确认全部出库") {
                onConfirm()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.orange)
            .disabled(!canSubmit)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
    }

    private func detailRow(label: String, value: String, accent: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 86, alignment: .leading)

            Spacer()

            Text(value.isEmpty ? "-" : value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(accent ?? .primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
            content()
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(NSColor.controlBackgroundColor))
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
    }
}

// MARK: - 资产详情视图

struct AssetDetailView: View {
    let asset: macOS_Asset
    @EnvironmentObject var assetVM: AssetViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showCheckIn = false
    @State private var showCheckOut = false
    @State private var showDeleteConfirmation = false
    @State private var operatorName = "当前用户"
    @State private var note = ""
    @State private var estimatedReturnDate = Date()
    
    private var currentAsset: macOS_Asset {
        assetVM.assets.first(where: { $0.id == asset.id }) ?? asset
    }

    var statusColor: Color {
        switch currentAsset.status {
        case .inStock: return AppTheme.green
        case .checkedOut: return AppTheme.orange
        case .maintenance: return AppTheme.red
        case .scrapped: return .gray
        }
    }

    var statusGradient: [Color] {
        switch currentAsset.status {
        case .inStock:
            return [AppTheme.green, Color(red: 0.15, green: 0.6, blue: 0.35)]
        case .checkedOut:
            return [AppTheme.orange, Color(red: 0.9, green: 0.45, blue: 0.0)]
        case .maintenance:
            return [AppTheme.red, Color(red: 0.8, green: 0.2, blue: 0.25)]
        case .scrapped:
            return [.gray, Color(red: 0.35, green: 0.35, blue: 0.38)]
        }
    }

    var statusIcon: String {
        switch currentAsset.status {
        case .inStock: return "checkmark.circle.fill"
        case .checkedOut: return "arrow.up.circle.fill"
        case .maintenance: return "wrench.and.screwdriver"
        case .scrapped: return "trash.slash.fill"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 状态卡片
                statusCard

                // 信息区
                infoSection

                // 最近出库记录
                recentCheckOutRecords

                // 操作按钮
                actionButtons
            }
        }
        .background(Color(.windowBackgroundColor))
        .navigationTitle(currentAsset.assetName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("删除设备", systemImage: "trash") {
                    showDeleteConfirmation = true
                }
            }
        }
        .alert("确认归还", isPresented: $showCheckIn) {
            TextField("操作人", text: $operatorName)
            TextField("备注", text: $note)
            Button("确认") {
                assetVM.checkIn(asset: currentAsset, operatorName: operatorName, note: note.isEmpty ? nil : note)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确认归还「\(currentAsset.assetName)」?")
        }
        .confirmationDialog("删除这个设备条目？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("删除设备", role: .destructive) {
                assetVM.deleteAsset(currentAsset)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后会同时清理对应的历史记录与来源关联，无法撤销。")
        }
        .sheet(isPresented: $showCheckOut) {
            CheckOutSheetView(
                asset: currentAsset,
                operatorName: $operatorName,
                note: $note,
                estimatedReturnDate: $estimatedReturnDate
            ) {
                assetVM.checkOut(
                    asset: currentAsset,
                    operatorName: operatorName,
                    note: note.isEmpty ? nil : note,
                    estimatedReturnDate: estimatedReturnDate
                )
            }
        }
    }

    // MARK: - 状态卡片

    @ViewBuilder
    private var statusCard: some View {
        ZStack {
            LinearGradient(
                colors: statusGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.system(size: 44))
                    .foregroundColor(.white)
                    .shadow(radius: 4)

                Text(currentAsset.assetName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                HStack(spacing: 6) {
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                    Text(currentAsset.status.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.2))
                .cornerRadius(16)

                Text(currentAsset.id)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.vertical, 32)
        }
        .cornerRadius(16)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .shadow(color: statusColor.opacity(0.3), radius: 12, x: 0, y: 4)
    }

    // MARK: - 信息区

    @ViewBuilder
    private var infoSection: some View {
        VStack(spacing: 0) {
            infoRow(label: "内编号", value: currentAsset.internalCode)
            Divider().padding(.leading, 16)
            infoRow(label: "品牌", value: currentAsset.brand)
            Divider().padding(.leading, 16)
            infoRow(label: "型号", value: currentAsset.modelName)
            Divider().padding(.leading, 16)
            infoRow(label: "存放地", value: currentAsset.location)
            Divider().padding(.leading, 16)
            if let date = currentAsset.purchaseDate {
                infoRow(label: "采购日期", value: date, formatter: Self.dateFormatter)
                Divider().padding(.leading, 16)
            }
            infoRow(label: "最后更新", value: currentAsset.lastUpdated, formatter: Self.dateTimeFormatter)
        }
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Spacer()
            Text(value.isEmpty ? "-" : value)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func infoRow(label: String, value: Date, formatter: DateFormatter) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Spacer()
            Text(value, formatter: formatter)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 最近出库记录

    @ViewBuilder
    private var recentCheckOutRecords: some View {
        let recentRecords = assetVM.getRecentCheckOutRecords(for: currentAsset.id, limit: 3)

        if !recentRecords.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Text("最近出库记录")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                ForEach(recentRecords.indices, id: \.self) { index in
                    let record = recentRecords[index]
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(AppTheme.orange)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(record.operatorName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Text(record.timestamp, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    if record.estimatedReturnDate != nil {
                                        Label("预计归还", systemImage: "calendar")
                                            .font(.caption2)
                                            .foregroundColor(AppTheme.blue)
                                    }
                                }

                                if let note = record.note {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        if index < recentRecords.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
            .background(Color(.windowBackgroundColor))
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    // MARK: - 操作按钮

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: { showCheckIn = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("归还")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.greenGradient)
                .cornerRadius(12)
            }
            .disabled(currentAsset.status == .inStock)
            .opacity(currentAsset.status == .inStock ? 0.4 : 1)

            Button(action: { showCheckOut = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("出库")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.orangeGradient)
                .cornerRadius(12)
            }
            .disabled(currentAsset.status != .inStock)
            .opacity(currentAsset.status != .inStock ? 0.4 : 1)

            Button(action: { assetVM.markForMaintenance(asset: currentAsset) }) {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                    Text("送修")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [AppTheme.red, Color(red: 0.8, green: 0.2, blue: 0.25)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .disabled(currentAsset.status == .maintenance)
            .opacity(currentAsset.status == .maintenance ? 0.4 : 1)

            Button(action: { assetVM.markAsScrapped(asset: currentAsset) }) {
                HStack(spacing: 8) {
                    Image(systemName: "trash.slash.fill")
                    Text("报废")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [.gray, Color(red: 0.35, green: 0.35, blue: 0.38)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .disabled(currentAsset.status == .scrapped)
            .opacity(currentAsset.status == .scrapped ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 32)
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

struct CheckOutSheetView: View {
    let asset: macOS_Asset
    @Binding var operatorName: String
    @Binding var note: String
    @Binding var estimatedReturnDate: Date
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var canSubmit: Bool {
        !operatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 18) {
                    summaryCard
                    formCard
                }
                .padding(20)
            }

            actionBar
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 460, idealHeight: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppTheme.orange.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(AppTheme.orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("办理出库")
                    .font(.title2.weight(.semibold))
                Text(asset.assetName)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.75))
    }

    private var summaryCard: some View {
        VStack(spacing: 0) {
            detailRow(label: "外编号", value: asset.id)
            Divider().padding(.leading, 16)
            detailRow(label: "品牌 / 型号", value: [asset.brand, asset.modelName].filter { !$0.isEmpty }.joined(separator: " / "))
            Divider().padding(.leading, 16)
            detailRow(label: "当前状态", value: asset.status.displayName, accent: AppTheme.orange)
        }
        .background(panelBackground)
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("出库信息")
                .font(.headline)

            labeledField(title: "操作人") {
                TextField("填写借用人或经手人", text: $operatorName)
                    .textFieldStyle(.roundedBorder)
            }

            labeledField(title: "预计归还时间") {
                DatePicker(
                    "",
                    selection: $estimatedReturnDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("备注")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)

                TextEditor(text: $note)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 110)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            }
        }
        .padding(18)
        .background(panelBackground)
    }

    private var actionBar: some View {
        HStack {
            Button("取消") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("确认出库") {
                onConfirm()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.orange)
            .disabled(!canSubmit)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
    }

    private func detailRow(label: String, value: String, accent: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 86, alignment: .leading)

            Spacer()

            Text(value.isEmpty ? "-" : value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(accent ?? .primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
            content()
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(NSColor.controlBackgroundColor))
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
    }
}

// MARK: - 同步设置视图

struct SyncSettingsView: View {
    @ObservedObject var assetVM: AssetViewModel

    @State private var statusMessage: String = ""
    @State private var assetTableLink: String = ""
    @State private var recordTableLink: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsHeader
                syncDirectoryCard
                syncStatusCard
                syncActionsCard
                remindersCard
                feishuCard
                migrationCard
            }
            .padding(20)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("设置")
    }

    private var settingsHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.blue.opacity(0.14))
                    .frame(width: 56, height: 56)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(AppTheme.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("同步与集成")
                    .font(.title2.weight(.semibold))
                Text("管理目录权限、数据同步、提醒事项和飞书联动。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var syncDirectoryCard: some View {
        settingsCard(title: "同步目录", subtitle: "文件同步会使用这里配置的目录。") {
            VStack(alignment: .leading, spacing: 14) {
                pathPreview(title: "当前路径", value: assetVM.syncService.syncPath)

                VStack(alignment: .leading, spacing: 8) {
                    Text("手动路径")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)

                    TextField("同步路径", text: Binding(
                        get: { assetVM.syncService.syncPath },
                        set: { assetVM.syncService.setSyncPath($0) }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 10) {
                    Button("选择目录") { selectDirectory() }
                        .buttonStyle(.borderedProminent)
                    Button("恢复默认") { resetToDefault() }
                    Button("保存路径") { saveSettings() }
                }

                if !statusMessage.isEmpty {
                    infoMessage(statusMessage, isSuccess: statusMessage.contains("成功") || statusMessage.contains("已更新"))
                }
            }
        }
    }

    private var syncStatusCard: some View {
        settingsCard(title: "同步状态", subtitle: "这里显示最近一次同步情况和权限错误。") {
            VStack(spacing: 0) {
                statusRow("当前状态", value: assetVM.syncStatus, accent: assetVM.syncStatus.contains("✅") ? AppTheme.green : nil)
                if let lastSync = assetVM.syncService.lastSyncTime {
                    Divider().padding(.leading, 16)
                    statusRow("最后同步", value: Self.dateFormatter.string(from: lastSync))
                }
                if let error = assetVM.syncService.syncError {
                    Divider().padding(.leading, 16)
                    statusRow("错误信息", value: error, accent: AppTheme.red)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
    }

    private var syncActionsCard: some View {
        settingsCard(title: "同步操作", subtitle: "按场景选择导入、导出或双向同步。") {
            VStack(spacing: 12) {
                actionTile(
                    icon: "arrow.down.circle.fill",
                    color: AppTheme.blue,
                    title: "从同步目录导入",
                    description: "把同步目录中的数据拉取到本地，覆盖当前数据。",
                    buttonTitle: "立即导入",
                    action: importFromSync
                )

                actionTile(
                    icon: "arrow.up.circle.fill",
                    color: AppTheme.green,
                    title: "导出到同步目录",
                    description: "把当前本地数据推送到同步目录，适合备份和共享。",
                    buttonTitle: "立即导出",
                    action: exportToSync
                )

                actionTile(
                    icon: "arrow.left.arrow.right.circle.fill",
                    color: AppTheme.orange,
                    title: "双向同步",
                    description: "比较本地与同步目录数据，保留较多的一方后写回同步目录。",
                    buttonTitle: "开始同步",
                    action: bidirectionalSync
                )
            }
        }
    }

    private var remindersCard: some View {
        settingsCard(title: "提醒事项同步", subtitle: "把待归还记录同步到 Apple 提醒事项。") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("同步待归还记录") {
                        syncReminders()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.blue)

                    if assetVM.remindersService.isSyncing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }

                if let msg = assetVM.remindersService.syncMessage {
                    infoMessage(msg, isSuccess: !assetVM.remindersService.isSyncing)
                }
            }
        }
    }

    private var feishuCard: some View {
        settingsCard(title: "飞书多维表格", subtitle: "先配置应用身份，再粘贴两张在线表格链接。保存后会自动同步一次。") {
            VStack(alignment: .leading, spacing: 16) {
                feishuSectionTitle("1. 应用凭证")

                settingsField("App ID") {
                    TextField("输入 App ID", text: Binding(
                        get: { assetVM.feishuBitableService.appId },
                        set: { assetVM.feishuBitableService.appId = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                settingsField("App Secret") {
                    SecureField("输入 App Secret", text: Binding(
                        get: { assetVM.feishuBitableService.appSecret },
                        set: { assetVM.feishuBitableService.appSecret = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                Divider()

                feishuSectionTitle("2. 在线表格链接")

                tableLinkBox(
                    title: "资产状态 / 出入库状态表",
                    placeholder: "粘贴资产表链接，例如 https://.../base/...?...table=...",
                    text: $assetTableLink,
                    appToken: assetVM.feishuBitableService.assetAppToken,
                    tableId: assetVM.feishuBitableService.assetTableId,
                    action: parseAssetTableLink
                )

                tableLinkBox(
                    title: "操作记录表",
                    placeholder: "粘贴操作记录表链接，例如 https://.../base/...?...table=...",
                    text: $recordTableLink,
                    appToken: assetVM.feishuBitableService.recordAppToken,
                    tableId: assetVM.feishuBitableService.recordTableId,
                    action: parseRecordTableLink
                )

                DisclosureGroup("手动修改 App Token / Table ID") {
                    VStack(alignment: .leading, spacing: 12) {
                        settingsField("资产表 App Token") {
                            TextField("资产表所在 Base 的 App Token", text: Binding(
                                get: { assetVM.feishuBitableService.assetAppToken },
                                set: { assetVM.feishuBitableService.assetAppToken = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        settingsField("资产表 ID") {
                            TextField("资产表 Table ID", text: Binding(
                                get: { assetVM.feishuBitableService.assetTableId },
                                set: { assetVM.feishuBitableService.assetTableId = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        settingsField("记录表 App Token") {
                            TextField("记录表所在 Base 的 App Token", text: Binding(
                                get: { assetVM.feishuBitableService.recordAppToken },
                                set: { assetVM.feishuBitableService.recordAppToken = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        settingsField("记录表 ID") {
                            TextField("记录表 Table ID", text: Binding(
                                get: { assetVM.feishuBitableService.recordTableId },
                                set: { assetVM.feishuBitableService.recordTableId = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.top, 10)
                }

                Divider()

                feishuSectionTitle("3. 保存与同步")

                HStack(spacing: 10) {
                    Button("保存配置并同步") {
                        assetVM.configureFeishuAndSync()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("测试连接") {
                        Task { await assetVM.feishuBitableService.testConnection() }
                    }
                    .disabled(!assetVM.feishuBitableService.isConfigured || assetVM.feishuBitableService.isSyncing)

                    Spacer()

                    if assetVM.feishuBitableService.isSyncing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }

                HStack(spacing: 10) {
                    Button("全量同步") {
                        Task { await assetVM.syncAllToFeishu() }
                    }
                    .disabled(!assetVM.feishuBitableService.isConfigured || assetVM.feishuBitableService.isSyncing)

                    Button("从飞书导入") {
                        Task { await assetVM.importFromFeishu() }
                    }
                    .disabled(!assetVM.feishuBitableService.isConfigured || assetVM.feishuBitableService.isSyncing)

                    Button("双向同步") {
                        Task { await assetVM.syncFeishuBidirectionally() }
                    }
                    .disabled(!assetVM.feishuBitableService.isConfigured || assetVM.feishuBitableService.isSyncing)
                }

                VStack(spacing: 0) {
                    statusRow(
                        "连接状态",
                        value: assetVM.feishuBitableService.isConfigured ? "已配置" : "未配置",
                        accent: assetVM.feishuBitableService.isConfigured ? AppTheme.green : AppTheme.orange
                    )
                    Divider().padding(.leading, 16)
                    statusRow(
                        "当前动作",
                        value: assetVM.feishuBitableService.currentOperation ?? (assetVM.feishuBitableService.isSyncing ? "正在同步" : "待命"),
                        accent: assetVM.feishuBitableService.isSyncing ? AppTheme.blue : nil
                    )
                    Divider().padding(.leading, 16)
                    statusRow("资产表", value: assetVM.feishuBitableService.assetTableId.isEmpty ? "未设置" : assetVM.feishuBitableService.assetTableId)
                    Divider().padding(.leading, 16)
                    statusRow("记录表", value: assetVM.feishuBitableService.recordTableId.isEmpty ? "未设置" : assetVM.feishuBitableService.recordTableId)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )

                if let msg = assetVM.feishuBitableService.lastMessage {
                    infoMessage(msg, isSuccess: true)
                }

                if let error = assetVM.feishuBitableService.lastError {
                    infoMessage(error, isSuccess: false)
                }

                Text("iCloud 继续保持手动同步；飞书在保存配置后会自动执行一次同步，之后本地状态变化会自动回写。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var migrationCard: some View {
        settingsCard(title: "旧版迁移", subtitle: "从旧同步方式导入历史数据。") {
            Button("从旧同步方式迁移") {
                migrateFromOldSync()
            }
            .foregroundColor(AppTheme.orange)
        }
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择同步目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())

        if panel.runModal() == .OK, let url = panel.url {
            assetVM.syncService.setSyncDirectoryURL(url)
        }
    }

    private func resetToDefault() {
        let defaultPath = "\(NSHomeDirectory())/Documents/AssetManagerFile"
        assetVM.syncService.setSyncPath(defaultPath)
    }

    private func saveSettings() {
        assetVM.syncService.setSyncPath(assetVM.syncService.syncPath)
        if assetVM.syncService.syncError == nil {
            statusMessage = "同步路径已更新"
        } else {
            statusMessage = "设置失败: \(assetVM.syncService.syncError ?? "未知错误")"
        }
    }

    private func migrateFromOldSync() {
        let migrated = assetVM.syncService.migrateFromUserDefaults()
        if migrated {
            assetVM.errorMessage = "迁移完成,请重新同步"
        } else {
            assetVM.errorMessage = "未找到旧同步数据"
        }
    }

    private func importFromSync() { assetVM.importFromSync() }
    private func exportToSync() { assetVM.exportToSync() }
    private func bidirectionalSync() { assetVM.bidirectionalSync() }

    private func parseAssetTableLink() {
        let input = assetTableLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let config = assetVM.feishuBitableService.extractTableConfig(from: input) else {
            statusMessage = "资产表链接解析失败，请检查链接是否完整"
            return
        }
        assetVM.feishuBitableService.assetAppToken = config.appToken
        assetVM.feishuBitableService.assetTableId = config.tableId
        statusMessage = "已解析资产表链接"
    }

    private func parseRecordTableLink() {
        let input = recordTableLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let config = assetVM.feishuBitableService.extractTableConfig(from: input) else {
            statusMessage = "记录表链接解析失败，请检查链接是否完整"
            return
        }
        assetVM.feishuBitableService.recordAppToken = config.appToken
        assetVM.feishuBitableService.recordTableId = config.tableId
        statusMessage = "已解析记录表链接"
    }

    private func syncReminders() {
        Task {
            let syncedIds = await assetVM.remindersService.syncCheckOutRecords(assetVM.operationRecords)
            if !syncedIds.isEmpty {
                for id in syncedIds {
                    if let idx = assetVM.operationRecords.firstIndex(where: { $0.id == id }) {
                        var updatedRecord = assetVM.operationRecords[idx]
                        updatedRecord.isSyncedToReminders = true
                        assetVM.operationRecords[idx] = updatedRecord
                    }
                }
                assetVM.saveToStorage()
            }
        }
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func settingsCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            content()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
        )
    }

    private func pathPreview(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            Text(value.isEmpty ? "未设置" : value)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private func statusRow(_ label: String, value: String, accent: Color? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .leading)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(accent ?? .primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func actionTile(icon: String, color: Color, title: String, description: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
        )
    }

    private func settingsField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
            content()
        }
    }

    private func feishuSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundColor(.primary)
    }

    private func tableLinkBox(
        title: String,
        placeholder: String,
        text: Binding<String>,
        appToken: String,
        tableId: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(action)
                Button("解析", action: action)
                    .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            VStack(spacing: 0) {
                statusRow("App Token", value: appToken.isEmpty ? "未解析" : appToken)
                Divider().padding(.leading, 16)
                statusRow("Table ID", value: tableId.isEmpty ? "未解析" : tableId)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.windowBackgroundColor))
            )
        }
    }

    private func infoMessage(_ message: String, isSuccess: Bool) -> some View {
        Text(message)
            .font(.caption)
            .foregroundColor(isSuccess ? AppTheme.green : AppTheme.red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
