import { pbkdf2Sync, randomBytes, timingSafeEqual } from "crypto";

const iterations = 120_000;
const keyLength = 32;
const digest = "sha256";

export function hashPassword(password: string) {
  const salt = randomBytes(16).toString("hex");
  const hash = pbkdf2Sync(password, salt, iterations, keyLength, digest).toString("hex");
  return `pbkdf2:${iterations}:${salt}:${hash}`;
}

export function verifyPassword(password: string, stored: string) {
  const [scheme, iterationText, salt, expectedHash] = stored.split(":");
  if (scheme !== "pbkdf2" || !iterationText || !salt || !expectedHash) {
    return false;
  }

  const actual = pbkdf2Sync(password, salt, Number(iterationText), keyLength, digest);
  const expected = Buffer.from(expectedHash, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
