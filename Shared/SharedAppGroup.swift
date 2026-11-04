import Foundation

/// Sideloadly 等重签工具会把 App Group 改名，写死的名字会失效。
/// 这里在运行时从各自签名里的描述文件读出真实的 App Group，
/// 主 APP 和广播扩展各读各的，只要重签工具把两边改成同一个，就能对上。
enum SharedAppGroup {
    static let fallback = "group.app.cardcounter"

    static let identifier: String = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>"),
              let plistData = String(text[start.lowerBound..<end.upperBound]).data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String],
              // 两个进程排序后取同一个，保证挑到相同的 App Group
              let group = groups.sorted().first else {
            return fallback
        }
        return group
    }()
}
