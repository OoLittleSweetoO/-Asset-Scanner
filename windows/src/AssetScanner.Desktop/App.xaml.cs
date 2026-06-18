using System;
using System.Windows;
using AssetScanner.Services;
using AssetScanner.ViewModels;
using AssetScanner.Views;
using Microsoft.Extensions.DependencyInjection;

namespace AssetScanner;

public partial class App : Application
{
    private readonly ServiceProvider _services;

    public App()
    {
        var serviceCollection = new ServiceCollection();

        serviceCollection.AddSingleton<StorageService>();
        serviceCollection.AddSingleton<ExcelService>();
        serviceCollection.AddSingleton<BarcodeScannerService>();
        serviceCollection.AddSingleton<AssetViewModel>();

        _services = serviceCollection.BuildServiceProvider();
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        var assetViewModel = _services.GetRequiredService<AssetViewModel>();
        Resources["AssetViewModel"] = assetViewModel;

        var mainWindow = new MainWindow();
        MainWindow = mainWindow;
        mainWindow.Show();

        base.OnStartup(e);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _services.Dispose();
        base.OnExit(e);
    }
}
