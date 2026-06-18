using ClosedXML.Excel;
using AssetScanner.Models;
using System.Text;

namespace AssetScanner.Services;

/// <summary>
/// Excel/CSV 文件服务 - 替代 Android Apache POI / iOS 自实现 ZIP+XML
/// </summary>
public class ExcelService
{
    /// <summary>
    /// 读取 Excel/CSV 文件
    /// </summary>
    public async Task<List<Dictionary<string, string>>> ReadExcelAsync(string filePath)
    {
        var ext = Path.GetExtension(filePath).ToLowerInvariant();
        
        return ext switch
        {
            ".csv" => await ReadCsvAsync(filePath),
            ".xlsx" => await ReadXlsxAsync(filePath),
            ".xls" => await ReadXlsAsync(filePath),
            _ => throw new InvalidOperationException($"不支持的文件格式: {ext}")
        };
    }

    private async Task<List<Dictionary<string, string>>> ReadCsvAsync(string filePath)
    {
        var result = new List<Dictionary<string, string>>();
        var content = await File.ReadAllTextAsync(filePath, DetectEncoding(filePath));
        var rows = ParseCsv(content)
            .Where(row => row.Any(cell => !string.IsNullOrWhiteSpace(cell)))
            .ToList();

        if (rows.Count < 2)
            return result;

        var headers = rows[0].Select(h => h.Trim()).ToList();

        foreach (var values in rows.Skip(1))
        {
            var dict = new Dictionary<string, string>();
            for (var i = 0; i < headers.Count; i++)
                dict[headers[i]] = i < values.Count ? values[i].Trim() : "";
            result.Add(dict);
        }
        
        return result;
    }

    private async Task<List<Dictionary<string, string>>> ReadXlsxAsync(string filePath)
    {
        var result = new List<Dictionary<string, string>>();
        
        using var workbook = new XLWorkbook(filePath);
        var worksheet = workbook.Worksheet(1);
        
        var headers = new List<string>();
        var firstRow = true;
        
        for (var rowNum = 1; rowNum <= worksheet.LastCellUsed()?.Address.RowNumber; rowNum++)
        {
            var row = worksheet.Row(rowNum);
            var cells = new List<string>();
            
            var lastColAddress = row.LastCellUsed()?.Address;
            var lastColInt = lastColAddress != null ? lastColAddress.ColumnNumber : 1;
            if (lastColInt == 0) lastColInt = 1;
            for (var colNum = 1; colNum <= lastColInt; colNum++)
            {
                var cell = row.Cell(colNum);
                if (cell != null)
                {
                    // XLCellValue is a struct in ClosedXML 0.102.x
                    // Use the Get<string>() method or ToString() directly
                    cells.Add(cell.Value.ToString() ?? "");
                }
                else
                {
                    cells.Add("");
                }
            }
            
            if (firstRow)
            {
                headers = cells;
                firstRow = false;
                continue;
            }
            
            var dict = new Dictionary<string, string>();
            for (int i = 0; i < headers.Count; i++)
            {
                dict[headers[i]] = i < cells.Count ? cells[i] : "";
            }
            result.Add(dict);
        }
        
        return result;
    }

    private async Task<List<Dictionary<string, string>>> ReadXlsAsync(string filePath)
    {
        // 使用 Apache POI 的 .NET 端口 NPOI
        var result = new List<Dictionary<string, string>>();
        
        using var stream = File.OpenRead(filePath);
        using var workbook = new NPOI.HSSF.UserModel.HSSFWorkbook(stream);
        var worksheet = workbook.GetSheetAt(0);
        
        var headers = new List<string>();
        var firstRow = true;
        
        for (var rowNum = 0; rowNum <= worksheet.LastRowNum; rowNum++)
        {
            var row = worksheet.GetRow(rowNum);
            if (row == null) continue;
            
            var cells = new List<string>();
            for (var colNum = 0; colNum < row.LastCellNum; colNum++)
            {
                var cell = row.GetCell(colNum);
                cells.Add(cell?.ToString() ?? "");
            }
            
            if (firstRow)
            {
                headers = cells;
                firstRow = false;
                continue;
            }
            
            var dict = new Dictionary<string, string>();
            for (int i = 0; i < headers.Count; i++)
            {
                dict[headers[i]] = i < cells.Count ? cells[i] : "";
            }
            result.Add(dict);
        }
        
        return result;
    }

    private static Encoding DetectEncoding(string filePath)
    {
        using var reader = new StreamReader(filePath);
        var firstLine = reader.ReadLine() ?? "";
        
        // 检测 BOM
        if (firstLine.StartsWith("\uFEFF"))
            return Encoding.UTF8;
        
        // 尝试 GB18030 (常见于中文 Excel)
        try
        {
            var testBytes = File.ReadAllBytes(filePath).Take(1024).ToArray();
            Encoding.GetEncoding("gb18030").GetString(testBytes);
            return Encoding.GetEncoding("gb18030");
        }
        catch
        {
            return Encoding.UTF8;
        }
    }

