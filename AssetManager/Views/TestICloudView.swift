import SwiftUI

struct TestICloudView: View {
    @EnvironmentObject var syncService: iCloudSyncService
    @State private var testResult = ""
    @State private var testValue = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("iCloud 同步测试").font(.title).padding()
            
            Text("iCloud 状态: \(syncService.isICloudAvailable ? "可用 ✅" : "不可用 ❌")")
                .foregroundColor(syncService.isICloudAvailable ? .green : .red)
            
            if let lastSync = syncService.lastSyncTime {
                Text("最后同步: \(lastSync, formatter: Self.dateFormatter)").font(.caption)
            }
            
            Divider()
            TextField("输入测试值", text: $testValue).textFieldStyle(RoundedBorderTextFieldStyle()).padding(.horizontal)
            HStack {
                Button("写入 iCloud") { writeValue() }.buttonStyle(.borderedProminent)
                Button("读取 iCloud") { readValue() }.buttonStyle(.bordered)
            }
            
            if !testResult.isEmpty {
                Text("结果: \(testResult)").multilineTextAlignment(.center).padding().background(Color.gray.opacity(0.1)).cornerRadius(8)
            }
            Spacer()
        }.padding()
    }
    
    private func writeValue() {
        guard let icloud = UserDefaults(suiteName: "iCloud.com.user.AssetsScanner") else { testResult = "iCloud 不可用"; return }
        icloud.set(testValue, forKey: "test_\(Date().timeIntervalSince1970)")
        testResult = "写入成功"
    }
    
    private func readValue() {
        guard let icloud = UserDefaults(suiteName: "iCloud.com.user.AssetsScanner") else { testResult = "iCloud 不可用"; return }
        if let value = icloud.string(forKey: "test_value") { testResult = "读取成功: \(value)" }
        else { testResult = "未找到测试值" }
    }
    static let dateFormatter: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f }()
}