import { randomUUID } from "crypto";
import { AssetStatus, OperationType, TransferStatus, UserRole, type Asset, type FeishuConfig, type OperationRecord, type User } from "@prisma/client";
import { FeishuBitableClient } from "./feishu-bitable";
import { DesktopApiError, nullableTextField, parseDateField, textField } from "./desktop-api";
import { prisma } from "./prisma";

type ApiUser = Pick<User, "id" | "email" | "name" | "role">;
type AssetWithRelations = Asset & { owner?: Pick<User, "id" | "email" | "name"> | null; source?: { id: string; fileName: string } | null };

function isAdmin(user: ApiUser) {
  return user.role === UserRole.ADMIN;
}

function scopedWhere(user: ApiUser) {
  return isAdmin(user) ? {} : { ownerId: user.id };
}

function operationTypeForStatus(status: AssetStatus) {
  return {
    IN_STOCK: OperationType.CHECK_IN,
    CHECKED_OUT: OperationType.CHECK_OUT,
    MAINTENANCE: OperationType.REPAIR,
    SCRAPPED: OperationType.SCRAP
  }[status];
}

function parseStatus(value: unknown): AssetStatus {
  const raw = textField(value);
  if ((Object.values(AssetStatus) as string[]).includes(raw)) return raw as AssetStatus;

  const normalized = raw.toLowerCase().replace(/[\s-]/g, "_");
  if (["checked_out", "checkedout", "checkout", "out", "1", "出库", "已出库"].includes(normalized)) return AssetStatus.CHECKED_OUT;
  if (["maintenance", "repair", "2", "送修", "维修中"].includes(normalized)) return AssetStatus.MAINTENANCE;
  if (["scrapped", "scrap", "3", "报废", "待报废"].includes(normalized)) return AssetStatus.SCRAPPED;
  return AssetStatus.IN_STOCK;
}

function parseOperationType(value: unknown): OperationType {
  const raw = textField(value);
  if ((Object.values(OperationType) as string[]).includes(raw)) return raw as OperationType;

  const normalized = raw.toLowerCase().replace(/[\s-]/g, "_");
  if (["check_out", "checkout", "1", "出库"].includes(normalized)) return OperationType.CHECK_OUT;
  if (["repair", "2", "送修"].includes(normalized)) return OperationType.REPAIR;
  if (["scrap", "3", "报废"].includes(normalized)) return OperationType.SCRAP;
  if (["transfer_out", "转出"].includes(normalized)) return OperationType.TRANSFER_OUT;
  if (["transfer_in", "转入"].includes(normalized)) return OperationType.TRANSFER_IN;
  return OperationType.CHECK_IN;
}

function dateToIso(date: Date | null | undefined) {
  return date ? date.toISOString() : null;
}

function assetDto(asset: AssetWithRelations) {
  return {
    id: asset.id,
    ownerId: asset.ownerId,
    owner: asset.owner ? { id: asset.owner.id, email: asset.owner.email, name: asset.owner.name } : null,
    assetCode: asset.assetCode,
    assetName: asset.assetName,
    modelName: asset.modelName,
    brand: asset.brand,
    status: asset.status,
    internalCode: asset.internalCode,
    location: asset.location,
    purchaseDate: dateToIso(asset.purchaseDate),
    note: asset.note,
    sourceId: asset.sourceId,
    source: asset.source ? { id: asset.source.id, fileName: asset.source.fileName } : null,
    createdAt: asset.createdAt.toISOString(),
    updatedAt: asset.updatedAt.toISOString()
  };
}

function recordDto(record: OperationRecord) {
  return {
    id: record.id,
    ownerId: record.ownerId,
    assetId: record.assetId,
    assetCode: record.assetCode,
    assetName: record.assetName,
    type: record.type,
    operatorName: record.operatorName,
    note: record.note,
    estimatedReturnDate: dateToIso(record.estimatedReturnDate),
    isSyncedToReminders: record.isSyncedToReminders,
    createdAt: record.createdAt.toISOString()
  };
}

