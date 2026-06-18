namespace AssetScanner.Models;

/// <summary>
/// 资产状态
/// </summary>
public enum AssetStatus
{
    /// <summary>在库</summary>
    InStock = 0,
    /// <summary>已出库</summary>
    CheckedOut = 1,
    /// <summary>送修</summary>
    Maintenance = 2,
    /// <summary>待报废</summary>
    Scrapped = 3
}

/// <summary>
/// 操作类型
/// </summary>
public enum OperationType
{
    /// <summary>入库</summary>
    CheckIn = 0,
    /// <summary>出库</summary>
    CheckOut = 1,
    /// <summary>送修</summary>
    Repair = 2,
    /// <summary>报废</summary>
    Scrap = 3
}
