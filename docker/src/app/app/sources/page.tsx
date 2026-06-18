import { requireUser } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { dateText } from "@/lib/format";
import { deleteSourceAction, importAssetFileAction, importSyncJsonAction } from "../actions";

export default async function SourcesPage() {
  const user = await requireUser();
  const sources = await prisma.assetSource.findMany({
    where: { ownerId: user.id },
    include: { assets: { orderBy: { updatedAt: "desc" }, take: 5 } },
    orderBy: { updatedAt: "desc" }
  });

  return (
    <>
      <div className="topbar">
        <div>
          <p className="eyebrow">文件导入</p>
          <h1>导入来源</h1>
        </div>
        <a className="button secondary" href="/api/export?type=sync">下载同步 JSON</a>
      </div>

      <div className="grid grid-2">
        <section className="panel panel-pad">
          <h2 style={{ marginBottom: 14 }}>来源列表</h2>
          <div className="asset-list scroll-list">
            {sources.map((source) => (
              <article className="asset-row" key={source.id}>
                <div>
                  <div className="asset-title">{source.fileName}</div>
                  <div className="meta">
                    <span>{source.assetCount} 个资产</span>
                    <span>导入：{dateText(source.createdAt)}</span>
                    <span>更新：{dateText(source.updatedAt)}</span>
                  </div>
                  <div className="meta">
                    {source.assets.map((asset) => <span key={asset.id}>{asset.assetCode}</span>)}
                  </div>
                </div>
                <div className="actions">
                  <form action={importAssetFileAction}>
                    <input type="hidden" name="fileName" value={source.fileName} />
                    <input className="input compact-file" type="file" name="file" accept=".xlsx,.xls,.csv" required />
                    <button className="button secondary" type="submit">更新文件</button>
                  </form>
                  <form action={deleteSourceAction}>
                    <input type="hidden" name="sourceId" value={source.id} />
                    <button className="button danger" type="submit">删除来源</button>
                  </form>
                </div>
              </article>
            ))}
            {sources.length === 0 ? <p className="muted">还没有导入来源。</p> : null}
          </div>
        </section>

        <aside className="grid">
          <section className="panel panel-pad">
            <h2 style={{ marginBottom: 14 }}>导入新来源</h2>
            <form className="form" action={importAssetFileAction}>
              <input className="input" type="file" name="file" accept=".xlsx,.xls,.csv" required />
              <input className="input" name="fileName" placeholder="来源名称，留空使用文件名" />
              <button className="button blue" type="submit">导入</button>
            </form>
          </section>

          <section className="panel panel-pad">
            <h2 style={{ marginBottom: 14 }}>桌面端同步文件</h2>
            <form className="form" action={importSyncJsonAction}>
              <input className="input" type="file" name="files" accept=".json" multiple required />
              <button className="button blue" type="submit">上传并识别</button>
            </form>
            <p className="muted" style={{ marginTop: 10 }}>
              可一次多选上传 assets.json、records.json、sources.json、meta.json，系统会按文件名自动识别并导入资产、历史记录和来源关系。
            </p>
          </section>

          <section className="panel panel-pad">
            <h2 style={{ marginBottom: 10 }}>更新规则</h2>
            <p className="muted">
              使用同名来源更新时，系统会按外编号核对：文件里新增的编号会加入，仍存在的编号会更新名称/型号/品牌/位置，文件里消失的编号会从该来源移除。
            </p>
          </section>
        </aside>
      </div>
    </>
  );
}
