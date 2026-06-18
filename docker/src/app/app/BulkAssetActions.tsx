"use client";

import { useEffect, useRef, useState } from "react";

type UserOption = {
  id: string;
  name: string;
  email: string;
};

type Props = {
  users: UserOption[];
  currentUserName: string;
  action: (formData: FormData) => Promise<void>;
  autoOpen?: boolean;
};

const operationLabels = {
  checkin: "归还 / 入库",
  checkout: "出库",
  repair: "送修",
  transfer: "转移",
  scrap: "报废",
  delete: "删除"
};

export function BulkAssetActions({ users, currentUserName, action, autoOpen = false }: Props) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [operation, setOperation] = useState<keyof typeof operationLabels>("checkout");

  function openDialog() {
    const checked = Array.from(document.querySelectorAll<HTMLInputElement>('input[data-asset-select="true"]:checked')).map((input) => input.value);
    setSelectedIds(checked);
    dialogRef.current?.showModal();
  }

  useEffect(() => {
    if (!autoOpen) return;
    const timer = window.setTimeout(() => {
      openDialog();
      const url = new URL(window.location.href);
      url.searchParams.delete("operate");
      window.history.replaceState({}, "", `${url.pathname}${url.search}`);
    }, 120);
    return () => window.clearTimeout(timer);
  }, [autoOpen]);

  return (
    <>
      <button className="button blue" type="button" onClick={openDialog}>
        操作选中
      </button>
      <dialog className="dialog" ref={dialogRef}>
        <form
          className="form"
          action={action}
          onSubmit={() => {
            dialogRef.current?.close();
          }}
        >
          <div className="section-head">
            <h2>资产操作</h2>
            <button className="button secondary" type="button" onClick={() => dialogRef.current?.close()}>
              关闭
            </button>
          </div>
          <input type="hidden" name="assetIds" value={selectedIds.join(",")} />
          <div className="field">
            <label>已选资产</label>
            <input className="input" value={`${selectedIds.length} 项`} readOnly />
          </div>
          <div className="field">
            <label>操作</label>
            <select className="select" name="operation" value={operation} onChange={(event) => setOperation(event.target.value as keyof typeof operationLabels)}>
              {Object.entries(operationLabels).map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
          </div>
          {operation === "transfer" ? (
            <div className="field">
              <label>转移到</label>
              <select className="select" name="toUserId" required>
                <option value="">选择账户</option>
                {users.map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.name} / {item.email}
                  </option>
                ))}
              </select>
            </div>
          ) : null}
          {operation !== "transfer" && operation !== "delete" ? (
            <div className="field">
              <label>操作人</label>
              <input className="input" name="operatorName" defaultValue={currentUserName} />
            </div>
          ) : null}
          {operation === "checkout" ? (
            <div className="field">
              <label>预计归还</label>
              <input className="input" type="datetime-local" name="estimatedReturnDate" />
            </div>
          ) : null}
          <div className="field">
            <label>备注</label>
            <textarea className="textarea" name="note" />
          </div>
          <div className="actions">
            <button className="button secondary" type="button" onClick={() => dialogRef.current?.close()}>
              取消
            </button>
            <button className={operation === "delete" ? "button danger" : "button blue"} type="submit" disabled={selectedIds.length === 0}>
              确认
            </button>
          </div>
        </form>
      </dialog>
    </>
  );
}
