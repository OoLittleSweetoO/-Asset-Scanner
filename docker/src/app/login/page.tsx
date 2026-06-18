import { loginAction, registerAction } from "./actions";

export default function LoginPage({ searchParams }: { searchParams: { error?: string } }) {
  return (
    <main className="login-page">
      <div className="login-grid">
        <section className="panel login-card">
          <div className="brand">
            <span className="brand-mark" />
            <span>AssetManager</span>
          </div>
          <div style={{ marginBottom: 20 }}>
            <p className="eyebrow">多账户固定资产管理</p>
            <h1>登录</h1>
          </div>
          {searchParams.error ? <p className="pill red" style={{ marginBottom: 14 }}>{searchParams.error}</p> : null}
          <form className="form" action={loginAction}>
            <div className="field">
              <label htmlFor="email">邮箱</label>
              <input className="input" id="email" name="email" type="email" autoComplete="email" required />
            </div>
            <div className="field">
              <label htmlFor="password">密码</label>
              <input className="input" id="password" name="password" type="password" autoComplete="current-password" required />
            </div>
            <button className="button blue" type="submit">登录</button>
          </form>
        </section>

        <section className="panel login-card">
          <div style={{ marginBottom: 20 }}>
            <p className="eyebrow">创建独立资产账户</p>
            <h1>注册</h1>
          </div>
          <form className="form" action={registerAction}>
            <div className="field">
              <label htmlFor="register-name">名称</label>
              <input className="input" id="register-name" name="name" autoComplete="name" required />
            </div>
            <div className="field">
              <label htmlFor="register-email">邮箱</label>
              <input className="input" id="register-email" name="email" type="email" autoComplete="email" required />
            </div>
            <div className="field">
              <label htmlFor="register-password">密码</label>
              <input className="input" id="register-password" name="password" type="password" autoComplete="new-password" minLength={8} required />
            </div>
            <div className="field">
              <label htmlFor="register-confirm">确认密码</label>
              <input className="input" id="register-confirm" name="confirmPassword" type="password" autoComplete="new-password" minLength={8} required />
            </div>
            <button className="button" type="submit">注册并进入</button>
          </form>
        </section>
      </div>
    </main>
  );
}
