import SwiftUI

struct ImportFilesView: View {
    @ObservedObject var assetVM: AssetViewModel
    
    var body: some View {
        List {
            Section("已导入的文件") {
                if assetVM.sources.isEmpty {
                    Text("暂无导入记录\n点击左上角导入 CSV 文件")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    ForEach(assetVM.sources) { source in
                        ImportSourceRow(source: source)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("删除导入", role: .destructive) {
                                    deleteSource(source)
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("导入文件管理")
    }
    
    private func deleteSource(_ source: macOS_AssetSource) {
        assetVM.deleteSource(source)
    }
}

struct ImportSourceRow: View {
    let source: macOS_AssetSource
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.text.fill")
                Text(source.fileName)
                    .font(.headline)
                    .lineLimit(1)
            }
            HStack {
                Text("⏱️ \(source.importDate, formatter: Self.dateFormatter)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("📄 \(source.assetCount) 个资产")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}