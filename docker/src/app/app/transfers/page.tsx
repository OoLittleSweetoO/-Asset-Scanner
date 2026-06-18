import { requireUser } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { dateText, transferText } from "@/lib/format";
import { decideTransferAction } from "../actions";

export default async function TransfersPage() {
  const user = await requireUser();
  const [incoming, outgoing] = await Promise.all([
    prisma.assetTransfer.findMany({
      where: { toUserId: user.id },
      include: { asset: true, fromUser: true },
      orderBy: { createdAt: "desc" }
    }),
    prisma.assetTransfer.findMany({
      where: { fromUserId: user.id },
      include: { asset: true, toUser: true },
      orderBy: { createdAt: "desc" }
    })
  ]);

  return (
    <>
      <div className="topbar">
        <div>
          <p className="eyebrow">账户间流转</p>
          <h1>资产转移</h1>
        </div>
      </div>

      <div className="grid grid-2">
        <section className="panel panel-pad">
          <h2 style={{ marginBottom: 14 }}>待我处理</h2>
          <div className="asset-list">
            {incoming.length === 0 ? <p className="muted">暂无转入请求。</p> : null}
            {incoming.map((item) => (
              <article className="asset-row" key={item.id}>
                <div>
                  <div className="asset-title"><span className="pill">{transferText(item.status)}</span>{item.asset.assetName}</div>
                  <div className="meta"><span>来自：{item.fromUser.name}</span><span>外编号：{item.asset.assetCode}</span><span>{dateText(item.createdAt)}</span></div>
                </div>
                {item.status === "PENDING" ? (
                  <div className="actions">
                    <form action={decideTransferAction}><input type="hidden" name="transferId" value={item.id} /><input type="hidden" name="decision" value="accept" /><button className="button blue" type="submit">接收</button></form>
                    <form action={decideTransferAction}><input type="hidden" name="transferId" value={item.id} /><input type="hidden" name="decision" value="reject" /><button className="button secondary" type="submit">拒绝</button></form>
                  </div>
                ) : null}
              </article>
            ))}
          </div>
        </section>

        <section className="panel panel-pad">
          <h2 style={{ marginBottom: 14 }}>我发起的</h2>
          <div className="asset-list">
            {outgoing.length === 0 ? <p className="muted">暂无转出请求。</p> : null}
            {outgoing.map((item) => (
              <article className="asset-row" key={item.id}>
                <div>
                  <div className="asset-title"><span className="pill">{transferText(item.status)}</span>{item.asset.assetName}</div>
                  <div className="meta"><span>转给：{item.toUser.name}</span><span>外编号：{item.asset.assetCode}</span><span>{dateText(item.createdAt)}</span></div>
                </div>
              </article>
            ))}
          </div>
        </section>
      </div>
    </>
  );
}
