import Foundation

/// 黄金当前实际保管人 / 持有人（如首饰或积存金在家庭哪位成员手上）。
/// 未设置（空字符串 / `nil`）代表自己持有，列表不额外展示人物头像。
enum HoldingHolder: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case mother
    case father
    case husband
    case wife
    case child
    case grandfather
    case grandmother

    var id: String { rawValue }

    /// 本地化角色称呼。
    var displayName: String {
        switch self {
        case .mother: L10n.tr("母亲")
        case .father: L10n.tr("父亲")
        case .husband: L10n.tr("老公")
        case .wife: L10n.tr("老婆")
        case .child: L10n.tr("孩子")
        case .grandfather: L10n.tr("爷爷")
        case .grandmother: L10n.tr("奶奶")
        }
    }

    /// 详情页与无障碍朗读用的归属短语（如「母亲持有」）。
    var ownershipLabel: String {
        L10n.fmt("%@持有", displayName)
    }

    /// 解析存储或同步过来的原始字符串；空字符串或非法值返回 `nil`。
    static func parse(_ raw: String?) -> HoldingHolder? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return HoldingHolder(rawValue: trimmed)
    }

    /// 校验云端文档字段：允许 `nil` 或合法枚举值。
    static func isValidCloudValue(_ raw: String?) -> Bool {
        guard let raw else { return true }
        return HoldingHolder(rawValue: raw) != nil
    }
}