    public async Task ExportAssetsAsync(List<Asset> assets, string outputPath)
    {
        var rows = BuildAssetRows(assets);
        await ExportRowsAsync(rows, outputPath, "资产列表");
    }

    public async Task ExportRecordsAsync(List<OperationRecord> records, string outputPath)
    {
        var rows = BuildRecordRows(records);
        await ExportRowsAsync(rows, outputPath, "操作记录");
    }

    private async Task ExportRowsAsync(List<IReadOnlyList<string>> rows, string outputPath, string sheetName)
    {
        var ext = Path.GetExtension(outputPath).ToLowerInvariant();
        if (ext == ".xlsx")
        {
            ExportRowsToXlsx(rows, outputPath, sheetName);
            return;
        }

        await File.WriteAllTextAsync(outputPath, EncodeCsv(rows), new UTF8Encoding(true));
    }

    private static List<IReadOnlyList<string>> BuildAssetRows(List<Asset> assets)
    {
        var rows = new List<IReadOnlyList<string>>
        {
            new[] { "外编号", "名称", "型号", "品牌", "一级状态", "内编号", "一级存放地", "采购日期", "备注" }
        };

        rows.AddRange(assets.Select(asset => new[]
        {
            asset.Id,
            asset.AssetName,
            asset.ModelName,
            asset.Brand,
            StatusToText(asset.Status),
            asset.InternalCode,
            asset.Location,
            asset.PurchaseDate?.ToString("yyyy-MM-dd HH:mm:ss") ?? "",
            asset.Note ?? ""
        }));

        return rows;
    }

    private static List<IReadOnlyList<string>> BuildRecordRows(List<OperationRecord> records)
    {
        var rows = new List<IReadOnlyList<string>>
        {
            new[] { "id", "外编号", "名称", "类型", "操作人", "时间", "备注", "预计归还时间" }
        };

        rows.AddRange(records.Select(record => new[]
        {
            record.Id.ToString(),
            record.AssetId,
            record.AssetName,
            record.Type switch
            {
                OperationType.CheckIn => "入库",
                OperationType.CheckOut => "出库",
                OperationType.Repair => "送修",
                OperationType.Scrap => "报废",
                _ => "未知"
            },
            record.Operator,
            record.Timestamp.ToString("yyyy-MM-dd HH:mm:ss"),
            record.Note ?? "",
            record.EstimatedReturnDate?.ToString("yyyy-MM-dd HH:mm:ss") ?? ""
        }));

        return rows;
    }

    private static void ExportRowsToXlsx(List<IReadOnlyList<string>> rows, string outputPath, string sheetName)
    {
        using var workbook = new XLWorkbook();
        var worksheet = workbook.Worksheets.Add(sheetName);

        for (var rowIndex = 0; rowIndex < rows.Count; rowIndex++)
        {
            var row = rows[rowIndex];
            for (var colIndex = 0; colIndex < row.Count; colIndex++)
            {
                worksheet.Cell(rowIndex + 1, colIndex + 1).Value = row[colIndex];
            }
        }

        var header = worksheet.Row(1);
        header.Style.Font.Bold = true;
        header.Style.Fill.BackgroundColor = XLColor.FromHtml("#EEF2F7");
        worksheet.SheetView.FreezeRows(1);
        worksheet.Columns().AdjustToContents();
        workbook.SaveAs(outputPath);
    }

    private static List<List<string>> ParseCsv(string content)
    {
        var rows = new List<List<string>>();
        var row = new List<string>();
        var cell = new StringBuilder();
        var inQuotes = false;

        for (var i = 0; i < content.Length; i++)
        {
            var ch = content[i];
            if (ch == '"')
            {
                if (inQuotes && i + 1 < content.Length && content[i + 1] == '"')
                {
                    cell.Append('"');
                    i++;
                }
                else
                {
                    inQuotes = !inQuotes;
                }
                continue;
            }

            if (ch == ',' && !inQuotes)
            {
                row.Add(cell.ToString());
                cell.Clear();
                continue;
            }

            if ((ch == '\n' || ch == '\r') && !inQuotes)
            {
                if (ch == '\r' && i + 1 < content.Length && content[i + 1] == '\n')
                    i++;
                row.Add(cell.ToString());
                cell.Clear();
                rows.Add(row);
                row = new List<string>();
                continue;
            }

            cell.Append(ch);
        }

        row.Add(cell.ToString());
        rows.Add(row);
        return rows;
    }

    private static string EncodeCsv(IEnumerable<IReadOnlyList<string>> rows)
    {
        return string.Join(Environment.NewLine, rows.Select(row => string.Join(",", row.Select(EscapeCsv))));
    }

    private static string EscapeCsv(string value)
    {
        value ??= "";
        return value.Contains('"') || value.Contains(',') || value.Contains('\n') || value.Contains('\r')
            ? $"\"{value.Replace("\"", "\"\"")}\""
            : value;
    }

    private static string StatusToText(AssetStatus status) => status switch
    {
        AssetStatus.InStock => "在库",
        AssetStatus.CheckedOut => "已出库",
        AssetStatus.Maintenance => "送修",
        AssetStatus.Scrapped => "待报废",
        _ => "在库"
    };
}
