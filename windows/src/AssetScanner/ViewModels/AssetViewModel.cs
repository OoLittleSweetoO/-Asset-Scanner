using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using System.ComponentModel;
using System.Collections.ObjectModel;
using System.Text.Json;
using System.Windows.Input;
using System.Windows.Data;
using AssetScanner.Models;
using AssetScanner.Services;

namespace AssetScanner.ViewModels;

/// <summary>
/// 主视图模型 - 对应原 AssetViewModel.swift
/// </summary>
public partial class AssetViewModel : ObservableObject
{
    private readonly StorageService _storageService = new();
    private readonly ExcelService _excelService = new();
    private readonly BarcodeScannerService _barcodeService = new();
    private readonly SyncFileService _syncFileService = new();
    private readonly OutlookCalendarService _outlookCalendarService = new();
    private readonly FeishuBitableService _feishuBitableService = new();
    private readonly AssetManagerServerService _serverService = new();
    private readonly Dictionary<string, string> _serverAssetIdsByCode = new(StringComparer.OrdinalIgnoreCase);
    private readonly string _appConfigurationPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "AssetManager",
        "configuration.json");

    // 数据
    public ObservableCollection<Asset> Assets { get; } = new();
    public ObservableCollection<OperationRecord> OperationRecords { get; } = new();
    public ObservableCollection<AssetSource> Sources { get; } = new();
    public ICollectionView FilteredAssets { get; }
    public ICollectionView FilteredSources { get; }
    public ICollectionView FilteredRecords { get; }
    
    [ObservableProperty] private Asset? _selectedAsset;
    [ObservableProperty] private AssetSource? _selectedSource;
    [ObservableProperty] private OperationRecord? _selectedRecord;
    
    // 状态
    [ObservableProperty] private bool _isLoading;
    [ObservableProperty] private string? _errorMessage;
    [ObservableProperty] private string _searchText = string.Empty;
    [ObservableProperty] private string _sourceSearchText = string.Empty;
    [ObservableProperty] private string _recordSearchText = string.Empty;
    [ObservableProperty] private AssetStatus? _filterStatus;
    [ObservableProperty] private string? _scannedAssetId;
    [ObservableProperty] private string _syncStatus = "就绪";
    [ObservableProperty] private string _syncPath = string.Empty;
    [ObservableProperty] private string _operatorName = "当前用户";
    [ObservableProperty] private string _operationNote = string.Empty;
    [ObservableProperty] private DateTime _estimatedReturnDate = DateTime.Today.AddDays(7);
    [ObservableProperty] private string _feishuAppId = string.Empty;
    [ObservableProperty] private string _feishuAppSecret = string.Empty;
    [ObservableProperty] private string _feishuAssetTableLink = string.Empty;
    [ObservableProperty] private string _feishuRecordTableLink = string.Empty;
    [ObservableProperty] private string _feishuAssetAppToken = string.Empty;
    [ObservableProperty] private string _feishuAssetTableId = string.Empty;
    [ObservableProperty] private string _feishuRecordAppToken = string.Empty;
    [ObservableProperty] private string _feishuRecordTableId = string.Empty;
    [ObservableProperty] private string _feishuStatus = "未配置";
    
    // 状态栏辅助属性
    public string AssetCountText => $"资产: {Assets.Count} 项";
    public string RecordCountText => $"记录: {OperationRecords.Count} 条";
    public string SourceCountText => $"来源: {Sources.Count} 个";
    [ObservableProperty] private string _serverUrl = "https://10.10.10.71";
    [ObservableProperty] private string _serverEmail = string.Empty;
    [ObservableProperty] private string _serverPassword = string.Empty;
    [ObservableProperty] private string _serverToken = string.Empty;
    [ObservableProperty] private DateTime? _serverTokenExpiresAt;
    [ObservableProperty] private string _serverStatus = "Server disconnected";
    [ObservableProperty] private string _serverUserDisplay = "Local mode";
    [ObservableProperty] private bool _serverAllowInvalidCertificate;
    [ObservableProperty] private bool _isServerConnected;

    public int CheckedOutAssetCount => Assets.Count(a => a.Status == AssetStatus.CheckedOut);
    public int InStockAssetCount => Assets.Count(a => a.Status == AssetStatus.InStock);
    public int MaintenanceAssetCount => Assets.Count(a => a.Status == AssetStatus.Maintenance);
    public int ScrappedAssetCount => Assets.Count(a => a.Status == AssetStatus.Scrapped);
    public bool HasAssets => Assets.Count > 0;
    public bool HasSources => Sources.Count > 0;

    // 命令
    public ICommand ScanCommand => new RelayCommand(Scan);
    public ICommand ImportCommand => new AsyncRelayCommand(ImportAsync);
    public ICommand ExportAssetsCommand => new AsyncRelayCommand(ExportAssetsAsync);
    public ICommand ExportRecordsCommand => new AsyncRelayCommand(ExportRecordsAsync);
    public ICommand SaveConfigurationCommand => new RelayCommand(SaveConfiguration);
    public ICommand LoadConfigurationCommand => new RelayCommand(LoadConfiguration);
    public ICommand SyncOutlookCalendarCommand => new AsyncRelayCommand(SyncOutlookCalendarAsync);
    public ICommand AddAssetCommand => new RelayCommand<Asset>(asset => AddAsset(asset));
    public ICommand CheckInCommand => new RelayCommand<Asset>(a => CheckIn(a));
    public ICommand CheckOutCommand => new RelayCommand<Asset>(a => CheckOut(a));
    public ICommand RepairCommand => new RelayCommand<Asset>(a => MarkForRepair(a));
    public ICommand ScrapCommand => new RelayCommand<Asset>(a => MarkAsScrapped(a));
    public ICommand DeleteAssetCommand => new RelayCommand<Asset>(a => DeleteAsset(a));
    public ICommand DeleteRecordCommand => new RelayCommand<OperationRecord>(r => DeleteRecord(r));
    public ICommand DeleteSelectedAssetCommand => new RelayCommand(() => DeleteAsset(SelectedAsset));
    public ICommand CheckInSelectedCommand => new RelayCommand(() => CheckIn(SelectedAsset));
    public ICommand CheckOutSelectedCommand => new RelayCommand(() => CheckOut(SelectedAsset));
    public ICommand RepairSelectedCommand => new RelayCommand(() => MarkForRepair(SelectedAsset));
    public ICommand ScrapSelectedCommand => new RelayCommand(() => MarkAsScrapped(SelectedAsset));
    public ICommand CheckOutAllCommand => new RelayCommand(CheckOutAllInStockAssets);
    public ICommand ClearRecordsCommand => new RelayCommand(ClearOperationRecords);
    public ICommand DeleteSourceCommand => new RelayCommand<AssetSource>(s => DeleteSource(s));
    public ICommand SelectSyncDirectoryCommand => new RelayCommand(SelectSyncDirectory);
    public ICommand ImportFromSyncCommand => new AsyncRelayCommand(ImportFromSyncAsync);
    public ICommand ExportToSyncCommand => new AsyncRelayCommand(ExportToSyncAsync);
    public ICommand BidirectionalSyncCommand => new AsyncRelayCommand(BidirectionalSyncAsync);
    public ICommand ParseFeishuAssetLinkCommand => new RelayCommand(ParseFeishuAssetLink);
    public ICommand ParseFeishuRecordLinkCommand => new RelayCommand(ParseFeishuRecordLink);
    public ICommand SaveFeishuConfigCommand => new RelayCommand(SaveFeishuConfig);
    public ICommand TestFeishuCommand => new AsyncRelayCommand(TestFeishuAsync);
    public ICommand SyncToFeishuCommand => new AsyncRelayCommand(SyncToFeishuAsync);
    public ICommand ImportFromFeishuCommand => new AsyncRelayCommand(ImportFromFeishuAsync);
    public ICommand BidirectionalFeishuCommand => new AsyncRelayCommand(BidirectionalFeishuAsync);
    public ICommand ServerLoginCommand => new AsyncRelayCommand(ServerLoginAsync);
    public ICommand ServerLogoutCommand => new AsyncRelayCommand(ServerLogoutAsync);
    public ICommand PullServerDataCommand => new AsyncRelayCommand(PullServerDataAsync);
    public ICommand PushLocalSnapshotCommand => new AsyncRelayCommand(PushLocalSnapshotAsync);

    public AssetViewModel()
    {
        FilteredAssets = CollectionViewSource.GetDefaultView(Assets);
        FilteredAssets.Filter = FilterAsset;
        FilteredSources = CollectionViewSource.GetDefaultView(Sources);
        FilteredSources.Filter = FilterSource;
        FilteredRecords = CollectionViewSource.GetDefaultView(OperationRecords);
        FilteredRecords.Filter = FilterRecord;

        Assets.CollectionChanged += (_, _) => NotifySummaryChanged();
        OperationRecords.CollectionChanged += (_, _) => NotifySummaryChanged();
        Sources.CollectionChanged += (_, _) => NotifySummaryChanged();

        LoadFeishuConfig();
        LoadLocalConfiguration();
        ConfigureServerClient();
        _ = InitializeAsync();
    }

    partial void OnSearchTextChanged(string value) => FilteredAssets.Refresh();
    partial void OnSourceSearchTextChanged(string value) => FilteredSources.Refresh();
    partial void OnRecordSearchTextChanged(string value) => FilteredRecords.Refresh();
    partial void OnFilterStatusChanged(AssetStatus? value) => FilteredAssets.Refresh();
    partial void OnSelectedAssetChanged(Asset? value) { }

    private async Task InitializeAsync()
    {
        await LoadFromStorage();

        if (string.IsNullOrWhiteSpace(ServerToken))
            return;

        IsServerConnected = true;
        ServerStatus = "Using saved server session";
        await PullServerDataAsync();
    }

    /// <summary>
    /// 从存储加载数据
    /// </summary>
    private async Task LoadFromStorage()
    {
        await _storageService.InitializeAsync();
        var (assets, records, sources) = await _storageService.LoadAsync();
        
        Assets.Clear();
        foreach (var asset in assets) Assets.Add(asset);
        
        OperationRecords.Clear();
        foreach (var record in records) OperationRecords.Add(record);
        
        Sources.Clear();
        foreach (var source in sources) Sources.Add(source);

        FilteredAssets.Refresh();
        FilteredSources.Refresh();
        FilteredRecords.Refresh();
        NotifySummaryChanged();
    }

    /// <summary>
    /// 保存到存储
    /// </summary>
    private async Task SaveToStorage()
    {
        await _storageService.SaveAsync(
            Assets.ToList(), 
            OperationRecords.ToList(), 
            Sources.ToList());
    }

    private void ConfigureServerClient()
    {
        if (string.IsNullOrWhiteSpace(ServerUrl))
            return;

        _serverService.Configure(ServerUrl, ServerToken, ServerAllowInvalidCertificate);
    }

    private async Task ServerLoginAsync()
    {
        if (string.IsNullOrWhiteSpace(ServerUrl) ||
            string.IsNullOrWhiteSpace(ServerEmail) ||
            string.IsNullOrWhiteSpace(ServerPassword))
        {
            ServerStatus = "Server URL, email and password are required";
            ErrorMessage = ServerStatus;
            return;
        }

        IsLoading = true;
        try
        {
            ServerStatus = "Logging in...";
            var result = await _serverService.LoginAsync(ServerUrl, ServerEmail, ServerPassword, ServerAllowInvalidCertificate);
            ServerUrl = AssetManagerServerService.NormalizeServerUrl(ServerUrl);
            ServerToken = result.Token;
            ServerTokenExpiresAt = result.ExpiresAt;
            ServerPassword = string.Empty;
            IsServerConnected = true;
            ServerUserDisplay = $"{result.User.Name} ({result.User.Role})";
            ServerStatus = $"Connected: {ServerUserDisplay}";
            SaveLocalConfiguration();
            await PullServerDataAsync();
        }
        catch (Exception ex)
        {
            IsServerConnected = false;
            ServerStatus = $"Login failed: {ex.Message}";
            ErrorMessage = ServerStatus;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task ServerLogoutAsync()
    {
        IsLoading = true;
        try
        {
            await _serverService.LogoutAsync();
        }
        catch
        {
            // Local logout should still clear the cached token even if the server is unreachable.
        }
        finally
        {
            ServerToken = string.Empty;
            ServerTokenExpiresAt = null;
            IsServerConnected = false;
            ServerUserDisplay = "Local mode";
            ServerStatus = "Server logged out, local mode";
            _serverAssetIdsByCode.Clear();
            ConfigureServerClient();
            SaveLocalConfiguration();
            IsLoading = false;
        }
    }

    private async Task PullServerDataAsync()
    {
        if (string.IsNullOrWhiteSpace(ServerToken))
        {
            ServerStatus = "Please login to server first";
            ErrorMessage = ServerStatus;
            return;
        }

        IsLoading = true;
        try
        {
            ConfigureServerClient();
            ServerStatus = "Pulling server data...";
            var snapshot = await _serverService.BootstrapAsync();
            ApplyServerBootstrap(snapshot);
            await SaveToStorage();
            IsServerConnected = true;
            ServerUserDisplay = $"{snapshot.User.Name} ({snapshot.User.Role})";
            ServerStatus = $"Server data loaded: {Assets.Count} assets, {OperationRecords.Count} records";
            ErrorMessage = ServerStatus;
            SaveLocalConfiguration();
        }
        catch (Exception ex)
        {
            ServerStatus = $"Pull failed: {ex.Message}";
            ErrorMessage = ServerStatus;
            if (ex.Message.Contains("expired", StringComparison.OrdinalIgnoreCase) ||
                ex.Message.Contains("unauthorized", StringComparison.OrdinalIgnoreCase))
            {
                ServerToken = string.Empty;
                IsServerConnected = false;
                SaveLocalConfiguration();
            }
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task PushLocalSnapshotAsync()
    {
        if (string.IsNullOrWhiteSpace(ServerToken))
        {
            ServerStatus = "Please login to server first";
            ErrorMessage = ServerStatus;
            return;
        }

        IsLoading = true;
        try
        {
            ConfigureServerClient();
            ServerStatus = "Uploading local snapshot...";
            var result = await _serverService.ImportSnapshotAsync(Assets, OperationRecords, Sources);
            ServerStatus = $"Uploaded: {result.ImportedAssets} assets, {result.ImportedRecords} records";
            ErrorMessage = ServerStatus;
            await PullServerDataAsync();
        }
        catch (Exception ex)
        {
            ServerStatus = $"Upload failed: {ex.Message}";
            ErrorMessage = ServerStatus;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private void ApplyServerBootstrap(ServerBootstrap snapshot)
    {
        _serverAssetIdsByCode.Clear();
        foreach (var asset in snapshot.Assets)
        {
            if (!string.IsNullOrWhiteSpace(asset.AssetCode))
                _serverAssetIdsByCode[asset.AssetCode] = asset.Id;
        }

        ReplaceAll(
            snapshot.Assets.Select(AssetManagerServerService.ToLocalAsset),
            snapshot.Records.Select(AssetManagerServerService.ToLocalRecord),
            snapshot.Sources.Select(AssetManagerServerService.ToLocalSource).Where(source => source is not null).Select(source => source!));
    }

    private void QueueServerAssetUpsert(Asset asset)
    {
        if (!IsServerConnected || string.IsNullOrWhiteSpace(ServerToken)) return;
        var snapshot = asset.WithId(asset.Id);
        _ = SyncServerAssetAsync(snapshot);
    }

    private async Task SyncServerAssetAsync(Asset asset)
    {
        try
        {
            ConfigureServerClient();
            var serverAsset = await _serverService.UpsertAssetAsync(asset);
            _serverAssetIdsByCode[serverAsset.AssetCode] = serverAsset.Id;
            ServerStatus = $"Server synced asset: {asset.Id}";
        }
        catch (Exception ex)
        {
            ServerStatus = $"Server asset sync failed: {asset.Id} - {ex.Message}";
            ErrorMessage = ServerStatus;
        }
    }

    private void QueueServerStatusSync(Asset asset, OperationRecord record)
    {
        if (!IsServerConnected || string.IsNullOrWhiteSpace(ServerToken)) return;
        var assetSnapshot = asset.WithId(asset.Id);
        var recordSnapshot = new OperationRecord(
            id: record.Id,
            assetId: record.AssetId,
            assetName: record.AssetName,
            type: record.Type,
            @operator: record.Operator,
            timestamp: record.Timestamp,
            note: record.Note,
            estimatedReturnDate: record.EstimatedReturnDate,
            isSyncedToReminders: record.IsSyncedToReminders);

        _ = SyncServerStatusAsync(assetSnapshot, recordSnapshot);
    }

    private async Task SyncServerStatusAsync(Asset asset, OperationRecord record)
    {
        try
        {
            ConfigureServerClient();
            if (!_serverAssetIdsByCode.TryGetValue(asset.Id, out var serverAssetId))
            {
                var created = await _serverService.UpsertAssetAsync(asset);
                serverAssetId = created.Id;
                _serverAssetIdsByCode[created.AssetCode] = created.Id;
            }

            var updated = await _serverService.UpdateAssetStatusAsync(
                serverAssetId,
                asset.Status,
                string.IsNullOrWhiteSpace(record.Operator) ? OperatorName : record.Operator,
                record.Note,
                record.EstimatedReturnDate);

            _serverAssetIdsByCode[updated.AssetCode] = updated.Id;
            ServerStatus = $"Server synced status: {asset.Id}";
        }
        catch (Exception ex)
        {
            ServerStatus = $"Server status sync failed: {asset.Id} - {ex.Message}";
            ErrorMessage = ServerStatus;
        }
    }

    private void QueueServerDelete(Asset asset)
    {
        if (!IsServerConnected || string.IsNullOrWhiteSpace(ServerToken)) return;
        if (!_serverAssetIdsByCode.TryGetValue(asset.Id, out var serverAssetId)) return;

        _serverAssetIdsByCode.Remove(asset.Id);
        _ = DeleteServerAssetAsync(asset.Id, serverAssetId);
    }

    private async Task DeleteServerAssetAsync(string assetCode, string serverAssetId)
    {
        try
        {
            ConfigureServerClient();
            await _serverService.DeleteAssetAsync(serverAssetId);
            ServerStatus = $"Server deleted asset: {assetCode}";
        }
        catch (Exception ex)
        {
            ServerStatus = $"Server delete failed: {assetCode} - {ex.Message}";
            ErrorMessage = ServerStatus;
        }
    }

    /// <summary>
    /// 条码扫描
    /// </summary>
    private void Scan()
    {
        // TODO: 实现相机扫描界面
        // 这里模拟扫描结果
        ErrorMessage = "请集成 MediaCapture 实现相机扫描";
    }

    /// <summary>
    /// 处理扫描到的条码
    /// </summary>
    public void ProcessBarcode(string code)
    {
        var cleanedCode = code.Trim();
        
        // 精确匹配
        if (Assets.FirstOrDefault(a => a.Id == cleanedCode) is Asset asset)
        {
            SelectedAsset = asset;
            ScannedAssetId = asset.Id;
            return;
        }
        
        // 模糊匹配
        if (Assets.FirstOrDefault(a => a.Id.Contains(cleanedCode) || cleanedCode.Contains(a.Id)) is Asset fuzzyAsset)
        {
            SelectedAsset = fuzzyAsset;
            ScannedAssetId = fuzzyAsset.Id;
            return;
        }
        
        ErrorMessage = $"未找到条码: {cleanedCode}";
    }

    /// <summary>
    /// 导入 Excel/CSV 文件
    /// </summary>
    private async Task ImportAsync()
    {
        IsLoading = true;
        try
        {
            var dialog = new OpenFileDialog
            {
                Filter = "Excel / CSV 文件|*.xlsx;*.xls;*.csv;*.txt|Excel 文件|*.xlsx;*.xls|CSV 文件|*.csv|文本文件|*.txt|所有文件|*.*",
                Title = "导入 Excel / CSV"
            };
            
            if (dialog.ShowDialog() != true) return;
            
            var rows = await _excelService.ReadExcelAsync(dialog.FileName);
            if (rows.Count < 2)
            {
                ErrorMessage = "文件至少需要包含表头和一行数据";
                return;
            }
            
            var fileName = Path.GetFileName(dialog.FileName);
            var reservedIds = new HashSet<string>(Assets.Select(a => a.Id));
            
            // 检查是否已存在同名来源
            if (Sources.FirstOrDefault(s => s.FileName == fileName) is AssetSource existingSource)
            {
                // 删除旧数据
                var oldAssetIds = existingSource.AssetIds.ToHashSet();
                for (int i = Assets.Count - 1; i >= 0; i--)
                {
                    if (oldAssetIds.Contains(Assets[i].Id) || Assets[i].SourceId == existingSource.Id)
                        Assets.RemoveAt(i);
                }
                Sources.Remove(existingSource);
            }
            
            var sourceId = Guid.NewGuid();
            var newAssets = new List<Asset>();
            var newAssetIds = new List<string>();
            
            for (int i = 0; i < rows.Count; i++)
            {
                if (Asset.FromDict(rows[i], sourceId) is Asset asset)
                {
                    var newId = asset.MakeImportAssetId(reservedIds, i);
                    reservedIds.Add(newId);
                    newAssetIds.Add(newId);
                    var finalAsset = asset.WithId(newId);
                    newAssets.Add(finalAsset);
                    Assets.Add(finalAsset);
                }
            }
            
            Sources.Add(new AssetSource
            {
                Id = sourceId,
                FileName = fileName,
                ImportDate = DateTime.Now,
                AssetCount = newAssets.Count,
                AssetIds = newAssetIds
            });
            
            await SaveToStorage();
            ErrorMessage = newAssets.Count > 0 ? $"导入成功：{newAssets.Count} 个资产" : "未解析到任何资产数据，请检查文件格式";
        }
        catch (Exception ex)
        {
            ErrorMessage = $"导入失败: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    /// <summary>
    /// 导出资产列表
    /// </summary>
    private async Task<string?> ExportAssetsAsync()
    {
        try
        {
            var dialog = new SaveFileDialog
            {
                Filter = "Excel 工作簿|*.xlsx|CSV 文件|*.csv",
                FileName = "asset_list.xlsx",
                DefaultExt = ".xlsx",
                AddExtension = true
            };
            
            if (dialog.ShowDialog() == true)
            {
                await _excelService.ExportAssetsAsync(Assets.ToList(), dialog.FileName);
                ErrorMessage = $"已导出资产：{dialog.FileName}";
                return dialog.FileName;
            }
            
            return null;
        }
        catch (Exception ex)
        {
            ErrorMessage = $"导出失败: {ex.Message}";
            return null;
        }
    }

    /// <summary>
    /// 导出操作记录
    /// </summary>
    private async Task<string?> ExportRecordsAsync()
    {
        try
        {
            var dialog = new SaveFileDialog
            {
                Filter = "Excel 工作簿|*.xlsx|CSV 文件|*.csv",
                FileName = "operation_records.xlsx",
                DefaultExt = ".xlsx",
                AddExtension = true
            };
            
            if (dialog.ShowDialog() == true)
            {
                await _excelService.ExportRecordsAsync(OperationRecords.ToList(), dialog.FileName);
                ErrorMessage = $"已导出记录：{dialog.FileName}";
                return dialog.FileName;
            }
            
            return null;
        }
        catch (Exception ex)
        {
            ErrorMessage = $"导出失败: {ex.Message}";
            return null;
        }
    }

    private void SaveConfiguration()
    {
        try
        {
            var dialog = new SaveFileDialog
            {
                Filter = "JSON 配置文件|*.json",
                FileName = "AssetManager-配置.json",
                DefaultExt = ".json",
                AddExtension = true
            };

            if (dialog.ShowDialog() != true) return;

            var snapshot = CreateConfigurationSnapshot();

            File.WriteAllText(dialog.FileName, JsonSerializer.Serialize(snapshot, ConfigurationJsonOptions));
            SaveLocalConfiguration(snapshot);
            _feishuBitableService.SaveConfig(CurrentFeishuConfig());
            ErrorMessage = $"配置已保存：{Path.GetFileName(dialog.FileName)}";
        }
        catch (Exception ex)
        {
            ErrorMessage = $"保存配置失败: {ex.Message}";
        }
    }

    private void LoadConfiguration()
    {
        try
        {
            var dialog = new OpenFileDialog
            {
                Filter = "JSON 配置文件|*.json|所有文件|*.*",
                Title = "读取 AssetManager 配置"
            };

            if (dialog.ShowDialog() != true) return;

            var snapshot = JsonSerializer.Deserialize<AssetManagerConfigurationFile>(File.ReadAllText(dialog.FileName), ConfigurationJsonOptions);
            if (snapshot is null)
            {
                ErrorMessage = "配置文件无法读取";
                return;
            }

            ApplyConfiguration(snapshot);
            SaveLocalConfiguration(snapshot);
            SyncStatus = string.IsNullOrWhiteSpace(SyncPath) ? "已读取配置" : $"已读取同步目录：{SyncPath}";
            ErrorMessage = $"配置已读取：{Path.GetFileName(dialog.FileName)}";
        }
        catch (Exception ex)
        {
            ErrorMessage = $"读取配置失败: {ex.Message}";
        }
    }

    /// <summary>
    /// 入库
    /// </summary>
    public void AddAsset(Asset? asset)
    {
        if (asset is null) return;

        asset.Id = asset.Id.Trim();
        asset.AssetName = asset.AssetName.Trim();
        asset.ModelName = asset.ModelName.Trim();
        asset.Brand = asset.Brand.Trim();
        asset.InternalCode = asset.InternalCode.Trim();
        asset.Location = asset.Location.Trim();
        asset.Note = string.IsNullOrWhiteSpace(asset.Note) ? null : asset.Note.Trim();
        asset.LastUpdated = DateTime.Now;

        if (string.IsNullOrWhiteSpace(asset.Id))
        {
            ErrorMessage = "外编号不能为空";
            return;
        }

        if (string.IsNullOrWhiteSpace(asset.AssetName))
        {
            ErrorMessage = "名称不能为空";
            return;
        }

        if (Assets.Any(existing => string.Equals(existing.Id, asset.Id, StringComparison.OrdinalIgnoreCase)))
        {
            ErrorMessage = $"外编号已存在：{asset.Id}";
            return;
        }

        Assets.Add(asset);
        SelectedAsset = asset;
        _ = SaveToStorage();
        QueueServerAssetUpsert(asset);
        ErrorMessage = "添加成功";
        NotifySummaryChanged();
    }

    /// <summary>
    /// 入库
    /// </summary>
    public void CheckIn(Asset? asset)
    {
        if (asset is null) return;
        
        var existing = Assets.FirstOrDefault(x => x.Id == asset.Id);
        if (existing is null) return;
        
        existing.Status = AssetStatus.InStock;
        existing.LastUpdated = DateTime.Now;
        
        var record = new OperationRecord(
            assetId: existing.Id,
            assetName: existing.AssetName,
            type: OperationType.CheckIn,
            @operator: "当前用户");
        
        OperationRecords.Insert(0, record);
        _ = SaveToStorage();
        QueueFeishuStatusSync(existing, record);
        NotifySummaryChanged();
    }

    /// <summary>
    /// 出库
    /// </summary>
    public void CheckOut(Asset? asset)
    {
        if (asset is null) return;
        
        var existing = Assets.FirstOrDefault(x => x.Id == asset.Id);
        if (existing is null) return;
        
        existing.Status = AssetStatus.CheckedOut;
        existing.LastUpdated = DateTime.Now;
        
        var record = new OperationRecord(
            assetId: existing.Id,
            assetName: existing.AssetName,
            type: OperationType.CheckOut,
            @operator: "当前用户");
        
        OperationRecords.Insert(0, record);
        _ = SaveToStorage();
        QueueFeishuStatusSync(existing, record);
        NotifySummaryChanged();
    }

    public void CheckOut(Asset? asset, string operatorName, string? note, DateTime? estimatedReturnDate)
    {
        if (asset is null) return;

        var existing = Assets.FirstOrDefault(x => x.Id == asset.Id);
        if (existing is null || existing.Status != AssetStatus.InStock) return;

        existing.Status = AssetStatus.CheckedOut;
        existing.LastUpdated = DateTime.Now;

        var record = new OperationRecord(
            assetId: existing.Id,
            assetName: existing.AssetName,
            type: OperationType.CheckOut,
            @operator: string.IsNullOrWhiteSpace(operatorName) ? "当前用户" : operatorName.Trim(),
            note: string.IsNullOrWhiteSpace(note) ? null : note.Trim(),
            estimatedReturnDate: estimatedReturnDate);

        OperationRecords.Insert(0, record);
        _ = SaveToStorage();
        QueueFeishuStatusSync(existing, record);
        NotifySummaryChanged();
    }

    /// <summary>
    /// 送修
    /// </summary>
    public void MarkForRepair(Asset? asset)
    {
        if (asset is null) return;
        
        var existing = Assets.FirstOrDefault(x => x.Id == asset.Id);
        if (existing is null || existing.Status == AssetStatus.Maintenance) return;
        
        existing.Status = AssetStatus.Maintenance;
        existing.LastUpdated = DateTime.Now;
        
        var record = new OperationRecord(
            assetId: existing.Id,
            assetName: existing.AssetName,
            type: OperationType.Repair,
            @operator: "当前用户");
        
        OperationRecords.Insert(0, record);
        _ = SaveToStorage();
        QueueFeishuStatusSync(existing, record);
        NotifySummaryChanged();
    }

    public void MarkAsScrapped(Asset? asset)
    {
        if (asset is null) return;

        var existing = Assets.FirstOrDefault(x => x.Id == asset.Id);
        if (existing is null || existing.Status == AssetStatus.Scrapped) return;

        existing.Status = AssetStatus.Scrapped;
        existing.LastUpdated = DateTime.Now;

        var record = new OperationRecord(
            assetId: existing.Id,
            assetName: existing.AssetName,
            type: OperationType.Scrap,
            @operator: string.IsNullOrWhiteSpace(OperatorName) ? "当前用户" : OperatorName.Trim());

        OperationRecords.Insert(0, record);
        _ = SaveToStorage();
        QueueFeishuStatusSync(existing, record);
        NotifySummaryChanged();
    }

    public void CheckOutAllInStockAssets()
    {
        var targets = Assets.Where(a => a.Status == AssetStatus.InStock).ToList();
        if (targets.Count == 0) return;

        foreach (var asset in targets)
        {
            asset.Status = AssetStatus.CheckedOut;
            asset.LastUpdated = DateTime.Now;
            var record = new OperationRecord(
                assetId: asset.Id,
                assetName: asset.AssetName,
                type: OperationType.CheckOut,
                @operator: string.IsNullOrWhiteSpace(OperatorName) ? "当前用户" : OperatorName,
                note: string.IsNullOrWhiteSpace(OperationNote) ? null : OperationNote,
                estimatedReturnDate: EstimatedReturnDate);
            OperationRecords.Insert(0, record);
            QueueFeishuStatusSync(asset, record);
        }

        _ = SaveToStorage();
        ErrorMessage = $"已出库 {targets.Count} 个在库资产";
        NotifySummaryChanged();
    }

    public void UpdateAssets(IEnumerable<Asset> targets, AssetStatus status, string operatorName = "当前用户", string? note = null, DateTime? estimatedReturnDate = null)
    {
        var ids = targets.Select(a => a.Id).ToHashSet();
        if (ids.Count == 0) return;

        var timestamp = DateTime.Now;
        var changed = 0;

        foreach (var asset in Assets.Where(a => ids.Contains(a.Id)).ToList())
        {
            if (asset.Status == status) continue;

            asset.Status = status;
            asset.LastUpdated = timestamp;
            changed++;

            var type = status switch
            {
                AssetStatus.InStock => OperationType.CheckIn,
                AssetStatus.CheckedOut => OperationType.CheckOut,
                AssetStatus.Maintenance => OperationType.Repair,
                AssetStatus.Scrapped => OperationType.Scrap,
                _ => OperationType.CheckIn
            };

            var record = new OperationRecord(
                assetId: asset.Id,
                assetName: asset.AssetName,
                type: type,
                @operator: string.IsNullOrWhiteSpace(operatorName) ? "当前用户" : operatorName.Trim(),
                timestamp: timestamp,
                note: string.IsNullOrWhiteSpace(note) ? null : note.Trim(),
                estimatedReturnDate: status == AssetStatus.CheckedOut ? estimatedReturnDate : null);
            OperationRecords.Insert(0, record);
            QueueFeishuStatusSync(asset, record);
        }

        if (changed == 0) return;

        _ = SaveToStorage();
        ErrorMessage = $"已更新 {changed} 个资产";
        NotifySummaryChanged();
    }

    /// <summary>
    /// 删除资产
    /// </summary>
    public void DeleteAsset(Asset? asset)
    {
        if (asset is null) return;
        
        QueueServerDelete(asset);
        Assets.Remove(asset);
        var records = OperationRecords.Where(r => r.AssetId == asset.Id).ToList();
        foreach (var record in records) OperationRecords.Remove(record);
        
        _ = SaveToStorage();
        NotifySummaryChanged();
    }

    public void DeleteAssets(IEnumerable<Asset> assets)
    {
        var ids = assets.Select(a => a.Id).ToHashSet();
        if (ids.Count == 0) return;

        foreach (var asset in Assets.Where(a => ids.Contains(a.Id)).ToList())
        {
            QueueServerDelete(asset);
        }

        for (var i = Assets.Count - 1; i >= 0; i--)
        {
            if (ids.Contains(Assets[i].Id))
                Assets.RemoveAt(i);
        }

        for (var i = OperationRecords.Count - 1; i >= 0; i--)
        {
            if (ids.Contains(OperationRecords[i].AssetId))
                OperationRecords.RemoveAt(i);
        }

        var existingSources = Sources.ToList();
        Sources.Clear();
        foreach (var source in existingSources)
        {
            var remaining = source.AssetIds.Where(id => !ids.Contains(id)).ToList();
            if (remaining.Count == 0) continue;
            source.AssetIds = remaining;
            source.AssetCount = remaining.Count;
            Sources.Add(source);
        }

        _ = SaveToStorage();
        ErrorMessage = $"已删除 {ids.Count} 个资产";
        NotifySummaryChanged();
    }

    /// <summary>
    /// 删除操作记录
    /// </summary>
    public void DeleteRecord(OperationRecord? record)
    {
        if (record is null) return;
        OperationRecords.Remove(record);
        _ = SaveToStorage();
        NotifySummaryChanged();
    }

    public void DeleteRecords(IEnumerable<OperationRecord> records)
    {
        var ids = records.Select(r => r.Id).ToHashSet();
        if (ids.Count == 0) return;

        for (var i = OperationRecords.Count - 1; i >= 0; i--)
        {
            if (ids.Contains(OperationRecords[i].Id))
                OperationRecords.RemoveAt(i);
        }

        _ = SaveToStorage();
        ErrorMessage = $"已删除 {ids.Count} 条历史记录";
        NotifySummaryChanged();
    }

    private async Task SyncOutlookCalendarAsync()
    {
        await SyncOutlookCalendarAsync(OperationRecords);
    }

    public async Task SyncOutlookCalendarAsync(IEnumerable<OperationRecord> records)
    {
        IsLoading = true;
        try
        {
            var result = await _outlookCalendarService.SyncCheckOutRecordsAsync(records);
            if (result.SuccessCount > 0)
                await SaveToStorage();

            ErrorMessage = result.Message;
            NotifySummaryChanged();
        }
        catch (Exception ex)
        {
            ErrorMessage = $"同步 Outlook 日历失败: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    public void UpdateRecord(
        OperationRecord record,
        OperationType type,
        string operatorName,
        string? note,
        DateTime? estimatedReturnDate)
    {
        var existing = OperationRecords.FirstOrDefault(r => r.Id == record.Id);
        if (existing is null) return;

        existing.Type = type;
        existing.Operator = string.IsNullOrWhiteSpace(operatorName) ? "当前用户" : operatorName.Trim();
        existing.Note = string.IsNullOrWhiteSpace(note) ? null : note.Trim();
        existing.EstimatedReturnDate = estimatedReturnDate;
        existing.IsSyncedToReminders = false;

        _ = SaveToStorage();
        ErrorMessage = "历史记录已更新";
        NotifySummaryChanged();
        FilteredRecords.Refresh();
    }

    public void ClearOperationRecords()
    {
        if (OperationRecords.Count == 0) return;
        OperationRecords.Clear();
        _ = SaveToStorage();
        NotifySummaryChanged();
    }

    public void DeleteSource(AssetSource? source)
    {
        if (source is null) return;

        var sourceAssetIds = source.AssetIds.ToHashSet();
        var assetsToRemove = Assets
            .Where(a => a.SourceId == source.Id || sourceAssetIds.Contains(a.Id))
            .Select(a => a.Id)
            .ToHashSet();

        for (var i = Assets.Count - 1; i >= 0; i--)
        {
            if (assetsToRemove.Contains(Assets[i].Id))
                Assets.RemoveAt(i);
        }

        for (var i = OperationRecords.Count - 1; i >= 0; i--)
        {
            if (assetsToRemove.Contains(OperationRecords[i].AssetId))
                OperationRecords.RemoveAt(i);
        }

        Sources.Remove(source);
        _ = SaveToStorage();
        ErrorMessage = $"已删除导入源「{source.FileName}」及其 {assetsToRemove.Count} 个资产";
        NotifySummaryChanged();
    }

    public async Task<SourceUpdatePreview?> PrepareSourceUpdateAsync(AssetSource? source, string filePath)
    {
        if (source is null) return null;

        IsLoading = true;
        try
        {
            var rows = await _excelService.ReadExcelAsync(filePath);
            var sourceAssetIds = source.AssetIds.ToHashSet();
            var ownedAssets = Assets
                .Where(asset => asset.SourceId == source.Id || sourceAssetIds.Contains(asset.Id))
                .ToList();
            var ownedById = ownedAssets.ToDictionary(asset => asset.Id, asset => asset);
            var retainedIds = new HashSet<string>();
            var reservedIds = Assets
                .Where(asset => asset.SourceId != source.Id && !sourceAssetIds.Contains(asset.Id))
                .Select(asset => asset.Id)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);

            var replacementAssets = new List<Asset>();
            var addedCount = 0;
            var updatedCount = 0;

            for (var rowIndex = 0; rowIndex < rows.Count; rowIndex++)
            {
                if (Asset.FromDict(rows[rowIndex], source.Id) is not Asset importedAsset)
                    continue;

                var externalCode = importedAsset.Id.Trim();
                if (!string.IsNullOrWhiteSpace(externalCode) &&
                    ownedById.TryGetValue(externalCode, out var existingAsset) &&
                    retainedIds.Add(existingAsset.Id))
                {
                    importedAsset.Id = existingAsset.Id;
                    importedAsset.SourceId = source.Id;
                    importedAsset.Status = existingAsset.Status;
                    importedAsset.LastUpdated = existingAsset.LastUpdated;
                    replacementAssets.Add(importedAsset);
                    updatedCount++;
                    continue;
                }

                var newId = importedAsset.MakeImportAssetId(reservedIds, rowIndex);
                reservedIds.Add(newId);
                importedAsset = importedAsset.WithId(newId);
                importedAsset.SourceId = source.Id;
                replacementAssets.Add(importedAsset);
                retainedIds.Add(newId);
                addedCount++;
            }

            var removedAssets = ownedAssets
                .Where(asset => !retainedIds.Contains(asset.Id))
                .OrderBy(asset => string.IsNullOrWhiteSpace(asset.AssetName) ? asset.Id : asset.AssetName)
                .Select(asset => new SourceRemovedAssetPreview(
                    asset.Id,
                    string.IsNullOrWhiteSpace(asset.AssetName) ? asset.Id : asset.AssetName,
                    asset.Id,
                    StatusToText(asset.Status)))
                .ToList();

            return new SourceUpdatePreview(
                source,
                Path.GetFileName(filePath),
                replacementAssets,
                removedAssets.Select(asset => asset.Id).ToHashSet(),
                removedAssets,
                addedCount,
                updatedCount);
        }
        catch (Exception ex)
        {
            ErrorMessage = $"更新来源失败: {ex.Message}";
            return null;
        }
        finally
        {
            IsLoading = false;
        }
    }

    public void ApplySourceUpdate(SourceUpdatePreview preview)
    {
        var source = preview.Source;
        var sourceAssetIds = source.AssetIds.ToHashSet();
        var replacementIds = preview.ReplacementAssets.Select(asset => asset.Id).ToHashSet();

        for (var i = Assets.Count - 1; i >= 0; i--)
        {
            var asset = Assets[i];
            var belongsToSource = asset.SourceId == source.Id || sourceAssetIds.Contains(asset.Id);
            if (belongsToSource && !replacementIds.Contains(asset.Id))
                Assets.RemoveAt(i);
        }

        for (var i = OperationRecords.Count - 1; i >= 0; i--)
        {
            if (preview.RemovedAssetIds.Contains(OperationRecords[i].AssetId))
                OperationRecords.RemoveAt(i);
        }

        foreach (var replacement in preview.ReplacementAssets)
        {
            var existing = Assets.FirstOrDefault(asset => asset.Id == replacement.Id);
            if (existing is null)
            {
                Assets.Add(replacement);
                continue;
            }

            existing.AssetName = replacement.AssetName;
            existing.ModelName = replacement.ModelName;
            existing.Brand = replacement.Brand;
            existing.InternalCode = replacement.InternalCode;
            existing.Location = replacement.Location;
            existing.PurchaseDate = replacement.PurchaseDate;
            existing.Note = replacement.Note;
            existing.SourceId = source.Id;
        }

        var updatedSource = new AssetSource
        {
            Id = source.Id,
            FileName = preview.FileName,
            ImportDate = DateTime.Now,
            AssetCount = preview.ReplacementAssets.Count,
            AssetIds = preview.ReplacementAssets.Select(asset => asset.Id).ToList()
        };

        var sourceIndex = Sources.IndexOf(source);
        if (sourceIndex >= 0)
        {
            Sources[sourceIndex] = updatedSource;
            SelectedSource = updatedSource;
        }
        else
        {
            source.FileName = updatedSource.FileName;
            source.ImportDate = updatedSource.ImportDate;
            source.AssetIds = updatedSource.AssetIds;
            source.AssetCount = updatedSource.AssetCount;
        }

        _ = SaveToStorage();
        FilteredAssets.Refresh();
        FilteredSources.Refresh();
        NotifySummaryChanged();

        if (preview.RemovedAssets.Count == 0)
        {
            ErrorMessage = $"来源更新完成：新增 {preview.AddedCount} 个，保持/更新 {preview.UpdatedCount} 个，删除 0 个";
        }
        else
        {
            var previewNames = string.Join("、", preview.RemovedAssets.Take(6).Select(asset => asset.AssetName));
            var suffix = preview.RemovedAssets.Count > 6 ? $" 等 {preview.RemovedAssets.Count} 个" : "";
            ErrorMessage = $"来源更新完成：新增 {preview.AddedCount} 个，保持/更新 {preview.UpdatedCount} 个，删除 {preview.RemovedAssetIds.Count} 个（{previewNames}{suffix}）";
        }
    }

    /// <summary>
    /// 获取资产的最近出库记录
    /// </summary>
    public List<OperationRecord> GetRecentCheckOutRecords(string assetId, int limit = 5)
    {
        return OperationRecords
            .Where(r => r.AssetId == assetId && r.Type == OperationType.CheckOut)
            .Take(limit)
            .ToList();
    }

    /// <summary>
    /// 搜索资产
    /// </summary>
    public IEnumerable<Asset> SearchAssets()
    {
        var query = Assets.AsEnumerable();
        
        if (!string.IsNullOrWhiteSpace(SearchText))
        {
            var text = SearchText.ToLower();
            query = query.Where(a => 
                a.Id.ToLower().Contains(text) ||
                a.AssetName.ToLower().Contains(text) ||
                a.ModelName.ToLower().Contains(text) ||
                a.Brand.ToLower().Contains(text) ||
                a.Location.ToLower().Contains(text));
        }
        
        if (FilterStatus.HasValue)
        {
            query = query.Where(a => a.Status == FilterStatus.Value);
        }
        
        return query;
    }

    private bool FilterAsset(object item)
    {
        if (item is not Asset asset) return false;

        if (!string.IsNullOrWhiteSpace(SearchText))
        {
            var text = SearchText.Trim();
            if (!asset.Id.Contains(text, StringComparison.OrdinalIgnoreCase) &&
                !asset.AssetName.Contains(text, StringComparison.OrdinalIgnoreCase) &&
                !asset.ModelName.Contains(text, StringComparison.OrdinalIgnoreCase) &&
                !asset.Brand.Contains(text, StringComparison.OrdinalIgnoreCase) &&
                !asset.Location.Contains(text, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
        }

        return !FilterStatus.HasValue || asset.Status == FilterStatus.Value;
    }

    private bool FilterSource(object item)
    {
        if (item is not AssetSource source) return false;
        return string.IsNullOrWhiteSpace(SourceSearchText) ||
               source.FileName.Contains(SourceSearchText.Trim(), StringComparison.OrdinalIgnoreCase);
    }

    private bool FilterRecord(object item)
    {
        if (item is not OperationRecord record) return false;
        if (string.IsNullOrWhiteSpace(RecordSearchText)) return true;

        var text = RecordSearchText.Trim();
        return record.AssetId.Contains(text, StringComparison.OrdinalIgnoreCase) ||
               record.AssetName.Contains(text, StringComparison.OrdinalIgnoreCase) ||
               record.Operator.Contains(text, StringComparison.OrdinalIgnoreCase) ||
               (record.Note?.Contains(text, StringComparison.OrdinalIgnoreCase) ?? false) ||
               OperationTypeToText(record.Type).Contains(text, StringComparison.OrdinalIgnoreCase);
    }

    private static string OperationTypeToText(OperationType type) => type switch
    {
        OperationType.CheckIn => "入库",
        OperationType.CheckOut => "出库",
        OperationType.Repair => "送修",
        OperationType.Scrap => "报废",
        _ => ""
    };

    private static string StatusToText(AssetStatus status) => status switch
    {
        AssetStatus.InStock => "在库",
        AssetStatus.CheckedOut => "已出库",
        AssetStatus.Maintenance => "送修",
        AssetStatus.Scrapped => "待报废",
        _ => ""
    };

    private void SelectSyncDirectory()
    {
        var dialog = new OpenFileDialog
        {
            Title = "选择同步 JSON 文件",
            Filter = "AssetManager 同步文件|*.json|所有文件|*.*",
            CheckFileExists = false,
            CheckPathExists = true,
            ValidateNames = false,
            Multiselect = false,
            FileName = "选择此文件夹或任意同步 JSON 文件"
        };

        if (!string.IsNullOrWhiteSpace(SyncPath) && Directory.Exists(SyncPath))
            dialog.InitialDirectory = SyncPath;

        if (dialog.ShowDialog() == true)
        {
            SyncPath = Directory.Exists(dialog.FileName)
                ? dialog.FileName
                : Path.GetDirectoryName(dialog.FileName) ?? string.Empty;
            SaveLocalConfiguration();
            SyncStatus = $"已选择同步目录：{SyncPath}";
        }
    }

    private async Task ImportFromSyncAsync()
    {
        IsLoading = true;
        try
        {
            var snapshot = await _syncFileService.ImportAsync(
                SyncPath,
                Assets.ToList(),
                OperationRecords.ToList(),
                Sources.ToList());

            ReplaceAll(snapshot.Assets, snapshot.Records, snapshot.Sources);
            await SaveToStorage();
            SyncStatus = $"已导入同步文件：{Assets.Count} 个资产，{OperationRecords.Count} 条记录";
            ErrorMessage = SyncStatus;
        }
        catch (Exception ex)
        {
            SyncStatus = $"导入同步文件失败：{ex.Message}";
            ErrorMessage = SyncStatus;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task ExportToSyncAsync()
    {
        IsLoading = true;
        try
        {
            await _syncFileService.ExportAsync(
                SyncPath,
                Assets.ToList(),
                OperationRecords.ToList(),
                Sources.ToList());

            SyncStatus = $"已导出同步文件：{Assets.Count} 个资产，{OperationRecords.Count} 条记录";
            ErrorMessage = SyncStatus;
        }
        catch (Exception ex)
        {
            SyncStatus = $"导出同步文件失败：{ex.Message}";
            ErrorMessage = SyncStatus;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task BidirectionalSyncAsync()
    {
        IsLoading = true;
        try
        {
            var localAssets = Assets.ToList();
            var localRecords = OperationRecords.ToList();
            var localSources = Sources.ToList();

            var snapshot = await _syncFileService.ImportAsync(SyncPath, localAssets, localRecords, localSources);
            var mergedAssets = snapshot.Assets.Count >= localAssets.Count ? snapshot.Assets : localAssets;
            var mergedRecords = snapshot.Records.Count >= localRecords.Count ? snapshot.Records : localRecords;
            var mergedSources = snapshot.Sources.Count >= localSources.Count ? snapshot.Sources : localSources;

            ReplaceAll(mergedAssets, mergedRecords, mergedSources);
            await SaveToStorage();
            await _syncFileService.ExportAsync(SyncPath, mergedAssets, mergedRecords, mergedSources);

            SyncStatus = $"双向同步完成：{Assets.Count} 个资产，{OperationRecords.Count} 条记录";
            ErrorMessage = SyncStatus;
        }
        catch (Exception ex)
        {
            SyncStatus = $"双向同步失败：{ex.Message}";
            ErrorMessage = SyncStatus;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private AssetManagerConfigurationFile CreateConfigurationSnapshot() => new(
        Version: 2,
        SavedAt: DateTime.Now,
        SyncPath: SyncPath,
        Feishu: new AssetManagerFeishuConfiguration(
            FeishuAppId,
            FeishuAppSecret,
            FeishuAssetAppToken,
            FeishuAssetTableId,
            FeishuRecordAppToken,
            FeishuRecordTableId,
            FeishuAssetTableLink,
            FeishuRecordTableLink),
        Server: new AssetManagerServerConfiguration(
            ServerUrl,
            ServerEmail,
            ServerToken,
            ServerTokenExpiresAt,
            ServerAllowInvalidCertificate));

    private void ApplyConfiguration(AssetManagerConfigurationFile snapshot)
    {
        SyncPath = snapshot.SyncPath ?? "";
        FeishuAppId = snapshot.Feishu.AppId ?? "";
        FeishuAppSecret = snapshot.Feishu.AppSecret ?? "";
        FeishuAssetAppToken = snapshot.Feishu.AssetAppToken ?? "";
        FeishuAssetTableId = snapshot.Feishu.AssetTableId ?? "";
        FeishuRecordAppToken = snapshot.Feishu.RecordAppToken ?? "";
        FeishuRecordTableId = snapshot.Feishu.RecordTableId ?? "";
        FeishuAssetTableLink = string.IsNullOrWhiteSpace(snapshot.Feishu.AssetTableLink)
            ? BuildFeishuTableLink(FeishuAssetAppToken, FeishuAssetTableId)
            : snapshot.Feishu.AssetTableLink;
        FeishuRecordTableLink = string.IsNullOrWhiteSpace(snapshot.Feishu.RecordTableLink)
            ? BuildFeishuTableLink(FeishuRecordAppToken, FeishuRecordTableId)
            : snapshot.Feishu.RecordTableLink;
        _feishuBitableService.SaveConfig(CurrentFeishuConfig());
        if (snapshot.Server is not null)
        {
            ServerUrl = snapshot.Server.Url ?? ServerUrl;
            ServerEmail = snapshot.Server.Email ?? "";
            ServerToken = snapshot.Server.Token ?? "";
            ServerTokenExpiresAt = snapshot.Server.TokenExpiresAt;
            ServerAllowInvalidCertificate = snapshot.Server.AllowInvalidCertificate;
            IsServerConnected = !string.IsNullOrWhiteSpace(ServerToken);
            ServerUserDisplay = IsServerConnected ? ServerEmail : "Local mode";
            ServerStatus = IsServerConnected ? "Saved server session loaded" : "Local mode";
        }

        ConfigureServerClient();
        FeishuStatus = _feishuBitableService.IsConfigured ? "已配置" : "未配置";
    }

    private void LoadLocalConfiguration()
    {
        try
        {
            if (!File.Exists(_appConfigurationPath))
                return;

            var snapshot = JsonSerializer.Deserialize<AssetManagerConfigurationFile>(
                File.ReadAllText(_appConfigurationPath),
                ConfigurationJsonOptions);
            if (snapshot is null)
                return;

            ApplyConfiguration(snapshot);
            SyncStatus = string.IsNullOrWhiteSpace(SyncPath) ? "已加载本地配置" : $"已加载同步目录：{SyncPath}";
        }
        catch
        {
            SyncStatus = "本地配置读取失败";
        }
    }

    private void SaveLocalConfiguration(AssetManagerConfigurationFile? snapshot = null)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_appConfigurationPath)!);
        File.WriteAllText(
            _appConfigurationPath,
            JsonSerializer.Serialize(snapshot ?? CreateConfigurationSnapshot(), ConfigurationJsonOptions));
    }

    private static string BuildFeishuTableLink(string appToken, string tableId)
    {
        if (string.IsNullOrWhiteSpace(appToken) || string.IsNullOrWhiteSpace(tableId))
            return string.Empty;

        return $"https://feishu.cn/base/{appToken}?table={tableId}";
    }

    private void LoadFeishuConfig()
    {
        var config = _feishuBitableService.Config;
        FeishuAppId = config.AppId;
        FeishuAppSecret = config.AppSecret;
        FeishuAssetAppToken = config.AssetAppToken;
        FeishuAssetTableId = config.AssetTableId;
        FeishuRecordAppToken = config.RecordAppToken;
        FeishuRecordTableId = config.RecordTableId;
        FeishuAssetTableLink = BuildFeishuTableLink(FeishuAssetAppToken, FeishuAssetTableId);
        FeishuRecordTableLink = BuildFeishuTableLink(FeishuRecordAppToken, FeishuRecordTableId);
        FeishuStatus = _feishuBitableService.IsConfigured ? "已配置" : "未配置";
    }

    private void ParseFeishuAssetLink()
    {
        var parsed = FeishuBitableService.ExtractTableConfig(FeishuAssetTableLink);
        if (parsed is null)
        {
            FeishuStatus = "资产表链接无法解析";
            return;
        }

        FeishuAssetAppToken = parsed.Value.AppToken;
        FeishuAssetTableId = parsed.Value.TableId;
        SaveLocalConfiguration();
        FeishuStatus = "已解析资产表链接";
    }

    private void ParseFeishuRecordLink()
    {
        var parsed = FeishuBitableService.ExtractTableConfig(FeishuRecordTableLink);
        if (parsed is null)
        {
            FeishuStatus = "记录表链接无法解析";
            return;
        }

        FeishuRecordAppToken = parsed.Value.AppToken;
        FeishuRecordTableId = parsed.Value.TableId;
        SaveLocalConfiguration();
        FeishuStatus = "已解析记录表链接";
    }

    private void SaveFeishuConfig()
    {
        _feishuBitableService.SaveConfig(CurrentFeishuConfig());
        SaveLocalConfiguration();
        FeishuStatus = _feishuBitableService.IsConfigured ? "已保存飞书配置" : "飞书配置不完整";
        ErrorMessage = FeishuStatus;
    }

    private async Task TestFeishuAsync()
    {
        IsLoading = true;
        try
        {
            SaveFeishuConfig();
            FeishuStatus = await _feishuBitableService.TestConnectionAsync();
            ErrorMessage = FeishuStatus;
        }
        catch (Exception ex)
        {
            FeishuStatus = $"飞书连接失败: {ex.Message}";
            ErrorMessage = FeishuStatus;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task SyncToFeishuAsync()
    {
        IsLoading = true;
        try
        {
            SaveFeishuConfig();
            FeishuStatus = await _feishuBitableService.SyncAllAsync(Assets.ToList(), OperationRecords.ToList());
            ErrorMessage = FeishuStatus;
        }
        catch (Exception ex)
        {
            FeishuStatus = $"同步到飞书失败: {ex.Message}";
            ErrorMessage = FeishuStatus;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task ImportFromFeishuAsync()
    {
        IsLoading = true;
        try
        {
            SaveFeishuConfig();
            var snapshot = await _feishuBitableService.ImportRemoteAsync();
            ReplaceAll(MergeAssets(Assets, snapshot.Assets), MergeRecords(OperationRecords, snapshot.Records), Sources);
            await SaveToStorage();
            FeishuStatus = $"已从飞书导入：资产 {snapshot.Assets.Count} 个，记录 {snapshot.Records.Count} 条";
            ErrorMessage = FeishuStatus;
        }
        catch (Exception ex)
        {
            FeishuStatus = $"从飞书导入失败: {ex.Message}";
            ErrorMessage = FeishuStatus;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task BidirectionalFeishuAsync()
    {
        IsLoading = true;
        try
        {
            SaveFeishuConfig();
            var (snapshot, message) = await _feishuBitableService.SyncBidirectionallyAsync(Assets.ToList(), OperationRecords.ToList());
            ReplaceAll(MergeAssets(Assets, snapshot.Assets), MergeRecords(OperationRecords, snapshot.Records), Sources);
            await SaveToStorage();
            FeishuStatus = message;
            ErrorMessage = FeishuStatus;
        }
        catch (Exception ex)
        {
            FeishuStatus = $"飞书双向同步失败: {ex.Message}";
            ErrorMessage = FeishuStatus;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private void QueueFeishuStatusSync(Asset asset, OperationRecord record)
    {
        if (IsServerConnected)
        {
            QueueServerStatusSync(asset, record);
            return;
        }

        if (!_feishuBitableService.HasBaseConfig || !_feishuBitableService.CanSyncAssets)
            return;

        var assetSnapshot = asset.WithId(asset.Id);
        var recordSnapshot = new OperationRecord(
            id: record.Id,
            assetId: record.AssetId,
            assetName: record.AssetName,
            type: record.Type,
            @operator: record.Operator,
            timestamp: record.Timestamp,
            note: record.Note,
            estimatedReturnDate: record.EstimatedReturnDate,
            isSyncedToReminders: record.IsSyncedToReminders);

        _ = SyncFeishuStatusAsync(assetSnapshot, recordSnapshot);
    }

    private async Task SyncFeishuStatusAsync(Asset asset, OperationRecord record)
    {
        try
        {
            FeishuStatus = $"正在回写飞书：{asset.Id}";
            FeishuStatus = await _feishuBitableService.SyncAssetStatusAsync(asset, record);
            ErrorMessage = FeishuStatus;
        }
        catch (Exception ex)
        {
            FeishuStatus = $"飞书单条状态同步失败: {ex.Message}";
            ErrorMessage = FeishuStatus;
        }
    }

    private FeishuBitableConfig CurrentFeishuConfig() => new(
        FeishuAppId,
        FeishuAppSecret,
        FeishuAssetAppToken,
        FeishuAssetTableId,
        FeishuRecordAppToken,
        FeishuRecordTableId);

    private static List<Asset> MergeAssets(IEnumerable<Asset> local, IEnumerable<Asset> remote)
    {
        var merged = local.ToDictionary(asset => asset.Id, asset => asset);
        foreach (var remoteAsset in remote)
        {
            if (!merged.TryGetValue(remoteAsset.Id, out var existing) || remoteAsset.LastUpdated > existing.LastUpdated)
                merged[remoteAsset.Id] = remoteAsset;
        }
        return merged.Values.OrderByDescending(asset => asset.LastUpdated).ToList();
    }

    private static List<OperationRecord> MergeRecords(IEnumerable<OperationRecord> local, IEnumerable<OperationRecord> remote)
    {
        var merged = local.ToDictionary(record => record.Id, record => record);
        foreach (var remoteRecord in remote)
        {
            if (!merged.TryGetValue(remoteRecord.Id, out var existing) || remoteRecord.Timestamp > existing.Timestamp)
                merged[remoteRecord.Id] = remoteRecord;
        }
        return merged.Values.OrderByDescending(record => record.Timestamp).ToList();
    }

    private void ReplaceAll(
        IEnumerable<Asset> assets,
        IEnumerable<OperationRecord> records,
        IEnumerable<AssetSource> sources)
    {
        var nextAssets = assets.ToList();
        var nextRecords = records.ToList();
        var nextSources = sources.ToList();

        Assets.Clear();
        foreach (var asset in nextAssets) Assets.Add(asset);

        OperationRecords.Clear();
        foreach (var record in nextRecords) OperationRecords.Add(record);

        Sources.Clear();
        foreach (var source in nextSources) Sources.Add(source);

        FilteredAssets.Refresh();
        FilteredSources.Refresh();
        NotifySummaryChanged();
    }

    private void NotifySummaryChanged()
    {
        OnPropertyChanged(nameof(AssetCountText));
        OnPropertyChanged(nameof(RecordCountText));
        OnPropertyChanged(nameof(SourceCountText));
        OnPropertyChanged(nameof(CheckedOutAssetCount));
        OnPropertyChanged(nameof(InStockAssetCount));
        OnPropertyChanged(nameof(MaintenanceAssetCount));
        OnPropertyChanged(nameof(ScrappedAssetCount));
        OnPropertyChanged(nameof(HasAssets));
        OnPropertyChanged(nameof(HasSources));
    }

    private sealed record AssetManagerConfigurationFile(
        int Version,
        DateTime SavedAt,
        string? SyncPath,
        AssetManagerFeishuConfiguration Feishu,
        AssetManagerServerConfiguration? Server = null);

    private sealed record AssetManagerFeishuConfiguration(
        string? AppId,
        string? AppSecret,
        string? AssetAppToken,
        string? AssetTableId,
        string? RecordAppToken,
        string? RecordTableId,
        string? AssetTableLink = null,
        string? RecordTableLink = null);

    private sealed record AssetManagerServerConfiguration(
        string? Url,
        string? Email,
        string? Token,
        DateTime? TokenExpiresAt,
        bool AllowInvalidCertificate);

    private static readonly JsonSerializerOptions ConfigurationJsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };
}

public sealed record SourceRemovedAssetPreview(
    string Id,
    string AssetName,
    string ExternalCode,
    string StatusDisplayName);

public sealed record SourceUpdatePreview(
    AssetSource Source,
    string FileName,
    List<Asset> ReplacementAssets,
    HashSet<string> RemovedAssetIds,
    List<SourceRemovedAssetPreview> RemovedAssets,
    int AddedCount,
    int UpdatedCount);
