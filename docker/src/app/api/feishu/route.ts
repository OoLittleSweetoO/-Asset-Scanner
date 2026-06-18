import { NextRequest, NextResponse } from "next/server";
import { UserRole } from "@prisma/client";
import { requireUser } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { FeishuBitableClient } from "@/lib/feishu-bitable";

export const dynamic = "force-dynamic";

async function effectiveFeishuConfig(ownerId: string) {
  const [owner, ownerConfig, adminConfig] = await Promise.all([
    prisma.user.findUnique({ where: { id: ownerId }, select: { role: true } }),
    prisma.feishuConfig.findUnique({ where: { ownerId } }),
    prisma.feishuConfig.findFirst({
      where: {
        owner: { role: UserRole.ADMIN },
        appId: { not: "" },
        appSecretCipher: { not: "" }
      },
      orderBy: { updatedAt: "desc" }
    })
  ]);
  const config = ownerConfig ?? adminConfig;
  if (!config) return null;
  const credentialConfig = owner?.role === UserRole.ADMIN ? ownerConfig ?? adminConfig : adminConfig;
  return {
    ...config,
    appId: credentialConfig?.appId || "",
    appSecretCipher: credentialConfig?.appSecretCipher || ""
  };
}

export async function GET(request: NextRequest) {
  const user = await requireUser();
  const action = request.nextUrl.searchParams.get("action") ?? "test";
  const config = await effectiveFeishuConfig(user.id);
  if (!config) return NextResponse.json({ ok: false, message: "请先保存飞书配置" }, { status: 400 });

  const client = new FeishuBitableClient(config);

  try {
    if (action === "test") {
      const result = await client.testConnection();
      return NextResponse.json({ ok: true, message: "飞书连接成功", result });
    }

    if (action === "sync") {
      const [assets, records] = await Promise.all([
        prisma.asset.findMany({ where: { ownerId: user.id } }),
        prisma.operationRecord.findMany({ where: { ownerId: user.id } })
      ]);
      const result = await client.syncAll(assets, records);
      return NextResponse.json({ ok: true, message: `同步完成：资产 ${result.assetCount} 个，记录 ${result.recordCount} 条` });
    }

    if (action === "import" || action === "bidirectional") {
      const remote = await client.importRemote();
      for (const asset of remote.assets) {
        await prisma.asset.upsert({
          where: { ownerId_assetCode: { ownerId: user.id, assetCode: asset.assetCode } },
          create: { ownerId: user.id, ...asset },
          update: asset
        });
      }
      for (const record of remote.records) {
        const asset = await prisma.asset.findUnique({ where: { ownerId_assetCode: { ownerId: user.id, assetCode: record.assetCode } } });
        await prisma.operationRecord.upsert({
          where: { id: record.id },
          create: { ownerId: user.id, assetId: asset?.id, ...record },
          update: { assetId: asset?.id, ...record }
        });
      }

      if (action === "bidirectional") {
        const [assets, records] = await Promise.all([
          prisma.asset.findMany({ where: { ownerId: user.id } }),
          prisma.operationRecord.findMany({ where: { ownerId: user.id } })
        ]);
        await client.syncAll(assets, records);
      }

      return NextResponse.json({
        ok: true,
        message: `已从飞书导入：资产 ${remote.assets.length} 个，记录 ${remote.records.length} 条`
      });
    }

    return NextResponse.json({ ok: false, message: "未知飞书操作" }, { status: 400 });
  } catch (error) {
    return NextResponse.json({ ok: false, message: error instanceof Error ? error.message : "飞书操作失败" }, { status: 500 });
  }
}
