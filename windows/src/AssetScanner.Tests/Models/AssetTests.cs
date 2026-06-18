using AssetScanner.Models;

namespace AssetScanner.Tests.Models;

/// <summary>
/// Asset 模型测试类
/// </summary>
public class AssetTests
{
    [Fact]
    public void Asset_Constructor_ShouldInitializeProperties()
    {
        // Arrange & Act
        var asset = new Asset
        {
            Id = "TEST-001",
            AssetName = "测试资产",
            ModelName = "Model-A",
            Brand = "Brand-X",
            Status = AssetStatus.InStock,
            InternalCode = "INT-001",
            Location = "Location-A",
            PurchaseDate = new DateTime(2024, 1, 1),
            LastUpdated = DateTime.Now
        };

        // Assert
        Assert.Equal("TEST-001", asset.Id);
        Assert.Equal("测试资产", asset.AssetName);
        Assert.Equal("Model-A", asset.ModelName);
        Assert.Equal("Brand-X", asset.Brand);
        Assert.Equal(AssetStatus.InStock, asset.Status);
        Assert.Equal("INT-001", asset.InternalCode);
        Assert.Equal("Location-A", asset.Location);
        Assert.NotNull(asset.PurchaseDate);
    }

    [Fact]
    public void Asset_EqualityOperator_ShouldCompareById()
    {
        // Arrange
        var asset1 = new Asset { Id = "TEST-001", AssetName = "Test" };
        var asset2 = new Asset { Id = "TEST-001", AssetName = "Different Name" };
        var asset3 = new Asset { Id = "TEST-002", AssetName = "Test" };

        // Act & Assert
        Assert.Equal(asset1, asset2);
        Assert.NotEqual(asset1, asset3);
    }

    [Fact]
    public void Asset_WithId_ShouldCreateCopyWithNewId()
    {
        // Arrange
        var original = new Asset
        {
            Id = "OLD-001",
            AssetName = "测试资产",
            ModelName = "Model-A",
            Brand = "Brand-X",
            Status = AssetStatus.InStock,
            Location = "Location-A"
        };

        // Act
        var copy = original.WithId("NEW-001");

        // Assert
        Assert.Equal("NEW-001", copy.Id);
        Assert.Equal("测试资产", copy.AssetName);
        Assert.Equal("Model-A", copy.ModelName);
        Assert.Equal("Brand-X", copy.Brand);
        Assert.Equal(AssetStatus.InStock, copy.Status);
        Assert.Equal("Location-A", copy.Location);
    }

    [Fact]
    public void Asset_FromDict_ShouldCreateAssetFromDictionary()
    {
        // Arrange
        var dict = new Dictionary<string, string>
        {
            { "外编号", "TEST-001" },
            { "名称", "测试资产" },
            { "型号", "Model-A" },
            { "品牌", "Brand-X" },
            { "一级状态", "在库" },
            { "内编号", "INT-001" },
            { "一级存放地", "Location-A" },
            { "采购日期", "2024-01-01" },
            { "备注", "测试备注" }
        };

        // Act
        var asset = Asset.FromDict(dict);

        // Assert
        Assert.NotNull(asset);
        Assert.Equal("TEST-001", asset!.Id);
        Assert.Equal("测试资产", asset.AssetName);
        Assert.Equal("Model-A", asset.ModelName);
        Assert.Equal("Brand-X", asset.Brand);
        Assert.Equal(AssetStatus.InStock, asset.Status);
    }

    [Fact]
    public void Asset_FromDict_WithCheckedOutStatus_ShouldSetCorrectStatus()
    {
        // Arrange
        var dict = new Dictionary<string, string>
        {
            { "外编号", "TEST-002" },
            { "名称", "测试资产2" },
            { "一级状态", "已出库" }
        };

        // Act
        var asset = Asset.FromDict(dict);

        // Assert
        Assert.NotNull(asset);
        Assert.Equal(AssetStatus.CheckedOut, asset!.Status);
    }

    [Fact]
    public void Asset_FromDict_WithNullBarcode_ShouldReturnNull()
    {
        // Arrange
        var dict = new Dictionary<string, string>
        {
            { "名称", "测试资产" },
            { "型号", "Model-A" }
        };

        // Act
        var asset = Asset.FromDict(dict);

        // Assert
        Assert.Null(asset);
    }

    [Fact]
    public void Asset_MakeImportAssetId_ShouldReturnBaseIdWhenNotReserved()
    {
        // Arrange
        var asset = new Asset { Id = "TEST-001", InternalCode = "INT-001", AssetName = "测试" };
        var reservedIds = new HashSet<string>();

        // Act
        var newId = asset.MakeImportAssetId(reservedIds);

        // Assert
        Assert.Equal("TEST-001", newId);
    }

    [Fact]
    public void Asset_MakeImportAssetId_ShouldAppendIndexWhenIdReserved()
    {
        // Arrange
        var asset = new Asset { Id = "TEST-001", InternalCode = "INT-001", AssetName = "测试" };
        var reservedIds = new HashSet<string> { "TEST-001" };

        // Act
        var newId = asset.MakeImportAssetId(reservedIds, 0);

        // Assert
        Assert.True(newId.StartsWith("TEST-001#"), $"Expected ID to start with 'TEST-001#', but got: {newId}");
    }
}