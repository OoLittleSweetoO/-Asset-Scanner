# Windows and Docker Versions

This repository now includes the macOS/iOS project plus two companion implementations:

- `windows/`: Windows WPF desktop app built with .NET 8.
- `docker/`: Docker-ready web app built with Next.js, Prisma, and MariaDB.

## Windows desktop

```powershell
cd windows
dotnet build AssetScanner.sln
dotnet run --project src/AssetScanner.Desktop/AssetScanner.Desktop.csproj
```

The Windows app preserves the local desktop workflow, Excel import/export, Feishu sync settings, and the new server login/sync flow for connecting to the Docker deployment.

## Docker web app

```bash
cd docker
docker compose up -d --build
```

The web app includes account registration/login, admin and normal user roles, per-account asset isolation, Feishu Bitable configuration, desktop JSON import, account-to-account asset transfers, mobile layout, and barcode scanning.

Default local port: `8090`.

## Desktop/server integration

The Docker app exposes desktop-facing endpoints under `/api/desktop/v1`. A deployed URL can be entered in the Windows app so the desktop version can authenticate with a Docker account and sync assets/operation records against the server database.
