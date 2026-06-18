using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using Microsoft.Win32;
using System.Runtime.InteropServices;
using System.Diagnostics;
using System.IO;
using AssetScanner.Models;
using AssetScanner.ViewModels;

namespace AssetScanner.Views;

/// <summary>
/// MainWindow 交互逻辑
/// </summary>
public partial class MainWindow : Window
{
    public AssetViewModel ViewModel { get; }

    public MainWindow()
    {
        InitializeComponent();
        SourceInitialized += (_, _) => ApplyWindowsTheme();
        ApplyWindowsTheme();
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
        
        // 从 App.Resources 获取 ViewModel 实例
        var app = Application.Current as App;
        ViewModel = app?.Resources["AssetViewModel"] as AssetViewModel 
                    ?? new AssetViewModel();
        
        DataContext = ViewModel;
        Closed += (_, _) => SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
    }

    private List<Asset> SelectedAssets => AssetGrid.SelectedItems.OfType<Asset>().ToList();
    private List<OperationRecord> SelectedRecords => RecordGrid.SelectedItems.OfType<OperationRecord>().ToList();

    private void AssetGrid_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (SelectedAssetsCountText is not null)
            SelectedAssetsCountText.Text = $"已选 {AssetGrid.SelectedItems.Count}";
    }

    private void ServerPasswordBox_PasswordChanged(object sender, RoutedEventArgs e)
    {
        if (sender is PasswordBox passwordBox)
            ViewModel.ServerPassword = passwordBox.Password;
    }

    private void OpenHelp_Click(object sender, RoutedEventArgs e)
    {
        var helpPath = FindHelpPagePath();

        if (!File.Exists(helpPath))
        {
            MessageBox.Show(this, "未找到帮助页文件。", "帮助", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        Process.Start(new ProcessStartInfo(helpPath) { UseShellExecute = true });
    }

    private static string FindHelpPagePath()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current is not null)
        {
            var candidate = Path.Combine(current.FullName, "AssetManager", "AssetManagerHelp.html");
            if (File.Exists(candidate))
                return candidate;
            current = current.Parent;
        }

        return Path.Combine(Environment.CurrentDirectory, "AssetManager", "AssetManagerHelp.html");
    }

    private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        Dispatcher.BeginInvoke(ApplyWindowsTheme);
    }

    private void ApplyWindowsTheme()
    {
        var accent = ReadWindowsAccentColor();
        var isLight = IsWindowsLightTheme();

        var page = isLight ? ColorFromHex("#F6F8FC") : ColorFromHex("#0F172A");
        var surface = isLight ? Colors.White : ColorFromHex("#111827");
        var text = isLight ? ColorFromHex("#172033") : ColorFromHex("#E5E7EB");
        var muted = isLight ? ColorFromHex("#667085") : ColorFromHex("#9CA3AF");
        var border = isLight ? ColorFromHex("#E5EAF3") : ColorFromHex("#263244");
        var gridLine = isLight ? ColorFromHex("#EEF2F7") : ColorFromHex("#283449");

        SetBrush("PageBrush", page);
        SetBrush("SurfaceBrush", surface);
        SetBrush("TextBrush", text);
        SetBrush("MutedTextBrush", muted);
        SetBrush("GridForegroundBrush", text);
        SetBrush("BorderBrushSoft", border);
        SetBrush("PrimaryBrush", accent);
        SetBrush("PrimaryHoverBrush", isLight ? Mix(accent, Colors.Black, 0.12) : Mix(accent, Colors.White, 0.18));
        SetBrush("PrimarySoftBrush", Mix(surface, accent, isLight ? 0.10 : 0.22));
        SetBrush("ButtonHoverBrush", Mix(surface, accent, isLight ? 0.05 : 0.12));
        SetBrush("ButtonPressedBrush", Mix(surface, accent, isLight ? 0.09 : 0.18));
        SetBrush("InputDisabledBrush", isLight ? ColorFromHex("#F3F5F8") : ColorFromHex("#1F2937"));
        SetBrush("GridHeaderBrush", isLight ? ColorFromHex("#F8FAFC") : ColorFromHex("#182033"));
        SetBrush("GridLineBrush", gridLine);
        SetBrush("GridAlternateBrush", isLight ? ColorFromHex("#FAFBFE") : ColorFromHex("#121B2A"));
        SetBrush("GridHoverBrush", Mix(surface, accent, isLight ? 0.06 : 0.14));
        SetBrush("GridSelectedBrush", Mix(surface, accent, isLight ? 0.13 : 0.26));
        SetBrush("StatusPillBrush", isLight ? ColorFromHex("#F1F5F9") : ColorFromHex("#1F2937"));
        ApplyNativeTitleBar(isLight, surface, text, accent);
    }

    private void SetBrush(string key, Color color)
    {
        if (Resources[key] is SolidColorBrush brush && !brush.IsFrozen)
        {
            brush.Color = color;
            return;
        }

        Resources[key] = new SolidColorBrush(color);
    }

    private static bool IsWindowsLightTheme()
    {
        const string key = @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
        return Registry.GetValue(key, "AppsUseLightTheme", 1) is not int value || value != 0;
    }

    private static Color ReadWindowsAccentColor()
    {
        const string key = @"HKEY_CURRENT_USER\Software\Microsoft\Windows\DWM";
        if (Registry.GetValue(key, "AccentColor", null) is int accent)
        {
            return Color.FromRgb(
                (byte)(accent & 0xFF),
                (byte)((accent >> 8) & 0xFF),
                (byte)((accent >> 16) & 0xFF));
        }

        return SystemParameters.WindowGlassColor;
    }

    private void ApplyNativeTitleBar(bool isLight, Color captionColor, Color textColor, Color borderColor)
    {
        var handle = new WindowInteropHelper(this).Handle;
        if (handle == IntPtr.Zero)
            return;

        var useDarkMode = isLight ? 0 : 1;
        _ = DwmSetWindowAttribute(handle, 20, ref useDarkMode, sizeof(int));

        var caption = ToColorRef(captionColor);
        var captionText = ToColorRef(textColor);
        var border = ToColorRef(borderColor);
        _ = DwmSetWindowAttribute(handle, 35, ref caption, sizeof(int));
        _ = DwmSetWindowAttribute(handle, 36, ref captionText, sizeof(int));
        _ = DwmSetWindowAttribute(handle, 34, ref border, sizeof(int));
    }

    private static Color Mix(Color baseColor, Color overlayColor, double overlayWeight)
    {
        overlayWeight = Math.Clamp(overlayWeight, 0, 1);
        var baseWeight = 1 - overlayWeight;
        return Color.FromRgb(
            (byte)Math.Round(baseColor.R * baseWeight + overlayColor.R * overlayWeight),
            (byte)Math.Round(baseColor.G * baseWeight + overlayColor.G * overlayWeight),
            (byte)Math.Round(baseColor.B * baseWeight + overlayColor.B * overlayWeight));
    }

    private static Color ColorFromHex(string hex) =>
        (Color)ColorConverter.ConvertFromString(hex)!;

    private static int ToColorRef(Color color) =>
        color.R | (color.G << 8) | (color.B << 16);

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int attributeValue, int attributeSize);

    private void StatusFilterCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ViewModel is null) return;
        ViewModel.FilterStatus = StatusFilterCombo.SelectedIndex switch
        {
            1 => AssetStatus.InStock,
            2 => AssetStatus.CheckedOut,
            3 => AssetStatus.Maintenance,
            4 => AssetStatus.Scrapped,
            _ => null
        };
    }

    private void AssetGrid_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (AssetGrid.SelectedItem is not Asset)
            return;

        if (AssetGrid.ContextMenu is { } menu)
        {
            menu.PlacementTarget = AssetGrid;
            menu.IsOpen = true;
        }
    }

    private void AssetDetails_Click(object sender, RoutedEventArgs e)
    {
        var asset = SelectedAssets.FirstOrDefault();
        if (asset is null) return;

        var recentRecords = ViewModel.GetRecentCheckOutRecords(asset.Id, 5);
        var recentText = recentRecords.Count == 0
            ? "暂无最近出库记录"
            : string.Join(Environment.NewLine, recentRecords.Select(r => $"{r.Timestamp:yyyy-MM-dd HH:mm}  {r.Operator}  {r.Note ?? ""}"));

        MessageBox.Show(
            this,
            $"名称：{asset.AssetName}{Environment.NewLine}" +
            $"外编号：{asset.Id}{Environment.NewLine}" +
            $"品牌 / 型号：{asset.Brand} / {asset.ModelName}{Environment.NewLine}" +
            $"内编号：{asset.InternalCode}{Environment.NewLine}" +
            $"状态：{StatusText(asset.Status)}{Environment.NewLine}" +
            $"位置：{asset.Location}{Environment.NewLine}" +
            $"采购日期：{asset.PurchaseDate:yyyy-MM-dd}{Environment.NewLine}" +
            $"备注：{asset.Note ?? "-"}{Environment.NewLine}{Environment.NewLine}" +
            $"最近出库记录：{Environment.NewLine}{recentText}",
            asset.AssetName,
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void AddAsset_Click(object sender, RoutedEventArgs e)
    {
        if (!TryCollectAssetInfo(out var asset))
            return;

        ViewModel.AddAsset(asset);
    }

    private void CheckInSelected_Click(object sender, RoutedEventArgs e)
    {
        var targets = SelectedAssets;
        if (targets.Count == 0) return;
        ViewModel.UpdateAssets(targets, AssetStatus.InStock);
    }

    private void CheckOutSelected_Click(object sender, RoutedEventArgs e)
    {
        var targets = SelectedAssets.Where(a => a.Status == AssetStatus.InStock).ToList();
        if (targets.Count == 0) return;

        if (!TryCollectCheckOutInfo(targets.Count, out var operatorName, out var note, out var estimatedReturnDate))
            return;

        ViewModel.UpdateAssets(targets, AssetStatus.CheckedOut, operatorName, note, estimatedReturnDate);
    }

    private void RepairSelected_Click(object sender, RoutedEventArgs e)
    {
        var targets = SelectedAssets;
        if (targets.Count == 0) return;
        ViewModel.UpdateAssets(targets, AssetStatus.Maintenance);
    }

    private void ScrapSelected_Click(object sender, RoutedEventArgs e)
    {
        var targets = SelectedAssets;
        if (targets.Count == 0) return;
        ViewModel.UpdateAssets(targets, AssetStatus.Scrapped);
    }

    private void CheckOutAll_Click(object sender, RoutedEventArgs e)
    {
        var targets = ViewModel.Assets.Where(a => a.Status == AssetStatus.InStock).ToList();
        if (targets.Count == 0) return;

        if (!TryCollectCheckOutInfo(targets.Count, out var operatorName, out var note, out var estimatedReturnDate))
            return;

        ViewModel.UpdateAssets(targets, AssetStatus.CheckedOut, operatorName, note, estimatedReturnDate);
    }

    private void DeleteSelected_Click(object sender, RoutedEventArgs e)
    {
        var targets = SelectedAssets;
        if (targets.Count == 0) return;

        var result = MessageBox.Show(
            this,
            $"删除选中的 {targets.Count} 个设备条目？删除后会同时清理对应历史记录，无法撤销。",
            "删除设备",
            MessageBoxButton.OKCancel,
            MessageBoxImage.Warning);

        if (result == MessageBoxResult.OK)
            ViewModel.DeleteAssets(targets);
    }

    private void RecordGrid_PreviewMouseRightButtonDown(object sender, MouseButtonEventArgs e)
    {
        var row = FindVisualParent<DataGridRow>((DependencyObject)e.OriginalSource);
        if (row?.Item is not OperationRecord record)
            return;

        if (!row.IsSelected)
        {
            RecordGrid.SelectedItems.Clear();
            row.IsSelected = true;
            ViewModel.SelectedRecord = record;
        }
    }

    private void DeleteSelectedRecords_Click(object sender, RoutedEventArgs e)
    {
        var targets = SelectedRecords;
        if (targets.Count == 0) return;

        var result = MessageBox.Show(
            this,
            $"删除选中的 {targets.Count} 条历史记录？此操作无法撤销。",
            "删除历史记录",
            MessageBoxButton.OKCancel,
            MessageBoxImage.Warning);

        if (result == MessageBoxResult.OK)
            ViewModel.DeleteRecords(targets);
    }

    private void SelectAllRecords_Click(object sender, RoutedEventArgs e)
    {
        RecordGrid.SelectAll();
    }

    private async void SyncSelectedRecords_Click(object sender, RoutedEventArgs e)
    {
        var targets = SelectedRecords;
        if (targets.Count == 0) return;
        await ViewModel.SyncOutlookCalendarAsync(targets);
    }

    private void ClearRecords_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel.OperationRecords.Count == 0) return;

        var result = MessageBox.Show(
            this,
            $"清空全部 {ViewModel.OperationRecords.Count} 条历史记录？此操作无法撤销。",
            "清空历史",
            MessageBoxButton.OKCancel,
            MessageBoxImage.Warning);

        if (result == MessageBoxResult.OK)
            ViewModel.ClearOperationRecords();
    }

    private async void UpdateSource_Click(object sender, RoutedEventArgs e)
    {
        var source = ViewModel.SelectedSource;
        if (source is null)
        {
            MessageBox.Show(this, "请先选择一个导入来源。", "更新来源", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var dialog = new OpenFileDialog
        {
            Filter = "Excel / CSV 文件|*.xlsx;*.xls;*.csv;*.txt|Excel 文件|*.xlsx;*.xls|CSV 文件|*.csv|文本文件|*.txt|所有文件|*.*",
            Title = "选择用于更新的资产文件"
        };

        if (dialog.ShowDialog(this) != true)
            return;

        var preview = await ViewModel.PrepareSourceUpdateAsync(source, dialog.FileName);
        if (preview is null)
            return;

        if (preview.RemovedAssetIds.Count == 0)
        {
            ViewModel.ApplySourceUpdate(preview);
            return;
        }

        if (ShowSourceUpdateConfirmation(preview))
            ViewModel.ApplySourceUpdate(preview);
    }

    private void EditSelectedRecord_Click(object sender, RoutedEventArgs e)
    {
        var record = SelectedRecords.FirstOrDefault();
        if (record is null) return;
        EditRecord(record);
    }

    private bool ShowSourceUpdateConfirmation(SourceUpdatePreview preview)
    {
        var dialog = new Window
        {
            Owner = this,
            Title = "确认更新来源",
            Width = 560,
            Height = 520,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize
        };

        var removedList = new ListBox
        {
            MinHeight = 220,
            MaxHeight = 260,
            ItemsSource = preview.RemovedAssets.Select(asset =>
                $"{asset.AssetName}    {asset.ExternalCode}    {asset.StatusDisplayName}").ToList()
        };

        var okButton = new Button
        {
            Content = "确认批量删除并更新",
            MinWidth = 150,
            Padding = new Thickness(12, 6, 12, 6),
            IsDefault = true
        };
        var cancelButton = new Button
        {
            Content = "取消",
            MinWidth = 76,
            Padding = new Thickness(12, 6, 12, 6),
            IsCancel = true,
            Margin = new Thickness(8, 0, 0, 0)
        };

        okButton.Click += (_, _) => dialog.DialogResult = true;

        dialog.Content = new StackPanel
        {
            Margin = new Thickness(22),
            Children =
            {
                new TextBlock { Text = "确认更新来源", FontSize = 20, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 10) },
                new TextBlock
                {
                    Text = "将按资产编号优先比对，并保留已命中条目的当前出入库状态。以下条目在新文件中已消失，确认后会批量删除：",
                    TextWrapping = TextWrapping.Wrap,
                    Foreground = Brushes.DimGray,
                    Margin = new Thickness(0, 0, 0, 14)
                },
                new UniformGrid
                {
                    Columns = 3,
                    Margin = new Thickness(0, 0, 0, 14),
                    Children =
                    {
                        PreviewStat("新增", preview.AddedCount.ToString()),
                        PreviewStat("保持/更新", preview.UpdatedCount.ToString()),
                        PreviewStat("待删除", preview.RemovedAssetIds.Count.ToString())
                    }
                },
                removedList,
                new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    HorizontalAlignment = HorizontalAlignment.Right,
                    Margin = new Thickness(0, 18, 0, 0),
                    Children = { okButton, cancelButton }
                }
            }
        };

        return dialog.ShowDialog() == true;
    }

    private static Border PreviewStat(string title, string value)
    {
        return new Border
        {
            Background = new SolidColorBrush(Color.FromRgb(248, 250, 252)),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(12, 10, 12, 10),
            Margin = new Thickness(0, 0, 8, 0),
            Child = new StackPanel
            {
                Children =
                {
                    new TextBlock { Text = value, FontSize = 18, FontWeight = FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center },
                    new TextBlock { Text = title, FontSize = 12, Foreground = Brushes.DimGray, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 4, 0, 0) }
                }
            }
        };
    }

    private static T? FindVisualParent<T>(DependencyObject? child) where T : DependencyObject
    {
        while (child is not null)
        {
            if (child is T match)
                return match;

            child = VisualTreeHelper.GetParent(child);
        }

        return null;
    }

    private bool TryCollectCheckOutInfo(int count, out string operatorName, out string? note, out DateTime? estimatedReturnDate)
    {
        var dialog = new Window
        {
            Owner = this,
            Title = count == 1 ? "办理出库" : "批量办理出库",
            Width = 440,
            Height = 300,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize
        };

        var operatorBox = new TextBox { Text = ViewModel.OperatorName, Margin = new Thickness(0, 4, 0, 12) };
        var noteBox = new TextBox { Text = ViewModel.OperationNote, Margin = new Thickness(0, 4, 0, 12) };
        var datePicker = new DatePicker { SelectedDate = ViewModel.EstimatedReturnDate, Margin = new Thickness(0, 4, 0, 18) };

        var okButton = new Button { Content = "确认出库", MinWidth = 90, Padding = new Thickness(12, 6, 12, 6), IsDefault = true };
        var cancelButton = new Button { Content = "取消", MinWidth = 76, Padding = new Thickness(12, 6, 12, 6), IsCancel = true, Margin = new Thickness(8, 0, 0, 0) };

        okButton.Click += (_, _) =>
        {
            if (string.IsNullOrWhiteSpace(operatorBox.Text))
            {
                MessageBox.Show(dialog, "请填写操作人。", "出库信息", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            dialog.DialogResult = true;
        };

        dialog.Content = new StackPanel
        {
            Margin = new Thickness(20),
            Children =
            {
                new TextBlock { Text = $"将对 {count} 个设备执行出库", FontSize = 18, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 14) },
                new TextBlock { Text = "操作人" },
                operatorBox,
                new TextBlock { Text = "备注" },
                noteBox,
                new TextBlock { Text = "预计归还时间" },
                datePicker,
                new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    HorizontalAlignment = HorizontalAlignment.Right,
                    Children = { okButton, cancelButton }
                }
            }
        };

        var confirmed = dialog.ShowDialog() == true;
        operatorName = operatorBox.Text.Trim();
        note = string.IsNullOrWhiteSpace(noteBox.Text) ? null : noteBox.Text.Trim();
        estimatedReturnDate = datePicker.SelectedDate;

        if (confirmed)
        {
            ViewModel.OperatorName = operatorName;
            ViewModel.OperationNote = note ?? "";
            ViewModel.EstimatedReturnDate = estimatedReturnDate ?? DateTime.Today.AddDays(7);
        }

        return confirmed;
    }

    private bool TryCollectAssetInfo(out Asset asset)
    {
        var dialog = new Window
        {
            Owner = this,
            Title = "添加资产",
            Width = 520,
            Height = 620,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize
        };

        var idBox = new TextBox { Margin = new Thickness(0, 4, 0, 12) };
        var nameBox = new TextBox { Margin = new Thickness(0, 4, 0, 12) };
        var modelBox = new TextBox { Margin = new Thickness(0, 4, 0, 12) };
        var brandBox = new TextBox { Margin = new Thickness(0, 4, 0, 12) };
        var internalCodeBox = new TextBox { Margin = new Thickness(0, 4, 0, 12) };
        var locationBox = new TextBox { Margin = new Thickness(0, 4, 0, 12) };
        var statusBox = new ComboBox { Margin = new Thickness(0, 4, 0, 12), SelectedIndex = 0 };
        statusBox.Items.Add("在库");
        statusBox.Items.Add("已出库");
        statusBox.Items.Add("送修");
        statusBox.Items.Add("待报废");
        var purchaseDatePicker = new DatePicker { Margin = new Thickness(0, 4, 0, 12) };
        var noteBox = new TextBox
        {
            Margin = new Thickness(0, 4, 0, 18),
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            MinHeight = 72,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto
        };

        var okButton = new Button { Content = "保存", MinWidth = 90, Padding = new Thickness(12, 6, 12, 6), IsDefault = true };
        var cancelButton = new Button { Content = "取消", MinWidth = 76, Padding = new Thickness(12, 6, 12, 6), IsCancel = true, Margin = new Thickness(8, 0, 0, 0) };

        okButton.Click += (_, _) =>
        {
            if (string.IsNullOrWhiteSpace(idBox.Text))
            {
                MessageBox.Show(dialog, "外编号不能为空。", "添加资产", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            if (string.IsNullOrWhiteSpace(nameBox.Text))
            {
                MessageBox.Show(dialog, "名称不能为空。", "添加资产", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            if (ViewModel.Assets.Any(existing => string.Equals(existing.Id, idBox.Text.Trim(), StringComparison.OrdinalIgnoreCase)))
            {
                MessageBox.Show(dialog, $"外编号已存在：{idBox.Text.Trim()}", "添加资产", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            dialog.DialogResult = true;
        };

        dialog.Content = new ScrollViewer
        {
            Content = new StackPanel
            {
                Margin = new Thickness(20),
                Children =
                {
                    new TextBlock { Text = "基本信息", FontSize = 18, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 14) },
                    new TextBlock { Text = "外编号" },
                    idBox,
                    new TextBlock { Text = "名称" },
                    nameBox,
                    new TextBlock { Text = "型号" },
                    modelBox,
                    new TextBlock { Text = "品牌" },
                    brandBox,
                    new TextBlock { Text = "内编号" },
                    internalCodeBox,
                    new TextBlock { Text = "存放地" },
                    locationBox,
                    new TextBlock { Text = "状态" },
                    statusBox,
                    new TextBlock { Text = "采购日期" },
                    purchaseDatePicker,
                    new TextBlock { Text = "备注" },
                    noteBox,
                    new StackPanel
                    {
                        Orientation = Orientation.Horizontal,
                        HorizontalAlignment = HorizontalAlignment.Right,
                        Children = { okButton, cancelButton }
                    }
                }
            }
        };

        var confirmed = dialog.ShowDialog() == true;
        asset = new Asset
        {
            Id = idBox.Text,
            AssetName = nameBox.Text,
            ModelName = modelBox.Text,
            Brand = brandBox.Text,
            InternalCode = internalCodeBox.Text,
            Location = locationBox.Text,
            Status = statusBox.SelectedIndex switch
            {
                1 => AssetStatus.CheckedOut,
                2 => AssetStatus.Maintenance,
                3 => AssetStatus.Scrapped,
                _ => AssetStatus.InStock
            },
            PurchaseDate = purchaseDatePicker.SelectedDate,
            Note = string.IsNullOrWhiteSpace(noteBox.Text) ? null : noteBox.Text,
            LastUpdated = DateTime.Now
        };

        return confirmed;
    }

    private static string StatusText(AssetStatus status) => status switch
    {
        AssetStatus.InStock => "在库",
        AssetStatus.CheckedOut => "已出库",
        AssetStatus.Maintenance => "送修",
        AssetStatus.Scrapped => "待报废",
        _ => ""
    };

    private void EditRecord(OperationRecord record)
    {
        var dialog = new Window
        {
            Owner = this,
            Title = "编辑历史记录",
            Width = 460,
            Height = 390,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize
        };

        var typeBox = new ComboBox { Margin = new Thickness(0, 4, 0, 12), SelectedIndex = record.Type switch
        {
            OperationType.CheckOut => 1,
            OperationType.Repair => 2,
            OperationType.Scrap => 3,
            _ => 0
        }};
        typeBox.Items.Add("入库");
        typeBox.Items.Add("出库");
        typeBox.Items.Add("送修");
        typeBox.Items.Add("报废");

        var operatorBox = new TextBox { Text = record.Operator, Margin = new Thickness(0, 4, 0, 12) };
        var noteBox = new TextBox { Text = record.Note ?? "", Margin = new Thickness(0, 4, 0, 12), AcceptsReturn = true, MinHeight = 70, TextWrapping = TextWrapping.Wrap };
        var returnDatePicker = new DatePicker { SelectedDate = record.EstimatedReturnDate, Margin = new Thickness(0, 4, 0, 18) };
        var okButton = new Button { Content = "保存", MinWidth = 90, Padding = new Thickness(12, 6, 12, 6), IsDefault = true };
        var cancelButton = new Button { Content = "取消", MinWidth = 76, Padding = new Thickness(12, 6, 12, 6), IsCancel = true, Margin = new Thickness(8, 0, 0, 0) };

        okButton.Click += (_, _) =>
        {
            if (string.IsNullOrWhiteSpace(operatorBox.Text))
            {
                MessageBox.Show(dialog, "操作人不能为空。", "编辑历史记录", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            dialog.DialogResult = true;
        };

        dialog.Content = new StackPanel
        {
            Margin = new Thickness(20),
            Children =
            {
                new TextBlock { Text = $"{record.AssetName} / {record.AssetId}", FontSize = 16, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 14) },
                new TextBlock { Text = "类型" },
                typeBox,
                new TextBlock { Text = "操作人" },
                operatorBox,
                new TextBlock { Text = "备注" },
                noteBox,
                new TextBlock { Text = "预计归还时间" },
                returnDatePicker,
                new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    HorizontalAlignment = HorizontalAlignment.Right,
                    Children = { okButton, cancelButton }
                }
            }
        };

        if (dialog.ShowDialog() == true)
        {
            var type = typeBox.SelectedIndex switch
            {
                1 => OperationType.CheckOut,
                2 => OperationType.Repair,
                3 => OperationType.Scrap,
                _ => OperationType.CheckIn
            };
            ViewModel.UpdateRecord(record, type, operatorBox.Text, noteBox.Text, returnDatePicker.SelectedDate);
        }
    }
}
