import Foundation

/// Providers whose usage AI·mana can read straight from the provider's own (undocumented) endpoint.
public enum DirectProvider: String, Sendable, CaseIterable {
    case claude, codex
}

/// The user's explicit opt-in to direct access, per provider. It is the only gate: without a current consent no
/// CLI credential is read, nothing is renewed and no direct endpoint is called, even when a session is stored.
///
/// A consent counts only for the notice version the user accepted; raising `currentNoticeVersion` asks again.
/// `UserDefaults` is thread-safe but not marked `Sendable` in this SDK.
public struct DirectAccessConsent: @unchecked Sendable {
    public static let currentNoticeVersion = 1

    private let defaults: UserDefaults

    /// The app and the widget share `DisplayPreferences.shared`; the Mac passes `.standard`.
    public init(defaults: UserDefaults = DisplayPreferences.shared) {
        self.defaults = defaults
    }

    public func isGranted(_ provider: DirectProvider) -> Bool {
        guard defaults.object(forKey: Self.versionKey(provider)) != nil,
              defaults.integer(forKey: Self.versionKey(provider)) >= Self.currentNoticeVersion else { return false }
        return consentedAt(provider) != nil
    }

    public func grant(_ provider: DirectProvider, now: Date = Date()) {
        defaults.set(now.timeIntervalSince1970, forKey: Self.dateKey(provider))
        defaults.set(Self.currentNoticeVersion, forKey: Self.versionKey(provider))
    }

    public func revoke(_ provider: DirectProvider) {
        defaults.removeObject(forKey: Self.dateKey(provider))
        defaults.removeObject(forKey: Self.versionKey(provider))
    }

    public func consentedAt(_ provider: DirectProvider) -> Date? {
        guard defaults.object(forKey: Self.dateKey(provider)) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: Self.dateKey(provider)))
    }

    static func dateKey(_ provider: DirectProvider) -> String { "directAccess.\(provider.rawValue).consentedAt" }
    static func versionKey(_ provider: DirectProvider) -> String { "directAccess.\(provider.rawValue).noticeVersion" }
}
