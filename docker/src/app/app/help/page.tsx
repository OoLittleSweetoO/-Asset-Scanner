export default function HelpPage() {
  return (
    <>
      <div className="topbar">
        <div>
          <p className="eyebrow">使用指南</p>
          <h1>帮助说明</h1>
        </div>
      </div>

      <div className="grid grid-2 help-grid">
        <section className="panel panel-pad">
          <h2>资产操作流程</h2>
          <div className="help-list">
            <p><strong>扫码定位：</strong>进入资产页，点“扫码定位”，扫到外编号后会自动搜索并勾选对应资产。</p>
            <p><strong>入库 / 出库：</strong>勾选资产后点右上角“操作选中”，选择归还/入库、出库、送修、报废或删除。</p>
            <p><strong>出库细节：</strong>选择出库时可以填写操作人、预计归还时间和备注，确认后本地先保存，飞书在后台同步。</p>
            <p><strong>账户转移：</strong>转移会先创建待确认请求，目标账户接收后资产归属才会变更。</p>
          </div>
        </section>

        <section className="panel panel-pad">
          <h2>手机扫码说明</h2>
          <div className="help-list">
            <p><strong>实时扫码：</strong>手机浏览器要求 HTTPS。请使用 https://10.10.10.71 访问。</p>
            <p><strong>证书信任：</strong>如果手机提示证书不受信任，先打开 http://10.10.10.71/assetmanager-local-ca.crt 下载本地 CA 证书，并在手机系统设置里安装并信任。</p>
            <p><strong>拍照识别：</strong>HTTP 下建议使用拍照识别。拍照时让条形码占画面三分之一以上，保持对焦清晰、避免反光。</p>
            <p><strong>相册识别：</strong>如果拍照后没有识别到，可以先用手机相机拍一张清晰照片，再用相册识别。</p>
            <p><strong>兜底定位：</strong>条形码污损、太小或反光时，直接手动输入外编号即可定位。</p>
          </div>
        </section>

        <section className="panel panel-pad">
          <h2>飞书同步逻辑</h2>
          <div className="help-list">
            <p><strong>密钥归属：</strong>App ID 和 App Secret 只需要管理员配置，普通用户只填写自己的资产表链接和记录表链接。</p>
            <p><strong>全量同步：</strong>设置页点“同步到飞书”后会立刻返回，服务器后台继续同步，不会卡住页面。</p>
            <p><strong>逐条同步：</strong>入库、出库、送修、报废、删除、转移接收后，会优先保存本地数据，再后台更新飞书。</p>
            <p><strong>多账户：</strong>管理员可以看到所有账户资产；普通用户同步时会使用管理员密钥和自己的表格链接。</p>
          </div>
        </section>

        <section className="panel panel-pad">
          <h2>常见问题</h2>
          <div className="help-list">
            <p><strong>实时扫码不可用：</strong>通常是证书还没有被手机信任。信任本地 CA 后，重新打开 https://10.10.10.71。</p>
            <p><strong>识别不到条形码：</strong>请靠近条码、横向对齐、避免阴影和反光。条码过小、模糊或破损时识别率会明显下降。</p>
            <p><strong>同步失败：</strong>先确认管理员密钥正确，再确认当前账户的两张飞书表链接已保存。</p>
            <p><strong>找不到资产：</strong>确认扫码结果或手动输入的是资产外编号，而不是内编号或设备序列号。</p>
          </div>
        </section>
      </div>
    </>
  );
}