async function accessibleAsset(user: ApiUser, assetId: string) {
  const asset = await prisma.asset.findFirst({
    where: { id: assetId, ...scopedWhere(user) },
    include: { owner: { select: { id: true, email: true, name: true } }, source: { select: { id: true, fileName: true } } }
  });
  if (!asset) throw new DesktopApiError(404, "Asset not found", "ASSET_NOT_FOUND");
  return asset;
}

async function effectiveFeishuConfig(ownerId: string): Promise<FeishuConfig | null> {
  const [owner, ownerConfig, adminConfig] = await Promise.all([
    prisma.user.findUnique({ where: { id: ownerId }, select: { role: true } }),
    prisma.feishuConfig.findUnique({ where: { ownerId } }),
    prisma.feishuConfig.findFirst({
      where: {
        owner: { role: UserRole.ADMIN },
        appId: { not: "" },
        appSecretCipher: { not: "" }
      },
      orderBy: { updatedAt: "desc" }
    })
  ]);
  const config = ownerConfig ?? adminConfig;
  if (!config) return null;
  const credentialConfig = owner?.role === UserRole.ADMIN ? ownerConfig ?? adminConfig : adminConfig;
  return {
    ...config,
    appId: credentialConfig?.appId || "",
    appSecretCipher: credentialConfig?.appSecretCipher || ""
  };
}

async function syncSingleStatusToFeishu(ownerId: string, assetId: string, recordId: string) {
  const [config, asset, record] = await Promise.all([
    effectiveFeishuConfig(ownerId),
    prisma.asset.findUnique({ where: { id: assetId } }),
    prisma.operationRecord.findUnique({ where: { id: recordId } })
  ]);
  if (!config || !asset || !record) return;
  if (!config.appId || !config.appSecretCipher || !config.assetAppToken || !config.assetTableId) return;

  try {
    await new FeishuBitableClient(config).syncSingleAsset(asset, record);
  } catch (error) {
    console.error("Feishu desktop single sync failed", error);
  }
}

async function deleteAssetsFromFeishu(ownerId: string, assetCodes: string[]) {
  const config = await effectiveFeishuConfig(ownerId);
  if (!config || !config.appId || !config.appSecretCipher || !config.assetAppToken || !config.assetTableId) return;

  try {
    const client = new FeishuBitableClient(config);
    for (const code of assetCodes) {
      await client.deleteAssetByCode(code);
    }
  } catch (error) {
    console.error("Feishu desktop delete sync failed", error);
  }
}

async function transferAssetInFeishu(fromUserId: string, toUserId: string, assetCode: string, assetId: string, recordId: string) {
  await deleteAssetsFromFeishu(fromUserId, [assetCode]);
  await syncSingleStatusToFeishu(toUserId, assetId, recordId);
}

async function runFeishuFullSync(ownerId: string) {
  const config = await effectiveFeishuConfig(ownerId);
  if (!config || !config.appId || !config.appSecretCipher || !config.assetAppToken || !config.assetTableId) return;
  const [assets, records] = await Promise.all([
    prisma.asset.findMany({ where: { ownerId } }),
    prisma.operationRecord.findMany({ where: { ownerId } })
  ]);
  await new FeishuBitableClient(config).syncAll(assets, records).catch((error) => console.error("Feishu desktop full sync failed", error));
}

