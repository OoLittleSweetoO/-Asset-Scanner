import Foundation
import AVFoundation
import SwiftUI
import Combine
import CoreMedia

/// macOS Continuity Camera 扫码服务
/// 使用 iPhone 摄像头进行条码扫描
@MainActor
class ContinuityCameraScanner: NSObject, ObservableObject {
    @Published var scannedCode: String?
    @Published var isScanning = false
    @Published var scanError: String?
    @Published var hasContinuityCamera = false
    
    private var _session: AVCaptureSession?
    var session: AVCaptureSession? { _session }
    private var onScan: ((String) -> Void)?
    
    // 支持的条码类型
    static let supportedTypes: [AVMetadataObject.ObjectType] = [
        .ean8, .ean13, .code128, .code39, .code93,
        .qr, .upce, .itf14
    ]
    
    override init() {
        super.init()
        checkContinuityCamera()
    }
    
    /// 检查是否有 Continuity Camera 可用
    func checkContinuityCamera() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        
        let devices = discovery.devices
        hasContinuityCamera = devices.contains { (device: AVCaptureDevice) -> Bool in
            let name = device.localizedName.lowercased()
            return name.contains("iphone") || device.deviceType == .external
        }
        
        // 打印权限状态
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("📷 相机权限状态: \(status.rawValue) (\(status == .authorized ? "已授权" : "未授权"))")
    }
    
    /// 开始扫码
    func startScanning(onScan: @escaping (String) -> Void) {
        checkContinuityCamera()
        
        guard hasContinuityCamera else {
            scanError = "未检测到 iPhone 摄像头，请确保 iPhone 与 Mac 在同一 iCloud 账户下"
            isScanning = false
            return
        }
        
        // 请求相机权限
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("📷 相机权限状态: \(status.rawValue) (\(status == .authorized ? "已授权" : "未授权"))")
        
        if status == .denied || status == .restricted {
            scanError = "未获得相机权限，请在系统设置 → 隐私与安全 → 相机中允许访问"
            isScanning = false
            return
        }
        
        if status == .notDetermined {
            // 异步请求权限
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted {
                    await MainActor.run {
                        self.startScanningInternal(onScan: onScan)
                    }
                } else {
                    await MainActor.run {
                        self.scanError = "未获得相机权限，请在系统设置中允许访问相机"
                        self.isScanning = false
                    }
                }
            }
            return
        }
        
        // 已授权，直接启动
        startScanningInternal(onScan: onScan)
    }
    
    private func startScanningInternal(onScan: @escaping (String) -> Void) {
        self.onScan = onScan
        self.isScanning = true
        self.scanError = nil
        self.scannedCode = nil
        
        setupAndRunSession()
    }
    
    /// 停止扫码
    func stopScanning() {
        isScanning = false
        if let session = _session, session.isRunning {
            session.stopRunning()
        }
        _session = nil
    }
    
    private func setupAndRunSession() {
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high  // 第一刀：必须设置 preset 触发视频流
        
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        
        print("📷 发现设备: \(discovery.devices.map { "\($0.localizedName) (\($0.deviceType.rawValue))" })")
        
        // 第四刀：优先选 external 设备
        let device = discovery.devices.first { $0.deviceType == .external }
                     ?? discovery.devices.first { $0.localizedName.lowercased().contains("iphone") }
                     ?? discovery.devices.first
        
        guard let device = device else {
            scanError = "未找到可用的摄像头"
            isScanning = false
            return
        }
        
        print("📷 使用设备: \(device.localizedName) (类型: \(device.deviceType.rawValue))")
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                print("✅ 已添加输入设备")
            } else {
                scanError = "无法添加输入设备"
                isScanning = false
                return
            }
            
            // 条码输出
            let metadataOutput = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(metadataOutput) {
                captureSession.addOutput(metadataOutput)
                
                let availableTypes = metadataOutput.availableMetadataObjectTypes
                print("📷 可用条码类型: \(availableTypes.map { $0.rawValue })")
                
                let safeTypes = Self.supportedTypes.filter { availableTypes.contains($0) }
                if safeTypes.isEmpty {
                    scanError = "当前摄像头不支持识别预期的条码类型"
                    isScanning = false
                    return
                }
                print("✅ 支持的条码类型: \(safeTypes.map { $0.rawValue })")
                
                metadataOutput.metadataObjectTypes = safeTypes
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            } else {
                scanError = "无法添加扫码输出设备"
                isScanning = false
                return
            }
            
            // 视频数据输出（强制唤醒）
            let videoOutput = AVCaptureVideoDataOutput()
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .background))
                
                // 第二刀：强制激活 video connection
                if let connection = videoOutput.connection(with: .video) {
                    connection.isEnabled = true
                    print("✅ 已激活视频连接")
                }
                
                print("✅ 已添加视频输出并设置代理")
            }
            
            self._session = captureSession
            
            // 第五刀：在主线程启动会话
            captureSession.startRunning()
            print("✅ 扫码会话已启动（主线程）")
            
        } catch {
            print("❌ 启动失败: \(error.localizedDescription)")
            print("❌ 错误详情: \(error)")
            scanError = "启动失败: \(error.localizedDescription)"
            isScanning = false
        }
    }
}

// MARK: - 条码扫描代理
extension ContinuityCameraScanner: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                     didOutput metadataObjects: [AVMetadataObject],
                                     from connection: AVCaptureConnection) {
        
        guard let machineReadable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = machineReadable.stringValue else { return }
        
        let cleanedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task { @MainActor in
            guard self.isScanning else { return }
            
            print("📷 扫码成功: \(cleanedCode)")
            self.scannedCode = cleanedCode
            self.onScan?(cleanedCode)
            
            // 扫码成功后自动停止
            if let session = self._session, session.isRunning {
                session.stopRunning()
            }
            self._session = nil
        }
    }
}

// MARK: - 视频数据输出代理（故意留空，骗过系统省电机制）
extension ContinuityCameraScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 什么都不做，系统只要检测到有 Delegate 接收数据就会供电唤醒
    }
}
