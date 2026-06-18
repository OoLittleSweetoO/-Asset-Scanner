import { UserRole } from "@prisma/client";
import { requireUser } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import {
  bidirectionalFeishuAction,
  changePasswordAction,
  createUserAction,
  importFromFeishuAction,
  saveFeishuConfigAction,
  syncToFeishuAction,
  testFeishuAction
} from "../actions";

export default async function SettingsPage() {
  const user = await requireUser();
  const [config, adminConfig, users] = await Promise.all([
    prisma.feishuConfig.findUnique({ where: { ownerId: user.id } }),
    prisma.feishuConfig.findFirst({
      where: {
        owner: { role: UserRole.ADMIN },
        appId: { not: "" },
        appSecretCipher: { not: "" }
      },
      orderBy: { updatedAt: "desc" }
    }),
    prisma.user.findMany({ orderBy: { createdAt: "asc" }, select: { id: true, name: true, email: true, role: true } })
  ]);
  const isAdmin = user.role === UserRole.ADMIN;
  const hasAdminCredential = Boolean(adminConfig?.appId && adminConfig.appSecretCipher);

  return (
    <>
      <div className="topbar">
        <div>
          <p className="eyebrow">账户配置</p>
          <h1>账户与飞书</h1>
        </div>
      </div>

      <div className="grid grid-2">
        <section className="panel panel-pad">
          <h2 style={{ marginBottom: 14 }}>飞书多维表格</h2>
          <form className="form" action={saveFeishuConfigAction}>
            {isAdmin ? (
              <>
                <div className="field">
                  <label>App ID</label>
                  <input className="input" name="appId" defaultValue={config?.appId} />
                </div>
                <div className="field">
                  <label>App Secret</label>
                  <input className="input" name="appSecret" defaultValue={config?.appSecretCipher} type="password" />
                </div>
              </>
            ) : (
              <p className="muted">{hasAdminCredential ? "当前使用管理员维护的飞书应用密钥。" : "管理员还没有配置飞书 App ID / App Secret。"}</p>
            )}
            <div className="field">
              <label>资产表链接</label>
              <input className="input" name="assetTableLink" defaultValue={config?.assetTableLink} />
            </div>
            <div className="field">
              <label>记录表链接</label>
              <input className="input" name="recordTableLink" defaultValue={config?.recordTableLink} />
            </div>
            <div className="grid grid-2">
              <div className="field">
                <label>资产 App Token</label>
                <input className="input" name="assetAppToken" defaultValue={config?.assetAppToken} />
              </div>
              <div className="field">
                <label>资产 Table ID</label>
                <input className="input" name="assetTableId" defaultValue={config?.assetTableId} />
              </div>
              <div className="field">
                <label>记录 App Token</label>
                <input className="input" name="recordAppToken" defaultValue={config?.recordAppToken} />
              </div>
              <div className="field">
                <label>记录 Table ID</label>
                <input className="input" name="recordTableId" defaultValue={config?.recordTableId} />
              </div>
            </div>
            <button className="button blue" type="submit">
              保存配置
            </button>
          </form>

          <div className="actions" style={{ marginTop: 14, justifyContent: "flex-start" }}>
            <form action={testFeishuAction}>
              <button className="button secondary" type="submit">
                测试连接
              </button>
            </form>
            <form action={syncToFeishuAction}>
              <button className="button secondary" type="submit">
                后台同步到飞书
              </button>
            </form>
            <form action={importFromFeishuAction}>
              <button className="button secondary" type="submit">
                从飞书导入
              </button>
            </form>
            <form action={bidirectionalFeishuAction}>
              <button className="button blue" type="submit">
                导入并后台同步
              </button>
            </form>
          </div>
        </section>

        <aside className="grid">
          <section className="panel panel-pad">
            <h2 style={{ marginBottom: 14 }}>修改密码</h2>
            <form className="form" action={changePasswordAction}>
              <div className="field">
                <label>当前密码</label>
                <input className="input" name="currentPassword" type="password" autoComplete="current-password" required />
              </div>
              <div className="field">
                <label>新密码</label>
                <input className="input" name="newPassword" type="password" autoComplete="new-password" minLength={8} required />
              </div>
              <div className="field">
                <label>确认新密码</label>
                <input className="input" name="confirmPassword" type="password" autoComplete="new-password" minLength={8} required />
              </div>
              <button className="button" type="submit">
                修改密码
              </button>
            </form>
          </section>

          <section className="panel panel-pad">
            <h2 style={{ marginBottom: 14 }}>账户</h2>
            <table className="tableish">
              <thead>
                <tr>
                  <th>名称</th>
                  <th>邮箱</th>
                  <th>角色</th>
                </tr>
              </thead>
              <tbody>
                {users.map((item) => (
                  <tr key={item.id}>
                    <td>{item.name}</td>
                    <td>{item.email}</td>
                    <td>{item.role}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </section>

          {isAdmin ? (
            <section className="panel panel-pad">
              <h2 style={{ marginBottom: 14 }}>新建账户</h2>
              <form className="form" action={createUserAction}>
                <div className="field">
                  <label>名称</label>
                  <input className="input" name="name" required />
                </div>
                <div className="field">
                  <label>邮箱</label>
                  <input className="input" name="email" type="email" required />
                </div>
                <div className="field">
                  <label>初始密码</label>
                  <input className="input" name="password" type="password" required />
                </div>
                <button className="button" type="submit">
                  创建
                </button>
              </form>
            </section>
          ) : null}
        </aside>
      </div>
    </>
  );
}
