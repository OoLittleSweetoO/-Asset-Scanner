export function extractFeishuTableConfig(link: string) {
  try {
    const url = new URL(link.trim());
    const parts = url.pathname.split("/").filter(Boolean);
    const baseIndex = parts.findIndex((part) => part === "base");
    const appToken = baseIndex >= 0 ? parts[baseIndex + 1] : "";
    const tableId = url.searchParams.get("table") || "";
    if (!appToken || !tableId) return null;
    return { appToken, tableId };
  } catch {
    return null;
  }
}
