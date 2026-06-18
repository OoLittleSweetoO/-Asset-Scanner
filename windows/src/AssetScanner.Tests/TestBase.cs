using AssetScanner.Services;

namespace AssetScanner.Tests;

/// <summary>
/// 测试基类 - 提供通用的测试设置
/// </summary>
public class TestBase : IDisposable
{
    protected StorageService? StorageService { get; private set; }
    protected ExcelService? ExcelService { get; private set; }
    protected BarcodeScannerService? BarcodeScannerService { get; private set; }
    protected readonly string _testDbPath;

    public TestBase()
    {
        // 使用临时数据库文件进行测试
        _testDbPath = Path.Combine(Path.GetTempPath(), $"AssetScanner_Test_{Guid.NewGuid()}.db");
    }

    protected void InitializeServices()
    {
        StorageService = new StorageService(_testDbPath);
        ExcelService = new ExcelService();
        BarcodeScannerService = new BarcodeScannerService();
    }

    public void Dispose()
    {
        // 清理测试数据库
        if (StorageService != null)
        {
            StorageService.Dispose();
            StorageService = null;
        }

        // 删除临时数据库文件
        if (File.Exists(_testDbPath))
        {
            try
            {
                File.Delete(_testDbPath);
            }
            catch
            {
                // 忽略删除失败
            }
        }

        GC.SuppressFinalize(this);
    }
}