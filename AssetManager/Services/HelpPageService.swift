import Foundation
import AppKit

enum HelpPageService {
    static func openAssetManagerHelpPage() {
        let url = preparedHelpPageURL()
        NSWorkspace.shared.open(url)
    }

    private static func preparedHelpPageURL() -> URL {
        if let bundled = Bundle.main.url(forResource: "AssetManagerHelp", withExtension: "html") {
            return bundled
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssetManager-Help")
            .appendingPathExtension("html")

        do {
            try htmlContent.write(to: temporaryURL, atomically: true, encoding: .utf8)
            return temporaryURL
        } catch {
            let fallbackURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("AssetManager-Help-Fallback")
                .appendingPathExtension("html")
            try? fallbackHTML.write(to: fallbackURL, atomically: true, encoding: .utf8)
            return fallbackURL
        }
    }

    private static var htmlContent: String {
        if let sourceURL = Bundle.main.url(forResource: "AssetManagerHelp", withExtension: "html"),
           let content = try? String(contentsOf: sourceURL, encoding: .utf8) {
            return content
        }

        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>AssetManager 使用说明</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif; margin: 40px auto; max-width: 920px; padding: 0 20px; line-height: 1.7; color: #172033; background: #f5f7fb; }
            h1, h2 { color: #1f4fbf; }
            .box { background: white; border: 1px solid rgba(23,32,51,0.08); border-radius: 14px; padding: 20px; margin-bottom: 16px; }
            code { background: rgba(50,104,204,0.08); color: #3268cc; padding: 2px 6px; border-radius: 6px; }
          </style>
        </head>
        <body>
          <h1>AssetManager 使用说明</h1>
          <div class="box">
            <p>当前帮助页资源未打包进应用，所以这里展示的是内置回退版本。</p>
            <p>你可以从工具栏查看资产列表、资产管理、历史记录、配置保存/读取、iCloud 同步、飞书同步、Reminder 同步等功能说明。</p>
          </div>
        </body>
        </html>
        """
    }

    private static let fallbackHTML = """
    <!doctype html>
    <html lang="zh-CN">
    <head>
      <meta charset="utf-8">
      <title>AssetManager 帮助</title>
    </head>
    <body>
      <p>帮助页打开失败，请稍后重试。</p>
    </body>
    </html>
    """
}
