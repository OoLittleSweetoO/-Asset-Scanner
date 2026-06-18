import { NextRequest } from "next/server";
import { requireDesktopUser } from "@/lib/desktop-auth";
import { desktopBootstrap } from "@/lib/desktop-assets";
import { jsonError, jsonOk } from "@/lib/desktop-api";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const user = await requireDesktopUser(request);
    const bootstrap = await desktopBootstrap(user);
    return jsonOk(bootstrap);
  } catch (error) {
    return jsonError(error);
  }
}
