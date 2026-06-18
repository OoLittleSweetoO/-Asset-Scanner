import { AssetStatus, OperationType, TransferStatus } from "@prisma/client";

export function statusText(status: AssetStatus) {
  return {
    IN_STOCK: "在库",
    CHECKED_OUT: "已出库",
    MAINTENANCE: "送修",
    SCRAPPED: "待报废"
  }[status];
}

export function operationText(type: OperationType) {
  return {
    CHECK_IN: "入库",
    CHECK_OUT: "出库",
    REPAIR: "送修",
    SCRAP: "报废",
    TRANSFER_OUT: "转出",
    TRANSFER_IN: "转入"
  }[type];
}

export function transferText(status: TransferStatus) {
  return {
    PENDING: "等待确认",
    ACCEPTED: "已接收",
    REJECTED: "已拒绝",
    CANCELLED: "已取消"
  }[status];
}

export function dateText(value: Date | null | undefined) {
  if (!value) return "-";
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  }).format(value);
}