export async function desktopBootstrap(user: ApiUser) {
  const where = scopedWhere(user);
  const [assets, records, sources, users, transfers, config] = await Promise.all([
    prisma.asset.findMany({
      where,
      include: { owner: { select: { id: true, email: true, name: true } }, source: { select: { id: true, fileName: true } } },
      orderBy: { updatedAt: "desc" }
    }),
    prisma.operationRecord.findMany({ where, orderBy: { createdAt: "desc" } }),
    prisma.assetSource.findMany({
      where,
      include: { assets: { select: { assetCode: true } } },
      orderBy: { updatedAt: "desc" }
    }),
    isAdmin(user)
      ? prisma.user.findMany({ select: { id: true, email: true, name: true, role: true }, orderBy: { createdAt: "asc" } })
      : prisma.user.findMany({ select: { id: true, email: true, name: true, role: true }, orderBy: { createdAt: "asc" } }),
    prisma.assetTransfer.findMany({
      where: isAdmin(user) ? {} : { OR: [{ fromUserId: user.id }, { toUserId: user.id }, { requestedById: user.id }] },
      include: {
        asset: { select: { id: true, assetCode: true, assetName: true } },
        fromUser: { select: { id: true, email: true, name: true } },
        toUser: { select: { id: true, email: true, name: true } },
        requestedBy: { select: { id: true, email: true, name: true } }
      },
      orderBy: { createdAt: "desc" }
    }),
    prisma.feishuConfig.findUnique({ where: { ownerId: user.id } })
  ]);

  return {
    serverTime: new Date().toISOString(),
    user,
    assets: assets.map(assetDto),
    records: records.map(recordDto),
    sources: sources.map((source) => ({
      id: source.id,
      ownerId: source.ownerId,
      fileName: source.fileName,
      assetCount: source.assetCount,
      assetCodes: source.assets.map((asset) => asset.assetCode),
      createdAt: source.createdAt.toISOString(),
      updatedAt: source.updatedAt.toISOString()
    })),
    users,
    transfers: transfers.map((transfer) => ({
      id: transfer.id,
      asset: transfer.asset,
      fromUser: transfer.fromUser,
      toUser: transfer.toUser,
      requestedBy: transfer.requestedBy,
      status: transfer.status,
      note: transfer.note,
      createdAt: transfer.createdAt.toISOString(),
      decidedAt: dateToIso(transfer.decidedAt)
    })),
    feishu: {
      assetTableLink: config?.assetTableLink ?? "",
      recordTableLink: config?.recordTableLink ?? "",
      configured: Boolean(config?.assetAppToken && config?.assetTableId && config?.recordAppToken && config?.recordTableId)
    }
  };
}

export async function createDesktopAsset(user: ApiUser, body: Record<string, unknown>) {
  const assetCode = textField(body.assetCode ?? body.id);
  const assetName = textField(body.assetName ?? body.name);
  if (!assetCode || !assetName) throw new DesktopApiError(400, "assetCode and assetName are required", "INVALID_ASSET");

  const ownerId = isAdmin(user) && textField(body.ownerId) ? textField(body.ownerId) : user.id;
  const data = {
    assetName,
    modelName: textField(body.modelName),
    brand: textField(body.brand),
    status: parseStatus(body.status),
    internalCode: textField(body.internalCode),
    location: textField(body.location),
    purchaseDate: parseDateField(body.purchaseDate),
    note: nullableTextField(body.note)
  };

  const asset = await prisma.asset.upsert({
    where: { ownerId_assetCode: { ownerId, assetCode } },
    create: { ownerId, assetCode, ...data },
    update: data,
    include: { owner: { select: { id: true, email: true, name: true } }, source: { select: { id: true, fileName: true } } }
  });

  void runFeishuFullSync(ownerId);
  return assetDto(asset);
}

export async function updateDesktopAsset(user: ApiUser, assetId: string, body: Record<string, unknown>) {
  const asset = await accessibleAsset(user, assetId);
  const data = {
    assetName: textField(body.assetName ?? asset.assetName),
    modelName: textField(body.modelName ?? asset.modelName),
    brand: textField(body.brand ?? asset.brand),
    internalCode: textField(body.internalCode ?? asset.internalCode),
    location: textField(body.location ?? asset.location),
    purchaseDate: body.purchaseDate === undefined ? asset.purchaseDate : parseDateField(body.purchaseDate),
    note: body.note === undefined ? asset.note : nullableTextField(body.note)
  };

  const updated = await prisma.asset.update({
    where: { id: asset.id },
    data,
    include: { owner: { select: { id: true, email: true, name: true } }, source: { select: { id: true, fileName: true } } }
  });

  void runFeishuFullSync(updated.ownerId);
  return assetDto(updated);
}

