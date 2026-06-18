import { NextRequest } from "next/server";
import { requireDesktopUser } from "@/lib/desktop-auth";
import { createDesktopAsset } from "@/lib/desktop-assets";
import { jsonError, jsonOk, readJson } from "@/lib/desktop-api";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  try {
    const user = await requireDesktopUser(request);
    const body = await readJson(request);
    const asset = await createDesktopAsset(user, body);
    return jsonOk({ asset });
  } catch (error) {
    return jsonError(error);
  }
}
