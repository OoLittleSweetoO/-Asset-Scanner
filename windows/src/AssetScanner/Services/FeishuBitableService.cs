using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using AssetScanner.Models;

namespace AssetScanner.Services;

public sealed class FeishuBitableService
{
    private const string BaseUrl = "https://open.feishu.cn/open-apis";
    private readonly HttpClient _http = new();
    private readonly string _configPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "AssetManager",
        "feishu_config.json");

    private string _accessToken = "";
    private DateTime _tokenExpiry = DateTime.MinValue;

    public FeishuBitableConfig Config { get; private set; } = FeishuBitableConfig.Default;

    public FeishuBitableService()
    {
        LoadConfig();
    }

    public bool HasBaseConfig =>
        !string.IsNullOrWhiteSpace(Config.AppId) &&
        !string.IsNullOrWhiteSpace(Config.AppSecret) &&
        (!string.IsNullOrWhiteSpace(Config.AssetAppToken) || !string.IsNullOrWhiteSpace(Config.RecordAppToken));

    public bool CanSyncAssets =>
        !string.IsNullOrWhiteSpace(Config.AssetAppToken) &&
        !string.IsNullOrWhiteSpace(Config.AssetTableId);

    public bool CanSyncRecords =>
        !string.IsNullOrWhiteSpace(Config.RecordAppToken) &&
        !string.IsNullOrWhiteSpace(Config.RecordTableId);

    public bool IsConfigured => HasBaseConfig && CanSyncRecords;

    public bool IsReadyForAutoSync => HasBaseConfig && CanSyncAssets && CanSyncRecords;

    public void SaveConfig(FeishuBitableConfig config)
    {
        Config = config.Normalized();
        Directory.CreateDirectory(Path.GetDirectoryName(_configPath)!);
        File.WriteAllText(_configPath, JsonSerializer.Serialize(Config, new JsonSerializerOptions { WriteIndented = true }));
        _accessToken = "";
        _tokenExpiry = DateTime.MinValue;
    }

    public void LoadConfig()
    {
        if (!File.Exists(_configPath))
            return;

        var config = JsonSerializer.Deserialize<FeishuBitableConfig>(File.ReadAllText(_configPath));
        if (config is not null)
            Config = config.Normalized();
    }

    public static (string AppToken, string TableId)? ExtractTableConfig(string link)
    {
        if (!Uri.TryCreate(link.Trim(), UriKind.Absolute, out var uri))
            return null;

        var parts = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        var baseIndex = Array.FindIndex(parts, part => part == "base");
        if (baseIndex < 0 || baseIndex + 1 >= parts.Length)
            return null;

        var tableId = ParseQuery(uri.Query)
            .FirstOrDefault(pair => pair.Key == "table")
            .Value;

        return string.IsNullOrWhiteSpace(tableId) ? null : (parts[baseIndex + 1], tableId);
    }

    public async Task<string> TestConnectionAsync()
    {
        await EnsureAccessTokenAsync();
        var inspection = await InspectRemoteTablesAsync();
        var chunks = new[] { inspection.AssetSummary, inspection.RecordSummary }
            .Where(text => !string.IsNullOrWhiteSpace(text));
        return $"飞书连接成功：{string.Join("；", chunks)}";
    }

    public async Task<string> SyncAllAsync(IReadOnlyList<Asset> assets, IReadOnlyList<OperationRecord> records)
    {
        EnsureFullSyncConfig();
        await EnsureAccessTokenAsync();
        var result = await SyncAllDataOnceAsync(assets, records);
        return $"飞书全量同步完成：资产 {result.AssetCount} 条，记录 {result.RecordCount} 条，删除远端资产 {result.DeletedAssetCount} 条，删除远端记录 {result.DeletedRecordCount} 条";
    }

    public async Task<string> SyncAssetStatusAsync(Asset asset, OperationRecord? statusRecord)
    {
        EnsureAssetSyncConfig();
        await EnsureAccessTokenAsync();
        await EnsureRemoteSchemaAsync();

        var assetFieldTypes = await FetchFieldDefinitionsAsync(Config.AssetAppToken, Config.AssetTableId);
        ValidateAssetSchema(assetFieldTypes.Keys.ToHashSet());
        var assetRecordId = await SearchSingleRecordIdByFieldAsync(Config.AssetAppToken, Config.AssetTableId, "外编号", asset.Id);

        await UpsertRecordAsync(
            Config.AssetAppToken,
            Config.AssetTableId,
            AssetFields(asset, statusRecord, assetFieldTypes),
            assetRecordId);

        var syncedRecord = false;
        if (statusRecord is not null && CanSyncRecords)
        {
            var recordFieldTypes = await FetchFieldDefinitionsAsync(Config.RecordAppToken, Config.RecordTableId);
            var recordFieldNames = recordFieldTypes.Keys.ToHashSet();
            var userDirectory = await FetchOperatorDirectoryAsync(Config.RecordAppToken, Config.RecordTableId);
            var operationRecordId = await SearchOperationRecordIdAsync(statusRecord, recordFieldNames);

            await UpsertRecordAsync(
                Config.RecordAppToken,
                Config.RecordTableId,
                RecordFields(statusRecord, asset, recordFieldTypes, userDirectory),
                operationRecordId);
            syncedRecord = true;
        }

        return syncedRecord
            ? $"飞书已更新：{asset.Id} 状态，并写入操作记录"
            : $"飞书已更新：{asset.Id} 状态";
    }

    public async Task<FeishuSnapshot> ImportRemoteAsync()
    {
        await EnsureAccessTokenAsync();
        return await FetchRemoteSnapshotAsync();
    }

    public async Task<(FeishuSnapshot Snapshot, string Message)> SyncBidirectionallyAsync(
        IReadOnlyList<Asset> localAssets,
        IReadOnlyList<OperationRecord> localRecords)
    {
        await EnsureAccessTokenAsync();

        var warnings = new List<string>();
        if (CanSyncAssets && CanSyncRecords)
        {
            try
            {
                await SyncAllDataOnceAsync(localAssets, localRecords);
            }
            catch (Exception ex)
            {
                warnings.Add($"推送到飞书失败：{ex.Message}");
            }
        }
        else
        {
            if (!CanSyncAssets) warnings.Add("资产表未配置完整");
            if (!CanSyncRecords) warnings.Add("记录表未配置完整");
        }

        var remote = await FetchRemoteSnapshotAsync();
        warnings.AddRange(remote.Warnings);
        var warningText = warnings.Count == 0 ? "" : $"（{string.Join("；", warnings)}）";
        return (remote with { Warnings = warnings }, $"飞书双向同步完成：读取资产 {remote.Assets.Count} 个，记录 {remote.Records.Count} 条{warningText}");
    }

    private void EnsureFullSyncConfig()
    {
        if (!HasBaseConfig)
            throw new InvalidOperationException("请先配置 App ID、App Secret 和 App Token");
        if (!CanSyncAssets)
            throw new InvalidOperationException("缺少资产表 ID，暂时无法同步资产列表");
        if (!CanSyncRecords)
            throw new InvalidOperationException("缺少记录表 ID，暂时无法同步出入库记录");
    }

    private void EnsureAssetSyncConfig()
    {
        if (!HasBaseConfig)
            throw new InvalidOperationException("请先配置 App ID、App Secret 和 App Token");
        if (!CanSyncAssets)
            throw new InvalidOperationException("缺少资产表 ID，暂时无法同步资产状态");
    }

    private async Task EnsureAccessTokenAsync()
    {
        if (!string.IsNullOrWhiteSpace(_accessToken) && _tokenExpiry > DateTime.Now.AddMinutes(5))
            return;

        if (string.IsNullOrWhiteSpace(Config.AppId) || string.IsNullOrWhiteSpace(Config.AppSecret))
            throw new InvalidOperationException("请先填写飞书 App ID 和 App Secret");

        var body = new JsonObject
        {
            ["app_id"] = Config.AppId,
            ["app_secret"] = Config.AppSecret
        };

        var json = await SendAsync(HttpMethod.Post, $"{BaseUrl}/auth/v3/tenant_access_token/internal", body, authorize: false);
        _accessToken = json["tenant_access_token"]?.GetValue<string>() ?? "";
        var expire = json["expire"]?.GetValue<int>() ?? 7200;
        _tokenExpiry = DateTime.Now.AddSeconds(expire);

        if (string.IsNullOrWhiteSpace(_accessToken))
            throw new InvalidOperationException("飞书访问令牌为空");
    }

    private async Task<FeishuSyncResult> SyncAllDataOnceAsync(
        IReadOnlyList<Asset> assets,
        IReadOnlyList<OperationRecord> records)
    {
        await EnsureRemoteSchemaAsync();

        var assetFieldTypes = await FetchFieldDefinitionsAsync(Config.AssetAppToken, Config.AssetTableId);
        ValidateAssetSchema(assetFieldTypes.Keys.ToHashSet());
        var recordFieldTypes = await FetchFieldDefinitionsAsync(Config.RecordAppToken, Config.RecordTableId);
        var recordFieldNames = recordFieldTypes.Keys.ToHashSet();

        var assetIndex = await FetchRecordIndexAsync(Config.AssetAppToken, Config.AssetTableId, "外编号");
        var assetGroups = await FetchRecordIdsGroupedByFieldAsync(Config.AssetAppToken, Config.AssetTableId, "外编号");
        var recordIndex = await FetchExistingOperationRecordIdsAsync(Config.RecordAppToken, Config.RecordTableId, recordFieldNames);
        var recordGroups = await FetchExistingOperationRecordFingerprintGroupsAsync(Config.RecordAppToken, Config.RecordTableId);
        var userDirectory = await FetchOperatorDirectoryAsync(Config.RecordAppToken, Config.RecordTableId);
        var latestActiveRecords = LatestActiveRecordsByAsset(records);
        var assetById = assets.ToDictionary(asset => asset.Id, asset => asset);

        var assetCount = 0;
        var recordCount = 0;
        foreach (var asset in assets)
        {
            await UpsertRecordAsync(
                Config.AssetAppToken,
                Config.AssetTableId,
                AssetFields(asset, latestActiveRecords.GetValueOrDefault(asset.Id), assetFieldTypes),
                assetIndex.GetValueOrDefault(asset.Id));
            assetCount++;
        }

        foreach (var record in records)
        {
            await UpsertRecordAsync(
                Config.RecordAppToken,
                Config.RecordTableId,
                RecordFields(record, assetById.GetValueOrDefault(record.AssetId), recordFieldTypes, userDirectory),
                OperationRecordLookupKeys(record).Select(key => recordIndex.GetValueOrDefault(key)).FirstOrDefault(id => !string.IsNullOrWhiteSpace(id)));
            recordCount++;
        }

        var deletedAssetCount = await DeleteStaleAssetRecordsAsync(assets, assetGroups, assetIndex);
        var deletedRecordCount = await DeleteStaleOperationRecordsAsync(records, recordGroups, recordIndex);

        return new FeishuSyncResult(assetCount, recordCount, deletedAssetCount, deletedRecordCount);
    }

    private async Task<FeishuSnapshot> FetchRemoteSnapshotAsync()
    {
        var assets = new List<Asset>();
        var records = new List<OperationRecord>();
        var warnings = new List<string>();

        if (CanSyncAssets)
        {
            var assetFieldTypes = await FetchFieldDefinitionsAsync(Config.AssetAppToken, Config.AssetTableId);
            var missingAssetFields = MissingAssetFields(assetFieldTypes.Keys.ToHashSet());
            if (missingAssetFields.Count == 0)
            {
                assets = (await FetchAllRecordsAsync(Config.AssetAppToken, Config.AssetTableId))
                    .Select(record => RemoteAsset(record.Fields))
                    .Where(asset => asset is not null)
                    .Cast<Asset>()
                    .ToList();
            }
            else
            {
                warnings.Add($"资产表缺少字段：{string.Join("、", missingAssetFields)}");
            }
        }

        if (CanSyncRecords)
        {
            records = (await FetchAllRecordsAsync(Config.RecordAppToken, Config.RecordTableId))
                .Select(record => RemoteRecord(record.RecordId, record.Fields))
                .Where(record => record is not null)
                .Cast<OperationRecord>()
                .OrderByDescending(record => record.Timestamp)
                .ToList();
        }

        return new FeishuSnapshot(assets, records, warnings);
    }

    private async Task<FeishuSyncInspection> InspectRemoteTablesAsync()
    {
        var assetSummary = "";
        var recordSummary = "";

        if (CanSyncAssets)
        {
            var fields = await FetchFieldDefinitionsAsync(Config.AssetAppToken, Config.AssetTableId);
            var missing = MissingAssetFields(fields.Keys.ToHashSet());
            assetSummary = missing.Count == 0
                ? "资产表字段完整"
                : $"资产表缺少：{string.Join("、", missing)}";
        }

        if (CanSyncRecords)
        {
            var fields = await FetchFieldDefinitionsAsync(Config.RecordAppToken, Config.RecordTableId);
            var missing = MissingRecordFields(fields.Keys.ToHashSet());
            var recordIdentity = fields.ContainsKey("记录ID")
                ? "使用记录ID对齐"
                : "将按外编号+操作类型+操作时间对齐";
            recordSummary = missing.Count == 0
                ? $"记录表可读，{recordIdentity}"
                : $"记录表缺少：{string.Join("、", missing)}，{recordIdentity}";
        }

        return new FeishuSyncInspection(assetSummary, recordSummary);
    }

    private async Task EnsureRemoteSchemaAsync()
    {
        if (CanSyncAssets)
            await EnsureFieldsAsync(Config.AssetAppToken, Config.AssetTableId, AssetFieldSpecs);
        if (CanSyncRecords)
            await EnsureFieldsAsync(Config.RecordAppToken, Config.RecordTableId, RecordFieldSpecs);
    }

    private async Task EnsureFieldsAsync(string appToken, string tableId, IReadOnlyList<FeishuFieldSpec> specs)
    {
        var existing = await FetchFieldDefinitionsAsync(appToken, tableId);
        foreach (var spec in specs.Where(spec => !existing.ContainsKey(spec.Name)))
            await CreateFieldAsync(appToken, tableId, spec);
    }

    private async Task<Dictionary<string, int>> FetchFieldDefinitionsAsync(string appToken, string tableId)
    {
        var json = await SendAsync(HttpMethod.Get, $"{BaseUrl}/bitable/v1/apps/{appToken}/tables/{tableId}/fields?page_size=500");
        var items = json["data"]?["items"]?.AsArray() ?? new JsonArray();
        return items
            .OfType<JsonObject>()
            .Where(item => item["field_name"] is not null && item["type"] is not null)
            .ToDictionary(item => item["field_name"]!.GetValue<string>(), item => item["type"]!.GetValue<int>());
    }

    private async Task CreateFieldAsync(string appToken, string tableId, FeishuFieldSpec spec)
    {
        var body = new JsonObject
        {
            ["field_name"] = spec.Name,
            ["type"] = spec.Type
        };
        if (spec.Property is not null)
            body["property"] = JsonNode.Parse(JsonSerializer.Serialize(spec.Property));

        await SendAsync(HttpMethod.Post, $"{BaseUrl}/bitable/v1/apps/{appToken}/tables/{tableId}/fields", body);
    }

    private async Task<List<FeishuRemoteRecord>> FetchAllRecordsAsync(string appToken, string tableId)
    {
        var result = new List<FeishuRemoteRecord>();
        string? pageToken = null;

        do
        {
            var url = $"{BaseUrl}/bitable/v1/apps/{appToken}/tables/{tableId}/records?page_size=500";
            if (!string.IsNullOrWhiteSpace(pageToken))
                url += $"&page_token={Uri.EscapeDataString(pageToken)}";

            var json = await SendAsync(HttpMethod.Get, url);
            var data = json["data"]?.AsObject();
            var items = data?["items"]?.AsArray() ?? new JsonArray();

            foreach (var item in items.OfType<JsonObject>())
            {
                var recordId = item["record_id"]?.GetValue<string>() ?? "";
                var fields = item["fields"]?.AsObject() ?? new JsonObject();
                if (!string.IsNullOrWhiteSpace(recordId))
                    result.Add(new FeishuRemoteRecord(recordId, fields));
            }

            pageToken = data?["has_more"]?.GetValue<bool>() == true
                ? data?["page_token"]?.GetValue<string>()
                : null;
        } while (!string.IsNullOrWhiteSpace(pageToken));

        return result;
    }

    private async Task<Dictionary<string, string>> FetchRecordIndexAsync(string appToken, string tableId, string fieldName)
    {
        var records = await FetchAllRecordsAsync(appToken, tableId);
        var index = new Dictionary<string, string>();
        foreach (var record in records)
        {
            var value = StringValue(record.Fields[fieldName]);
            if (!string.IsNullOrWhiteSpace(value))
                index[value] = record.RecordId;
        }
        return index;
    }

    private async Task<string?> SearchSingleRecordIdByFieldAsync(string appToken, string tableId, string fieldName, string value)
    {
        return (await SearchRecordsByFieldAsync(appToken, tableId, fieldName, value, 2, fieldName))
            .Select(record => record.RecordId)
            .FirstOrDefault(id => !string.IsNullOrWhiteSpace(id));
    }

    private async Task<List<FeishuRemoteRecord>> SearchRecordsByFieldAsync(
        string appToken,
        string tableId,
        string fieldName,
        string value,
        int pageSize,
        params string[] fieldNames)
    {
        var fieldsToReturn = fieldNames.Length == 0 ? [fieldName] : fieldNames;
        var fieldNameArray = new JsonArray();
        foreach (var name in fieldsToReturn)
            fieldNameArray.Add(name);

        var body = new JsonObject
        {
            ["field_names"] = fieldNameArray,
            ["filter"] = new JsonObject
            {
                ["conjunction"] = "and",
                ["conditions"] = new JsonArray
                {
                    new JsonObject
                    {
                        ["field_name"] = fieldName,
                        ["operator"] = "is",
                        ["value"] = new JsonArray(value)
                    }
                }
            },
            ["automatic_fields"] = false
        };

        var json = await SendAsync(HttpMethod.Post, $"{BaseUrl}/bitable/v1/apps/{appToken}/tables/{tableId}/records/search?page_size={pageSize}", body);
        var items = json["data"]?["items"]?.AsArray() ?? new JsonArray();
        return items
            .OfType<JsonObject>()
            .Select(item => new FeishuRemoteRecord(
                item["record_id"]?.GetValue<string>() ?? "",
                item["fields"]?.AsObject() ?? new JsonObject()))
            .Where(record => !string.IsNullOrWhiteSpace(record.RecordId))
            .ToList();
    }

    private async Task<string?> SearchOperationRecordIdAsync(OperationRecord record, HashSet<string> availableFieldNames)
    {
        if (availableFieldNames.Contains("记录ID"))
        {
            var recordId = await SearchSingleRecordIdByFieldAsync(Config.RecordAppToken, Config.RecordTableId, "记录ID", record.Id.ToString());
            if (!string.IsNullOrWhiteSpace(recordId))
                return recordId;
        }

        var targetFingerprint = OperationRecordFingerprint(record);
        var candidates = await SearchRecordsByFieldAsync(
            Config.RecordAppToken,
            Config.RecordTableId,
            "外编号",
            record.AssetId,
            50,
            "外编号",
            "操作类型",
            "操作时间");

        return candidates
            .FirstOrDefault(candidate => OperationRecordFallbackFingerprint(candidate.Fields) == targetFingerprint)
            ?.RecordId;
    }

    private async Task<Dictionary<string, List<string>>> FetchRecordIdsGroupedByFieldAsync(string appToken, string tableId, string fieldName)
    {
        var records = await FetchAllRecordsAsync(appToken, tableId);
        var groups = new Dictionary<string, List<string>>();
        foreach (var record in records)
        {
            var value = StringValue(record.Fields[fieldName]);
            if (string.IsNullOrWhiteSpace(value))
                continue;
            if (!groups.TryGetValue(value, out var ids))
            {
                ids = new List<string>();
                groups[value] = ids;
            }
            ids.Add(record.RecordId);
        }
        return groups;
    }

    private async Task<Dictionary<string, string>> FetchExistingOperationRecordIdsAsync(string appToken, string tableId, HashSet<string> availableFieldNames)
    {
        var records = await FetchAllRecordsAsync(appToken, tableId);
        var result = new Dictionary<string, string>();
        foreach (var record in records)
        {
            foreach (var key in OperationRecordLookupKeys(record.Fields, availableFieldNames))
            {
                if (!string.IsNullOrWhiteSpace(key))
                    result[key] = record.RecordId;
            }
        }
        return result;
    }

    private async Task<Dictionary<string, List<string>>> FetchExistingOperationRecordIdGroupsAsync(string appToken, string tableId, HashSet<string> availableFieldNames)
    {
        var records = await FetchAllRecordsAsync(appToken, tableId);
        var result = new Dictionary<string, List<string>>();
        foreach (var record in records)
        {
            foreach (var key in OperationRecordLookupKeys(record.Fields, availableFieldNames).Where(key => !string.IsNullOrWhiteSpace(key)))
            {
                if (!result.TryGetValue(key, out var ids))
                {
                    ids = new List<string>();
                    result[key] = ids;
                }
                ids.Add(record.RecordId);
            }
        }
        return result;
    }

    private async Task<Dictionary<string, List<string>>> FetchExistingOperationRecordFingerprintGroupsAsync(string appToken, string tableId)
    {
        var records = await FetchAllRecordsAsync(appToken, tableId);
        var result = new Dictionary<string, List<string>>();
        foreach (var record in records)
        {
            var key = OperationRecordFallbackFingerprint(record.Fields);
            if (string.IsNullOrWhiteSpace(key))
                continue;

            if (!result.TryGetValue(key, out var ids))
            {
                ids = new List<string>();
                result[key] = ids;
            }
            ids.Add(record.RecordId);
        }
        return result;
    }

    private async Task<Dictionary<string, string>> FetchOperatorDirectoryAsync(string appToken, string tableId)
    {
        var records = await FetchAllRecordsAsync(appToken, tableId);
        var directory = new Dictionary<string, string>();
        foreach (var record in records)
        {
            if (record.Fields["操作人"] is not JsonArray users)
                continue;
            foreach (var user in users.OfType<JsonObject>())
            {
                var name = user["name"]?.GetValue<string>();
                var id = user["id"]?.GetValue<string>();
                if (!string.IsNullOrWhiteSpace(name) && !string.IsNullOrWhiteSpace(id))
                    directory[name] = id;
            }
        }
        return directory;
    }

    private async Task UpsertRecordAsync(string appToken, string tableId, JsonObject fields, string? existingRecordId)
    {
        var body = new JsonObject { ["fields"] = fields };
        if (!string.IsNullOrWhiteSpace(existingRecordId))
        {
            try
            {
                await SendAsync(HttpMethod.Put, $"{BaseUrl}/bitable/v1/apps/{appToken}/tables/{tableId}/records/{existingRecordId}", body);
                return;
            }
            catch (InvalidOperationException ex) when (ShouldRetryAsCreate(ex.Message))
            {
                // Some legacy rows can leave stale record IDs. Create a fresh row instead.
            }
        }

        await SendAsync(HttpMethod.Post, $"{BaseUrl}/bitable/v1/apps/{appToken}/tables/{tableId}/records", body);
    }

    private async Task<int> DeleteStaleAssetRecordsAsync(
        IReadOnlyList<Asset> localAssets,
        Dictionary<string, List<string>> groupedRemoteRecordIds,
        Dictionary<string, string> retainedRecordIds)
    {
        var localAssetIds = localAssets.Select(asset => asset.Id).ToHashSet();
        var staleRecordIds = new List<string>();
        foreach (var (assetId, recordIds) in groupedRemoteRecordIds)
        {
            if (!localAssetIds.Contains(assetId))
            {
                staleRecordIds.AddRange(recordIds);
                continue;
            }

            if (recordIds.Count > 1 && retainedRecordIds.TryGetValue(assetId, out var retainedId))
                staleRecordIds.AddRange(recordIds.Where(id => id != retainedId));
        }

        return await DeleteRecordsAsync(Config.AssetAppToken, Config.AssetTableId, staleRecordIds);
    }

    private async Task<int> DeleteStaleOperationRecordsAsync(
        IReadOnlyList<OperationRecord> localRecords,
        Dictionary<string, List<string>> groupedRemoteRecordIds,
        Dictionary<string, string> retainedRecordIds)
    {
        var localFingerprints = localRecords.Select(OperationRecordFingerprint).ToHashSet();
        var staleRecordIds = new List<string>();
        foreach (var (fingerprint, recordIds) in groupedRemoteRecordIds)
        {
            if (!localFingerprints.Contains(fingerprint))
            {
                staleRecordIds.AddRange(recordIds);
                continue;
            }

            if (recordIds.Count > 1 && retainedRecordIds.TryGetValue(fingerprint, out var retainedId))
                staleRecordIds.AddRange(recordIds.Where(id => id != retainedId));
        }

        return await DeleteRecordsAsync(Config.RecordAppToken, Config.RecordTableId, staleRecordIds);
    }

    private async Task<int> DeleteRecordsAsync(string appToken, string tableId, IEnumerable<string> recordIds)
    {
        var uniqueRecordIds = recordIds.Where(id => !string.IsNullOrWhiteSpace(id)).Distinct().ToList();
        foreach (var recordId in uniqueRecordIds)
            await SendAsync(HttpMethod.Delete, $"{BaseUrl}/bitable/v1/apps/{appToken}/tables/{tableId}/records/{recordId}");
        return uniqueRecordIds.Count;
    }

    private async Task<JsonObject> SendAsync(HttpMethod method, string url, JsonObject? body = null, bool authorize = true)
    {
        using var request = new HttpRequestMessage(method, url);
        if (authorize)
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", _accessToken);
        if (body is not null)
            request.Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json");

        using var response = await _http.SendAsync(request);
        var text = await response.Content.ReadAsStringAsync();
        var json = JsonNode.Parse(text)?.AsObject() ?? new JsonObject();
        var code = json["code"]?.GetValue<int>() ?? -1;
        if (code != 0)
        {
            var message = json["msg"]?.GetValue<string>() ?? response.ReasonPhrase ?? "未知错误";
            var detail = json["error"]?["message"]?.GetValue<string>();
            var combined = string.Join(" | ", new[] { message, detail, $"HTTP {(int)response.StatusCode}" }.Where(item => !string.IsNullOrWhiteSpace(item)));
            throw new InvalidOperationException($"飞书 API 错误: {combined}");
        }

        return json;
    }

    private static JsonObject AssetFields(Asset asset, OperationRecord? latestActiveRecord, Dictionary<string, int> fieldTypes)
    {
        var currentOperator = asset.Status == AssetStatus.InStock ? "" : latestActiveRecord?.Operator ?? "";
        var secondaryStatus = latestActiveRecord?.EstimatedReturnDate?.ToString("yyyy-MM-dd")
                              ?? StructuredNoteValue("二级状态", asset.Note)
                              ?? "";

        var fields = new Dictionary<string, object?>
        {
            ["资产属性"] = "固定资产",
            ["名称"] = asset.AssetName,
            ["型号"] = asset.ModelName,
            ["品牌"] = asset.Brand,
            ["外编号"] = asset.Id,
            ["内编号"] = asset.InternalCode,
            ["保管科室"] = StructuredNoteValue("保管科室", asset.Note) ?? "",
            ["资产专管"] = StructuredNoteValue("资产专管", asset.Note) ?? "",
            ["保管人"] = StructuredNoteValue("保管人", asset.Note) ?? "",
            ["使用人"] = string.IsNullOrWhiteSpace(currentOperator) ? StructuredNoteValue("使用人", asset.Note) ?? "" : currentOperator,
            ["一级状态"] = StatusToText(asset.Status),
            ["二级状态"] = secondaryStatus,
            ["一级存放地"] = asset.Location,
            ["二级存放地"] = StructuredNoteValue("二级存放地", asset.Note) ?? "",
            ["其他附件"] = StructuredNoteValue("其他附件", asset.Note) ?? ""
        };

        return ToFieldsObject(fields, fieldTypes.Keys.ToHashSet());
    }

    private static JsonObject RecordFields(
        OperationRecord record,
        Asset? asset,
        Dictionary<string, int> fieldTypes,
        Dictionary<string, string> userDirectory)
    {
        var note = record.Note ?? "";
        var fields = new Dictionary<string, object?>
        {
            ["记录ID"] = record.Id.ToString(),
            ["资产名称"] = record.AssetName,
            ["外编号"] = record.AssetId,
            ["型号"] = asset?.ModelName ?? "",
            ["品牌"] = asset?.Brand ?? "",
            ["操作类型"] = OperationTypeToText(record.Type),
            ["操作时间"] = DateFieldValue(record.Timestamp, "操作时间", fieldTypes),
            ["备注"] = note,
            ["预计归还"] = record.EstimatedReturnDate.HasValue
                ? DateFieldValue(record.EstimatedReturnDate.Value, "预计归还", fieldTypes)
                : null
        };

        if (fieldTypes.TryGetValue("操作人", out var operatorFieldType))
        {
            if (operatorFieldType == 11)
            {
                if (ResolveOperatorIdentifier(record.Operator, userDirectory) is { } operatorId)
                    fields["操作人"] = new JsonArray(new JsonObject { ["id"] = operatorId });
                else if (!string.IsNullOrWhiteSpace(record.Operator))
                    note = string.IsNullOrWhiteSpace(note) ? $"操作人：{record.Operator}" : $"操作人：{record.Operator}{Environment.NewLine}{note}";
            }
            else if (!string.IsNullOrWhiteSpace(record.Operator))
            {
                fields["操作人"] = record.Operator;
            }
        }
        else if (!string.IsNullOrWhiteSpace(record.Operator))
        {
            note = string.IsNullOrWhiteSpace(note) ? $"操作人：{record.Operator}" : $"操作人：{record.Operator}{Environment.NewLine}{note}";
        }

        fields["备注"] = note;
        return ToFieldsObject(fields, fieldTypes.Keys.ToHashSet());
    }

    private static JsonObject ToFieldsObject(Dictionary<string, object?> fields, HashSet<string> availableFields)
    {
        var obj = new JsonObject();
        foreach (var (key, value) in fields)
        {
            if (!availableFields.Contains(key) || value is null)
                continue;

            obj[key] = value switch
            {
                JsonNode node => node.DeepClone(),
                string text => JsonValue.Create(text),
                long number => JsonValue.Create(number),
                int number => JsonValue.Create(number),
                bool boolean => JsonValue.Create(boolean),
                DateTime date => JsonValue.Create(date.ToString("yyyy-MM-dd HH:mm")),
                _ => JsonValue.Create(value.ToString())
            };
        }
        return obj;
    }

    private static object DateFieldValue(DateTime date, string fieldName, Dictionary<string, int> fieldTypes) =>
        fieldTypes.GetValueOrDefault(fieldName) == 5
            ? new DateTimeOffset(date).ToUnixTimeMilliseconds()
            : date.ToString("yyyy-MM-dd HH:mm");

    private static Dictionary<string, OperationRecord> LatestActiveRecordsByAsset(IReadOnlyList<OperationRecord> records)
    {
        var result = new Dictionary<string, OperationRecord>();
        foreach (var record in records
                     .Where(record => record.Type is OperationType.CheckOut or OperationType.Repair or OperationType.Scrap)
                     .OrderByDescending(record => record.Timestamp))
        {
            result.TryAdd(record.AssetId, record);
        }
        return result;
    }

    private static Asset? RemoteAsset(JsonObject fields)
    {
        var id = StringValue(fields["外编号"])?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(id))
            return null;

        return new Asset
        {
            Id = id,
            AssetName = StringValue(fields["名称"]) ?? "",
            ModelName = StringValue(fields["型号"]) ?? "",
            Brand = StringValue(fields["品牌"]) ?? "",
            Status = TextToStatus(StringValue(fields["一级状态"])),
            InternalCode = StringValue(fields["内编号"]) ?? "",
            Location = StringValue(fields["一级存放地"]) ?? "",
            Note = RebuildAssetNote(fields),
            LastUpdated = DateTime.Now
        };
    }

    private static OperationRecord? RemoteRecord(string recordId, JsonObject fields)
    {
        var assetId = StringValue(fields["外编号"])?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(assetId))
            return null;

        var typeText = StringValue(fields["操作类型"]) ?? "";
        return new OperationRecord(
            id: Guid.TryParse(StringValue(fields["记录ID"]), out var id) ? id : DeterministicGuid(recordId),
            assetId: assetId,
            assetName: StringValue(fields["资产名称"]) ?? "",
            type: TextToOperationType(typeText),
            @operator: OperatorName(fields["操作人"]) ?? ExtractOperatorName(StringValue(fields["备注"])),
            timestamp: DateValue(fields["操作时间"]) ?? DateTime.Now,
            note: StringValue(fields["备注"]),
            estimatedReturnDate: DateValue(fields["预计归还"]));
    }

    private static string? StringValue(JsonNode? node)
    {
        if (node is null) return null;
        if (node is JsonValue valueNode)
        {
            if (valueNode.TryGetValue<string>(out var text)) return text;
            if (valueNode.TryGetValue<long>(out var longNumber)) return longNumber.ToString(CultureInfo.InvariantCulture);
            if (valueNode.TryGetValue<double>(out var doubleNumber)) return doubleNumber.ToString(CultureInfo.InvariantCulture);
        }
        if (node is JsonArray array)
        {
            return string.Join(",", array.Select(item =>
            {
                if (item is not JsonObject obj) return null;
                return obj["text"]?.GetValue<string>() ??
                       obj["name"]?.GetValue<string>() ??
                       obj["en_name"]?.GetValue<string>();
            }).Where(text => !string.IsNullOrWhiteSpace(text)));
        }
        return node.ToJsonString();
    }

    private static string? OperatorName(JsonNode? node)
    {
        if (node is not JsonArray users)
            return StringValue(node);
        var first = users.OfType<JsonObject>().FirstOrDefault();
        return first?["name"]?.GetValue<string>() ?? first?["en_name"]?.GetValue<string>();
    }

    private static DateTime? DateValue(JsonNode? node)
    {
        var value = StringValue(node);
        if (string.IsNullOrWhiteSpace(value)) return null;
        if (long.TryParse(value, out var milliseconds))
            return DateTimeOffset.FromUnixTimeMilliseconds(milliseconds).LocalDateTime;
        if (DateTime.TryParse(value, out var date))
            return date;
        return null;
    }

    private static string? StructuredNoteValue(string label, string? note)
    {
        if (string.IsNullOrWhiteSpace(note)) return null;
        var prefix = $"{label}：";
        return note.Split(Environment.NewLine)
            .FirstOrDefault(line => line.StartsWith(prefix, StringComparison.Ordinal))
            ?.Substring(prefix.Length)
            .Trim();
    }

    private static string? RebuildAssetNote(JsonObject fields)
    {
        var labels = new[] { "保管科室", "资产专管", "保管人", "使用人", "二级状态", "二级存放地", "其他附件" };
        var lines = labels
            .Select(label => (label, value: StringValue(fields[label])?.Trim()))
            .Where(item => !string.IsNullOrWhiteSpace(item.value))
            .Select(item => $"{item.label}：{item.value}");
        var note = string.Join(Environment.NewLine, lines);
        return string.IsNullOrWhiteSpace(note) ? null : note;
    }

    private static string ExtractOperatorName(string? note)
    {
        if (string.IsNullOrWhiteSpace(note) || !note.StartsWith("操作人：", StringComparison.Ordinal))
            return "当前用户";
        return note.Split(Environment.NewLine).First().Replace("操作人：", "");
    }

    private static Guid DeterministicGuid(string seed)
    {
        var bytes = MD5.HashData(Encoding.UTF8.GetBytes(seed));
        return new Guid(bytes);
    }

    private static string? ResolveOperatorIdentifier(string operatorName, Dictionary<string, string> userDirectory)
    {
        if (string.IsNullOrWhiteSpace(operatorName))
            return null;
        if (operatorName.StartsWith("ou_", StringComparison.Ordinal))
            return operatorName;
        return userDirectory.GetValueOrDefault(operatorName);
    }

    private static string StatusToText(AssetStatus status) => status switch
    {
        AssetStatus.CheckedOut => "已出库",
        AssetStatus.Maintenance => "送修",
        AssetStatus.Scrapped => "待报废",
        _ => "在库"
    };

    private static AssetStatus TextToStatus(string? value) => value switch
    {
        "已出库" or "出库" => AssetStatus.CheckedOut,
        "送修" or "维修中" => AssetStatus.Maintenance,
        "待报废" or "报废" => AssetStatus.Scrapped,
        _ => AssetStatus.InStock
    };

    private static string OperationTypeToText(OperationType type) => type switch
    {
        OperationType.CheckOut => "出库",
        OperationType.Repair => "送修",
        OperationType.Scrap => "报废",
        _ => "入库"
    };

    private static OperationType TextToOperationType(string? value) => value switch
    {
        "出库" => OperationType.CheckOut,
        "送修" => OperationType.Repair,
        "报废" => OperationType.Scrap,
        _ => OperationType.CheckIn
    };

    private static long TimestampValue(DateTime date) => new DateTimeOffset(date).ToUnixTimeMilliseconds();

    private static string OperationRecordFingerprint(OperationRecord record) =>
        string.Join("|", record.AssetId, OperationTypeToText(record.Type), TimestampValue(record.Timestamp).ToString(CultureInfo.InvariantCulture));

    private static IEnumerable<string> OperationRecordLookupKeys(OperationRecord record)
    {
        yield return record.Id.ToString();
        yield return OperationRecordFingerprint(record);
    }

    private static IEnumerable<string> OperationRecordLookupKeys(JsonObject fields, HashSet<string> availableFieldNames)
    {
        if (availableFieldNames.Contains("记录ID"))
        {
            var recordId = StringValue(fields["记录ID"]);
            if (!string.IsNullOrWhiteSpace(recordId))
                yield return recordId;
        }

        var fallback = OperationRecordFallbackFingerprint(fields);
        if (!string.IsNullOrWhiteSpace(fallback))
            yield return fallback;
    }

    private static string OperationRecordFallbackFingerprint(JsonObject fields)
    {
        var assetId = StringValue(fields["外编号"]) ?? "";
        var type = StringValue(fields["操作类型"]) ?? "";
        var timestamp = NormalizedTimestampString(fields["操作时间"]) ?? "";
        return string.Join("|", assetId, type, timestamp);
    }

    private static string? NormalizedTimestampString(JsonNode? node)
    {
        var date = DateValue(node);
        return date.HasValue ? TimestampValue(date.Value).ToString(CultureInfo.InvariantCulture) : null;
    }

    private static void ValidateAssetSchema(HashSet<string> availableFieldNames)
    {
        var missing = MissingAssetFields(availableFieldNames);
        if (missing.Count > 0)
            throw new InvalidOperationException($"资产表缺少字段：{string.Join("、", missing)}");
    }

    private static List<string> MissingAssetFields(HashSet<string> availableFieldNames) =>
        AssetRequiredFields.Where(field => !availableFieldNames.Contains(field)).ToList();

    private static List<string> MissingRecordFields(HashSet<string> availableFieldNames) =>
        RecordRequiredFields.Where(field => !availableFieldNames.Contains(field)).ToList();

    private static bool ShouldRetryAsCreate(string message)
    {
        var normalized = message.ToLowerInvariant();
        return normalized.Contains("deleted") ||
               normalized.Contains("record is not found") ||
               normalized.Contains("record not found") ||
               normalized.Contains("not found");
    }

    private static Dictionary<string, string> ParseQuery(string query)
    {
        return query.TrimStart('?')
            .Split('&', StringSplitOptions.RemoveEmptyEntries)
            .Select(part => part.Split('=', 2))
            .Where(parts => parts.Length == 2)
            .ToDictionary(parts => Uri.UnescapeDataString(parts[0]), parts => Uri.UnescapeDataString(parts[1]));
    }

    private static readonly string[] AssetRequiredFields =
    [
        "资产属性", "名称", "型号", "品牌", "外编号", "内编号",
        "保管科室", "资产专管", "保管人", "使用人",
        "一级状态", "二级状态", "一级存放地", "二级存放地", "其他附件"
    ];

    private static readonly string[] RecordRequiredFields =
    [
        "记录ID", "资产名称", "外编号", "型号", "品牌", "操作类型", "操作人", "操作时间", "备注", "预计归还"
    ];

    private static readonly FeishuFieldSpec[] AssetFieldSpecs =
    [
        new("资产属性", 1), new("名称", 1), new("外编号", 1), new("型号", 1), new("品牌", 1), new("内编号", 1),
        new("保管科室", 1), new("资产专管", 1), new("保管人", 1), new("使用人", 1), new("一级状态", 1), new("二级状态", 1),
        new("一级存放地", 1), new("二级存放地", 1), new("其他附件", 1)
    ];

    private static readonly FeishuFieldSpec[] RecordFieldSpecs =
    [
        new("记录ID", 1), new("资产名称", 1), new("外编号", 1), new("型号", 1), new("品牌", 1), new("操作类型", 1),
        new("操作人", 1), new("操作时间", 5, new Dictionary<string, object> { ["date_formatter"] = "yyyy/MM/dd HH:mm", ["auto_fill"] = false }),
        new("备注", 1), new("预计归还", 5, new Dictionary<string, object> { ["date_formatter"] = "yyyy/MM/dd HH:mm", ["auto_fill"] = false })
    ];
}

