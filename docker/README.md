# AssetManager Web

AssetManager Web is the Docker-ready multi-account version of the desktop AssetManager.

## First run

```powershell
cd docker
copy .env.example .env
npm install
npx prisma db push
npm run db:seed
npm run dev
```

## Docker

```bash
docker compose up -d --build
```

Default port: `8090`.

## Scope

- Account login and per-account asset isolation
- MariaDB persistence through Prisma
- Asset status operation records and asset transfers
- Per-account Feishu Bitable configuration with admin-owned API credentials
- Account-to-account asset transfer workflow
- Desktop API endpoints under `/api/desktop/v1`
- Mobile layout and barcode scanning workflow
- Mac-inspired management UI
