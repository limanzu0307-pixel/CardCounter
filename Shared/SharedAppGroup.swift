import Foundation
import Security

/// 免费 Apple 账号不支持 App Group，改用同队列的 keychain 共享组传数据。
/// 运行时从各自签名的描述文件里读出真实的共享组（重签工具会改前缀），
/// 主 APP 和广播扩展都指向同一个组，就能互相读写。
enum SharedKeychain {
    /// 真实的 keychain 共享组，形如 <团队前缀>.app.cardcounter.shared。
    static let group: String? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>"),
              let plistData = String(text[start.lowerBound..<end.upperBound]).data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["keychain-access-groups"] as? [String] else {
            return nil
        }
        return groups.first { $0.hasSuffix(".shared") } ?? groups.sorted().first
    }()
}

/// 广播扩展和主 APP 共用的键值存储，底层用 keychain。
protocol BroadcastBackend: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
}

final class KeychainBackend: BroadcastBackend {
    private let service = "app.cardcounter.broadcast"
    private let group = SharedKeychain.group

    private func base(_ key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    func data(forKey key: String) -> Data? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func set(_ data: Data, forKey key: String) {
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(base(key) as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = base(key)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
