using CommunityToolkit.Mvvm.ComponentModel;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace AssetScanner.Models;

/// <summary>
/// 资产实体 - 对应原 iOS/macOS Asset.swift
/// </summary>
public partial class Asset : ObservableObject
{
    [ObservableProperty] private string _id = string.Empty;                    // 外编号/条码 (唯一标识)
    [ObservableProperty] private string _assetName = string.Empty;            // 资产名称
    [ObservableProperty] private string _modelName = string.Empty;           // 型号
    [ObservableProperty] private string _brand = string.Empty;               // 品牌
    [ObservableProperty] private AssetStatus _status;                        // 状态
    [ObservableProperty] private string _internalCode = string.Empty;        // 内编号
    [ObservableProperty] private string _location = string.Empty;            // 存放位置
    [ObservableProperty] private DateTime? _purchaseDate;                    // 采购日期
    [ObservableProperty] private string? _note;                              // 备注
    [ObservableProperty] private DateTime _lastUpdated;                      // 最后更新时间
    [ObservableProperty] private Guid? _sourceId;                            // 资产来源 ID

    /// <summary>
    /// 默认构造函数
    /// </summary>
    public Asset()
    {
        _lastUpdated = DateTime.Now;
    }

    public Asset(
        string id,
        string assetName,
        string modelName = "",
        string brand = "",
        AssetStatus status = AssetStatus.InStock,
        string internalCode = "",
        string location = "",
        DateTime? purchaseDate = null,
        string? note = null,
        Guid? sourceId = null)
    {
        _id = id;
        _assetName = assetName;
        _modelName = modelName;
        _brand = brand;
        _status = status;
        _internalCode = internalCode;
        _location = location;
        _purchaseDate = purchaseDate;
        _note = note;
        _sourceId = sourceId;
        _lastUpdated = DateTime.Now;
    }

    /// <summary>
    /// 从 Excel/CSV 行字典创建资产
    /// </summary>
    public static Asset? FromDict(Dictionary<string, string> fromDict, Guid? sourceId = null)
    {
        static string FirstValue(Dictionary<string, string> dict, params string[] keys)
        {
            foreach (var key in keys)
            {
                if (dict.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value))
                    return value;
            }

            return string.Empty;
        }

        var barcode = FirstValue(fromDict, "外编号", "条码", "barcode").Trim();
        if (string.IsNullOrEmpty(barcode))
            return null;

        var statusStr = FirstValue(fromDict, "一级状态", "状态", "status");
        var status = statusStr switch
        {
            "已出库" or "出库" => AssetStatus.CheckedOut,
            "送修" or "维修中" => AssetStatus.Maintenance,
            "待报废" or "报废" => AssetStatus.Scrapped,
            _ => AssetStatus.InStock
        };

        DateTime? purchaseDate = null;
        if (fromDict.TryGetValue("采购日期", out var pd) && !string.IsNullOrEmpty(pd))
        {
            if (DateTime.TryParse(pd, out var parsedDate))
                purchaseDate = parsedDate;
        }

        return new Asset
        {
            Id = barcode,
            AssetName = FirstValue(fromDict, "名称", "资产名称", "name"),
            ModelName = FirstValue(fromDict, "型号", "model"),
            Brand = FirstValue(fromDict, "品牌", "brand"),
            Status = status,
            InternalCode = FirstValue(fromDict, "内编号", "internalCode"),
            Location = FirstValue(fromDict, "一级存放地", "存放位置", "location"),
            PurchaseDate = purchaseDate,
            Note = FirstValue(fromDict, "备注", "note"),
            SourceId = sourceId,
            LastUpdated = DateTime.Now
        };
    }

    /// <summary>
    /// 生成新的资产 ID (处理重复)
    /// </summary>
    public string MakeImportAssetId(HashSet<string> reservedIds, int rowIndex = 0)
    {
        var barcode = Id.Trim();
        var internalCode = InternalCode.Trim();
        var name = AssetName.Trim();

        var baseId = new[] { barcode, internalCode, name }
            .FirstOrDefault(s => !string.IsNullOrEmpty(s)) ?? "NO-CODE";

        if (!reservedIds.Contains(baseId))
            return baseId;

        var candidateIndex = Math.Max(rowIndex + 1, 2);
        while (reservedIds.Contains($"{baseId}#{candidateIndex}"))
            candidateIndex++;

        return $"{baseId}#{candidateIndex}";
    }

    /// <summary>
    /// 创建带新 ID 的资产副本
    /// </summary>
    public Asset WithId(string newId) => new Asset
    {
        Id = newId,
        AssetName = AssetName,
        ModelName = ModelName,
        Brand = Brand,
        Status = Status,
        InternalCode = InternalCode,
        Location = Location,
        PurchaseDate = PurchaseDate,
        Note = Note,
        SourceId = SourceId,
        LastUpdated = LastUpdated
    };

    public override bool Equals(object? obj) =>
        obj is Asset other && Id == other.Id;

    public override int GetHashCode() => Id.GetHashCode();

    public static bool operator ==(Asset? a, Asset? b) =>
        (a is null && b is null) || (a is not null && b is not null && a.Id == b.Id);

    public static bool operator !=(Asset? a, Asset? b) => !(a == b);
}
