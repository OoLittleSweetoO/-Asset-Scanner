import Foundation

// MARK: - 中文本地化字典

private let chineseTranslations: [String: String] = [
    // ========== 通用 ==========
    "language": "语言",
    "confirm": "确认",
    "cancel": "取消",
    "error_title": "错误",
    "sync_selected": "同步选中",
    
    // ========== Tab 标签 ==========
    "tab_scan": "扫码",
    "tab_assets": "资产",
    "tab_management": "管理", 
    "tab_history": "历史",
    
    // ========== 扫码页面 ==========
    "scan_title": "资产扫码",
    "scan_input_placeholder": "输入资产编号",
    "scan_query": "查询",
    "scan_import": "导入",
    "scan_hint": "扫描资产条码或手动输入编号",
    "scan_success": "扫码成功",
    "scan_redirecting": "跳转中...",
    
    // ========== 资产列表 ==========
    "asset_list_title": "资产列表",
    "asset_count": "%d 件资产",
    "search_assets": "搜索资产",
    "empty_assets_title": "暂无资产",
    "empty_assets_hint": "导入资产表后会在这里显示",
    
    // ========== 资产管理 ==========
    "management_title": "管理",
    "stat_file_sources": "文件来源",
    "stat_total_assets": "资产总数",
    "empty_management_title": "暂无导入记录",
    "empty_management_hint": "在扫码页面导入资产表后\n这里会显示文件来源",
    "source_assets_count": "%d 件资产",
    
    // ========== 历史记录 ==========
    "history_title": "历史",
    "delete": "删除",
    "sync_reminder": "同步提醒",
    "sync_complete": "同步完成",
    "empty_history_title": "暂无操作记录",
    "empty_history_hint": "资产的出入库记录会显示在这里",
    "estimated_return_label": "预计归还时间",
    
    // ========== 资产详情 ==========
    "current_user": "当前用户",
    "check_in": "入库",
    "check_out": "出库",
    "check_in_confirm": "确认入库 %@？",
    "check_out_section": "操作信息",
    "confirm_check_out": "确认出库",
    "check_out_title": "出库",
    "loading": "加载中...",
    "info_internal_code": "内部编号",
    "info_brand": "品牌",
    "info_model": "型号",
    "info_location": "位置",
    "info_purchase_date": "采购日期",
    "info_last_updated": "最后更新",
    "recent_check_out": "最近出库记录",
    "operator": "操作人",
    "note": "备注",
    "estimated_return": "预计归还",
    "status_in_stock": "在库",
    "status_checked_out": "已出库",
    "status_maintenance": "维修中",
    "type_check_in": "入库",
    "type_check_out": "出库",
    "note_barcode": "条码",
    "note_borrower": "借用人",
    "note_checkout_time": "出库时间",
    "error_reminder_permission": "需要提醒事项权限",
    "error_reminder_list_create": "创建提醒列表失败",
    "error_sync_failed": "同步失败: %@",
    "sync_success": "%d 条记录同步成功",
    "sync_skip": " %d 条已存在",
    "sync_all_exist": "所有记录都已同步",
    "sync_no_records": "没有需要同步的记录"
]

// MARK: - 本地化函数

func L(_ key: String) -> String {
    return chineseTranslations[key] ?? key
}

func L(_ key: String, _ args: CVarArg...) -> String {
    let format = L(key)
    if args.isEmpty { return format }
    return String(format: format, arguments: args)
}