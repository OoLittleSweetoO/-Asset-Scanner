import Link from "next/link";
import { requireUser } from "@/lib/auth";
import { logoutAction } from "./actions";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const user = await requireUser();

  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark" />
          <span>AssetManager</span>
        </div>
        <nav className="nav">
          <Link href="/app">资产</Link>
          <Link href="/app/sources">导入来源</Link>
          <Link href="/app/records">历史记录</Link>
          <Link href="/app/transfers">账户转移</Link>
          <Link href="/app/settings">账户与飞书</Link>
          <Link href="/app/help">帮助说明</Link>
          <form action={logoutAction}>
            <button type="submit">退出登录</button>
          </form>
        </nav>
        <div className="account-card">
          <div className="muted" style={{ fontSize: 13 }}>
            当前账户
          </div>
          <strong>{user.name}</strong>
          <div className="muted" style={{ fontSize: 13, marginTop: 4 }}>
            {user.email}
          </div>
        </div>
      </aside>
      <main className="main">{children}</main>
    </div>
  );
}
