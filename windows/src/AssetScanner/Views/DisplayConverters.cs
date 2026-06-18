using System.Globalization;
using System.Windows.Data;
using System.Windows.Media;
using AssetScanner.Models;

namespace AssetScanner.Views;

public sealed class AssetStatusDisplayConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value switch
        {
            AssetStatus.InStock => "在库",
            AssetStatus.CheckedOut => "已出库",
            AssetStatus.Maintenance => "送修",
            AssetStatus.Scrapped => "待报废",
            _ => ""
        };

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => Binding.DoNothing;
}

public sealed class OperationTypeDisplayConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value switch
        {
            OperationType.CheckIn => "入库",
            OperationType.CheckOut => "出库",
            OperationType.Repair => "送修",
            OperationType.Scrap => "报废",
            _ => ""
        };

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => Binding.DoNothing;
}

public sealed class AssetStatusBrushConverter : IValueConverter
{
    private static readonly Brush Green = new SolidColorBrush(Color.FromRgb(51, 179, 102));
    private static readonly Brush Orange = new SolidColorBrush(Color.FromRgb(255, 140, 0));
    private static readonly Brush Red = new SolidColorBrush(Color.FromRgb(230, 64, 77));
    private static readonly Brush Gray = new SolidColorBrush(Color.FromRgb(107, 114, 128));

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value switch
        {
            AssetStatus.InStock => Green,
            AssetStatus.CheckedOut => Orange,
            AssetStatus.Maintenance => Red,
            AssetStatus.Scrapped => Gray,
            _ => Gray
        };

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => Binding.DoNothing;
}

public sealed class AssetDetailSummaryConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not Asset asset) return "";

        var parts = new[]
        {
            asset.Id,
            asset.InternalCode,
            asset.Brand,
            asset.ModelName,
            StructuredNoteValue(asset.Note, "保管科室"),
            StructuredNoteValue(asset.Note, "使用人"),
            StructuredNoteValue(asset.Note, "二级状态"),
            StructuredNoteValue(asset.Note, "二级存放地"),
            StructuredNoteValue(asset.Note, "其他附件")
        };

        return string.Join("  ·  ", parts.Where(part => !string.IsNullOrWhiteSpace(part)));
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => Binding.DoNothing;

    private static string StructuredNoteValue(string? note, string label)
    {
        if (string.IsNullOrWhiteSpace(note)) return "";
        var prefix = $"{label}：";
        return note
            .Split(Environment.NewLine)
            .FirstOrDefault(line => line.StartsWith(prefix, StringComparison.Ordinal))
            ?.Substring(prefix.Length)
            .Trim() ?? "";
    }
}
