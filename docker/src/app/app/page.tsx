import { AssetStatus } from "@prisma/client";
import { requireUser } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { dateText, statusText } from "@/lib/format";
import { bulkAssetOperationAction, createAssetAction, importAssetFileAction } from "./actions";
import { AssetBarcodeScanner } from "./AssetBarcodeScanner";
import { BulkAssetActions } from "./BulkAssetActions";

function pillClass(status: AssetStatus) {
  if (status === "IN_STOCK") return "pill green";
  if (status === "CHECKED_OUT") return "pill";
  if (status === "MAINTENANCE") return "pill orange";
  return "pill red";
}

export default async function AssetsPage({
  searchParams
}: {
  searchParams: { q?: string; status?: AssetStatus; operate?: string };
}) {
  const user = await requireUser();
  const isAdmin = user.role === "ADMIN";
  const q = (searchParams.q ?? "").trim();
  const status = searchParams.status;
  const where = {
    ...(isAdmin ? {} : { ownerId: user.id }),
    ...(status ? { status } : {}),
    ...(q
      ? {
          OR: [
            { assetCode: { contains: q } },
            { assetName: { contains: q } },
            { modelName: { contains: q } },
            { brand: { contains: q } },
            { internalCode: { contains: q } },
            { location: { contains: q } }
          ]
        }
      : {})
  };

  const [assets, users, counts, records] = await Promise.all([
    prisma.asset.findMany({
      where,
      include: { source: true, owner: { select: { name: true, email: true } } },
      orderBy: { updatedAt: "desc" }
    }),
    prisma.user.findMany({
      where: isAdmin ? {} : { id: { not: user.id } },
      orderBy: { name: "asc" },
      select: { id: true, name: true, email: true }
    }),
    prisma.asset.groupBy({
      by: ["status"],
      where: isAdmin ? {} : { ownerId: user.id },
      _count: { status: true }
    }),
    prisma.operationRecord.findMany({
      where: isAdmin ? {} : { ownerId: user.id },
      orderBy: { createdAt: "desc" },
      take: 8
    })
  ]);

  const countMap = Object.fromEntries(counts.map((item) => [item.status, item._count.status]));
  const exactAssetCodeQuery = q.toLowerCase();
  const autoOpenOperation = searchParams.operate === "1";

  return (
    <>
      <div className="topbar clean-topbar">
        <div>
          <p className="eyebrow">固定资产</p>
          <h1>资产管理</h1>
        </div>
      </div>

      <section className="stats compact-stats">
        <div className="stat">
          <span>全部资产</span>
          <strong>{assets.length}</strong>
        </div>
        <div className="stat">
          <span>在库</span>
          <strong>{countMap.IN_STOCK || 0}</strong>
        </div>
        <div className="stat">
          <span>已出库</span>
          <strong>{countMap.CHECKED_OUT || 0}</strong>
        </div>
        <div className="stat">
          <span>异常状态</span>
          <strong>{(countMap.MAINTENANCE || 0) + (countMap.SCRAPPED || 0)}</strong>
        </div>
      </section>

      <section className="panel panel-pad workspace-panel">
        <div className="workspace-tabs">
          <input id="tab-assets" name="asset-workspace-tab" type="radio" defaultChecked />
          <input id="tab-import" name="asset-workspace-tab" type="radio" />
          <input id="tab-create" name="asset-workspace-tab" type="radio" />
          <input id="tab-recent" name="asset-workspace-tab" type="radio" />

          <div className="tab-labels">
            <label htmlFor="tab-assets">资产列表</label>
            <label htmlFor="tab-import">导入</label>
            <label htmlFor="tab-create">添加资产</label>
            <label htmlFor="tab-recent">最近记录</label>
          </div>

          <div className="tab-content tab-assets">
            <form className="asset-filter-row">
              <input className="input" name="q" placeholder="搜索资产" defaultValue={q} />
              <select className="select" name="status" defaultValue={status ?? ""} aria-label="状态筛选">
                <option value="">全部状态</option>
                <option value="IN_STOCK">在库</option>
                <option value="CHECKED_OUT">已出库</option>
                <option value="MAINTENANCE">送修</option>
                <option value="SCRAPPED">待报废</option>
              </select>
              <button className="button secondary" type="submit">
                筛选
              </button>
            </form>

            <div className="asset-action-row">
              <AssetBarcodeScanner />
              <a className="button secondary" href="/api/export?type=sync">
                导出同步文件
              </a>
              <a className="button secondary" href="/api/export?type=assets&format=xlsx">
                导出 Excel
              </a>
              <BulkAssetActions users={users} currentUserName={user.name} action={bulkAssetOperationAction} autoOpen={autoOpenOperation} />
            </div>

            <div className="asset-list scroll-list clean-list">
              {assets.length === 0 ? <p className="muted">还没有资产，先导入文件或手动添加一条。</p> : null}
              {assets.map((asset) => (
                <article className="asset-row asset-row-selectable" key={asset.id}>
                  <label className="checkline">
                    <input
                      data-asset-select="true"
                      type="checkbox"
                      value={asset.id}
                      aria-label={`选择 ${asset.assetName}`}
                      defaultChecked={Boolean(exactAssetCodeQuery && asset.assetCode.toLowerCase() === exactAssetCodeQuery)}
                    />
                  </label>
                  <div>
                    <div className="asset-title">
                      <span className={pillClass(asset.status)}>{statusText(asset.status)}</span>
                      {asset.assetName}
                    </div>
                    <div className="meta">
                      <span>外编号：{asset.assetCode}</span>
                      <span>型号：{asset.modelName || "-"}</span>
                      <span>品牌：{asset.brand || "-"}</span>
                      <span>位置：{asset.location || "-"}</span>
                      {isAdmin ? <span>账户：{asset.owner.name || asset.owner.email}</span> : null}
                      <span>来源：{asset.source?.fileName || "-"}</span>
                      <span>更新：{dateText(asset.updatedAt)}</span>
                    </div>
                  </div>
                </article>
              ))}
            </div>
          </div>

          <div className="tab-content tab-import">
            <div className="tab-section-head">
              <h2>导入 Excel / CSV / 同步 JSON</h2>
            </div>
            <form className="form clean-form" action={importAssetFileAction}>
              <input className="input" type="file" name="file" accept=".xlsx,.xls,.csv,.json" multiple required />
              <input className="input" name="fileName" placeholder="来源名称，留空使用文件名" />
              <button className="button blue" type="submit">
                导入或更新来源
              </button>
            </form>
          </div>

          <div className="tab-content tab-create">
            <div className="tab-section-head">
              <h2>添加资产</h2>
            </div>
            <form className="form clean-form asset-create-grid" action={createAssetAction}>
              <div className="field">
                <label>外编号</label>
                <input className="input" name="assetCode" required />
              </div>
              <div className="field">
                <label>名称</label>
                <input className="input" name="assetName" required />
              </div>
              <div className="field">
                <label>型号</label>
                <input className="input" name="modelName" />
              </div>
              <div className="field">
                <label>品牌</label>
                <input className="input" name="brand" />
              </div>
              <div className="field">
                <label>内编号</label>
                <input className="input" name="internalCode" />
              </div>
              <div className="field">
                <label>存放地</label>
                <input className="input" name="location" />
              </div>
              <div className="field">
                <label>采购日期</label>
                <input className="input" type="date" name="purchaseDate" />
              </div>
              <div className="field full-span">
                <label>备注</label>
                <textarea className="textarea" name="note" />
              </div>
              <button className="button blue" type="submit">
                添加
              </button>
            </form>
          </div>

          <div className="tab-content tab-recent">
            <div className="tab-section-head">
              <h2>最近记录</h2>
            </div>
            <div className="asset-list clean-list">
              {records.map((record) => (
                <div className="asset-row slim" key={record.id}>
                  <div>
                    <strong>{record.assetName}</strong>
                    <div className="meta">
                      <span>{record.assetCode}</span>
                      <span>{dateText(record.createdAt)}</span>
                    </div>
                  </div>
                </div>
              ))}
              {records.length === 0 ? <p className="muted">暂无操作记录。</p> : null}
            </div>
          </div>
        </div>
      </section>
    </>
  );
}
