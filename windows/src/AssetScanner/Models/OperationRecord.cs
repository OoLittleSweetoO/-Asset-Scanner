using CommunityToolkit.Mvvm.ComponentModel;

namespace AssetScanner.Models;

/// <summary>
/// 操作记录 - 对应原 OperationRecord.swift
/// </summary>
public partial class OperationRecord : ObservableObject
{
    [ObservableProperty] private Guid _id = Guid.NewGuid();
    [ObservableProperty] private string _assetId = string.Empty;        // 关联资产条码
    [ObservableProperty] private string _assetName = string.Empty;     // 资产名称
    [ObservableProperty] private OperationType _type;                  // 类型
    [ObservableProperty] private string _operator = string.Empty;      // 操作人
    [ObservableProperty] private DateTime _timestamp = DateTime.Now;   // 时间
    [ObservableProperty] private string? _note;                        // 备注
    [ObservableProperty] private DateTime? _estimatedReturnDate;       // 预计归还时间
    [ObservableProperty] private bool _isSyncedToReminders;            // 是否已同步到提醒事项

    public OperationRecord() { }

    public OperationRecord(
        Guid? id = null,
        string assetId = "",
        string assetName = "",
        OperationType type = OperationType.CheckIn,
        string @operator = "当前用户",
        DateTime? timestamp = null,
        string? note = null,
        DateTime? estimatedReturnDate = null,
        bool isSyncedToReminders = false)
    {
        _id = id ?? Guid.NewGuid();
        _assetId = assetId;
        _assetName = assetName;
        _type = type;
        _operator = @operator;
        _timestamp = timestamp ?? DateTime.Now;
        _note = note;
        _estimatedReturnDate = estimatedReturnDate;
        _isSyncedToReminders = isSyncedToReminders;
    }

    public override bool Equals(object? obj) =>
        obj is OperationRecord other && Id == other.Id;

    public override int GetHashCode() => Id.GetHashCode();

    public static bool operator ==(OperationRecord? a, OperationRecord? b) =>
        (a is null && b is null) || (a is not null && b is not null && a.Id == b.Id);

    public static bool operator !=(OperationRecord? a, OperationRecord? b) => !(a == b);
}