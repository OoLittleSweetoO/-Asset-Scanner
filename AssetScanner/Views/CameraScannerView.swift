import SwiftUI
import AVFoundation

/// 相机扫码视图 (UIViewRepresentable)
struct CameraScannerView: UIViewRepresentable {
    var onScan: (String) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = ScannerUIView(onScan: onScan)
        view.backgroundColor = .black
        view.clipsToBounds = true
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// 内部 UIView — 管理 AVCaptureSession
private class ScannerUIView: UIView {
    private let session = AVCaptureSession()
    private let onScan: (String) -> Void
    
    init(onScan: @escaping (String) -> Void) {
        self.onScan = onScan
        super.init(frame: .zero)
        setupSession()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
    
    private func setupSession() {
        session.sessionPreset = .high
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = BarcodeScannerService.supportedTypes
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = layer.bounds
        layer.insertSublayer(previewLayer, at: 0)
        
        Task { session.startRunning() }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if let previewLayer = layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            // 确保 previewLayer 铺满整个 UIView
            previewLayer.frame = bounds
        }
    }
}

extension ScannerUIView: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let machineReadable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = machineReadable.stringValue else { return }
        onScan(code)
    }
}
