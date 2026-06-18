"use client";

import { useRef } from "react";
import type { AssetStatus } from "@prisma/client";

type TargetUser = {
  id: string;
  name: string;
};

type Props = {
  assetId: string;
  status: AssetStatus;
  currentUserName: string;
  users: TargetUser[];
  updateAction: (formData: FormData) => void | Promise<void>;
  transferAction: (formData: FormData) => void | Promise<void>;
};

export function AssetActions({ assetId, status, currentUserName, users, updateAction, transferAction }: Props) {
  const checkoutDialog = useRef<HTMLDialogElement>(null);

  return (
    <div className="actions">
      <form action={updateAction}>
        <input type="hidden" name="assetId" value={assetId} />
        <input type="hidden" name="status" value="IN_STOCK" />
        <input type="hidden" name="operatorName" value={currentUserName} />
        <button className="button secondary" type="submit" disabled={status === "IN_STOCK"}>归还</button>
      </form>

      <button className="button secondary" type="button" disabled={status !== "IN_STOCK"} onClick={() => checkoutDialog.current?.showModal()}>
        出库
      </button>

      <form action={updateAction}>
        <input type="hidden" name="assetId" value={assetId} />
        <input type="hidden" name="status" value="MAINTENANCE" />
        <input type="hidden" name="operatorName" value={currentUserName} />
        <button className="button secondary" type="submit" disabled={status === "MAINTENANCE"}>送修</button>
      </form>

      <form action={updateAction}>
        <input type="hidden" name="assetId" value={assetId} />
        <input type="hidden" name="status" value="SCRAPPED" />
        <input type="hidden" name="operatorName" value={currentUserName} />
        <button className="button secondary" type="submit" disabled={status === "SCRAPPED"}>报废</button>
      </form>

      {users.length > 0 ? (
        <form action={transferAction}>
          <input type="hidden" name="assetId" value={assetId} />
          <select className="select compact" name="toUserId" aria-label="转移账户">
            {users.map((target) => <option key={target.id} value={target.id}>{target.name}</option>)}
          </select>
          <button className="button secondary" type="submit">转移</button>
        </form>
      ) : null}

      <dialog className="dialog" ref={checkoutDialog}>
        <form className="form" action={updateAction}>
          <input type="hidden" name="assetId" value={assetId} />
          <input type="hidden" name="status" value="CHECKED_OUT" />
          <h2>出库信息</h2>
          <div className="field">
            <label>操作人</label>
            <input className="input" name="operatorName" defaultValue={currentUserName} required />
          </div>
          <div className="field">
            <label>预计归还日期</label>
            <input className="input" name="estimatedReturnDate" type="date" />
          </div>
          <div className="field">
            <label>备注</label>
            <textarea className="textarea" name="note" />
          </div>
          <div className="actions">
            <button className="button secondary" type="button" onClick={() => checkoutDialog.current?.close()}>取消</button>
            <button className="button blue" type="submit">确认出库</button>
          </div>
        </form>
      </dialog>
    </div>
  );
}
