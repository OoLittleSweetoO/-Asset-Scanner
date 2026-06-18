import { AssetStatus, OperationType, type Asset, type AssetSource, type OperationRecord } from "@prisma/client";
import * as XLSX from "xlsx";

export type ParsedAssetRow = {
  assetCode: string;
  assetName: string;
  modelName: string;
  brand: string;
  status: AssetStatus;
  internalCode: string;
  location: string;
  purchaseDate: Date | null;
  note: string | null;
};

type Row = Record<string, unknown>;

function text(value: unknown) {
  return String(value ?? "").trim();
}

function first(row: Row, keys: string[]) {
  for (const key of keys) {
    const value = text(row[key]);
    if (value) return value;
  }
  return "";
}

export function statusFromText(value: string): AssetStatus {
  const normalized = value.trim().toLowerCase();
  if (["已出库", "出库", "checkedout", "checked_out", "1"].includes(normalized)) return "CHECKED_OUT";
  if (["送修", "维修中", "maintenance", "2"].includes(normalized)) return "MAINTENANCE";
  if (["待报废", "报废", "scrapped", "3"].includes(normalized)) return "SCRAPPED";
  return "IN_STOCK";
}

export function statusToText(status: AssetStatus) {
  return {
    IN_STOCK: "在库",
    CHECKED_OUT: "已出库",
    MAINTENANCE: "送修",
    SCRAPPED: "待报废"
  }[status];
}

export function operationTypeToText(type: OperationType) {
  return {
    CHECK_IN: "入库",
    CHECK_OUT: "出库",
    REPAIR: "送修",
    SCRAP: "报废",
    TRANSFER_OUT: "转出",
    TRANSFER_IN: "转入"
  }[type];
}

export function operationTypeFromText(value: string): OperationType {
  const normalized = value.trim().toLowerCase();
  if (["出库", "checkout", "check_out", "1"].includes(normalized)) return "CHECK_OUT";
  if (["送修", "repair", "2"].includes(normalized)) return "REPAIR";
  if (["报废", "scrap", "3"].includes(normalized)) return "SCRAP";
  if (["转出", "transfer_out"].includes(normalized)) return "TRANSFER_OUT";
  if (["转入", "transfer_in"].includes(normalized)) return "TRANSFER_IN";
  return "CHECK_IN";
}

function parseDate(value: string) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function parseAssetRows(rows: Row[]) {
  const parsed: ParsedAssetRow[] = [];
  const reserved = new Set<string>();

  rows.forEach((row, index) => {
    const rawCode = first(row, ["外编号", "条码", "资产编号", "barcode", "id", "assetCode"]);
    const assetName = first(row, ["名称", "资产名称", "name", "assetName"]);
    const internalCode = first(row, ["内编号", "internalCode"]);
    const baseCode = rawCode || internalCode || assetName || `NO-CODE-${index + 1}`;
    let assetCode = baseCode;
    let suffix = Math.max(index + 1, 2);
    while (reserved.has(assetCode)) {
      assetCode = `${baseCode}#${suffix++}`;
    }
    reserved.add(assetCode);

    if (!assetCode || !assetName) return;

    parsed.push({
      assetCode,
      assetName,
      modelName: first(row, ["型号", "model", "modelName"]),
      brand: first(row, ["品牌", "brand"]),
      status: statusFromText(first(row, ["一级状态", "状态", "status"])),
      internalCode,
      location: first(row, ["一级存放地", "存放位置", "location"]),
      purchaseDate: parseDate(first(row, ["采购日期", "purchaseDate"])),
      note: first(row, ["备注", "note"]) || buildStructuredNote(row)
    });
  });

  return parsed;
}

function buildStructuredNote(row: Row) {
  const labels = ["保管科室", "资产专管", "保管人", "使用人", "二级状态", "二级存放地", "其他附件"];
  const lines = labels
    .map((label) => [label, text(row[label])] as const)
    .filter(([, value]) => value)
    .map(([label, value]) => `${label}：${value}`);
  return lines.length ? lines.join("\n") : null;
}

export async function readRowsFromUpload(file: File) {
  const bytes = Buffer.from(await file.arrayBuffer());
  const workbook = XLSX.read(bytes, { type: "buffer", raw: false, cellDates: true });
  const sheet = workbook.Sheets[workbook.SheetNames[0]];
  if (!sheet) return [];
  return XLSX.utils.sheet_to_json<Row>(sheet, { defval: "" });
}

export function workbookBuffer(rows: Record<string, unknown>[], sheetName: string) {
  const workbook = XLSX.utils.book_new();
  const sheet = XLSX.utils.json_to_sheet(rows);
  XLSX.utils.book_append_sheet(workbook, sheet, sheetName);
  return XLSX.write(workbook, { type: "buffer", bookType: "xlsx" }) as Buffer;
}

export function csvBuffer(rows: Record<string, unknown>[]) {
  const sheet = XLSX.utils.json_to_sheet(rows);
  return Buffer.from("\ufeff" + XLSX.utils.sheet_to_csv(sheet), "utf8");
}

export function assetExportRows(assets: Asset[]) {
  return assets.map((asset) => ({
    外编号: asset.assetCode,
    名称: asset.assetName,
    型号: asset.modelName,
    品牌: asset.brand,
    一级状态: statusToText(asset.status),
    内编号: asset.internalCode,
    一级存放地: asset.location,
    采购日期: asset.purchaseDate ? asset.purchaseDate.toISOString().slice(0, 10) : "",
    备注: asset.note ?? "",
    最后更新: asset.updatedAt.toISOString()
  }));
}

export function recordExportRows(records: OperationRecord[]) {
  return records.map((record) => ({
    id: record.id,
    外编号: record.assetCode,
    名称: record.assetName,
    类型: operationTypeToText(record.type),
    操作人: record.operatorName,
    时间: record.createdAt.toISOString(),
    备注: record.note ?? "",
    预计归还时间: record.estimatedReturnDate ? record.estimatedReturnDate.toISOString() : "",
    Outlook: record.isSyncedToReminders ? "已同步" : ""
  }));
}

export function syncJsonPayload(
  assets: Asset[],
  records: OperationRecord[],
  sources: (AssetSource & { assets: Pick<Asset, "assetCode">[] })[]
) {
  return {
    assets: assets.map((asset) => ({
      id: asset.assetCode,
      assetName: asset.assetName,
      modelName: asset.modelName,
      brand: asset.brand,
      status: statusToText(asset.status),
      internalCode: asset.internalCode,
      location: asset.location,
      purchaseDate: asset.purchaseDate?.toISOString() ?? null,
      note: asset.note,
      lastUpdated: asset.updatedAt.toISOString(),
      sourceId: asset.sourceId
    })),
    records: records.map((record) => ({
      id: record.id,
      assetId: record.assetCode,
      assetName: record.assetName,
      type: operationTypeToText(record.type),
      operatorName: record.operatorName,
      timestamp: record.createdAt.toISOString(),
      note: record.note,
      estimatedReturnDate: record.estimatedReturnDate?.toISOString() ?? null,
      isSyncedToReminders: record.isSyncedToReminders
    })),
    sources: sources.map((source) => ({
      id: source.id,
      fileName: source.fileName,
      importDate: source.createdAt.toISOString(),
      assetCount: source.assetCount,
      assetIds: source.assets.map((asset) => asset.assetCode)
    })),
    meta: {
      lastSyncTimestamp: Date.now() / 1000,
      lastImportTimestamp: null
    }
  };
}
