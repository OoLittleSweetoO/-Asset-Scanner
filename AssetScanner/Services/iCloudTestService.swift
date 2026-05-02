import Foundation

/// 简单的 iCloud 可用性测试
class iCloudTestService {
    static func isICloudAvailable() -> Bool {
        let icloudDefaults = UserDefaults(suiteName: "iCloud.com.user.AssetsScanner")
        return icloudDefaults != nil
    }
    
    static func testICloudWrite() -> Bool {
        guard let icloudDefaults = UserDefaults(suiteName: "iCloud.com.user.AssetsScanner") else {
            return false
        }
        
        icloudDefaults.set("test_value", forKey: "icloud_test_key")
        return true
    }
    
    static func testICloudRead() -> String? {
        guard let icloudDefaults = UserDefaults(suiteName: "iCloud.com.user.AssetsScanner") else {
            return nil
        }
        
        return icloudDefaults.string(forKey: "icloud_test_key")
    }
}