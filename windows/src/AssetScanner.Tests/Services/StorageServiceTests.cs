using AssetScanner.Models;
using AssetScanner.Services;

namespace AssetScanner.Tests.Services;

/// <summary>
/// StorageService 测试类
/// </summary>
public class StorageServiceTests : TestBase
{
    [Fact]
    public async Task InitializeAsync_ShouldCreateDatabaseTables()
    {
        // Arrange
        InitializeServices();

        // Act
        await StorageService!.InitializeAsync();

        // Assert - 验证数据库文件已创建
        Assert.True(File.Exists(_testDbPath));
    }

    [Fact]
    public async Task SaveAsync_And_LoadAsync_ShouldPersistData()
    {
        // Arrange
        InitializeServices();
        await StorageService!.InitializeAsync();

        var assets = new List<Asset>
        {
            new Asset
            {
                Id = "TEST-001",
                AssetName = "测试资产1",
                ModelName = "Model-A",
                Brand = "Brand-X",
                Status = AssetStatus.InStock,
                InternalCode = "INT-001",
                Location = "Location-A",
                PurchaseDate = new DateTime(2024, 1, 1),
                LastUpdated = DateTime.Now
            }
        };

        var records = new List<OperationRecord>
        {
            new OperationRecord
            {
                AssetId = "TEST-001",
                AssetName = "测试资产1",
                Type = OperationType.CheckIn,
                Operator = "TestUser",
                Timestamp = DateTime.Now
            }
        };

        var sources = new List<AssetSource>
        {
            new AssetSource(fileName: "test_import.xlsx")
            {
                ImportDate = DateTime.Now,
                AssetCount = 1,
                AssetIds = new List<string> { "TEST-001" }
            }
        };

        // Act
        await StorageService.SaveAsync(assets, records, sources);
        var (loadedAssets, loadedRecords, loadedSources) = await StorageService.LoadAsync();

        // Assert
        Assert.Equal(assets.Count, loadedAssets.Count);
        Assert.Equal(records.Count, loadedRecords.Count);
        Assert.Equal(sources.Count, loadedSources.Count);
        Assert.Equal("TEST-001", loadedAssets[0].Id);
        Assert.Equal("测试资产1", loadedAssets[0].AssetName);
    }

    [Fact]
    public async Task ClearAsync_ShouldRemoveAllData()
    {
        // Arrange
        InitializeServices();
        await StorageService!.InitializeAsync();

        var assets = new List<Asset>
        {
            new Asset { Id = "TEST-001", AssetName = "Test Asset" }
        };

        await StorageService.SaveAsync(assets, new List<OperationRecord>(), new List<AssetSource>());

        // Act
        await StorageService.ClearAsync();
        var (loadedAssets, loadedRecords, loadedSources) = await StorageService.LoadAsync();

        // Assert
        Assert.Empty(loadedAssets);
        Assert.Empty(loadedRecords);
        Assert.Empty(loadedSources);
    }
}