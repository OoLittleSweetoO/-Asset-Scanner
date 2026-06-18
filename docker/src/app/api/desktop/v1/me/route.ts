import { NextRequest } from "next/server";
import { requireDesktopUser } from "@/lib/desktop-auth";
import { jsonError, jsonOk } from "@/lib/desktop-api";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const user = await requireDesktopUser(request);
    return jsonOk({ user });
  } catch (error) {
    return jsonError(error);
  }
}