export async function updateDesktopAssetStatus(user: ApiUser, assetId: string, body: Record<string, unknown>) {
  const asset = await accessibleAsset(user, assetId);
  const status = parseStatus(body.status ?? body.operation);
  const operatorName = textField(body.operatorName) || user.name;
  const note = nullableTextField(body.note ?? body.detail);
  const estimatedReturnDate = parseDateField(body.estimatedReturnDate);

  if (asset.status === status) return { asset: assetDto(asset), record: null };

  const result = await prisma.$transaction(async (tx) => {
    const updatedAsset = await tx.asset.update({
      where: { id: asset.id },
      data: { status },
      include: { owner: { select: { id: true, email: true, name: true } }, source: { select: { id: true, fileName: true } } }
    });
    const record = await tx.operationRecord.create({
      data: {
        ownerId: asset.ownerId,
        assetId: asset.id,
        assetCode: asset.assetCode,
        assetName: asset.assetName,
        type: operationTypeForStatus(status),
        operatorName,
        note,
        estimatedReturnDate: status === AssetStatus.CHECKED_OUT ? estimatedReturnDate : null
      }
    });
    return { updatedAsset, record };
  });

  void syncSingleStatusToFeishu(asset.ownerId, result.updatedAsset.id, result.record.id);
  return { asset: assetDto(result.updatedAsset), record: recordDto(result.record) };
}

export async function deleteDesktopAsset(user: ApiUser, assetId: string) {
  const asset = await accessibleAsset(user, assetId);
  await prisma.$transaction([
    prisma.operationRecord.deleteMany({ where: { ownerId: asset.ownerId, assetCode: asset.assetCode } }),
    prisma.asset.delete({ where: { id: asset.id } })
  ]);
  void deleteAssetsFromFeishu(asset.ownerId, [asset.assetCode]);
  return { deletedId: asset.id };
}

export async function transferDesktopAsset(user: ApiUser, body: Record<string, unknown>) {
  const assetId = textField(body.assetId);
  const toUserId = textField(body.toUserId);
  const note = nullableTextField(body.note);
  const operatorName = textField(body.operatorName) || user.name;
  const immediate = isAdmin(user) || body.immediate === true;
  if (!assetId || !toUserId) throw new DesktopApiError(400, "assetId and toUserId are required", "INVALID_TRANSFER");

  const asset = await accessibleAsset(user, assetId);
  if (asset.ownerId === toUserId) throw new DesktopApiError(400, "Asset already belongs to target user", "SAME_OWNER");

  const target = await prisma.user.findUnique({ where: { id: toUserId }, select: { id: true, name: true } });
  if (!target) throw new DesktopApiError(404, "Target user not found", "TARGET_USER_NOT_FOUND");

  if (!immediate) {
    const transfer = await prisma.assetTransfer.create({
      data: {
        assetId: asset.id,
        fromUserId: asset.ownerId,
        toUserId,
        requestedById: user.id,
        note
      }
    });
    return { transfer, status: transfer.status };
  }

  const result = await prisma.$transaction(async (tx) => {
    await tx.asset.update({ where: { id: asset.id }, data: { ownerId: toUserId, sourceId: null } });
    const transfer = await tx.assetTransfer.create({
      data: {
        assetId: asset.id,
        fromUserId: asset.ownerId,
        toUserId,
        requestedById: user.id,
        status: TransferStatus.ACCEPTED,
        note,
        decidedAt: new Date()
      }
    });
    await tx.operationRecord.create({
      data: {
        ownerId: asset.ownerId,
        assetId: asset.id,
        assetCode: asset.assetCode,
        assetName: asset.assetName,
        type: OperationType.TRANSFER_OUT,
        operatorName,
        note: note || `Transfer to ${target.name}`
      }
    });
    const inRecord = await tx.operationRecord.create({
      data: {
        ownerId: toUserId,
        assetId: asset.id,
        assetCode: asset.assetCode,
        assetName: asset.assetName,
        type: OperationType.TRANSFER_IN,
        operatorName,
        note: note || "Account transfer accepted"
      }
    });
    const updatedAsset = await tx.asset.findUniqueOrThrow({
      where: { id: asset.id },
      include: { owner: { select: { id: true, email: true, name: true } }, source: { select: { id: true, fileName: true } } }
    });
    return { transfer, inRecord, updatedAsset };
  });

  void transferAssetInFeishu(asset.ownerId, toUserId, asset.assetCode, asset.id, result.inRecord.id);
  return { transfer: result.transfer, asset: assetDto(result.updatedAsset), status: result.transfer.status };
}

