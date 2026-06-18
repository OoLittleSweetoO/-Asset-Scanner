import { NextResponse } from "next/server";
import { OperationType } from "@prisma/client";
import { requireUser } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

function escapeIcs(value: string) {
  return value
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");
}

export async function GET() {
  const user = await requireUser();
  const records = await prisma.operationRecord.findMany({
    where: {
      ownerId: user.id,
      type: OperationType.CHECK_OUT,
      estimatedReturnDate: { not: null }
    },
    orderBy: { estimatedReturnDate: "asc" }
  });

  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//AssetManager//Calendar Sync//CN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH"
  ];

  for (const record of records) {
    const start = record.estimatedReturnDate!;
    const end = new Date(start);
    end.setDate(end.getDate() + 1);
    const date = (value: Date) => value.toISOString().slice(0, 10).replace(/-/g, "");
    const body = [
      "AssetManager 出库归还提醒",
      `条码: ${record.assetCode}`,
      `资产名称: ${record.assetName}`,
      `操作人: ${record.operatorName}`,
      `出库时间: ${record.createdAt.toISOString()}`,
      record.note ? `备注: ${record.note}` : ""
    ].filter(Boolean).join("\n");

    lines.push(
      "BEGIN:VEVENT",
      `UID:${record.id}@assetmanager`,
      `DTSTAMP:${new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "")}`,
      `DTSTART;VALUE=DATE:${date(start)}`,
      `DTEND;VALUE=DATE:${date(end)}`,
      `SUMMARY:${escapeIcs(`归还提醒: ${record.assetName}`)}`,
      `DESCRIPTION:${escapeIcs(body)}`,
      "CATEGORIES:AssetManager",
      "BEGIN:VALARM",
      "TRIGGER:-P1D",
      "ACTION:DISPLAY",
      `DESCRIPTION:${escapeIcs(`归还提醒: ${record.assetName}`)}`,
      "END:VALARM",
      "END:VEVENT"
    );
  }

  lines.push("END:VCALENDAR");

  await prisma.operationRecord.updateMany({
    where: { id: { in: records.map((record) => record.id) }, ownerId: user.id },
    data: { isSyncedToReminders: true }
  });

  return new NextResponse(lines.join("\r\n"), {
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": "attachment; filename=\"assetmanager-calendar.ics\""
    }
  });
}
