"use client";

import { useState } from "react";

type RecordItem = {
  id: string;
  assetCode: string;
  assetName: string;
  typeLabel: string;
  operatorName: string;
  createdAtLabel: string;
  estimatedReturnLabel: string | null;
  outlookLabel: string;
  note: string | null;
};

type Props = {
  records: RecordItem[];
  deleteAction: (formData: FormData) => Promise<void>;
};

export function RecordsList({ records, deleteAction }: Props) {
  const [selected, setSelected] = useState<string[]>([]);
  const [menu, setMenu] = useState<{ x: number; y: number } | null>(null);

  function toggle(id: string) {
    setSelected((current) => (current.includes(id) ? current.filter((item) => item !== id) : [...current, id]));
  }

  function openMenu(event: React.MouseEvent, id: string) {
    event.preventDefault();
    setSelected((current) => (current.includes(id) ? current : [id]));
    setMenu({ x: event.clientX, y: event.clientY });
  }

  return (
    <div onClick={() => setMenu(null)}>
      <form id="delete-records-form" action={deleteAction} onSubmit={() => setMenu(null)}>
        <input type="hidden" name="recordIds" value={selected.join(",")} />
      </form>
      <div className="asset-list scroll-list">
        {records.map((record) => (
          <article className="asset-row" key={record.id} onContextMenu={(event) => openMenu(event, record.id)}>
            <label className="checkline">
              <input type="checkbox" checked={selected.includes(record.id)} onChange={() => toggle(record.id)} />
            </label>
            <div>
              <div className="asset-title">
                <span className="pill">{record.typeLabel}</span>
                {record.assetName}
              </div>
              <div className="meta">
                <span>外编号：{record.assetCode}</span>
                <span>操作人：{record.operatorName}</span>
                <span>时间：{record.createdAtLabel}</span>
                {record.estimatedReturnLabel ? <span>预计归还：{record.estimatedReturnLabel}</span> : null}
                <span>Outlook：{record.outlookLabel}</span>
              </div>
              {record.note ? <p className="muted">{record.note}</p> : null}
            </div>
          </article>
        ))}
        {records.length === 0 ? <p className="muted">暂无历史记录。</p> : null}
      </div>
      {menu ? (
        <div className="context-menu" style={{ left: menu.x, top: menu.y }}>
          <button className="context-danger" form="delete-records-form" type="submit" disabled={selected.length === 0}>
            删除选中记录
          </button>
        </div>
      ) : null}
    </div>
  );
}
