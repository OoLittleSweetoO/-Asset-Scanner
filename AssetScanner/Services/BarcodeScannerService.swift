import Foundation
import AVFoundation

/// 条形码扫描服务
class BarcodeScannerService: NSObject, ObservableObject {
    @Published var scannedCode: String?
    @Published var isScanning = false
    @Published var scanError: String?
    
    // 支持的条码类型
    static let supportedTypes: [AVMetadataObject.ObjectType] = [
        .ean8,
        .ean13,
        .code128,
        .code39,
        .code93,
        .qr,
        .upce,
        .itf14
    ]
    
    /// 验证条码格式
    func validateBarcode(_ code: String) -> Bool {
        return !code.isEmpty && code.count >= 3
    }
    
    /// 清理条码字符串
    func cleanBarcode(_ code: String) -> String {
        return code.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
