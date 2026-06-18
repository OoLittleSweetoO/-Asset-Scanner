using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using AssetScanner.Models;

namespace AssetScanner.Services;

public sealed class AssetManagerServerService : IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        Converters = { new JsonStringEnumConverter() }
    };

    private HttpClient? _httpClient;
    private string _baseApiUrl = string.Empty;
    private string _token = string.Empty;
    private bool _allowInvalidCertificate;

    public bool IsConfigured => !string.IsNullOrWhiteSpace(_baseApiUrl);
    public bool IsAuthenticated => IsConfigured && !string.IsNullOrWhiteSpace(_token);

    public void Configure(string serverUrl, string token, bool allowInvalidCertificate)
    {
        var normalized = NormalizeServerUrl(serverUrl);
        if (_httpClient is not null &&
            string.Equals(_baseApiUrl, normalized, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(_token, token, StringComparison.Ordinal) &&
            _allowInvalidCertificate == allowInvalidCertificate)
        {
            return;
        }

        _baseApiUrl = normalized;
        _token = token;
        _allowInvalidCertificate = allowInvalidCertificate;
        RecreateClient();
    }

    public static string NormalizeServerUrl(string serverUrl)
    {
        var trimmed = serverUrl.Trim().TrimEnd('/');
        if (string.IsNullOrWhiteSpace(trimmed)) return string.Empty;

        if (trimmed.EndsWith("/api/desktop/v1", StringComparison.OrdinalIgnoreCase))
            return trimmed;

        if (trimmed.EndsWith("/api/desktop", StringComparison.OrdinalIgnoreCase))
            return $"{trimmed}/v1";

        return $"{trimmed}/api/desktop/v1";
    }

    public async Task<ServerLoginResult> LoginAsync(string serverUrl, string email, string password, bool allowInvalidCertificate)
    {
        Configure(serverUrl, string.Empty, allowInvalidCertificate);
        var result = await SendAsync<ServerLoginResult>(HttpMethod.Post, "auth/login", new
        {
            email,
            password,
            deviceName = Environment.MachineName
        }, requireAuth: false);

        Configure(serverUrl, result.Token, allowInvalidCertificate);
        return result;
    }

    public async Task LogoutAsync()
    {
        if (!IsAuthenticated) return;
        await SendAsync<JsonElement>(HttpMethod.Post, "auth/logout", null, requireAuth: true);
        _token = string.Empty;
        RecreateClient();
    }

    public Task<ServerBootstrap> BootstrapAsync()
    {
        return SendAsync<ServerBootstrap>(HttpMethod.Get, "bootstrap", null, requireAuth: true);
    }

    public Task<ServerImportSnapshotResult> ImportSnapshotAsync(
        IEnumerable<Asset> assets,
        IEnumerable<OperationRecord> records,
        IEnumerable<AssetSource> sources)
    {
        var payload = new
        {
            assets = assets.Select(asset => new
            {
                id = asset.Id,
                assetCode = asset.Id,
                assetName = asset.AssetName,
                modelName = asset.ModelName,
                brand = asset.Brand,
                status = ToServerStatus(asset.Status),
                internalCode = asset.InternalCode,
                location = asset.Location,
                purchaseDate = asset.PurchaseDate,
                note = asset.Note,
                sourceId = asset.SourceId?.ToString()
            }),
            records = records.Select(record => new
            {
                id = record.Id.ToString(),
                assetId = record.AssetId,
                assetCode = record.AssetId,
                assetName = record.AssetName,
                type = ToServerOperation(record.Type),
                operatorName = record.Operator,
                timestamp = record.Timestamp,
                note = record.Note,
                estimatedReturnDate = record.EstimatedReturnDate,
                isSyncedToReminders = record.IsSyncedToReminders
            }),
            sources = sources.Select(source => new
            {
                id = source.Id.ToString(),
                fileName = source.FileName,
                importDate = source.ImportDate,
                assetCount = source.AssetCount,
                assetIds = source.AssetIds
            })
        };

        return SendAsync<ServerImportSnapshotResult>(HttpMethod.Post, "import-snapshot", payload, requireAuth: true);
    }

    public async Task<ServerAsset> UpsertAssetAsync(Asset asset)
    {
        var result = await SendAsync<ServerAssetEnvelope>(HttpMethod.Post, "assets", new
        {
            assetCode = asset.Id,
            assetName = asset.AssetName,
            modelName = asset.ModelName,
            brand = asset.Brand,
            status = ToServerStatus(asset.Status),
            internalCode = asset.InternalCode,
            location = asset.Location,
            purchaseDate = asset.PurchaseDate,
            note = asset.Note
        }, requireAuth: true);
        return result.Asset;
    }

    public async Task<ServerAsset> UpdateAssetStatusAsync(
        string serverAssetId,
        AssetStatus status,
        string operatorName,
        string? note,
        DateTime? estimatedReturnDate)
    {
        var result = await SendAsync<ServerAssetStatusEnvelope>(HttpMethod.Patch, $"assets/{Uri.EscapeDataString(serverAssetId)}/status", new
        {
            status = ToServerStatus(status),
            operatorName,
            note,
            estimatedReturnDate
        }, requireAuth: true);
        return result.Asset;
    }

    public Task DeleteAssetAsync(string serverAssetId)
    {
        return SendAsync<JsonElement>(HttpMethod.Delete, $"assets/{Uri.EscapeDataString(serverAssetId)}", null, requireAuth: true);
    }

    public static Asset ToLocalAsset(ServerAsset asset)
    {
        return new Asset
        {
            Id = asset.AssetCode,
            AssetName = asset.AssetName,
            ModelName = asset.ModelName,
            Brand = asset.Brand,
            Status = ToLocalStatus(asset.Status),
            InternalCode = asset.InternalCode,
            Location = asset.Location,
            PurchaseDate = asset.PurchaseDate,
            Note = asset.Note,
            SourceId = TryGuid(asset.SourceId),
            LastUpdated = asset.UpdatedAt ?? DateTime.Now
        };
    }

    public static OperationRecord ToLocalRecord(ServerOperationRecord record)
    {
        return new OperationRecord
        {
            Id = GuidFromString(record.Id),
            AssetId = record.AssetCode,
            AssetName = record.AssetName,
            Type = ToLocalOperation(record.Type),
            Operator = record.OperatorName,
            Timestamp = record.CreatedAt ?? DateTime.Now,
            Note = record.Note,
            EstimatedReturnDate = record.EstimatedReturnDate,
            IsSyncedToReminders = record.IsSyncedToReminders
        };
    }

    public static AssetSource? ToLocalSource(ServerAssetSource source)
    {
        var id = TryGuid(source.Id);
        if (id is null) return null;

        return new AssetSource
        {
            Id = id.Value,
            FileName = source.FileName,
            ImportDate = source.CreatedAt ?? DateTime.Now,
            AssetCount = source.AssetCount,
            AssetIds = source.AssetCodes ?? new List<string>()
        };
    }

    private async Task<T> SendAsync<T>(HttpMethod method, string path, object? body, bool requireAuth)
    {
        if (_httpClient is null || string.IsNullOrWhiteSpace(_baseApiUrl))
            throw new InvalidOperationException("服务器地址未配置");

        if (requireAuth && string.IsNullOrWhiteSpace(_token))
            throw new InvalidOperationException("请先登录服务器");

        using var request = new HttpRequestMessage(method, path);
        if (body is not null)
            request.Content = JsonContent.Create(body, options: JsonOptions);

        using var response = await _httpClient.SendAsync(request);
        var json = await response.Content.ReadAsStringAsync();
        var envelope = JsonSerializer.Deserialize<ApiEnvelope<T>>(json, JsonOptions);

        if (!response.IsSuccessStatusCode || envelope?.Ok != true)
        {
            var message = envelope?.Message;
            if (string.IsNullOrWhiteSpace(message))
                message = response.StatusCode == HttpStatusCode.NotFound ? "服务器接口不存在" : $"服务器返回 {response.StatusCode}";
            throw new InvalidOperationException(message);
        }

        return envelope.ToPayload();
    }

    private void RecreateClient()
    {
        _httpClient?.Dispose();
        if (string.IsNullOrWhiteSpace(_baseApiUrl))
        {
            _httpClient = null;
            return;
        }

        var handler = new HttpClientHandler();
        if (_allowInvalidCertificate)
        {
            handler.ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator;
        }

        _httpClient = new HttpClient(handler)
        {
            BaseAddress = new Uri($"{_baseApiUrl}/"),
            Timeout = TimeSpan.FromSeconds(30)
        };
        _httpClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        if (!string.IsNullOrWhiteSpace(_token))
        {
            _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _token);
            _httpClient.DefaultRequestHeaders.Add("X-AssetManager-Token", _token);
        }
    }

    private static string ToServerStatus(AssetStatus status) => status switch
    {
        AssetStatus.CheckedOut => "CHECKED_OUT",
        AssetStatus.Maintenance => "MAINTENANCE",
        AssetStatus.Scrapped => "SCRAPPED",
        _ => "IN_STOCK"
    };

    private static AssetStatus ToLocalStatus(string status) => status switch
    {
        "CHECKED_OUT" => AssetStatus.CheckedOut,
        "MAINTENANCE" => AssetStatus.Maintenance,
        "SCRAPPED" => AssetStatus.Scrapped,
        _ => AssetStatus.InStock
    };

    private static string ToServerOperation(OperationType type) => type switch
    {
        OperationType.CheckOut => "CHECK_OUT",
        OperationType.Repair => "REPAIR",
        OperationType.Scrap => "SCRAP",
        _ => "CHECK_IN"
    };

    private static OperationType ToLocalOperation(string type) => type switch
    {
        "CHECK_OUT" => OperationType.CheckOut,
        "REPAIR" => OperationType.Repair,
        "SCRAP" => OperationType.Scrap,
        _ => OperationType.CheckIn
    };

    private static Guid? TryGuid(string? value)
    {
        return Guid.TryParse(value, out var guid) ? guid : null;
    }

    private static Guid GuidFromString(string value)
    {
        if (Guid.TryParse(value, out var guid)) return guid;
        var hash = MD5.HashData(System.Text.Encoding.UTF8.GetBytes(value));
        return new Guid(hash);
    }

    public void Dispose()
    {
        _httpClient?.Dispose();
    }

    private sealed class ApiEnvelope<T>
    {
        public bool Ok { get; set; }
        public string? Message { get; set; }
        public string? Code { get; set; }
        public T? Payload { get; set; }

        public string? Token { get; set; }
        public DateTime? ExpiresAt { get; set; }
        public ServerUser? User { get; set; }
        public List<ServerAsset>? Assets { get; set; }
        public List<ServerOperationRecord>? Records { get; set; }
        public List<ServerAssetSource>? Sources { get; set; }
        public List<ServerUser>? Users { get; set; }
        public List<ServerTransfer>? Transfers { get; set; }
        public ServerFeishuStatus? Feishu { get; set; }
        public DateTime? ServerTime { get; set; }
        public ServerAsset? Asset { get; set; }
        public ServerOperationRecord? Record { get; set; }
        public int ImportedAssets { get; set; }
        public int ImportedRecords { get; set; }
        public int ImportedSources { get; set; }

        public T ToPayload()
        {
            if (Payload is not null) return Payload;

            var json = JsonSerializer.Serialize(this, JsonOptions);
            var payload = JsonSerializer.Deserialize<T>(json, JsonOptions);
            return payload ?? throw new InvalidOperationException("服务器返回数据无法解析");
        }
    }
}

