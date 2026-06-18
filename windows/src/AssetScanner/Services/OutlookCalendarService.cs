using System.Runtime.InteropServices;
using System.Text;
using System.Diagnostics;
using AssetScanner.Models;

namespace AssetScanner.Services;

public sealed class OutlookCalendarService
{
    public Task<OutlookSyncResult> SyncCheckOutRecordsAsync(IEnumerable<OperationRecord> records)
    {
        var pendingRecords = records
            .Where(record =>
                record.Type == OperationType.CheckOut &&
                record.EstimatedReturnDate.HasValue &&
                !record.IsSyncedToReminders)
            .ToList();

        if (pendingRecords.Count == 0)
            return Task.FromResult(new OutlookSyncResult(0, 0, "没有需要同步的出库记录"));

        var outlookType = Type.GetTypeFromProgID("Outlook.Application");
        if (outlookType is null)
            return ExportIcsAndOpen(pendingRecords);

        dynamic? outlook = null;
        var success = 0;
        var failed = 0;

        try
        {
            outlook = Activator.CreateInstance(outlookType)
                ?? throw new InvalidOperationException("无法启动 Outlook。");

            foreach (var record in pendingRecords)
            {
                try
                {
                    CreateAppointment(outlook, record);
                    record.IsSyncedToReminders = true;
                    success++;
                }
                catch
                {
                    failed++;
                }
            }
        }
        finally
        {
            if (outlook is not null && Marshal.IsComObject(outlook))
                Marshal.ReleaseComObject(outlook);
        }

        return Task.FromResult(new OutlookSyncResult(
            success,
            failed,
            failed == 0 ? $"已同步 {success} 条出库记录到 Outlook 日历" : $"已同步 {success} 条，失败 {failed} 条"));
    }

    private static Task<OutlookSyncResult> ExportIcsAndOpen(List<OperationRecord> records)
    {
        var calendarPath = Path.Combine(
            Path.GetTempPath(),
            $"AssetManager-Outlook-{DateTime.Now:yyyyMMddHHmmss}.ics");

        File.WriteAllText(calendarPath, BuildCalendar(records), new UTF8Encoding(false));

        Process.Start(new ProcessStartInfo
        {
            FileName = calendarPath,
            UseShellExecute = true
        });

        foreach (var record in records)
            record.IsSyncedToReminders = true;

        return Task.FromResult(new OutlookSyncResult(
            records.Count,
            0,
            $"未检测到经典 Outlook，已生成并打开日历导入文件：{calendarPath}"));
    }

    private static void CreateAppointment(dynamic outlook, OperationRecord record)
    {
        const int olAppointmentItem = 1;
        const int olBusy = 2;

        var returnDate = record.EstimatedReturnDate!.Value.Date;
        dynamic appointment = outlook.CreateItem(olAppointmentItem);

        appointment.Subject = $"归还提醒: {record.AssetName}";
        appointment.Start = returnDate;
        appointment.End = returnDate.AddDays(1);
        appointment.AllDayEvent = true;
        appointment.BusyStatus = olBusy;
        appointment.ReminderSet = true;
        appointment.ReminderMinutesBeforeStart = 24 * 60;
        appointment.Body = BuildBody(record);
        appointment.Categories = "AssetManager";
        appointment.Save();

        if (Marshal.IsComObject(appointment))
            Marshal.ReleaseComObject(appointment);
    }

    private static string BuildBody(OperationRecord record)
    {
        var body = new StringBuilder();
        body.AppendLine("AssetManager 出库归还提醒");
        body.AppendLine($"条码: {record.AssetId}");
        body.AppendLine($"资产名称: {record.AssetName}");
        body.AppendLine($"操作人: {record.Operator}");
        body.AppendLine($"出库时间: {record.Timestamp:yyyy-MM-dd HH:mm}");

        if (!string.IsNullOrWhiteSpace(record.Note))
            body.AppendLine($"备注: {record.Note}");

        return body.ToString();
    }

    private static string BuildCalendar(IEnumerable<OperationRecord> records)
    {
        var builder = new StringBuilder();
        builder.AppendLine("BEGIN:VCALENDAR");
        builder.AppendLine("VERSION:2.0");
        builder.AppendLine("PRODID:-//AssetManager//Outlook Calendar Sync//CN");
        builder.AppendLine("CALSCALE:GREGORIAN");
        builder.AppendLine("METHOD:PUBLISH");

        foreach (var record in records)
            AppendEvent(builder, record);

        builder.AppendLine("END:VCALENDAR");
        return builder.ToString();
    }

    private static void AppendEvent(StringBuilder builder, OperationRecord record)
    {
        var start = record.EstimatedReturnDate!.Value.Date;
        var end = start.AddDays(1);

        builder.AppendLine("BEGIN:VEVENT");
        builder.AppendLine($"UID:{record.Id}@assetmanager");
        builder.AppendLine($"DTSTAMP:{DateTime.UtcNow:yyyyMMddTHHmmssZ}");
        builder.AppendLine($"DTSTART;VALUE=DATE:{start:yyyyMMdd}");
        builder.AppendLine($"DTEND;VALUE=DATE:{end:yyyyMMdd}");
        builder.AppendLine($"SUMMARY:{EscapeIcs($"归还提醒: {record.AssetName}")}");
        builder.AppendLine($"DESCRIPTION:{EscapeIcs(BuildBody(record))}");
        builder.AppendLine("CATEGORIES:AssetManager");
        builder.AppendLine("BEGIN:VALARM");
        builder.AppendLine("TRIGGER:-P1D");
        builder.AppendLine("ACTION:DISPLAY");
        builder.AppendLine($"DESCRIPTION:{EscapeIcs($"归还提醒: {record.AssetName}")}");
        builder.AppendLine("END:VALARM");
        builder.AppendLine("END:VEVENT");
    }

    private static string EscapeIcs(string value) => value
        .Replace("\\", "\\\\")
        .Replace(";", "\\;")
        .Replace(",", "\\,")
        .Replace("\r\n", "\\n")
        .Replace("\n", "\\n")
        .Replace("\r", "\\n");
}

public sealed record OutlookSyncResult(int SuccessCount, int FailedCount, string Message);
