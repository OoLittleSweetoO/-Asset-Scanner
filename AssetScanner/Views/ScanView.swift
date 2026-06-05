import SwiftUI
import UniformTypeIdentifiers

/// 扫码视图 — 全屏相机 + 毛玻璃 overlay
struct ScanView: View {
    @EnvironmentObject var viewModel: AssetViewModel
    @State private var showImportSheet = false
    @State private var manualCode = ""
    @State private var hasScanned = false
    @State private var scanSuccess = false
    @State private var scanEnabled = true
    @State private var scanMode: CameraScannerView.ScanMode = .single
    
    private var cleanedManualCode: String {
        manualCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var scanModeTitle: String {
        scanMode == .single ? "单次识别" : "连续识别"
    }
    
    var body: some View {
        CameraScannerView(onScan: { code in
            if scanMode == .single {
                guard !hasScanned else { return }
                hasScanned = true
                scanSuccess = true
            }

            viewModel.processBarcode(code)
        }, isEnabled: scanEnabled, mode: scanMode)
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
                .commaSeparatedText,
                .plainText,
                .text,
                UTType(filenameExtension: "xlsx") ?? .data,
                UTType(mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") ?? .data,
                UTType(filenameExtension: "csv") ?? .commaSeparatedText
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
        VStack(spacing: 14) {
            HStack {
                Circle()
                    .fill(scanEnabled ? Color.green.opacity(0.9) : Color.red.opacity(0.9))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L("scan_title"))
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                    Text(scanEnabled ? scanModeTitle : "扫码已暂停")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.78))
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(action: { showImportSheet = true }) {
                        overlayIcon(symbol: "square.and.arrow.down")
                    }

                    Button(action: { scanEnabled.toggle() }) {
                        overlayIcon(symbol: scanEnabled ? "camera.fill" : "camera.slash.fill")
                            .foregroundColor(scanEnabled ? .white : Color(red: 1.0, green: 0.78, blue: 0.78))
                    }
                    .accessibilityLabel(scanEnabled ? "关闭扫码" : "开启扫码")
                }
            }

            HStack(spacing: 10) {
                statusChip(title: scanEnabled ? "相机开启" : "相机关闭", symbol: scanEnabled ? "camera.aperture" : "pause.circle")
                statusChip(title: scanMode == .single ? "单次模式" : "连续模式", symbol: scanMode == .single ? "viewfinder.circle" : "repeat.circle")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 14)
        .background(
            VisualEffectBlur(style: .dark)
                .opacity(0.88)
        )
    }
    
    // MARK: - 底部毛玻璃面板
    
    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("扫码控制")
                            .font(.subheadline.weight(.semibold))
                        Text(scanEnabled ? "保持镜头开启，随时准备识别" : "暂停识别，保留当前页面")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $scanEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Picker("模式", selection: $scanMode) {
                    Text("单次").tag(CameraScannerView.ScanMode.single)
                    Text("连续").tag(CameraScannerView.ScanMode.continuous)
                }
                .pickerStyle(.segmented)
                .disabled(!scanEnabled)
            }
            .padding(14)
            .background(Color(.systemBackground).opacity(0.92))
            .cornerRadius(16)
            .padding(.horizontal, 20)
            .onChange(of: scanEnabled) { _, enabled in
                if enabled {
                    hasScanned = false
                    scanSuccess = false
                    viewModel.scannedAssetId = nil
                } else {
                    hasScanned = false
                    scanSuccess = false
                }
            }
            .onChange(of: scanMode) { _, newMode in
                if newMode == .continuous {
                    hasScanned = false
                    scanSuccess = false
                }
            }
            
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
                    if !cleanedManualCode.isEmpty {
                        viewModel.processBarcode(cleanedManualCode)
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
                .disabled(cleanedManualCode.isEmpty)
                .opacity(cleanedManualCode.isEmpty ? 0.6 : 1)
            }
            .padding(.horizontal, 20)

            if scanMode == .single, scanSuccess {
                Button(action: {
                    hasScanned = false
                    scanSuccess = false
                    viewModel.scannedAssetId = nil
                }) {
                    Label("重新扫码", systemImage: "arrow.clockwise")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .font(.system(size: 16))
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.25, green: 0.55, blue: 0.9), Color(red: 0.2, green: 0.45, blue: 0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                }
                .padding(.horizontal, 20)
            }
            
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

    @ViewBuilder
    private func overlayIcon(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .frame(width: 36, height: 36)
            .background(Color.white.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func statusChip(title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundColor(.white.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
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
