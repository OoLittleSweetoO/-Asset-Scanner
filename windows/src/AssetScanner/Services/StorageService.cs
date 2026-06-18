using Microsoft.Data.Sqlite;
using Dapper;
using System.Text.Json;
using AssetScanner.Models;

namespace AssetScanner.Services;

/// <summary>
/// 存储服务 - 使用 SQLite 持久化数据 (替代 Room/UserDefaults)
/// </summary>
public class StorageService : IDisposable
{
    private readonly string _connectionString;
    private bool _disposed;

    public StorageService(string? dbPath = null)
    {
        if (string.IsNullOrWhiteSpace(dbPath))
        {
            var basePath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "AssetScanner");
            Directory.CreateDirectory(basePath);
            dbPath = Path.Combine(basePath, "assets.db");
        }
        else
        {
            var directory = Path.GetDirectoryName(dbPath);
            if (!string.IsNullOrEmpty(directory))
                Directory.CreateDirectory(directory);
        }

        _connectionString = $"Data Source={dbPath}";
    }

    /// <summary>
    /// 初始化数据库表
    /// </summary>
    public async Task InitializeAsync()
    {
        using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync();
        
        await connection.ExecuteAsync(@"
            CREATE TABLE IF NOT EXISTS Assets (
                id TEXT PRIMARY KEY,
                assetName TEXT NOT NULL,
                modelName TEXT,
                brand TEXT,
                status INTEGER NOT NULL,
                internalCode TEXT,
                location TEXT,
                purchaseDate TEXT,
                note TEXT,
                lastUpdated TEXT NOT NULL,
                sourceId TEXT
            );
            
            CREATE TABLE IF NOT EXISTS OperationRecords (
                id TEXT PRIMARY KEY,
                assetId TEXT NOT NULL,
                assetName TEXT,
                type INTEGER NOT NULL,
                operator TEXT,
                timestamp TEXT NOT NULL,
                note TEXT,
                estimatedReturnDate TEXT,
                isSyncedToReminders INTEGER DEFAULT 0
            );
            
            CREATE TABLE IF NOT EXISTS AssetSources (
                id TEXT PRIMARY KEY,
                fileName TEXT NOT NULL,
                importDate TEXT NOT NULL,
                assetCount INTEGER,
                assetIds TEXT
            );
            
            CREATE INDEX IF NOT EXISTS idx_assets_lastUpdated ON Assets(lastUpdated);
            CREATE INDEX IF NOT EXISTS idx_records_assetId ON OperationRecords(assetId);
            CREATE INDEX IF NOT EXISTS idx_records_timestamp ON OperationRecords(timestamp);
        ");
    }

    /// <summary>
    /// 加载所有数据
    /// </summary>
    public async Task<(List<Asset> Assets, List<OperationRecord> Records, List<AssetSource> Sources)> LoadAsync()
    {
        using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync();
        
        // 加载资产
        var assets = (await connection.QueryAsync<Asset>(
            "SELECT * FROM Assets ORDER BY lastUpdated DESC")).ToList();
        
        // 转换状态枚举
        foreach (var asset in assets)
        {
            asset.Status = (AssetStatus)asset.Status;
        }
        
        // 加载操作记录
        var records = new List<OperationRecord>();
        var recordRows = await connection.QueryAsync(@"
            SELECT * FROM OperationRecords ORDER BY timestamp DESC");

        foreach (var row in recordRows)
        {
            records.Add(new OperationRecord
            {
                Id = Guid.Parse(row.id),
                AssetId = row.assetId,
                AssetName = row.assetName,
                Type = (OperationType)Convert.ToInt32(row.type),
                Operator = row.@operator,
                Timestamp = DateTime.Parse((string)row.timestamp),
                Note = row.note,
                EstimatedReturnDate = row.estimatedReturnDate != null
                    ? DateTime.Parse((string)row.estimatedReturnDate)
                    : null,
                IsSyncedToReminders = Convert.ToInt32(row.isSyncedToReminders) == 1
            });
        }
        
        // 加载资产来源
        var sources = new List<AssetSource>();
        var sourceRows = await connection.QueryAsync(@"
            SELECT * FROM AssetSources ORDER BY importDate DESC");
        
        foreach (var row in sourceRows)
        {
            var source = new AssetSource
            {
                Id = Guid.Parse(row.id),
                FileName = row.fileName,
                ImportDate = DateTime.Parse((string)row.importDate),
                AssetCount = Convert.ToInt32(row.assetCount),
                AssetIds = row.assetIds != null 
                    ? JsonSerializer.Deserialize<List<string>>((string)row.assetIds) ?? new() 
                    : new()
            };
            sources.Add(source);
        }
        
        return (assets, records, sources);
    }

    /// <summary>
    /// 保存所有数据
    /// </summary>
    public async Task SaveAsync(List<Asset> assets, List<OperationRecord> records, List<AssetSource> sources)
    {
        using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync();
        
        using var transaction = await connection.BeginTransactionAsync();
        
        try
        {
            // 清空并重新插入资产
            await connection.ExecuteAsync("DELETE FROM Assets", transaction: transaction);
            foreach (var asset in assets)
            {
                await connection.ExecuteAsync(@"
                    INSERT INTO Assets (id, assetName, modelName, brand, status, 
                        internalCode, location, purchaseDate, note, lastUpdated, sourceId)
                    VALUES (@Id, @AssetName, @ModelName, @Brand, @Status, 
                        @InternalCode, @Location, @PurchaseDate, @Note, @LastUpdated, @SourceId)",
                    new
                    {
                        Id = asset.Id,
                        AssetName = asset.AssetName,
                        ModelName = asset.ModelName,
                        Brand = asset.Brand,
                        Status = (int)asset.Status,
                        InternalCode = asset.InternalCode,
                        Location = asset.Location,
                        PurchaseDate = (object?)asset.PurchaseDate?.ToString("O"),
                        Note = (object?)asset.Note,
                        LastUpdated = asset.LastUpdated.ToString("O"),
                        SourceId = (object?)asset.SourceId?.ToString()
                    }, transaction: transaction);
            }
            
            // 清空并重新插入操作记录
            await connection.ExecuteAsync("DELETE FROM OperationRecords", transaction: transaction);
            foreach (var record in records)
            {
                await connection.ExecuteAsync(@"
                    INSERT INTO OperationRecords (id, assetId, assetName, type, 
                        operator, timestamp, note, estimatedReturnDate, isSyncedToReminders)
                    VALUES (@Id, @AssetId, @AssetName, @Type, 
                        @Operator, @Timestamp, @Note, @EstimatedReturnDate, @IsSyncedToReminders)",
                    new
                    {
                        Id = record.Id.ToString(),
                        AssetId = record.AssetId,
                        AssetName = record.AssetName,
                        Type = (int)record.Type,
                        Operator = record.Operator,
                        Timestamp = record.Timestamp.ToString("O"),
                        Note = (object?)record.Note,
                        EstimatedReturnDate = (object?)record.EstimatedReturnDate?.ToString("O"),
                        IsSyncedToReminders = record.IsSyncedToReminders ? 1 : 0
                    }, transaction: transaction);
            }
            
            // 清空并重新插入资产来源
            await connection.ExecuteAsync("DELETE FROM AssetSources", transaction: transaction);
            foreach (var source in sources)
            {
                await connection.ExecuteAsync(@"
                    INSERT INTO AssetSources (id, fileName, importDate, assetCount, assetIds)
                    VALUES (@Id, @FileName, @ImportDate, @AssetCount, @AssetIds)",
                    new
                    {
                        Id = source.Id.ToString(),
                        FileName = source.FileName,
                        ImportDate = source.ImportDate.ToString("O"),
                        AssetCount = source.AssetCount,
                        AssetIds = JsonSerializer.Serialize(source.AssetIds)
                    }, transaction: transaction);
            }
            
            await transaction.CommitAsync();
        }
        catch
        {
            await transaction.RollbackAsync();
            throw;
        }
    }

    /// <summary>
    /// 删除所有数据
    /// </summary>
    public async Task ClearAsync()
    {
        using var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync();
        
        await connection.ExecuteAsync("DELETE FROM Assets");
        await connection.ExecuteAsync("DELETE FROM OperationRecords");
        await connection.ExecuteAsync("DELETE FROM AssetSources");
    }

    public void Dispose()
    {
        _disposed = true;
    }
}
