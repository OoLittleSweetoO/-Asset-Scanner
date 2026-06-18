using System.Globalization;
using System.Threading;
using System.Windows;
using Microsoft.Extensions.DependencyInjection;
using AssetScanner.ViewModels;
using AssetScanner.Services;

namespace AssetScanner;

/// <summary>
/// App 入口 - 配置依赖注入
/// </summary>
public partial class App : Application
{
    private readonly ServiceProvider _services;

    public App()
    {
        var serviceCollection = new ServiceCollection();
        
        // 注册服务
        serviceCollection.AddSingleton<StorageService>();
        serviceCollection.AddSingleton<ExcelService>();
        serviceCollection.AddSingleton<BarcodeScannerService>();
        
        // 注册 ViewModel
        serviceCollection.AddSingleton<AssetViewModel>();
        
        _services = serviceCollection.BuildServiceProvider();
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        
        // 将 ViewModel 注入到 Resources
        var assetViewModel = _services.GetRequiredService<AssetViewModel>();
        Resources["AssetViewModel"] = assetViewModel;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        base.OnExit(e);
        _services.Dispose();
    }
}
