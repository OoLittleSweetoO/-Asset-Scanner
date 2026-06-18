using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Globalization;
using AssetScanner.Models;

namespace AssetScanner.Services;

public sealed class SyncFileService
{
    private const string AssetsFileName = "assets.json";
    private const string RecordsFileName = "records.json";
    private const string SourcesFileName = "sources.json";
    private const string MetaFileName = "meta.json";

    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public SyncFileService()
    {
        _jsonOptions.Converters.Add(new SwiftIsoDateTimeConverter());
        _jsonOptions.Converters.Add(new SwiftNullableIsoDateTimeConverter());
    }

    public async Task<SyncSnapshot> ImportAsync(
        string directoryPath,
        IReadOnlyList<Asset> currentAssets,
        IReadOnlyList<OperationRecord> currentRecords,
        IReadOnlyList<AssetSource> currentSources)
    {
        EnsureDirectoryReadable(directoryPath);

        var assets = await ReadJsonAsync<List<AssetDto>>(directoryPath, AssetsFileName);
        var records = await ReadJsonAsync<List<OperationRecordDto>>(directoryPath, RecordsFileName);
        var sources = await ReadJsonAsync<List<AssetSourceDto>>(directoryPath, SourcesFileName);
        var meta = await ReadJsonAsync<SyncMetaDto>(directoryPath, MetaFileName);

        return new SyncSnapshot(
            assets?.Select(a => a.ToModel()).ToList() ?? currentAssets.ToList(),
            records?.Select(r => r.ToModel()).ToList() ?? currentRecords.ToList(),
            sources?.Select(s => s.ToModel()).ToList() ?? currentSources.ToList(),
            meta);
    }

    public async Task ExportAsync(
        string directoryPath,
        IReadOnlyList<Asset> assets,
        IReadOnlyList<OperationRecord> records,
        IReadOnlyList<AssetSource> sources,
        DateTime? lastImportTime = null)
    {
        Directory.CreateDirectory(directoryPath);
        EnsureDirectoryWritable(directoryPath);

        await WriteJsonAsync(directoryPath, AssetsFileName, assets.Select(AssetDto.FromModel).ToList());
        await WriteJsonAsync(directoryPath, RecordsFileName, records.Select(OperationRecordDto.FromModel).ToList());
        await WriteJsonAsync(directoryPath, SourcesFileName, sources.Select(AssetSourceDto.FromModel).ToList());

        var meta = new SyncMetaDto(
            LastSyncTimestamp: new DateTimeOffset(DateTime.Now).ToUnixTimeMilliseconds() / 1000.0,
            LastImportTimestamp: lastImportTime.HasValue
                ? new DateTimeOffset(lastImportTime.Value).ToUnixTimeMilliseconds() / 1000.0
                : null);

        await WriteJsonAsync(directoryPath, MetaFileName, meta);
    }

    private async Task<T?> ReadJsonAsync<T>(string directoryPath, string fileName)
    {
        var path = Path.Combine(directoryPath, fileName);
        if (!File.Exists(path))
            return default;

        await using var stream = File.OpenRead(path);
        return await JsonSerializer.DeserializeAsync<T>(stream, _jsonOptions);
    }

    private async Task WriteJsonAsync<T>(string directoryPath, string fileName, T value)
    {
        var path = Path.Combine(directoryPath, fileName);
        var tempPath = $"{path}.tmp";

        await using (var stream = File.Create(tempPath))
        {
            await JsonSerializer.SerializeAsync(stream, value, _jsonOptions);
        }

        File.Copy(tempPath, path, true);
        File.Delete(tempPath);
    }

    private static void EnsureDirectoryReadable(string directoryPath)
    {
        if (string.IsNullOrWhiteSpace(directoryPath))
            throw new InvalidOperationException("请先选择同步目录");

        if (!Directory.Exists(directoryPath))
            throw new DirectoryNotFoundException($"同步目录不存在: {directoryPath}");
    }

    private static void EnsureDirectoryWritable(string directoryPath)
    {
        var testFile = Path.Combine(directoryPath, ".assetmanager_write_test");
        File.WriteAllText(testFile, "ok");
        File.Delete(testFile);
    }

    private sealed record AssetDto(
        string Id,
        string AssetName,
        string ModelName,
        string Brand,
        string Status,
        string InternalCode,
        string Location,
        DateTime? PurchaseDate,
        string? Note,
        DateTime LastUpdated,
        Guid? SourceId)
    {
        public static AssetDto FromModel(Asset asset) => new(
            asset.Id,
            asset.AssetName,
            asset.ModelName,
            asset.Brand,
            StatusToText(asset.Status),
            asset.InternalCode,
            asset.Location,
            asset.PurchaseDate,
            asset.Note,
            asset.LastUpdated,
            asset.SourceId);

        public Asset ToModel() => new()
        {
            Id = Id ?? string.Empty,
            AssetName = AssetName ?? string.Empty,
            ModelName = ModelName ?? string.Empty,
            Brand = Brand ?? string.Empty,
            Status = TextToStatus(Status),
            InternalCode = InternalCode ?? string.Empty,
            Location = Location ?? string.Empty,
            PurchaseDate = PurchaseDate,
            Note = Note,
            LastUpdated = LastUpdated == default ? DateTime.Now : LastUpdated,
            SourceId = SourceId
        };
    }

