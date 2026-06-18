import { NextRequest } from "next/server";
import { requireDesktopUser } from "@/lib/desktop-auth";
import { updateDesktopAssetStatus } from "@/lib/desktop-assets";
import { jsonError, jsonOk, readJson } from "@/lib/desktop-api";

export const dynamic = "force-dynamic";

export async function PATCH(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireDesktopUser(request);
    const body = await readJson(request);
    const result = await updateDesktopAssetStatus(user, params.id, body);
    return jsonOk(result);
  } catch (error) {
    return jsonError(error);
  }
}
