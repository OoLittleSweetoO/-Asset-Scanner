import { NextResponse } from "next/server";

export class DesktopApiError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly code = "BAD_REQUEST"
  ) {
    super(message);
  }
}

export function jsonOk(payload: Record<string, unknown> = {}, init?: ResponseInit) {
  return NextResponse.json({ ok: true, ...payload }, init);
}

export function jsonError(error: unknown) {
  if (error instanceof DesktopApiError) {
    return NextResponse.json({ ok: false, code: error.code, message: error.message }, { status: error.status });
  }

  console.error("Desktop API failed", error);
  return NextResponse.json({ ok: false, code: "INTERNAL_ERROR", message: "Internal server error" }, { status: 500 });
}

export async function readJson<T = Record<string, unknown>>(request: Request) {
  try {
    return (await request.json()) as T;
  } catch {
    throw new DesktopApiError(400, "Invalid JSON body", "INVALID_JSON");
  }
}

export function textField(value: unknown) {
  return String(value ?? "").trim();
}

export function nullableTextField(value: unknown) {
  const text = textField(value);
  return text || null;
}

export function parseDateField(value: unknown) {
  const text = textField(value);
  if (!text) return null;
  const date = new Date(text);
  return Number.isNaN(date.getTime()) ? null : date;
}