    private sealed record OperationRecordDto(
        Guid Id,
        string AssetId,
        string AssetName,
        string Type,
        string OperatorName,
        DateTime Timestamp,
        string? Note,
        DateTime? EstimatedReturnDate,
        bool IsSyncedToReminders)
    {
        public static OperationRecordDto FromModel(OperationRecord record) => new(
            record.Id,
            record.AssetId,
            record.AssetName,
            TypeToText(record.Type),
            record.Operator,
            record.Timestamp,
            record.Note,
            record.EstimatedReturnDate,
            record.IsSyncedToReminders);

        public OperationRecord ToModel() => new(
            id: Id == default ? Guid.NewGuid() : Id,
            assetId: AssetId ?? string.Empty,
            assetName: AssetName ?? string.Empty,
            type: TextToType(Type),
            @operator: OperatorName ?? "当前用户",
            timestamp: Timestamp == default ? DateTime.Now : Timestamp,
            note: Note,
            estimatedReturnDate: EstimatedReturnDate,
            isSyncedToReminders: IsSyncedToReminders);
    }

    private sealed record AssetSourceDto(
        Guid Id,
        string FileName,
        DateTime ImportDate,
        int AssetCount,
        List<string>? AssetIds)
    {
        public static AssetSourceDto FromModel(AssetSource source) => new(
            source.Id,
            source.FileName,
            source.ImportDate,
            source.AssetCount,
            source.AssetIds);

        public AssetSource ToModel() => new()
        {
            Id = Id == default ? Guid.NewGuid() : Id,
            FileName = FileName ?? string.Empty,
            ImportDate = ImportDate == default ? DateTime.Now : ImportDate,
            AssetCount = AssetCount,
            AssetIds = AssetIds ?? new()
        };
    }

    public sealed record SyncMetaDto(double? LastSyncTimestamp, double? LastImportTimestamp);

    public sealed record SyncSnapshot(
        List<Asset> Assets,
        List<OperationRecord> Records,
        List<AssetSource> Sources,
        SyncMetaDto? Meta);

    private static string StatusToText(AssetStatus status) => status switch
    {
        AssetStatus.CheckedOut => "已出库",
        AssetStatus.Maintenance => "送修",
        AssetStatus.Scrapped => "待报废",
        _ => "在库"
    };

    private static AssetStatus TextToStatus(string? value) => value switch
    {
        "已出库" or "出库" or "CheckedOut" or "checkedOut" or "1" => AssetStatus.CheckedOut,
        "送修" or "维修中" or "Maintenance" or "maintenance" or "2" => AssetStatus.Maintenance,
        "待报废" or "报废" or "Scrapped" or "scrapped" or "3" => AssetStatus.Scrapped,
        _ => AssetStatus.InStock
    };

    private static string TypeToText(OperationType type) => type switch
    {
        OperationType.CheckOut => "出库",
        OperationType.Repair => "送修",
        OperationType.Scrap => "报废",
        _ => "入库"
    };

    private static OperationType TextToType(string? value) => value switch
    {
        "出库" or "CheckOut" or "checkOut" or "1" => OperationType.CheckOut,
        "送修" or "Repair" or "repair" or "2" => OperationType.Repair,
        "报废" or "Scrap" or "scrap" or "3" => OperationType.Scrap,
        _ => OperationType.CheckIn
    };

    private sealed class SwiftIsoDateTimeConverter : JsonConverter<DateTime>
    {
        private const string SwiftIsoFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'";

        public override DateTime Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            var value = reader.GetString();
            if (string.IsNullOrWhiteSpace(value))
                return default;

            if (DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var parsed))
                return parsed.LocalDateTime;

            return DateTime.Parse(value, CultureInfo.InvariantCulture, DateTimeStyles.AssumeLocal);
        }

        public override void Write(Utf8JsonWriter writer, DateTime value, JsonSerializerOptions options)
        {
            writer.WriteStringValue(value.ToUniversalTime().ToString(SwiftIsoFormat, CultureInfo.InvariantCulture));
        }
    }

    private sealed class SwiftNullableIsoDateTimeConverter : JsonConverter<DateTime?>
    {
        private readonly SwiftIsoDateTimeConverter _inner = new();

        public override DateTime? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            if (reader.TokenType == JsonTokenType.Null)
                return null;

            return _inner.Read(ref reader, typeof(DateTime), options);
        }

        public override void Write(Utf8JsonWriter writer, DateTime? value, JsonSerializerOptions options)
        {
            if (value.HasValue)
                _inner.Write(writer, value.Value, options);
            else
                writer.WriteNullValue();
        }
    }
}