export async function importDesktopSnapshot(user: ApiUser, body: Record<string, unknown>) {
  const assets = Array.isArray(body.assets) ? body.assets : [];
  const records = Array.isArray(body.records) ? body.records : [];
  const sources = Array.isArray(body.sources) ? body.sources : [];
  const sourceMap = new Map<string, string>();
  let importedAssets = 0;
  let importedRecords = 0;
  let importedSources = 0;

  await prisma.$transaction(async (tx) => {
    for (const item of sources) {
      if (!item || typeof item !== "object") continue;
      const source = item as Record<string, unknown>;
      const fileName = textField(source.fileName) || "Desktop import";
      const localId = textField(source.id);
      const imported = await tx.assetSource.upsert({
        where: { ownerId_fileName: { ownerId: user.id, fileName } },
        create: { ownerId: user.id, fileName, assetCount: Number(source.assetCount || 0) || 0 },
        update: { assetCount: Number(source.assetCount || 0) || 0 }
      });
      importedSources += 1;
      sourceMap.set(localId || fileName, imported.id);
    }

    for (const item of assets) {
      if (!item || typeof item !== "object") continue;
      const asset = item as Record<string, unknown>;
      const assetCode = textField(asset.assetCode ?? asset.id);
      const assetName = textField(asset.assetName ?? asset.name);
      if (!assetCode || !assetName) continue;

      const sourceId = sourceMap.get(textField(asset.sourceId)) ?? null;
      await tx.asset.upsert({
        where: { ownerId_assetCode: { ownerId: user.id, assetCode } },
        create: {
          ownerId: user.id,
          assetCode,
          assetName,
          modelName: textField(asset.modelName),
          brand: textField(asset.brand),
          status: parseStatus(asset.status),
          internalCode: textField(asset.internalCode),
          location: textField(asset.location),
          purchaseDate: parseDateField(asset.purchaseDate),
          note: nullableTextField(asset.note),
          sourceId
        },
        update: {
          assetName,
          modelName: textField(asset.modelName),
          brand: textField(asset.brand),
          status: parseStatus(asset.status),
          internalCode: textField(asset.internalCode),
          location: textField(asset.location),
          purchaseDate: parseDateField(asset.purchaseDate),
          note: nullableTextField(asset.note),
          sourceId
        }
      });
      importedAssets += 1;
    }

    for (const item of records) {
      if (!item || typeof item !== "object") continue;
      const record = item as Record<string, unknown>;
      const assetCode = textField(record.assetCode ?? record.assetId);
      if (!assetCode) continue;
      const asset = await tx.asset.findUnique({ where: { ownerId_assetCode: { ownerId: user.id, assetCode } } });
      const recordId = textField(record.id) || randomUUID();
      const existing = await tx.operationRecord.findUnique({ where: { id: recordId } });
      const data = {
        ownerId: user.id,
        assetId: asset?.id,
        assetCode,
        assetName: textField(record.assetName || asset?.assetName),
        type: parseOperationType(record.type),
        operatorName: textField(record.operatorName ?? record.operator) || user.name,
        note: nullableTextField(record.note),
        estimatedReturnDate: parseDateField(record.estimatedReturnDate),
        isSyncedToReminders: Boolean(record.isSyncedToReminders),
        createdAt: parseDateField(record.createdAt ?? record.timestamp) ?? new Date()
      };

      if (existing?.ownerId === user.id) {
        await tx.operationRecord.update({ where: { id: recordId }, data });
      } else {
        await tx.operationRecord.create({ data: { id: existing ? undefined : recordId, ...data } });
      }
      importedRecords += 1;
    }
  });

  void runFeishuFullSync(user.id);
  return { importedAssets, importedRecords, importedSources };
}
