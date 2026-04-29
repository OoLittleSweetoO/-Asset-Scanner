import SwiftUI

/// 操作记录视图 — 卡片式 + 彩色 badge
struct HistoryView: View {
    @EnvironmentObject var viewModel: AssetViewModel
    @StateObject private var remindersService = RemindersService()
    @State private var showSyncAlert = false
    @State private var selectedRecordIds: Set<UUID> = []
    @State private var isSyncingSelected = false
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.operationRecords.isEmpty {
                    emptyStateView
                } else {
                    recordListView
                }
            }
            .navigationTitle(L("history_title"))
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    // MARK: - 记录列表
    
    @ViewBuilder
    private var recordListView: some View {
        List {
            ForEach(viewModel.operationRecords) { record in
                HStack {
                    if record.type == .checkOut && record.estimatedReturnDate != nil {
                        // 只有出库记录且有预计归还时间的才显示复选框
                        Image(systemName: selectedRecordIds.contains(record.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedRecordIds.contains(record.id) ? Color.blue : Color.secondary)
                            .onTapGesture {
                                if selectedRecordIds.contains(record.id) {
                                    selectedRecordIds.remove(record.id)
                                } else {
                                    selectedRecordIds.insert(record.id)
                                }
                            }
                    } else {
                        // 不可同步的记录显示空占位符
                        Spacer().frame(width: 24)
                    }
                    
                    RecordRowView(record: record)
                        .opacity(record.type == .checkOut && record.estimatedReturnDate != nil ? 1.0 : 0.7)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        viewModel.deleteRecord(record)
                    } label: {
                        Label(L("delete"), systemImage: "trash")
                    }
                }
            }
            .onDelete { offsets in
                viewModel.deleteRecord(at: offsets)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("history_title"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !selectedRecordIds.isEmpty {
                    Button(L("sync_selected")) {
                        Task {
                            await syncSelectedRecords()
                        }
                    }
                    .disabled(isSyncingSelected)
                }
                Button(action: {
                    Task {
                        let syncedIds = await remindersService.syncCheckOutRecords(viewModel.operationRecords)
                        // 更新同步状态
                        for recordId in syncedIds {
                            viewModel.updateRecordSyncStatus(recordId, isSynced: true)
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
        .alert(L("sync_reminder"), isPresented: $showSyncAlert) {
            Button(L("confirm")) {}
        } message: {
            Text(remindersService.syncMessage ?? L("sync_complete"))
        }
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
                    
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 50))
                        .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                }
                
                VStack(spacing: 8) {
                    Text(L("empty_history_title"))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(L("empty_history_hint"))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - 同步选中的记录
    
    private func syncSelectedRecords() async {
        isSyncingSelected = true
        var successCount = 0
        
        // 获取选中的记录
        let selectedRecords = viewModel.operationRecords.filter { selectedRecordIds.contains($0.id) }
        
        for record in selectedRecords {
            let synced = await remindersService.syncRecordToReminders(record)
            if synced {
                // 更新记录的同步状态
                viewModel.updateRecordSyncStatus(record.id, isSynced: true)
                successCount += 1
            }
        }
        
        // 清除选择
        selectedRecordIds.removeAll()
        
        // 显示结果
        if successCount > 0 {
            let message = String(format: L("sync_success"), successCount)
            remindersService.syncMessage = message
            showSyncAlert = true
        }
        
        isSyncingSelected = false
    }
}

// MARK: - 记录行视图

struct RecordRowView: View {
    let record: OperationRecord
    
    var typeIcon: String {
        switch record.type {
        case .checkIn: return "arrow.down.circle.fill"
        case .checkOut: return "arrow.up.circle.fill"
        }
    }
    
    var typeColor: Color {
        switch record.type {
        case .checkIn: return Color(red: 0.2, green: 0.7, blue: 0.4)
        case .checkOut: return Color(red: 1.0, green: 0.55, blue: 0.0)
        }
    }
    
    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 类型图标
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
                    // 类型 badge
                    Text(record.type.displayName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(typeColor)
                        .cornerRadius(8)
                    
                    Text(record.`operator`)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    // 同步状态指示器
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
                            .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                        Text(L("estimated_return_label"))
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

#Preview {
    HistoryView()
        .environmentObject(AssetViewModel())
}
