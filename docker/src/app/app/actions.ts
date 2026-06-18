"use server";

import { AssetStatus, OperationType, TransferStatus, UserRole } from "@prisma/client";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser, signOut } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { hashPassword } from "@/lib/password";
import { verifyPassword } from "@/lib/password";
import { extractFeishuTableConfig } from "@/lib/feishu";
import { parseAssetRows, readRowsFromUpload } from "@/lib/asset-io";
import { operationTypeFromText, statusFromText } from "@/lib/asset-io";
import { FeishuBitableClient } from "@/lib/feishu-bitable";

function stringValue(formData: FormData, key: string) {
  return String(formData.get(key) || "").trim();
}

function dateValue(formData: FormData, key: string) {
  const value = stringValue(formData, key);
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function operationTypeForStatus(status: AssetStatus) {
  return {
    IN_STOCK: OperationType.CHECK_IN,
    CHECKED_OUT: OperationType.CHECK_OUT,
    MAINTENANCE: OperationType.REPAIR,
    SCRAPPED: OperationType.SCRAP
  }[status];
}

async function isAdminUser(userId: string) {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { role: true } });
  return user?.role === UserRole.ADMIN;
}

async function effectiveFeishuConfig(ownerId: string) {
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

async function accessibleAssetWhere(userId: string, assetId: string) {
  return (await isAdminUser(userId)) ? { id: assetId } : { id: assetId, ownerId: userId };
}

function groupCodesByOwner(assets: Array<{ ownerId: string; assetCode: string }>) {
  const groups = new Map<string, string[]>();
  for (const asset of assets) {
    const codes = groups.get(asset.ownerId) ?? [];
    codes.push(asset.assetCode);
    groups.set(asset.ownerId, codes);
  }
  return groups;
}

function ownerCodeFilters(assets: Array<{ ownerId: string; assetCode: string }>) {
  return assets.map((asset) => ({ ownerId: asset.ownerId, assetCode: asset.assetCode }));
}

async function syncSingleStatusToFeishu(userId: string, assetId: string, recordId: string) {
  const [config, asset, record] = await Promise.all([
    effectiveFeishuConfig(userId),
    prisma.asset.findUnique({ where: { id: assetId } }),
    prisma.operationRecord.findUnique({ where: { id: recordId } })
  ]);
  if (!config || !asset || !record) return;
  if (!config.appId || !config.appSecretCipher || !config.assetAppToken || !config.assetTableId) return;

  try {
    await new FeishuBitableClient(config).syncSingleAsset(asset, record);
  } catch (error) {
    console.error("Feishu single status sync failed", error);
  }
}

async function deleteAssetsFromFeishu(userId: string, assetCodes: string[]) {
  const config = await effectiveFeishuConfig(userId);
  if (!config || !config.appId || !config.appSecretCipher || !config.assetAppToken || !config.assetTableId) return;
  try {
    const client = new FeishuBitableClient(config);
    for (const code of assetCodes) {
      await client.deleteAssetByCode(code);
    }
  } catch (error) {
    console.error("Feishu asset delete failed", error);
  }
}

async function transferAssetInFeishu(fromUserId: string, toUserId: string, assetCode: string, assetId: string, recordId: string) {
  try {
    await deleteAssetsFromFeishu(fromUserId, [assetCode]);
    await syncSingleStatusToFeishu(toUserId, assetId, recordId);
  } catch (error) {
    console.error("Feishu transfer sync failed", error);
  }
}

export async function logoutAction() {
  await signOut();
  redirect("/login");
}

export async function createUserAction(formData: FormData) {
  const user = await requireUser();
  if (user.role !== UserRole.ADMIN) return;

  const email = stringValue(formData, "email").toLowerCase();
  const name = stringValue(formData, "name");
  const password = stringValue(formData, "password");
  if (!email || !name || !password) return;

  await prisma.user.create({
    data: {
      email,
      name,
      passwordHash: hashPassword(password),
      role: "USER",
      feishuConfig: { create: {} }
    }
  });
  revalidatePath("/app/settings");
}

export async function changePasswordAction(formData: FormData) {
  const user = await requireUser();
  const currentPassword = stringValue(formData, "currentPassword");
  const newPassword = stringValue(formData, "newPassword");
  const confirmPassword = stringValue(formData, "confirmPassword");

  const freshUser = await prisma.user.findUnique({ where: { id: user.id } });
  if (!freshUser || !verifyPassword(currentPassword, freshUser.passwordHash)) return;
  if (newPassword.length < 8 || newPassword !== confirmPassword) return;

  await prisma.$transaction([
    prisma.user.update({ where: { id: user.id }, data: { passwordHash: hashPassword(newPassword) } }),
    prisma.session.deleteMany({ where: { userId: user.id } })
  ]);

  redirect("/login?error=" + encodeURIComponent("瀵嗙爜宸蹭慨鏀癸紝璇蜂娇鐢ㄦ柊瀵嗙爜鐧诲綍"));
}

export async function createAssetAction(formData: FormData) {
  const user = await requireUser();
  const assetCode = stringValue(formData, "assetCode");
  const assetName = stringValue(formData, "assetName");
  if (!assetCode || !assetName) return;

  await prisma.asset.create({
    data: {
      ownerId: user.id,
      assetCode,
      assetName,
      modelName: stringValue(formData, "modelName"),
      brand: stringValue(formData, "brand"),
      internalCode: stringValue(formData, "internalCode"),
      location: stringValue(formData, "location"),
      purchaseDate: dateValue(formData, "purchaseDate"),
      note: stringValue(formData, "note") || null
    }
  });
  revalidatePath("/app");
}

export async function updateAssetStatusAction(formData: FormData) {
  const user = await requireUser();
  const assetId = stringValue(formData, "assetId");
  const status = stringValue(formData, "status") as AssetStatus;
  const operatorName = stringValue(formData, "operatorName") || user.name;
  const note = stringValue(formData, "note");
  const estimatedReturnDate = dateValue(formData, "estimatedReturnDate");

  const asset = await prisma.asset.findFirst({ where: await accessibleAssetWhere(user.id, assetId) });
  if (!asset || asset.status === status) return;

  const result = await prisma.$transaction(async (tx) => {
    const updatedAsset = await tx.asset.update({
      where: { id: asset.id },
      data: { status }
    });
    const record = await tx.operationRecord.create({
      data: {
        ownerId: asset.ownerId,
        assetId: asset.id,
        assetCode: asset.assetCode,
        assetName: asset.assetName,
        type: operationTypeForStatus(status),
        operatorName,
        note: note || null,
        estimatedReturnDate
      }
    });
    return { updatedAsset, record };
  });

  void syncSingleStatusToFeishu(asset.ownerId, result.updatedAsset.id, result.record.id);

  revalidatePath("/app");
  revalidatePath("/app/records");
}

export async function bulkAssetOperationAction(formData: FormData) {
  const user = await requireUser();
  const ids = formData.getAll("assetIds").flatMap((value) => String(value).split(",")).map((id) => id.trim()).filter(Boolean);
  const operation = stringValue(formData, "operation");
  const operatorName = stringValue(formData, "operatorName") || user.name;
  const note = stringValue(formData, "note");
  const estimatedReturnDate = dateValue(formData, "estimatedReturnDate");
  const toUserId = stringValue(formData, "toUserId");

  if (ids.length === 0) return;

  if (operation === "delete") {
    const admin = user.role === UserRole.ADMIN;
    const assets = await prisma.asset.findMany({
      where: { id: { in: ids }, ...(admin ? {} : { ownerId: user.id }) },
      select: { id: true, assetCode: true }
    });
    const fullAssets = await prisma.asset.findMany({
      where: { id: { in: assets.map((asset) => asset.id) } },
      select: { ownerId: true, assetCode: true }
    });
    if (fullAssets.length === 0) return;
    await prisma.$transaction([
      prisma.operationRecord.deleteMany({ where: { OR: ownerCodeFilters(fullAssets) } }),
      prisma.asset.deleteMany({ where: { id: { in: assets.map((asset) => asset.id) }, ...(admin ? {} : { ownerId: user.id }) } })
    ]);
    for (const [ownerId, codes] of groupCodesByOwner(fullAssets)) {
      void deleteAssetsFromFeishu(ownerId, codes);
    }
    revalidatePath("/app");
    revalidatePath("/app/records");
    return;
  }

  if (operation === "transfer") {
    if (!toUserId) return;
    const assets = await prisma.asset.findMany({ where: { id: { in: ids }, ...(user.role === UserRole.ADMIN ? {} : { ownerId: user.id }) } });
    const transferable = assets.filter((asset) => asset.ownerId !== toUserId);
    if (transferable.length === 0) return;
    await prisma.assetTransfer.createMany({
      data: transferable.map((asset) => ({
        assetId: asset.id,
        fromUserId: asset.ownerId,
        toUserId,
        requestedById: user.id,
        note: note || null
      }))
    });
    revalidatePath("/app/transfers");
    return;
  }

  const statusMap: Record<string, AssetStatus> = {
    checkin: AssetStatus.IN_STOCK,
    checkout: AssetStatus.CHECKED_OUT,
    repair: AssetStatus.MAINTENANCE,
    scrap: AssetStatus.SCRAPPED
  };
  const status = statusMap[operation];
  if (!status) return;

  const results = await prisma.$transaction(async (tx) => {
    const assets = await tx.asset.findMany({ where: { id: { in: ids }, ...(user.role === UserRole.ADMIN ? {} : { ownerId: user.id }) } });
    const changed: Array<{ ownerId: string; assetId: string; recordId: string }> = [];
    for (const asset of assets) {
      if (asset.status === status) continue;
      const updated = await tx.asset.update({ where: { id: asset.id }, data: { status } });
      const record = await tx.operationRecord.create({
        data: {
          ownerId: asset.ownerId,
          assetId: asset.id,
          assetCode: asset.assetCode,
          assetName: asset.assetName,
          type: operationTypeForStatus(status),
          operatorName,
          note: note || null,
          estimatedReturnDate: status === AssetStatus.CHECKED_OUT ? estimatedReturnDate : null
        }
      });
      changed.push({ ownerId: asset.ownerId, assetId: updated.id, recordId: record.id });
    }
    return changed;
  });

  for (const item of results) {
    void syncSingleStatusToFeishu(item.ownerId, item.assetId, item.recordId);
  }

  revalidatePath("/app");
  revalidatePath("/app/records");
}

export async function deleteAssetAction(formData: FormData) {
  const user = await requireUser();
  const ids = formData.getAll("assetIds").flatMap((value) => String(value).split(",")).map((id) => id.trim()).filter(Boolean);
  if (ids.length === 0) return;
  const admin = user.role === UserRole.ADMIN;

  const assets = await prisma.asset.findMany({
    where: { id: { in: ids }, ...(admin ? {} : { ownerId: user.id }) },
    select: { id: true, ownerId: true, assetCode: true }
  });
  if (assets.length === 0) return;
  await prisma.$transaction([
    prisma.operationRecord.deleteMany({
      where: { OR: ownerCodeFilters(assets) }
    }),
    prisma.asset.deleteMany({ where: { id: { in: assets.map((asset) => asset.id) }, ...(admin ? {} : { ownerId: user.id }) } })
  ]);

  for (const [ownerId, codes] of groupCodesByOwner(assets)) {
    void deleteAssetsFromFeishu(ownerId, codes);
  }

  revalidatePath("/app");
  revalidatePath("/app/records");
}

export async function deleteRecordAction(formData: FormData) {
  const user = await requireUser();
  const ids = formData.getAll("recordIds").flatMap((value) => String(value).split(",")).map((id) => id.trim()).filter(Boolean);
  if (ids.length === 0) return;
  await prisma.operationRecord.deleteMany({ where: { id: { in: ids }, ...(user.role === UserRole.ADMIN ? {} : { ownerId: user.id }) } });
  revalidatePath("/app/records");
}

export async function importAssetFileAction(formData: FormData) {
  const user = await requireUser();
  const uploads = formData.getAll("file").filter((upload): upload is File => upload instanceof File && upload.size > 0);
  const upload = uploads[0];
  if (!(upload instanceof File) || upload.size === 0) return;
  if (uploads.some((item) => item.name.toLowerCase().endsWith(".json"))) {
    await importSyncJsonAction(formData);
    return;
  }

  const fileName = stringValue(formData, "fileName") || upload.name;
  const rows = await readRowsFromUpload(upload);
  const imported = parseAssetRows(rows);
  if (imported.length === 0) return;

  const existingSource = await prisma.assetSource.findFirst({ where: { ownerId: user.id, fileName } });

  await prisma.$transaction(async (tx) => {
    const source = existingSource
      ? await tx.assetSource.update({ where: { id: existingSource.id }, data: { assetCount: imported.length } })
      : await tx.assetSource.create({ data: { ownerId: user.id, fileName, assetCount: imported.length } });

    const current = await tx.asset.findMany({ where: { ownerId: user.id, sourceId: source.id } });
    const currentByCode = new Map(current.map((asset) => [asset.assetCode, asset]));
    const importedCodes = new Set(imported.map((asset) => asset.assetCode));
    const removed = current.filter((asset) => !importedCodes.has(asset.assetCode));

    if (removed.length > 0) {
      await tx.operationRecord.deleteMany({
        where: { ownerId: user.id, assetCode: { in: removed.map((asset) => asset.assetCode) } }
      });
      await tx.asset.deleteMany({ where: { id: { in: removed.map((asset) => asset.id) } } });
    }

    for (const row of imported) {
      const existing = await tx.asset.findFirst({
        where: { ownerId: user.id, assetCode: row.assetCode }
      });
      const preserved = currentByCode.get(row.assetCode) ?? existing;
      const data = {
        assetName: row.assetName,
        modelName: row.modelName,
        brand: row.brand,
        internalCode: row.internalCode,
        location: row.location,
        purchaseDate: row.purchaseDate,
        note: row.note,
        sourceId: source.id,
        status: preserved?.status ?? row.status
      };

      if (existing) {
        await tx.asset.update({ where: { id: existing.id }, data });
      } else {
        await tx.asset.create({
          data: {
            ownerId: user.id,
            assetCode: row.assetCode,
            ...data
          }
        });
      }
    }
  });

  revalidatePath("/app");
  revalidatePath("/app/sources");
}

export async function deleteSourceAction(formData: FormData) {
  const user = await requireUser();
  const sourceId = stringValue(formData, "sourceId");
  const source = await prisma.assetSource.findFirst({
    where: { id: sourceId, ownerId: user.id },
    include: { assets: { select: { id: true, assetCode: true } } }
  });
  if (!source) return;

  await prisma.$transaction([
    prisma.operationRecord.deleteMany({
      where: { ownerId: user.id, assetCode: { in: source.assets.map((asset) => asset.assetCode) } }
    }),
    prisma.asset.deleteMany({ where: { id: { in: source.assets.map((asset) => asset.id) } } }),
    prisma.assetSource.delete({ where: { id: source.id } })
  ]);

  revalidatePath("/app");
  revalidatePath("/app/sources");
  revalidatePath("/app/records");
}

export async function importSyncJsonAction(formData: FormData) {
  const user = await requireUser();
  const uploads = [...formData.getAll("files"), ...formData.getAll("file")]
    .filter((upload): upload is File => upload instanceof File && upload.size > 0);
  if (uploads.length === 0) return;

  const payload: { assets?: any[]; records?: any[]; sources?: any[]; meta?: unknown } = {};
  for (const upload of uploads) {
    const json = JSON.parse(Buffer.from(await upload.arrayBuffer()).toString("utf8"));
    const name = upload.name.toLowerCase();
    if (name === "assets.json") payload.assets = Array.isArray(json) ? json : json.assets;
    else if (name === "records.json") payload.records = Array.isArray(json) ? json : json.records;
    else if (name === "sources.json") payload.sources = Array.isArray(json) ? json : json.sources;
    else if (name === "meta.json") payload.meta = json;
    else if (!Array.isArray(json) && (json.assets || json.records || json.sources)) {
      payload.assets = json.assets;
      payload.records = json.records;
      payload.sources = json.sources;
      payload.meta = json.meta;
    }
  }

  const sources = Array.isArray(payload.sources) ? payload.sources : [];
  const assets = Array.isArray(payload.assets) ? payload.assets : [];
  const records = Array.isArray(payload.records) ? payload.records : [];

  await prisma.$transaction(async (tx) => {
    for (const source of sources) {
      const fileName = String(source.fileName || "同步来源");
      const desktopSourceId = String(source.id || "").trim();
      const existing = desktopSourceId
        ? await tx.assetSource.findFirst({ where: { OR: [{ id: desktopSourceId }, { ownerId: user.id, fileName }] } })
        : await tx.assetSource.findUnique({ where: { ownerId_fileName: { ownerId: user.id, fileName } } });

      if (existing) {
        await tx.assetSource.update({
          where: { id: existing.id },
          data: { ownerId: user.id, fileName, assetCount: Number(source.assetCount || source.assetIds?.length || 0) }
        });
      } else {
        await tx.assetSource.create({
          data: {
            id: desktopSourceId || undefined,
            ownerId: user.id,
            fileName,
            assetCount: Number(source.assetCount || source.assetIds?.length || 0)
          }
        });
      }
    }

    for (const asset of assets) {
      const assetCode = String(asset.id || asset.assetCode || "").trim();
      if (!assetCode) continue;
      const sourceByAssetIds = sources.find((source) =>
        Array.isArray(source.assetIds) && source.assetIds.map((id: unknown) => String(id)).includes(assetCode)
      );
      const rawSourceId = String(asset.sourceId || sourceByAssetIds?.id || "").trim();
      const source = rawSourceId
        ? await tx.assetSource.findFirst({ where: { id: rawSourceId, ownerId: user.id } })
        : sourceByAssetIds?.fileName
          ? await tx.assetSource.findUnique({ where: { ownerId_fileName: { ownerId: user.id, fileName: String(sourceByAssetIds.fileName) } } })
          : null;
      await tx.asset.upsert({
        where: { ownerId_assetCode: { ownerId: user.id, assetCode } },
        create: {
          ownerId: user.id,
          assetCode,
          assetName: String(asset.assetName || asset.name || ""),
          modelName: String(asset.modelName || ""),
          brand: String(asset.brand || ""),
          status: statusFromText(String(asset.status || "")),
          internalCode: String(asset.internalCode || ""),
          location: String(asset.location || ""),
          purchaseDate: asset.purchaseDate ? new Date(asset.purchaseDate) : null,
          note: asset.note || null,
          sourceId: source?.id
        },
        update: {
          assetName: String(asset.assetName || asset.name || ""),
          modelName: String(asset.modelName || ""),
          brand: String(asset.brand || ""),
          status: statusFromText(String(asset.status || "")),
          internalCode: String(asset.internalCode || ""),
          location: String(asset.location || ""),
          purchaseDate: asset.purchaseDate ? new Date(asset.purchaseDate) : null,
          note: asset.note || null,
          sourceId: source?.id
        }
      });
    }

    for (const record of records) {
      const assetCode = String(record.assetId || record.assetCode || "").trim();
      if (!assetCode) continue;
      const asset = await tx.asset.findUnique({ where: { ownerId_assetCode: { ownerId: user.id, assetCode } } });
      const id = String(record.id || globalThis.crypto.randomUUID());
      await tx.operationRecord.upsert({
        where: { id },
        create: {
          id,
          ownerId: user.id,
          assetId: asset?.id,
          assetCode,
          assetName: String(record.assetName || ""),
          type: operationTypeFromText(String(record.type || "")),
          operatorName: String(record.operatorName || record.operator || user.name),
          createdAt: record.timestamp ? new Date(record.timestamp) : new Date(),
          note: record.note || null,
          estimatedReturnDate: record.estimatedReturnDate ? new Date(record.estimatedReturnDate) : null,
          isSyncedToReminders: Boolean(record.isSyncedToReminders)
        },
        update: {
          assetId: asset?.id,
          assetName: String(record.assetName || ""),
          type: operationTypeFromText(String(record.type || "")),
          operatorName: String(record.operatorName || record.operator || user.name),
          createdAt: record.timestamp ? new Date(record.timestamp) : new Date(),
          note: record.note || null,
          estimatedReturnDate: record.estimatedReturnDate ? new Date(record.estimatedReturnDate) : null,
          isSyncedToReminders: Boolean(record.isSyncedToReminders)
        }
      });
    }
  });

  revalidatePath("/app");
  revalidatePath("/app/sources");
  revalidatePath("/app/records");
}

export async function requestTransferAction(formData: FormData) {
  const user = await requireUser();
  const assetId = stringValue(formData, "assetId");
  const toUserId = stringValue(formData, "toUserId");
  const note = stringValue(formData, "note");

  const asset = await prisma.asset.findFirst({ where: await accessibleAssetWhere(user.id, assetId) });
  if (!asset || !toUserId || toUserId === asset.ownerId) return;

  await prisma.assetTransfer.create({
    data: {
      assetId: asset.id,
      fromUserId: asset.ownerId,
      toUserId,
      requestedById: user.id,
      note: note || null
    }
  });
  revalidatePath("/app/transfers");
}

export async function decideTransferAction(formData: FormData) {
  const user = await requireUser();
  const transferId = stringValue(formData, "transferId");
  const decision = stringValue(formData, "decision");

  const transfer = await prisma.assetTransfer.findFirst({
    where: { id: transferId, toUserId: user.id, status: TransferStatus.PENDING },
    include: { asset: true }
  });
  if (!transfer) return;

  if (decision === "accept") {
    const result = await prisma.$transaction(async (tx) => {
      await tx.asset.update({
        where: { id: transfer.assetId },
        data: { ownerId: user.id, sourceId: null }
      });
      await tx.assetTransfer.update({
        where: { id: transfer.id },
        data: { status: TransferStatus.ACCEPTED, decidedAt: new Date() }
      });
      await tx.operationRecord.create({
        data: {
          ownerId: transfer.fromUserId,
          assetId: transfer.assetId,
          assetCode: transfer.asset.assetCode,
          assetName: transfer.asset.assetName,
          type: OperationType.TRANSFER_OUT,
          operatorName: user.name,
          note: `转移给 ${user.name}`
        }
      });
      const inRecord = await tx.operationRecord.create({
        data: {
          ownerId: user.id,
          assetId: transfer.assetId,
          assetCode: transfer.asset.assetCode,
          assetName: transfer.asset.assetName,
          type: OperationType.TRANSFER_IN,
          operatorName: user.name,
          note: "接收账户间转移"
        }
      });
      return { inRecordId: inRecord.id };
    });
    void transferAssetInFeishu(transfer.fromUserId, user.id, transfer.asset.assetCode, transfer.assetId, result.inRecordId);
  } else {
    await prisma.assetTransfer.update({
      where: { id: transfer.id },
      data: { status: TransferStatus.REJECTED, decidedAt: new Date() }
    });
  }

  revalidatePath("/app/transfers");
  revalidatePath("/app");
  revalidatePath("/app/records");
}
export async function saveFeishuConfigAction(formData: FormData) {
  const user = await requireUser();
  const assetTableLink = stringValue(formData, "assetTableLink");
  const recordTableLink = stringValue(formData, "recordTableLink");
  const assetParsed = extractFeishuTableConfig(assetTableLink);
  const recordParsed = extractFeishuTableConfig(recordTableLink);
  const existing = await prisma.feishuConfig.findUnique({ where: { ownerId: user.id } });
  const appId = user.role === UserRole.ADMIN ? stringValue(formData, "appId") : "";
  const appSecretCipher = user.role === UserRole.ADMIN ? stringValue(formData, "appSecret") : "";

  await prisma.feishuConfig.upsert({
    where: { ownerId: user.id },
    create: {
      ownerId: user.id,
      appId,
      appSecretCipher,
      assetTableLink,
      recordTableLink,
      assetAppToken: assetParsed?.appToken || stringValue(formData, "assetAppToken"),
      assetTableId: assetParsed?.tableId || stringValue(formData, "assetTableId"),
      recordAppToken: recordParsed?.appToken || stringValue(formData, "recordAppToken"),
      recordTableId: recordParsed?.tableId || stringValue(formData, "recordTableId")
    },
    update: {
      appId,
      appSecretCipher,
      assetTableLink,
      recordTableLink,
      assetAppToken: assetParsed?.appToken || stringValue(formData, "assetAppToken"),
      assetTableId: assetParsed?.tableId || stringValue(formData, "assetTableId"),
      recordAppToken: recordParsed?.appToken || stringValue(formData, "recordAppToken"),
      recordTableId: recordParsed?.tableId || stringValue(formData, "recordTableId")
    }
  });

  revalidatePath("/app/settings");
}

async function feishuClientForCurrentUser() {
  const user = await requireUser();
  const config = await effectiveFeishuConfig(user.id);
  if (!config) return { user, client: null };
  return { user, client: new FeishuBitableClient(config) };
}

export async function testFeishuAction() {
  const { client } = await feishuClientForCurrentUser();
  if (!client) return;
  await client.testConnection().catch((error) => console.error("Feishu test failed", error));
  revalidatePath("/app/settings");
}

async function runFeishuFullSync(userId: string) {
  const config = await effectiveFeishuConfig(userId);
  if (!config) return;
  const [assets, records] = await Promise.all([
    prisma.asset.findMany({ where: { ownerId: userId } }),
    prisma.operationRecord.findMany({ where: { ownerId: userId } })
  ]);
  await new FeishuBitableClient(config).syncAll(assets, records).catch((error) => console.error("Feishu full sync failed", error));
}

export async function syncToFeishuAction() {
  const user = await requireUser();
  void runFeishuFullSync(user.id);
  revalidatePath("/app/settings");
}

export async function importFromFeishuAction() {
  const { user, client } = await feishuClientForCurrentUser();
  if (!client) return;
  const remote = await client.importRemote().catch((error) => {
    console.error("Feishu import failed", error);
    return null;
  });
  if (!remote) return;

  for (const asset of remote.assets) {
    await prisma.asset.upsert({
      where: { ownerId_assetCode: { ownerId: user.id, assetCode: asset.assetCode } },
      create: { ownerId: user.id, ...asset },
      update: asset
    });
  }
  for (const record of remote.records) {
    const asset = await prisma.asset.findUnique({ where: { ownerId_assetCode: { ownerId: user.id, assetCode: record.assetCode } } });
    await prisma.operationRecord.upsert({
      where: { id: record.id },
      create: { ownerId: user.id, assetId: asset?.id, ...record },
      update: { assetId: asset?.id, ...record }
    });
  }

  revalidatePath("/app");
  revalidatePath("/app/records");
  revalidatePath("/app/settings");
}

export async function bidirectionalFeishuAction() {
  await importFromFeishuAction();
  const user = await requireUser();
  void runFeishuFullSync(user.id);
  revalidatePath("/app/settings");
}

