import { NextRequest } from "next/server";
import { requireDesktopUser } from "@/lib/desktop-auth";
import { deleteDesktopAsset, updateDesktopAsset } from "@/lib/desktop-assets";
import { jsonError, jsonOk, readJson } from "@/lib/desktop-api";

export const dynamic = "force-dynamic";

export async function PATCH(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireDesktopUser(request);
    const body = await readJson(request);
    const asset = await updateDesktopAsset(user, params.id, body);
    return jsonOk({ asset });
  } catch (error) {
    return jsonError(error);
  }
}

export async function DELETE(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await requireDesktopUser(request);
    const result = await deleteDesktopAsset(user, params.id);
    return jsonOk(result);
  } catch (error) {
    return jsonError(error);
  }
}
