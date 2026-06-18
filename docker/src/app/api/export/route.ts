import { NextRequest, NextResponse } from "next/server";
import { requireUser } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { assetExportRows, csvBuffer, recordExportRows, syncJsonPayload, workbookBuffer } from "@/lib/asset-io";

export const dynamic = "force-dynamic";

function download(buffer: Buffer, filename: string, contentType: string) {
  return new NextResponse(new Uint8Array(buffer), {
    headers: {
      "Content-Type": contentType,
      "Content-Disposition": `attachment; filename="${filename}"`
    }
  });
}

export async function GET(request: NextRequest) {
  const user = await requireUser();
  const isAdmin = user.role === "ADMIN";
  const type = request.nextUrl.searchParams.get("type") ?? "assets";
  const format = request.nextUrl.searchParams.get("format") ?? "xlsx";

  if (type === "records") {
    const records = await prisma.operationRecord.findMany({
      where: isAdmin ? {} : { ownerId: user.id },
      orderBy: { createdAt: "desc" }
    });
    const rows = recordExportRows(records);
    if (format === "csv") return download(csvBuffer(rows), "asset-records.csv", "text/csv; charset=utf-8");
    return download(
      workbookBuffer(rows, "操作记录"),
      "asset-records.xlsx",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    );
  }

  if (type === "sync") {
    const [assets, records, sources] = await Promise.all([
      prisma.asset.findMany({ where: isAdmin ? {} : { ownerId: user.id }, orderBy: { updatedAt: "desc" } }),
      prisma.operationRecord.findMany({ where: isAdmin ? {} : { ownerId: user.id }, orderBy: { createdAt: "desc" } }),
      prisma.assetSource.findMany({
        where: isAdmin ? {} : { ownerId: user.id },
        include: { assets: { select: { assetCode: true } } },
        orderBy: { createdAt: "desc" }
      })
    ]);
    const payload = syncJsonPayload(assets, records, sources);
    return download(Buffer.from(JSON.stringify(payload, null, 2), "utf8"), "assetmanager-sync.json", "application/json");
  }

  const assets = await prisma.asset.findMany({
    where: isAdmin ? {} : { ownerId: user.id },
    orderBy: { updatedAt: "desc" }
  });
  const rows = assetExportRows(assets);
  if (format === "csv") return download(csvBuffer(rows), "assets.csv", "text/csv; charset=utf-8");
  return download(
    workbookBuffer(rows, "资产列表"),
    "assets.xlsx",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  );
}
