import Foundation
import EventKit
import SwiftUI

/// Apple Reminders 同步服务
@MainActor
class RemindersService: ObservableObject {
    @Published var isSyncing = false
    @Published var syncMessage: String?
    @Published var hasPermission = false
    
    private let eventStore = EKEventStore()
    private let reminderListName = "AssetScanner"
    
    // MARK: - 请求权限
    
    func requestPermission() async -> Bool {
        do {
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToReminders()
            } else {
                granted = try await eventStore.requestAccess(to: .reminder)
            }
            hasPermission = granted
            return granted
        } catch {
            hasPermission = false
            return false
        }
    }
    
    // MARK: - 获取或创建提醒列表
    
    private func getOrCreateReminderList() async -> EKCalendar? {
        let calendars = eventStore.calendars(for: .reminder)
        
        // 查找已存在的列表
        if let existingCalendar = calendars.first(where: { $0.title == reminderListName }) {
            return existingCalendar
        }
        
        // 获取默认 source（模拟器/真机都适用）
        guard let source = eventStore.defaultCalendarForNewReminders()?.source ?? eventStore.sources.first(where: { $0.sourceType != .local }) ?? eventStore.sources.first else {
            return nil
        }
        
        let newCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
        newCalendar.title = reminderListName
        newCalendar.source = source
        
        do {
            try eventStore.saveCalendar(newCalendar, commit: true)
            return newCalendar
        } catch {
            print("创建提醒列表失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - 同步出库记录到 Reminders
    
    /// 同步单个记录到提醒事项
    func syncRecordToReminders(_ record: OperationRecord) async -> Bool {
        // 如果已经标记为已同步，直接返回 true
        if record.isSyncedToReminders {
            return true
        }
        
        // 检查权限
        if !hasPermission {
            let granted = await requestPermission()
            if !granted {
                return false
            }
        }
        
        // 获取提醒列表
        guard let calendar = await getOrCreateReminderList() else {
            return false
        }
        
        // 检查是否已存在（通过 assetId 判断）
        let predicate = eventStore.predicateForReminders(in: [calendar])
        let existingReminders = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
        
        let alreadyExists = existingReminders.contains { reminder in
            reminder.title?.contains(record.assetId) == true
        }
        
        if alreadyExists {
            return true  // 已存在，视为同步成功
        }
        
        // 创建提醒
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "📦 \(record.assetName)"
        reminder.calendar = calendar
        
        // 设置备注
        var noteComponents: [String] = []
        noteComponents.append(L("note_barcode") + " \(record.assetId)")
        noteComponents.append(L("note_borrower") + " \(record.operator)")
        noteComponents.append(L("note_checkout_time") + " \(Self.formatDateTime(record.timestamp))")
        if let note = record.note {
            noteComponents.append(L("note") + " \(note)")
        }
        reminder.notes = noteComponents.joined(separator: "\n")
        
        // 设置到期日期（预计归还时间）
        if let returnDate = record.estimatedReturnDate {
            reminder.dueDateComponents = Self.dateComponents(from: returnDate)
            reminder.isCompleted = false
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            return true
        } catch {
            print("同步单个记录失败: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 批量同步出库记录
    /// 返回成功同步的记录ID列表
    func syncCheckOutRecords(_ records: [OperationRecord]) async -> [UUID] {
        isSyncing = true
        syncMessage = nil
        
        // 检查权限
        if !hasPermission {
            let granted = await requestPermission()
            if !granted {
                syncMessage = L("error_reminder_permission")
                isSyncing = false
                return []
            }
        }
        
        // 获取提醒列表
        guard (await getOrCreateReminderList()) != nil else {
            syncMessage = L("error_reminder_list_create")
            isSyncing = false
            return []
        }
        
        // 筛选未归还且未同步的出库记录
        let pendingRecords = records.filter { record in
            record.type == .checkOut && 
            record.estimatedReturnDate != nil &&
            !record.isSyncedToReminders
        }
        
        var successCount = 0
        var syncedRecordIds: [UUID] = []
        
        for record in pendingRecords {
            let synced = await syncRecordToReminders(record)
            if synced {
                successCount += 1
                syncedRecordIds.append(record.id)
            }
        }
        
        if successCount > 0 {
            let msg = String(format: L("sync_success"), successCount)
            syncMessage = msg
        } else {
            syncMessage = L("sync_no_records")
        }
        
        isSyncing = false
        return syncedRecordIds
    }
    
    // MARK: - 工具方法
    
    private static func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
    
    private static func dateComponents(from date: Date) -> DateComponents {
        let calendar = Calendar.current
        return DateComponents(
            year: calendar.component(.year, from: date),
            month: calendar.component(.month, from: date),
            day: calendar.component(.day, from: date),
            hour: calendar.component(.hour, from: date),
            minute: calendar.component(.minute, from: date)
        )
    }
}
