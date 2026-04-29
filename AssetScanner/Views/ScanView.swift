import SwiftUI
import UniformTypeIdentifiers

/// 扫码视图 — 全屏相机 + 毛玻璃 overlay
struct ScanView: View {
    @EnvironmentObject var viewModel: AssetViewModel
    @State private var showImportSheet = false
    @State private var manualCode = ""
    @State private var hasScanned = false
    @State private var scanSuccess = false
    @State private var showImportAlert = false
    
    var body: some View {
        CameraScannerView { code in
            guard !hasScanned else { return }
            hasScanned = true
            scanSuccess = true
            
            // 震动反馈
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            viewModel.processBarcode(code)
        }
        .edgesIgnoringSafeArea(.all)
        .overlay {
            // 顶部毛玻璃导航栏
            VStack {
                topOverlay
                Spacer()
                bottomPanel
            }
            .ignoresSafeArea()
            
            // 扫描框动画
            if !scanSuccess {
                scanFrameOverlay
            } else {
                successOverlay
            }
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .onAppear {
            hasScanned = false
            scanSuccess = false
            viewModel.scannedAssetId = nil
        }
        .navigationDestination(isPresented: Binding(
            get: { viewModel.scannedAssetId != nil },
            set: { if !$0 { viewModel.scannedAssetId = nil } }
        )) {
            if let assetId = viewModel.scannedAssetId {
                AssetDetailView(assetId: assetId)
                    .environmentObject(viewModel)
            }
        }
        .fileImporter(
            isPresented: $showImportSheet,
            allowedContentTypes: [
                UTType(filenameExtension: "csv")!,
                UTType(filenameExtension: "xlsx")!,
                UTType(filenameExtension: "xls")!
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await viewModel.importAssets(from: url)
                    }
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - 顶部毛玻璃导航栏
    
    @ViewBuilder
    private var topOverlay: some View {
        HStack {
            Button(action: {}) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            .disabled(true)
            
            Spacer()
            
            Text(L("scan_title"))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .shadow(radius: 2)
            
            Spacer()
            
            Button(action: { showImportSheet = true }) {
                Image(systemName: "square.and.arrow.down")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 16)
        .background(
            VisualEffectBlur(style: .dark)
                .opacity(0.85)
        )
    }
    
    // MARK: - 底部毛玻璃面板
    
    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "barcode.viewfinder")
                        .foregroundColor(Color(red: 0.2, green: 0.4, blue: 0.8))
                    TextField(L("scan_input_placeholder"), text: $manualCode)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.systemBackground).opacity(0.9))
                .cornerRadius(12)
                
                Button(action: {
                    if !manualCode.isEmpty {
                        viewModel.processBarcode(manualCode)
                    }
                }) {
                    Text(L("scan_query"))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(width: 72, height: 44)
                        .font(.system(size: 16))
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.2, green: 0.4, blue: 0.8), Color(red: 0.15, green: 0.35, blue: 0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                }
                .disabled(manualCode.isEmpty)
                .opacity(manualCode.isEmpty ? 0.6 : 1)
            }
            .padding(.horizontal, 20)
            
            Button(action: { showImportSheet = true }) {
                Label(L("scan_import"), systemImage: "square.and.arrow.down")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .font(.system(size: 16))
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.2, green: 0.4, blue: 0.8), Color(red: 0.15, green: 0.35, blue: 0.75)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 120)
        .background(
            VisualEffectBlur(style: .systemMaterial)
                .opacity(0.9)
        )
    }
    
    // MARK: - 扫描框动画
    
    @ViewBuilder
    private var scanFrameOverlay: some View {
        GeometryReader { geo in
            let size = min(geo.size.width * 0.75, 260)
            
            ZStack {
                // 扫描框
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.8), lineWidth: 2.5)
                    .frame(width: size, height: size * 0.6)
                
                // 四角装饰
                cornerDecoration(size: size)
                
                // 扫描线动画
                scanningLine(size: size)
            }
            .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
            
            // 提示文字
            VStack {
                Spacer()
                Text(L("scan_hint"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(8)
                    .padding(.bottom, geo.size.height * 0.22)
            }
        }
        .allowsHitTesting(false)
    }
    
    @ViewBuilder
    private func cornerDecoration(size: CGFloat) -> some View {
        let cornerLen: CGFloat = 30
        let w = size
        let h = size * 0.6
        
        ZStack {
            // 左上
            Path { p in
                p.move(to: CGPoint(x: 0, y: cornerLen))
                p.addLine(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: cornerLen, y: 0))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            
            // 右上
            Path { p in
                p.move(to: CGPoint(x: w - cornerLen, y: 0))
                p.addLine(to: CGPoint(x: w, y: 0))
                p.addLine(to: CGPoint(x: w, y: cornerLen))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            
            // 左下
            Path { p in
                p.move(to: CGPoint(x: 0, y: h - cornerLen))
                p.addLine(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: cornerLen, y: h))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            
            // 右下
            Path { p in
                p.move(to: CGPoint(x: w - cornerLen, y: h))
                p.addLine(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: w, y: h - cornerLen))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .frame(width: w, height: h)
    }
    
    @State private var scanLineOffset: CGFloat = 0
    
    @ViewBuilder
    private func scanningLine(size: CGFloat) -> some View {
        let h = size * 0.6
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.2, green: 0.4, blue: 0.8).opacity(0),
                        Color(red: 0.2, green: 0.4, blue: 0.8).opacity(0.7),
                        Color(red: 0.2, green: 0.4, blue: 0.8).opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: size - 20, height: 2)
            .offset(y: scanLineOffset)
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: 2.0)
                        .repeatForever(autoreverses: true)
                ) {
                    scanLineOffset = h / 2 - 10
                }
            }
    }
    
    // MARK: - 扫码成功覆盖层
    
    @ViewBuilder
    private var successOverlay: some View {
        VStack {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
                .shadow(radius: 10)
                .scaleEffect(scanSuccess ? 1.2 : 0.8)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: scanSuccess)
            
            Text(L("scan_success"))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.top, 8)
            
            Text(L("scan_redirecting"))
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .padding(.top, 4)
            
            Spacer()
                .frame(height: 120)
        }
        .background(Color.black.opacity(0.3))
        .allowsHitTesting(false)
    }
}

// MARK: - VisualEffectBlur (毛玻璃)

struct VisualEffectBlur: UIViewRepresentable {
    var style: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
        return view
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

#Preview {
    ScanView()
        .environmentObject(AssetViewModel())
}
