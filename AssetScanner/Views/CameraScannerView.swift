import SwiftUI
import AVFoundation

/// 相机扫码视图 (UIViewRepresentable)
struct CameraScannerView: UIViewRepresentable {
    enum ScanMode: String, CaseIterable {
        case single
        case continuous
    }

    var onScan: (String) -> Void
    var isEnabled: Bool = true
    var mode: ScanMode = .single
    
    func makeUIView(context: Context) -> UIView {
        let view = ScannerUIView(onScan: onScan)
        view.backgroundColor = .black
        view.clipsToBounds = true
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? ScannerUIView else { return }
        view.setMode(mode)
        view.setEnabled(isEnabled)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        (uiView as? ScannerUIView)?.stopScanning()
    }
}

/// 内部 UIView — 管理 AVCaptureSession
private class ScannerUIView: UIView {
    private let session = AVCaptureSession()
    private let onScan: (String) -> Void
    private let sessionQueue = DispatchQueue(label: "asset-scanner.camera-session")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false
    private var didEmitCode = false
    private var isEnabled = true
    private var mode: CameraScannerView.ScanMode = .single
    private var lastScannedCode: String?
    private var lastScanAt: Date?
    private let continuousDebounceSeconds: TimeInterval = 1.0
    private lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    init(onScan: @escaping (String) -> Void) {
        self.onScan = onScan
        super.init(frame: .zero)
        setupMessageLabel()
        prepareCamera()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit {
        stopScanning()
    }

    func stopScanning() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled

        if enabled {
            showMessage("正在启动相机...")
            resetEmission()
            prepareCamera()
        } else {
            stopScanning()
            showMessage("扫码已关闭")
        }
    }

    func setMode(_ mode: CameraScannerView.ScanMode) {
        self.mode = mode
        if mode == .continuous {
            resetEmission()
        }
    }

    func resetEmission() {
        didEmitCode = false
        lastScannedCode = nil
        lastScanAt = nil
    }

    private func setupMessageLabel() {
        messageLabel.text = "正在启动相机..."
        addSubview(messageLabel)
        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func prepareCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.setupSession() : self?.showMessage("未获得相机权限\n请在系统设置中允许 AssetScanner 访问相机")
                }
            }
        case .denied, .restricted:
            showMessage("未获得相机权限\n请在系统设置中允许 AssetScanner 访问相机")
        @unknown default:
            showMessage("无法确认相机权限")
        }
    }
    
    private func setupSession() {
        guard !isConfigured else {
            startSession()
            return
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.showMessage("未找到可用的后置摄像头") }
                return
            }
            self.session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard self.session.canAddOutput(output) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.showMessage("无法启动条码识别") }
                return
            }
            self.session.addOutput(output)

            let supportedTypes = BarcodeScannerService.supportedTypes.filter {
                output.availableMetadataObjectTypes.contains($0)
            }
            guard !supportedTypes.isEmpty else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.showMessage("当前相机不支持条码识别") }
                return
            }

            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = supportedTypes
            self.session.commitConfiguration()
            self.isConfigured = true

            DispatchQueue.main.async {
                self.attachPreviewLayerIfNeeded()
                self.messageLabel.isHidden = true
            }
            self.startSession()
        }
    }

    private func startSession() {
        guard isEnabled else { return }
        sessionQueue.async { [session] in
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    private func attachPreviewLayerIfNeeded() {
        guard previewLayer == nil else { return }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = bounds
        layer.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer
    }

    private func showMessage(_ message: String) {
        messageLabel.text = message
        messageLabel.isHidden = false
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

extension ScannerUIView: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard isEnabled else { return }
        guard let machineReadable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = machineReadable.stringValue else { return }
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        switch mode {
        case .single:
            guard !didEmitCode else { return }
            didEmitCode = true
            onScan(cleaned)
        case .continuous:
            let now = Date()
            if let lastCode = lastScannedCode, let lastAt = lastScanAt,
               lastCode == cleaned, now.timeIntervalSince(lastAt) < continuousDebounceSeconds {
                return
            }
            lastScannedCode = cleaned
            lastScanAt = now
            onScan(cleaned)
        }
    }
}
