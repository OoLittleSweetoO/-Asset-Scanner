import { createHash, randomBytes } from "crypto";
import { type NextRequest } from "next/server";
import { type User } from "@prisma/client";
import { DesktopApiError } from "./desktop-api";
import { verifyPassword } from "./password";
import { prisma } from "./prisma";

const desktopSessionDays = Number(process.env.DESKTOP_SESSION_DAYS || "30");

type DesktopUser = Pick<User, "id" | "email" | "name" | "role">;

function hashToken(token: string) {
  return createHash("sha256").update(token).digest("hex");
}

function userDto(user: DesktopUser) {
  return {
    id: user.id,
    email: user.email,
    name: user.name,
    role: user.role
  };
}

export async function createDesktopSession(email: string, password: string) {
  const user = await prisma.user.findUnique({
    where: { email: email.trim().toLowerCase() },
    select: { id: true, email: true, name: true, role: true, passwordHash: true }
  });

  if (!user || !verifyPassword(password, user.passwordHash)) {
    throw new DesktopApiError(401, "Invalid email or password", "INVALID_CREDENTIALS");
  }

  const token = randomBytes(32).toString("base64url");
  const expiresAt = new Date(Date.now() + desktopSessionDays * 24 * 60 * 60 * 1000);

  await prisma.$transaction([
    prisma.session.deleteMany({ where: { userId: user.id, expiresAt: { lt: new Date() } } }),
    prisma.session.create({
      data: {
        tokenHash: hashToken(token),
        userId: user.id,
        expiresAt
      }
    })
  ]);

  return {
    token,
    expiresAt: expiresAt.toISOString(),
    user: userDto(user)
  };
}

export async function destroyDesktopSession(request: NextRequest) {
  const token = tokenFromRequest(request);
  if (!token) return;
  await prisma.session.deleteMany({ where: { tokenHash: hashToken(token) } });
}

export async function requireDesktopUser(request: NextRequest) {
  const token = tokenFromRequest(request);
  if (!token) throw new DesktopApiError(401, "Missing Bearer token", "UNAUTHORIZED");

  const session = await prisma.session.findUnique({
    where: { tokenHash: hashToken(token) },
    include: { user: true }
  });

  if (!session || session.expiresAt < new Date()) {
    if (session) await prisma.session.delete({ where: { id: session.id } }).catch(() => undefined);
    throw new DesktopApiError(401, "Session expired", "SESSION_EXPIRED");
  }

  return userDto(session.user);
}

function tokenFromRequest(request: NextRequest) {
  const authorization = request.headers.get("authorization") || "";
  const bearer = authorization.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
  return bearer || request.headers.get("x-assetmanager-token")?.trim() || "";
}
