import { requireUser } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { dateText, operationText } from "@/lib/format";
import { deleteRecordAction } from "../actions";
import { RecordsList } from "./RecordsList";

export default async function RecordsPage() {
  const user = await requireUser();
  const isAdmin = user.role === "ADMIN";
  const records = await prisma.operationRecord.findMany({
    where: isAdmin ? {} : { ownerId: user.id },
    orderBy: { createdAt: "desc" },
    take: 500
  });

  return (
    <>
      <div className="topbar">
        <div>
          <p className="eyebrow">操作追踪</p>
          <h1>历史记录</h1>
        </div>
        <div className="actions">
          <a className="button secondary" href="/api/calendar">
            导出 Outlook 日历
          </a>
          <a className="button secondary" href="/api/export?type=records&format=csv">
            导出 CSV
          </a>
          <a className="button blue" href="/api/export?type=records&format=xlsx">
            导出 Excel
          </a>
        </div>
      </div>

      <section className="panel panel-pad">
        <div className="section-head">
          <h2>记录列表</h2>
          <p className="muted">右键记录可删除选中项</p>
        </div>
        <RecordsList
          deleteAction={deleteRecordAction}
          records={records.map((record) => ({
            id: record.id,
            assetCode: record.assetCode,
            assetName: record.assetName,
            typeLabel: operationText(record.type),
            operatorName: record.operatorName,
            createdAtLabel: dateText(record.createdAt),
            estimatedReturnLabel: record.estimatedReturnDate ? dateText(record.estimatedReturnDate) : null,
            outlookLabel: record.isSyncedToReminders ? "已同步" : "未同步",
            note: record.note
          }))}
        />
      </section>
    </>
  );
}