public sealed record FeishuBitableConfig(
    string AppId,
    string AppSecret,
    string AssetAppToken,
    string AssetTableId,
    string RecordAppToken,
    string RecordTableId)
{
    private const string DefaultBaseAppToken = "Zj9zbNOBcaQpw0smtZDcu7R2n4d";
    private const string DefaultAssetTableId = "tblNjryuSQbfXpXM";
    private const string DefaultRecordTableId = "tbluOIuGYvgcU9b0";

    public static FeishuBitableConfig Default { get; } = new("", "", DefaultBaseAppToken, DefaultAssetTableId, DefaultBaseAppToken, DefaultRecordTableId);

    public FeishuBitableConfig Normalized()
    {
        var assetToken = AssetAppToken.Trim();
        var recordToken = string.IsNullOrWhiteSpace(RecordAppToken) ? assetToken : RecordAppToken.Trim();
        if (string.IsNullOrWhiteSpace(assetToken) && !string.IsNullOrWhiteSpace(recordToken))
            assetToken = recordToken;

        return new FeishuBitableConfig(
            AppId.Trim(),
            AppSecret.Trim(),
            string.IsNullOrWhiteSpace(assetToken) ? DefaultBaseAppToken : assetToken,
            string.IsNullOrWhiteSpace(AssetTableId) ? DefaultAssetTableId : AssetTableId.Trim(),
            string.IsNullOrWhiteSpace(recordToken) ? DefaultBaseAppToken : recordToken,
            string.IsNullOrWhiteSpace(RecordTableId) ? DefaultRecordTableId : RecordTableId.Trim());
    }
}

public sealed record FeishuSnapshot(List<Asset> Assets, List<OperationRecord> Records, List<string> Warnings);

internal sealed record FeishuRemoteRecord(string RecordId, JsonObject Fields);

internal sealed record FeishuFieldSpec(string Name, int Type, Dictionary<string, object>? Property = null);

internal sealed record FeishuSyncResult(int AssetCount, int RecordCount, int DeletedAssetCount, int DeletedRecordCount);

internal sealed record FeishuSyncInspection(string AssetSummary, string RecordSummary);