public sealed record ServerLoginResult(
    string Token,
    DateTime ExpiresAt,
    ServerUser User);

public sealed record ServerUser(
    string Id,
    string Email,
    string Name,
    string Role);

public sealed record ServerBootstrap(
    DateTime ServerTime,
    ServerUser User,
    List<ServerAsset> Assets,
    List<ServerOperationRecord> Records,
    List<ServerAssetSource> Sources,
    List<ServerUser> Users,
    List<ServerTransfer> Transfers,
    ServerFeishuStatus Feishu);

public sealed record ServerAsset(
    string Id,
    string OwnerId,
    string AssetCode,
    string AssetName,
    string ModelName,
    string Brand,
    string Status,
    string InternalCode,
    string Location,
    DateTime? PurchaseDate,
    string? Note,
    string? SourceId,
    DateTime? CreatedAt,
    DateTime? UpdatedAt);

public sealed record ServerOperationRecord(
    string Id,
    string OwnerId,
    string? AssetId,
    string AssetCode,
    string AssetName,
    string Type,
    string OperatorName,
    string? Note,
    DateTime? EstimatedReturnDate,
    bool IsSyncedToReminders,
    DateTime? CreatedAt);

public sealed record ServerAssetSource(
    string Id,
    string OwnerId,
    string FileName,
    int AssetCount,
    List<string>? AssetCodes,
    DateTime? CreatedAt,
    DateTime? UpdatedAt);

public sealed record ServerTransfer(
    string Id,
    string Status,
    string? Note,
    DateTime? CreatedAt,
    DateTime? DecidedAt);

public sealed record ServerFeishuStatus(
    string AssetTableLink,
    string RecordTableLink,
    bool Configured);

public sealed record ServerAssetEnvelope(ServerAsset Asset);

public sealed record ServerAssetStatusEnvelope(ServerAsset Asset, ServerOperationRecord? Record);

public sealed record ServerImportSnapshotResult(
    int ImportedAssets,
    int ImportedRecords,
    int ImportedSources);
