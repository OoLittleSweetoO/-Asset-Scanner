import { NextRequest } from "next/server";
import { destroyDesktopSession } from "@/lib/desktop-auth";
import { jsonError, jsonOk } from "@/lib/desktop-api";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  try {
    await destroyDesktopSession(request);
    return jsonOk();
  } catch (error) {
    return jsonError(error);
  }
}
