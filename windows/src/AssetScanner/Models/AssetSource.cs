namespace AssetScanner.Models;

/// <summary>
/// 资产来源 - 对应原 AssetSource.swift
/// </summary>
public class AssetSource
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string FileName { get; set; } = string.Empty;
    public DateTime ImportDate { get; set; } = DateTime.Now;
    public int AssetCount { get; set; }
    public List<string> AssetIds { get; set; } = new();

    public AssetSource() { }

    public AssetSource(
        Guid? id = null,
        string fileName = null!,
        DateTime? importDate = null,
        int assetCount = 0,
        List<string>? assetIds = null)
    {
        Id = id ?? Guid.NewGuid();
        FileName = fileName;
        ImportDate = importDate ?? DateTime.Now;
        AssetCount = assetCount;
        AssetIds = assetIds ?? new();
    }
}
