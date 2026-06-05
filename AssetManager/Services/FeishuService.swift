import Foundation
import SwiftUI
import Combine

/// 飞书通知服务 - 通过 Webhook 推送资产借用消息
@MainActor
class FeishuService: ObservableObject {
    @Published var webhookURL: String = ""
    @Published var isSending = false
    @Published var lastMessage: String?
    @Published var lastError: String?
    @Published var isEnabled: Bool = false
    
    private let webhookKey = "feishu_webhook_url"
    
    init() {
        // 从 UserDefaults 加载 Webhook URL
        if let saved = UserDefaults.standard.string(forKey: webhookKey), !saved.isEmpty {
            self.webhookURL = saved
            self.isEnabled = true
        }
    }
    
    /// 保存 Webhook URL
    func saveWebhookURL(_ url: String) {
        webhookURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(webhookURL, forKey: webhookKey)
        isEnabled = !webhookURL.isEmpty
    }
    
    /// 发送资产出库通知
    func sendCheckOutNotification(asset: macOS_Asset, operatorName: String, note: String?, estimatedReturnDate: Date?) async {
        let title = "资产出库通知"
        let content = """
        资产名称：\(asset.assetName)
        外编号：\(asset.id)
        型号：\(asset.modelName)
        品牌：\(asset.brand)
        操作人：\(operatorName)
        出库时间：\(formattedDate(Date()))
        \(note.map { "备注：\($0)" } ?? "")
        \(estimatedReturnDate.map { "预计归还：\(formattedDate($0))" } ?? "")
        """
        
        await sendFeishuMessage(title: title, content: content)
    }
    
    /// 发送资产入库通知
    func sendCheckInNotification(asset: macOS_Asset, operatorName: String, note: String?) async {
        let title = "资产入库通知"
        let content = """
        资产名称：\(asset.assetName)
        外编号：\(asset.id)
        型号：\(asset.modelName)
        品牌：\(asset.brand)
        操作人：\(operatorName)
        入库时间：\(formattedDate(Date()))
        \(note.map { "备注：\($0)" } ?? "")
        """
        
        await sendFeishuMessage(title: title, content: content)
    }
    
    /// 发送飞书消息（富文本卡片）
    private func sendFeishuMessage(title: String, content: String) async {
        guard isEnabled, let url = URL(string: webhookURL) else {
            lastError = "未配置飞书 Webhook URL"
            return
        }
        
        isSending = true
        lastError = nil
        
        // 构建飞书消息体
        let messageBody: [String: Any] = [
            "msg_type": "interactive",
            "card": [
                "header": [
                    "title": [
                        "tag": "plain_text",
                        "content": title
                    ],
                    "template": title.contains("出库") ? "orange" : "green"
                ],
                "elements": [
                    [
                        "tag": "div",
                        "text": [
                            "tag": "lark_md",
                            "content": content.replacingOccurrences(of: "\n", with: "\n")
                        ]
                    ],
                    [
                        "tag": "hr"
                    ],
                    [
                        "tag": "note",
                        "elements": [
                            [
                                "tag": "plain_text",
                                "content": "AssetManager 自动通知"
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: messageBody)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                lastMessage = "✅ 飞书通知已发送"
                print("✅ 飞书通知发送成功: \(title)")
            } else {
                lastError = "飞书通知发送失败，HTTP 状态码: \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                print("❌ 飞书通知发送失败")
            }
        } catch {
            lastError = "飞书通知发送失败: \(error.localizedDescription)"
            print("❌ 飞书通知发送错误: \(error.localizedDescription)")
        }
        
        isSending = false
    }
    
    /// 格式化日期
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
    
    /// 测试连接
    func testConnection() async {
        await sendFeishuMessage(
            title: "飞书连接测试",
            content: "这是一条测试消息\n\nAssetManager 飞书通知功能已配置成功！"
        )
    }
}
