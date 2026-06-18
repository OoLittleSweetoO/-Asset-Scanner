import { NextRequest } from "next/server";
import { createDesktopSession } from "@/lib/desktop-auth";
import { jsonError, jsonOk, readJson, textField } from "@/lib/desktop-api";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  try {
    const body = await readJson(request);
    const email = textField(body.email);
    const password = textField(body.password);
    const session = await createDesktopSession(email, password);
    return jsonOk(session);
  } catch (error) {
    return jsonError(error);
  }
}
