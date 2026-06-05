import SwiftUI
import AVFoundation
import Combine
import AppKit

/// 带预览画面的扫码弹窗视图
struct CameraScanSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var scanner: ContinuityCameraScanner
    var onScan: (String) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("扫码")
                    .font(.headline)
                Spacer()
                Button("取消") {
                    scanner.stopScanning()
                    dismiss()
                }
                .foregroundColor(.secondary)
            }
            .padding()
            
            // 相机预览
            CameraPreviewView(session: scanner.session ?? AVCaptureSession())
                .frame(minHeight: 300)
                .background(Color.black)
            
            // 提示文字
            VStack(spacing: 8) {
                if scanner.isScanning {
                    ProgressView("正在扫码...")
                    Text("将条码对准摄像头")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let error = scanner.scanError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding()
        }
        .frame(width: 400, height: 500)
        .onAppear {
            scanner.startScanning { code in
                onScan(code)
                dismiss()
            }
        }
        .onDisappear {
            scanner.stopScanning()
        }
    }
}

/// 相机预览视图 (macOS NSViewRepresentable)
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.wantsLayer = true
        view.layer = previewLayer
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let previewLayer = nsView.layer as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = nsView.bounds
        }
    }
}
