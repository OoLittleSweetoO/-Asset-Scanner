import { AssetStatus, OperationType, type Asset, type FeishuConfig, type OperationRecord } from "@prisma/client";
import { operationTypeFromText, operationTypeToText, statusFromText, statusToText } from "./asset-io";

const baseUrl = "https://open.feishu.cn/open-apis";

type RemoteRecord = {
  record_id: string;
  fields: Record<string, unknown>;
};

type FieldSpec = {
  name: string;
  type: number;
  property?: Record<string, unknown>;
};

const assetFieldSpecs: FieldSpec[] = [
  { name: "资产属性", type: 1 },
  { name: "名称", type: 1 },
  { name: "型号", type: 1 },
  { name: "品牌", type: 1 },
  { name: "外编号", type: 1 },
  { name: "内编号", type: 1 },
  { name: "保管科室", type: 1 },
  { name: "资产专管", type: 1 },
  { name: "保管人", type: 1 },
  { name: "使用人", type: 1 },
  { name: "一级状态", type: 1 },
  { name: "二级状态", type: 1 },
  { name: "一级存放地", type: 1 },
  { name: "二级存放地", type: 1 },
  { name: "其他附件", type: 1 },
  { name: "备注", type: 1 }
];

const recordFieldSpecs: FieldSpec[] = [
  { name: "记录ID", type: 1 },
  { name: "资产名称", type: 1 },
  { name: "外编号", type: 1 },
  { name: "型号", type: 1 },
  { name: "品牌", type: 1 },
  { name: "操作类型", type: 1 },
  { name: "操作人", type: 1 },
  { name: "操作时间", type: 5, property: { date_formatter: "yyyy/MM/dd HH:mm", auto_fill: false } },
  { name: "备注", type: 1 },
  { name: "预计归还", type: 5, property: { date_formatter: "yyyy/MM/dd HH:mm", auto_fill: false } }
];

export class FeishuBitableClient {
  private token = "";
  private tokenExpiresAt = 0;
  private assetFields = new Set<string>();
  private recordFields = new Set<string>();

  constructor(private readonly config: FeishuConfig) {}

  get canSyncAssets() {
    return Boolean(this.config.appId && this.config.appSecretCipher && this.config.assetAppToken && this.config.assetTableId);
  }

  get canSyncRecords() {
    return Boolean(this.config.appId && this.config.appSecretCipher && this.config.recordAppToken && this.config.recordTableId);
  }

  async testConnection() {
    await this.ensureToken();
    const assets = this.canSyncAssets ? await this.fieldNames(this.config.assetAppToken, this.config.assetTableId) : [];
    const records = this.canSyncRecords ? await this.fieldNames(this.config.recordAppToken, this.config.recordTableId) : [];
    return {
      assetMissing: assetFieldSpecs.map((field) => field.name).filter((field) => !assets.includes(field)),
      recordMissing: recordFieldSpecs.map((field) => field.name).filter((field) => !records.includes(field))
    };
  }

  async syncAll(assets: Asset[], records: OperationRecord[]) {
    if (!this.canSyncAssets || !this.canSyncRecords) throw new Error("飞书资产表或记录表配置不完整");
    await this.ensureSchema();

    const assetIndex = await this.recordIndex(this.config.assetAppToken, this.config.assetTableId, "外编号");
    const recordIndex = await this.recordIndex(this.config.recordAppToken, this.config.recordTableId, "记录ID");

    for (const asset of assets) {
      await this.upsert(
        this.config.assetAppToken,
        this.config.assetTableId,
        this.filterFields(this.assetPayload(asset), this.assetFields),
        assetIndex.get(asset.assetCode)
      );
    }

    for (const record of records) {
      await this.upsert(
        this.config.recordAppToken,
        this.config.recordTableId,
        this.filterFields(this.recordPayload(record), this.recordFields),
        recordIndex.get(record.id)
      );
    }

    return { assetCount: assets.length, recordCount: records.length };
  }

  async syncSingleAsset(asset: Asset, record?: OperationRecord | null) {
    if (!this.canSyncAssets) return;
    await this.ensureSchema();
    const recordId = await this.searchOne(this.config.assetAppToken, this.config.assetTableId, "外编号", asset.assetCode);
    await this.upsert(
      this.config.assetAppToken,
      this.config.assetTableId,
      this.filterFields(this.assetPayload(asset), this.assetFields),
      recordId
    );

    if (record && this.canSyncRecords) {
      const opRecordId = await this.searchOne(this.config.recordAppToken, this.config.recordTableId, "记录ID", record.id);
      await this.upsert(
        this.config.recordAppToken,
        this.config.recordTableId,
        this.filterFields(this.recordPayload(record), this.recordFields),
        opRecordId
      );
    }
  }

