import SwiftUI

/// 资产详情视图 — 状态卡片 + 分组信息 + 渐变操作按钮
struct AssetDetailView: View {
    let assetId: String
    @EnvironmentObject var viewModel: AssetViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var asset: Asset?
    
    func refreshAsset() {
        asset = viewModel.assets.first(where: { $0.id == assetId })
    }
    
    @State private var showCheckIn = false
    @State private var showCheckOut = false
    @State private var showDeleteConfirmation = false
    @State private var operatorName = L("current_user")
    @State private var note = ""
    @State private var estimatedReturnDate = Date()
    
    var statusColor: Color {
        guard let asset = asset else { return .gray }
        switch asset.status {
        case .inStock: return Color(red: 0.2, green: 0.7, blue: 0.4)
        case .checkedOut: return Color(red: 1.0, green: 0.55, blue: 0.0)
        case .maintenance: return Color(red: 0.9, green: 0.25, blue: 0.3)
        }
    }
    
    var statusGradient: [Color] {
        guard let asset = asset else { return [.gray] }
        switch asset.status {
        case .inStock:
            return [Color(red: 0.2, green: 0.7, blue: 0.4), Color(red: 0.15, green: 0.6, blue: 0.35)]
        case .checkedOut:
            return [Color(red: 1.0, green: 0.55, blue: 0.0), Color(red: 0.9, green: 0.45, blue: 0.0)]
        case .maintenance:
            return [Color(red: 0.9, green: 0.25, blue: 0.3), Color(red: 0.8, green: 0.2, blue: 0.25)]
        }
    }
    
    var body: some View {
        Group {
            if let asset = asset {
                ScrollView {
                    VStack(spacing: 0) {
                        // 状态卡片
                        statusCard(asset: asset)
                        
                        // 信息区
                        infoSection(asset: asset)
                        
                        // 最近出库记录
                        recentCheckOutRecords(asset: asset)
                        
                        // 操作按钮
                        actionButtons(asset: asset)
                    }
                }
                .background(Color(.systemGroupedBackground))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                .alert(L("check_in"), isPresented: $showCheckIn) {
                    TextField(L("operator"), text: $operatorName)
                    TextField(L("note"), text: $note)
                    Button(L("confirm")) {
                        viewModel.checkIn(asset: asset, operator: operatorName, note: note.isEmpty ? nil : note)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            refreshAsset()
                        }
                    }
                    Button(L("cancel"), role: .cancel) {}
                } message: {
                    Text(String(format: L("check_in_confirm"), asset.assetName))
                }
                .confirmationDialog("删除这个设备条目？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                    Button("删除设备", role: .destructive) {
                        viewModel.deleteAsset(asset)
                        dismiss()
                    }
                    Button(L("cancel"), role: .cancel) {}
                } message: {
                    Text("删除后会同时清理对应的历史记录与来源关联，无法撤销。")
                }
                .sheet(isPresented: $showCheckOut) {
                    NavigationStack {
                        Form {
                            Section(L("check_out_section")) {
                                TextField(L("operator"), text: $operatorName)
                                DatePicker(L("estimated_return"), selection: $estimatedReturnDate, displayedComponents: [.date, .hourAndMinute])
                                TextField(L("note"), text: $note)
                            }
                            Section {
                                Button(L("confirm_check_out")) {
                                    viewModel.checkOut(asset: asset, operator: operatorName, note: note.isEmpty ? nil : note, estimatedReturnDate: estimatedReturnDate)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        refreshAsset()
                                    }
                                    showCheckOut = false
                                }
                                .foregroundColor(.orange)
                            }
                        }
                        .navigationTitle(L("check_out_title") + " \(asset.assetName)")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(L("cancel")) {
                                    showCheckOut = false
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text(L("loading"))
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            refreshAsset()
        }
    }
    
    // MARK: - 状态卡片
    
    @ViewBuilder
    private func statusCard(asset: Asset) -> some View {
        ZStack {
            LinearGradient(
                colors: statusGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 12) {
                // 大图标
                Image(systemName: statusIcon)
                    .font(.system(size: 44))
                    .foregroundColor(.white)
                    .shadow(radius: 4)
                
                Text(asset.assetName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                // 状态标签
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
    
    private var statusIcon: String {
        guard let asset = asset else { return "questionmark.circle" }
        switch asset.status {
        case .inStock: return "checkmark.circle.fill"
        case .checkedOut: return "arrow.up.circle.fill"
        case .maintenance: return "wrench.and.screwdriver"
        }
    }
    
    // MARK: - 信息区
    
    @ViewBuilder
    private func infoSection(asset: Asset) -> some View {
        VStack(spacing: 0) {
            infoRow(label: L("info_internal_code"), value: asset.internalCode)
            Divider().padding(.leading, 16)
            infoRow(label: L("info_brand"), value: asset.brand)
            Divider().padding(.leading, 16)
            infoRow(label: L("info_model"), value: asset.modelName)
            Divider().padding(.leading, 16)
            infoRow(label: L("info_location"), value: asset.location)
            Divider().padding(.leading, 16)
            if let date = asset.purchaseDate {
                infoRow(label: L("info_purchase_date"), value: date, formatter: Self.dateFormatter)
                Divider().padding(.leading, 16)
            }
            infoRow(label: L("info_last_updated"), value: asset.lastUpdated, formatter: Self.dateTimeFormatter)
        }
        .background(Color(.systemBackground))
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
            Text(value.isEmpty ? "—" : value)
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
    private func recentCheckOutRecords(asset: Asset) -> some View {
        let recentRecords = viewModel.getRecentCheckOutRecords(for: asset.id, limit: 3)
        
        if !recentRecords.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Text(L("recent_check_out"))
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
                                .foregroundColor(.orange)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(record.`operator`)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    Text(record.timestamp, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    if record.estimatedReturnDate != nil {
                                        Label(L("estimated_return_label"), systemImage: "calendar")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
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
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }
    
    // MARK: - 操作按钮
    
    @ViewBuilder
    private func actionButtons(asset: Asset) -> some View {
        VStack(spacing: 12) {
            Button(action: { showCheckIn = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text(L("check_in"))
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.7, blue: 0.4), Color(red: 0.15, green: 0.6, blue: 0.35)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .disabled(asset.status == .inStock)
            .opacity(asset.status == .inStock ? 0.4 : 1)
            
            Button(action: { showCheckOut = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                    Text(L("check_out"))
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.55, blue: 0.0), Color(red: 0.9, green: 0.45, blue: 0.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .disabled(asset.status != .inStock)
            .opacity(asset.status != .inStock ? 0.4 : 1)

            Button(action: {
                viewModel.markForMaintenance(asset: asset, operator: operatorName, note: note.isEmpty ? nil : note)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    refreshAsset()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                    Text(L("status_maintenance"))
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.9, green: 0.25, blue: 0.3), Color(red: 0.8, green: 0.2, blue: 0.25)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .disabled(asset.status == .maintenance)
            .opacity(asset.status == .maintenance ? 0.4 : 1)
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

#Preview {
    NavigationStack {
        AssetDetailView(assetId: "TEST-001")
            .environmentObject(AssetViewModel())
    }
}
