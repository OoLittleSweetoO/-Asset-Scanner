import { NextRequest } from "next/server";
import { requireDesktopUser } from "@/lib/desktop-auth";
import { transferDesktopAsset } from "@/lib/desktop-assets";
import { jsonError, jsonOk, readJson } from "@/lib/desktop-api";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  try {
    const user = await requireDesktopUser(request);
    const body = await readJson(request);
    const result = await transferDesktopAsset(user, body);
    return jsonOk(result);
  } catch (error) {
    return jsonError(error);
  }
}