  async deleteAssetByCode(assetCode: string) {
    if (!this.canSyncAssets) return;
    await this.ensureSchema();
    const recordId = await this.searchOne(this.config.assetAppToken, this.config.assetTableId, "外编号", assetCode);
    if (recordId) {
      await this.send(`/bitable/v1/apps/${this.config.assetAppToken}/tables/${this.config.assetTableId}/records/${recordId}`, { method: "DELETE" });
    }
  }

  async importRemote() {
    await this.ensureToken();
    const assets: Array<Pick<Asset, "assetCode" | "assetName" | "modelName" | "brand" | "status" | "internalCode" | "location" | "note">> = [];
    const records: Array<Pick<OperationRecord, "id" | "assetCode" | "assetName" | "type" | "operatorName" | "createdAt" | "note" | "estimatedReturnDate">> = [];

    if (this.canSyncAssets) {
      const remoteAssets = await this.allRecords(this.config.assetAppToken, this.config.assetTableId);
      for (const item of remoteAssets) {
        const code = value(item.fields["外编号"]);
        if (!code) continue;
        assets.push({
          assetCode: code,
          assetName: value(item.fields["名称"]),
          modelName: value(item.fields["型号"]),
          brand: value(item.fields["品牌"]),
          status: statusFromText(value(item.fields["一级状态"])) as AssetStatus,
          internalCode: value(item.fields["内编号"]),
          location: value(item.fields["一级存放地"]),
          note: noteFromAssetFields(item.fields)
        });
      }
    }

    if (this.canSyncRecords) {
      const remoteRecords = await this.allRecords(this.config.recordAppToken, this.config.recordTableId);
      for (const item of remoteRecords) {
        const code = value(item.fields["外编号"]);
        if (!code) continue;
        records.push({
          id: value(item.fields["记录ID"]) || item.record_id,
          assetCode: code,
          assetName: value(item.fields["资产名称"]),
          type: operationTypeFromText(value(item.fields["操作类型"])) as OperationType,
          operatorName: value(item.fields["操作人"]) || "当前用户",
          createdAt: dateValue(item.fields["操作时间"]) ?? new Date(),
          note: value(item.fields["备注"]) || null,
          estimatedReturnDate: dateValue(item.fields["预计归还"])
        });
      }
    }

    return { assets, records };
  }

  private async ensureSchema() {
    if (this.canSyncAssets) this.assetFields = await this.ensureFields(this.config.assetAppToken, this.config.assetTableId, assetFieldSpecs);
    if (this.canSyncRecords) this.recordFields = await this.ensureFields(this.config.recordAppToken, this.config.recordTableId, recordFieldSpecs);
  }

  private async ensureFields(appToken: string, tableId: string, specs: FieldSpec[]) {
    const existing = new Set(await this.fieldNames(appToken, tableId));
    for (const spec of specs) {
      if (existing.has(spec.name)) continue;
      const body: Record<string, unknown> = { field_name: spec.name, type: spec.type };
      if (spec.property) body.property = spec.property;
      await this.send(`/bitable/v1/apps/${appToken}/tables/${tableId}/fields`, { method: "POST", body });
      existing.add(spec.name);
    }
    return existing;
  }

  private async fieldNames(appToken: string, tableId: string) {
    const json = await this.send(`/bitable/v1/apps/${appToken}/tables/${tableId}/fields?page_size=500`);
    const items = (json.data?.items ?? []) as Array<{ field_name?: string }>;
    return items.map((item) => item.field_name).filter(Boolean) as string[];
  }

  private async recordIndex(appToken: string, tableId: string, fieldName: string) {
    const records = await this.allRecords(appToken, tableId);
    const entries: Array<[string, string]> = [];
    for (const record of records) {
      const key = value(record.fields[fieldName]);
      if (key) entries.push([key, record.record_id]);
    }
    return new Map(entries);
  }

  private async searchOne(appToken: string, tableId: string, fieldName: string, fieldValue: string) {
    const body = {
      field_names: [fieldName],
      filter: { conjunction: "and", conditions: [{ field_name: fieldName, operator: "is", value: [fieldValue] }] },
      automatic_fields: false
    };
    const json = await this.send(`/bitable/v1/apps/${appToken}/tables/${tableId}/records/search?page_size=2`, { method: "POST", body });
    return (json.data?.items?.[0] as RemoteRecord | undefined)?.record_id;
  }

