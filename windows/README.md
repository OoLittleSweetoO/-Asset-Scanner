# AssetScanner Windows

This folder contains the Windows desktop version of AssetScanner / AssetManager.

## Requirements

- Windows 10 or later
- .NET 8 SDK
- Visual Studio 2022 or VS Code with the C# extension

## Build

```powershell
cd windows
dotnet build AssetScanner.sln
```

## Run

```powershell
cd windows
dotnet run --project src/AssetScanner.Desktop/AssetScanner.Desktop.csproj
```

## Publish portable app

```powershell
cd windows
dotnet publish src/AssetScanner.Desktop/AssetScanner.Desktop.csproj -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true
```

The desktop app keeps the local asset workflow and can also connect to the Docker server through the server login panel. Server mode uses `/api/desktop/v1` endpoints for login, asset sync, and operation uploads.
