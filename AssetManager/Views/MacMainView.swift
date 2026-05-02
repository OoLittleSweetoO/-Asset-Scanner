import SwiftUI
import UniformTypeIdentifiers

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
    @StateObject var assetVM = AssetViewModel()
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

            NavigationStack {
                SyncSettingsView(assetVM: assetVM)
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
            .tag(3)
        }
        .environmentObject(assetVM)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("导入 CSV", systemImage: "square.and.arrow.down") { showImportPanel = true }
            }
            ToolbarItem(placement: .primaryAction) {
                syncBadge
            }
        }
        .fileImporter(isPresented: $showImportPanel, allowedContentTypes: [.commaSeparatedText], onCompletion: handleImport)
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
    @State private var searchText = ""
    @State private var selection: macOS_Asset?        // 用于高亮
    @State private var navigateToAsset: macOS_Asset?  // 用于导航

    private var filteredAssets: [macOS_Asset] {
        if searchText.isEmpty { return assetVM.assets }
        return assetVM.assets.filter {
            $0.id.contains(searchText) ||
            $0.assetName.contains(searchText) ||
            $0.modelName.contains(searchText) ||
            $0.brand.contains(searchText)
        }
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
                Button("添加", systemImage: "plus") { showAddSheet = true }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                AddAssetView(assetVM: assetVM)
            }
        }
    }

    @ViewBuilder
    private var assetListView: some View {
        List(selection: $selection) {
            ForEach(filteredAssets) { asset in
                AssetRowView(asset: asset, onChevronTap: {
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
        .searchable(text: $searchText, prompt: "搜索外编号、名称、型号、品牌")
        .navigationDestination(item: $navigateToAsset) { asset in
            AssetDetailView(asset: asset)
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
    var onChevronTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
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
        }
    }
}

// MARK: - 资产管理视图

struct AssetManagementView: View {
    @ObservedObject var assetVM: AssetViewModel
    @State private var searchText = ""
    @State private var selection: macOS_AssetSource?        // 用于高亮
    @State private var navigateToSource: macOS_AssetSource? // 用于导航

    private var filteredSources: [macOS_AssetSource] {
        if searchText.isEmpty { return assetVM.sources }
        return assetVM.sources.filter { $0.fileName.contains(searchText) }
    }

    var body: some View {
        sourceListView
        .navigationTitle("资产管理")
    }

    @ViewBuilder
    private var sourceListView: some View {
        List(selection: $selection) {
            // 统计卡片
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    statItem(
                        icon: "doc.fill",
                        value: "\(assetVM.sources.count)",
                        label: "文件来源",
                        color: AppTheme.blue
                    )
                    statItem(
                        icon: "cube.box.fill",
                        value: "\(assetVM.assets.count)",
                        label: "资产总数",
                        color: AppTheme.green
                    )
                    statItem(
                        icon: "arrow.up.circle.fill",
                        value: "\(assetVM.operationRecords.filter { $0.type == .checkOut }.count)",
                        label: "出库数量",
                        color: AppTheme.orange
                    )
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [AppTheme.blue.opacity(0.06), AppTheme.blue.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(14)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)

            // 来源列表
            if !assetVM.sources.isEmpty {
                ForEach(filteredSources) { source in
                    SourceRowView(source: source, onChevronTap: {
                        navigateToSource = source
                    })
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .tag(source)
                    .simultaneousGesture(
                        TapGesture(count: 2)
                            .onEnded {
                                navigateToSource = source
                            },
                        including: .all
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("删除") {
                            assetVM.deleteSource(source)
                        }
                        .tint(.red)
                    }
                }
            } else {
                // 空状态提示
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("暂无导入记录")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("点击上方按钮导入 CSV 文件来管理资产")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 30)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "搜索文件来源")
        .navigationDestination(item: $navigateToSource) { source in
            SourceAssetListView(source: source, assetVM: assetVM)
        }
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

// MARK: - 来源资产列表

struct SourceAssetListView: View {
    let source: macOS_AssetSource
    @ObservedObject var assetVM: AssetViewModel
    @State private var searchText = ""
    @State private var selection: macOS_Asset?        // 用于高亮
    @State private var navigateToAsset: macOS_Asset?  // 用于导航

    private var filteredAssets: [macOS_Asset] {
        let assets = assetVM.assets.filter { $0.sourceId == source.id }
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
                AssetRowView(asset: asset, onChevronTap: {
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
    }

    @ViewBuilder
    private var recordListView: some View {
        List {
            ForEach(filteredRecords) { record in
                HStack {
                    if record.type == .checkOut && record.estimatedReturnDate != nil {
                        Image(systemName: selectedRecordIds.contains(record.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedRecordIds.contains(record.id) ? AppTheme.blue : Color.secondary)
                            .onTapGesture {
                                if selectedRecordIds.contains(record.id) {
                                    selectedRecordIds.remove(record.id)
                                } else {
                                    selectedRecordIds.insert(record.id)
                                }
                            }
                    } else {
                        Spacer().frame(width: 24)
                    }

                    RecordRowView(record: record)
                        .opacity(record.type == .checkOut && record.estimatedReturnDate != nil ? 1.0 : 0.7)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
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

            }
            ToolbarItem(placement: .automatic) {
                if !selectedRecordIds.isEmpty {
                    Button("同步选中") {
                        Task { await syncSelectedRecords() }
                    }
                    .disabled(isSyncingSelected)
                }
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
                        Image(systemName: "arrow.clockwise.circle")
                    }
                }
                .disabled(remindersService.isSyncing)
            }
        }
        .alert("同步提醒事项", isPresented: $showSyncAlert) {
            Button("确定") {}
        } message: {
            Text(remindersService.syncMessage ?? "同步完成")
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

        let selectedRecords = assetVM.operationRecords.filter { selectedRecordIds.contains($0.id) }
        for record in selectedRecords {
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

// MARK: - 记录行视图

struct RecordRowView: View {
    let record: macOS_OperationRecord

    var typeIcon: String {
        switch record.type {
        case .checkIn: return "arrow.down.circle.fill"
        case .checkOut: return "arrow.up.circle.fill"
        }
    }

    var typeColor: Color {
        switch record.type {
        case .checkIn: return AppTheme.green
        case .checkOut: return AppTheme.orange
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

// MARK: - 资产详情视图

struct AssetDetailView: View {
    let asset: macOS_Asset
    @EnvironmentObject var assetVM: AssetViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showCheckIn = false
    @State private var showCheckOut = false
    @State private var operatorName = "当前用户"
    @State private var note = ""
    @State private var estimatedReturnDate = Date()

    var statusColor: Color {
        switch asset.status {
        case .inStock: return AppTheme.green
        case .checkedOut: return AppTheme.orange
        case .maintenance: return AppTheme.red
        }
    }

    var statusGradient: [Color] {
        switch asset.status {
        case .inStock:
            return [AppTheme.green, Color(red: 0.15, green: 0.6, blue: 0.35)]
        case .checkedOut:
            return [AppTheme.orange, Color(red: 0.9, green: 0.45, blue: 0.0)]
        case .maintenance:
            return [AppTheme.red, Color(red: 0.8, green: 0.2, blue: 0.25)]
        }
    }

    var statusIcon: String {
        switch asset.status {
        case .inStock: return "checkmark.circle.fill"
        case .checkedOut: return "arrow.up.circle.fill"
        case .maintenance: return "wrench.and.screwdriver"
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
        .navigationTitle(asset.assetName)
        .alert("确认归还", isPresented: $showCheckIn) {
            TextField("操作人", text: $operatorName)
            TextField("备注", text: $note)
            Button("确认") {
                assetVM.checkIn(asset: asset, operatorName: operatorName, note: note.isEmpty ? nil : note)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确认归还「\(asset.assetName)」?")
        }
        .sheet(isPresented: $showCheckOut) {
            NavigationStack {
                Form {
                    Section("出库信息") {
                        TextField("操作人", text: $operatorName)
                        DatePicker("预计归还时间", selection: $estimatedReturnDate, displayedComponents: [.date, .hourAndMinute])
                        TextField("备注", text: $note)
                    }
                    Section {
                        Button("确认出库") {
                            assetVM.checkOut(asset: asset, operatorName: operatorName, note: note.isEmpty ? nil : note, estimatedReturnDate: estimatedReturnDate)
                            dismiss()
                        }
                        .foregroundColor(AppTheme.orange)
                    }
                }
                .navigationTitle("出库 \(asset.assetName)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
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

                Text(asset.assetName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                HStack(spacing: 6) {
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                    Text(asset.status.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.2))
                .cornerRadius(16)

                Text(asset.id)
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
            infoRow(label: "内编号", value: asset.internalCode)
            Divider().padding(.leading, 16)
            infoRow(label: "品牌", value: asset.brand)
            Divider().padding(.leading, 16)
            infoRow(label: "型号", value: asset.modelName)
            Divider().padding(.leading, 16)
            infoRow(label: "存放地", value: asset.location)
            Divider().padding(.leading, 16)
            if let date = asset.purchaseDate {
                infoRow(label: "采购日期", value: date, formatter: Self.dateFormatter)
                Divider().padding(.leading, 16)
            }
            infoRow(label: "最后更新", value: asset.lastUpdated, formatter: Self.dateTimeFormatter)
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
        let recentRecords = assetVM.getRecentCheckOutRecords(for: asset.id, limit: 3)

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
            .disabled(asset.status == .inStock)
            .opacity(asset.status == .inStock ? 0.4 : 1)

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
            .disabled(asset.status != .inStock)
            .opacity(asset.status != .inStock ? 0.4 : 1)
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

// MARK: - 同步设置视图

struct SyncSettingsView: View {
    @ObservedObject var assetVM: AssetViewModel

    @State private var tempPath: String
    @State private var statusMessage: String = ""

    init(assetVM: AssetViewModel) {
        self.assetVM = assetVM
        _tempPath = State(initialValue: assetVM.syncService.syncPath)
    }

    var body: some View {
        List {
            // 同步目录
            Section("同步目录") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("文件将同步到此目录")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(alignment: .top, spacing: 8) {
                        Text("当前路径:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize()
                        Text(assetVM.syncService.syncPath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(3)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)

                    TextField("同步路径", text: $tempPath)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    HStack(spacing: 12) {
                        Button("选择目录") { selectDirectory() }
                        Button("恢复默认") { resetToDefault() }
                        Button("保存") { saveSettings() }
                            .buttonStyle(.borderedProminent)
                    }

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(statusMessage.contains("成功") || statusMessage.contains("已更新") ? AppTheme.green : AppTheme.red)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 4)
            }

            // 同步状态
            Section("同步状态") {
                HStack {
                    Text("当前状态")
                    Spacer()
                    Text(assetVM.syncStatus)
                        .foregroundColor(assetVM.syncStatus.contains("✅") ? AppTheme.green : .secondary)
                }

                if let lastSync = assetVM.syncService.lastSyncTime {
                    HStack {
                        Text("最后同步")
                        Spacer()
                        Text(lastSync, formatter: Self.dateFormatter)
                            .foregroundColor(.secondary)
                    }
                }

                if let error = assetVM.syncService.syncError {
                    HStack {
                        Text("错误")
                        Spacer()
                        Text(error)
                            .foregroundColor(AppTheme.red)
                    }
                }
            }

            // 数据同步方向
            Section("数据同步方向") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("📥 从同步目录导入:将同步目录中的数据拉取到本地,覆盖当前数据(适用于恢复数据)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button { importFromSync() } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("从同步目录导入")
                        }
                    }
                    .foregroundColor(AppTheme.blue)
                }
                .padding(.vertical, 4)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("📤 导出到同步目录:将当前本地数据推送到同步目录(适用于备份/共享)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button { exportToSync() } label: {
                        HStack {
                            Image(systemName: "arrow.up.circle")
                            Text("导出到同步目录")
                        }
                    }
                    .foregroundColor(AppTheme.green)
                }
                .padding(.vertical, 4)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("🔄 双向同步:比较本地与同步目录数据,保留较多的一方,然后推送到同步目录")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button { bidirectionalSync() } label: {
                        HStack {
                            Image(systemName: "arrow.left.arrow.right.circle")
                            Text("双向同步")
                        }
                    }
                    .foregroundColor(.purple)
                }
                .padding(.vertical, 4)
            }

            // 数据迁移
            Section("数据迁移(旧版)") {
                Button("从旧同步方式迁移") {
                    migrateFromOldSync()
                }
                .foregroundColor(AppTheme.orange)
            }

            // 提醒事项同步
            Section("提醒事项同步") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("手动同步所有待归还记录到 Apple 提醒事项")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("同步待归还记录") {
                        syncReminders()
                    }
                    .foregroundColor(AppTheme.blue)

                    if let msg = assetVM.remindersService.syncMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(assetVM.remindersService.isSyncing ? AppTheme.orange : AppTheme.green)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("设置")
        // toolbarBackground removed for macOS
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
            tempPath = url.path
            saveSettings()
        }
    }

    private func resetToDefault() {
        let defaultPath = "\(NSHomeDirectory())/Documents/AssetManagerFile"
        tempPath = defaultPath
        saveSettings()
    }

    private func saveSettings() {
        let success = assetVM.syncService.setSyncPath(tempPath)
        if success {
            statusMessage = "同步路径已更新: \(tempPath)"
            tempPath = assetVM.syncService.syncPath
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
}