  private async allRecords(appToken: string, tableId: string) {
    const records: RemoteRecord[] = [];
    let pageToken = "";
    do {
      const suffix = pageToken ? `&page_token=${encodeURIComponent(pageToken)}` : "";
      const json = await this.send(`/bitable/v1/apps/${appToken}/tables/${tableId}/records?page_size=500${suffix}`);
      records.push(...((json.data?.items ?? []) as RemoteRecord[]));
      pageToken = json.data?.has_more ? json.data?.page_token ?? "" : "";
    } while (pageToken);
    return records;
  }

  private async upsert(appToken: string, tableId: string, fields: Record<string, unknown>, recordId?: string) {
    if (recordId) {
      await this.send(`/bitable/v1/apps/${appToken}/tables/${tableId}/records/${recordId}`, { method: "PUT", body: { fields } });
    } else {
      await this.send(`/bitable/v1/apps/${appToken}/tables/${tableId}/records`, { method: "POST", body: { fields } });
    }
  }

  private assetPayload(asset: Asset) {
    return {
      资产属性: "固定资产",
      名称: asset.assetName,
      型号: asset.modelName,
      品牌: asset.brand,
      外编号: asset.assetCode,
      内编号: asset.internalCode,
      一级状态: statusToText(asset.status),
      一级存放地: asset.location,
      备注: asset.note ?? ""
    };
  }

  private recordPayload(record: OperationRecord) {
    return {
      记录ID: record.id,
      资产名称: record.assetName,
      外编号: record.assetCode,
      操作类型: operationTypeToText(record.type),
      操作人: record.operatorName,
      操作时间: record.createdAt.getTime(),
      备注: record.note ?? "",
      预计归还: record.estimatedReturnDate?.getTime() ?? null
    };
  }

  private filterFields(fields: Record<string, unknown>, available: Set<string>) {
    const result: Record<string, unknown> = {};
    for (const [key, raw] of Object.entries(fields)) {
      if (!available.has(key) || raw === undefined || raw === null) continue;
      result[key] = raw;
    }
    return result;
  }

  private async ensureToken() {
    if (this.token && this.tokenExpiresAt > Date.now() + 5 * 60 * 1000) return;
    const response = await fetch(`${baseUrl}/auth/v3/tenant_access_token/internal`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ app_id: this.config.appId, app_secret: this.config.appSecretCipher })
    });
    const json = await response.json();
    if (json.code !== 0) throw new Error(`飞书认证失败：${json.msg || response.statusText}`);
    this.token = json.tenant_access_token;
    this.tokenExpiresAt = Date.now() + (json.expire ?? 7200) * 1000;
  }

  private async send(path: string, init: { method?: string; body?: unknown } = {}) {
    await this.ensureToken();
    const response = await fetch(`${baseUrl}${path}`, {
      method: init.method ?? "GET",
      headers: {
        Authorization: `Bearer ${this.token}`,
        "Content-Type": "application/json"
      },
      body: init.body ? JSON.stringify(init.body) : undefined
    });
    const json = await response.json();
    if (json.code !== 0) throw new Error(`飞书 API 错误：${json.msg || response.statusText}`);
    return json;
  }
}

function value(raw: unknown): string {
  if (raw == null) return "";
  if (Array.isArray(raw)) {
    return raw
      .map((item) => value(typeof item === "object" ? (item as Record<string, unknown>).text ?? (item as Record<string, unknown>).name : item))
      .filter(Boolean)
      .join(",");
  }
  if (typeof raw === "object") return value((raw as Record<string, unknown>).text ?? (raw as Record<string, unknown>).name);
  return String(raw).trim();
}

function dateValue(raw: unknown) {
  const textValue = value(raw);
  if (!textValue) return null;
  const numeric = Number(textValue);
  if (Number.isFinite(numeric) && numeric > 1000000000) return new Date(numeric);
  const date = new Date(textValue);
  return Number.isNaN(date.getTime()) ? null : date;
}

function noteFromAssetFields(fields: Record<string, unknown>) {
  const labels = ["保管科室", "资产专管", "保管人", "使用人", "二级状态", "二级存放地", "其他附件", "备注"];
  const lines = labels
    .map((label) => [label, value(fields[label])] as const)
    .filter(([, item]) => item)
    .map(([label, item]) => `${label}：${item}`);
  return lines.length ? lines.join("\n") : null;
}
