import Foundation

/// Small status sidecar for failures that cannot be represented by UsageInfo snapshots.
///
/// Sign-in problems are kept per provider, so an expired login for one provider never puts a
/// "sign in again" note under another provider whose data is fresh.
public enum WidgetStatusPreferences {
    /// Legacy global flag (a Bool). Still read for compatibility, but it never names a provider, so an old `true`
    /// counts as "unknown" and puts no note under any provider.
    static let legacyLoginKey = "widget.loginRequired"
    static let loginProvidersKey = "widget.loginRequiredProviders"

    /// IDs of the providers whose sign-in has expired, as of the last refresh.
    public static func loginRequiredProviderIDs(defaults: UserDefaults = DisplayPreferences.shared) -> Set<String> {
        Set(defaults.stringArray(forKey: loginProvidersKey) ?? [])
    }

    public static func setLoginRequiredProviderIDs(_ ids: Set<String>,
                                                   defaults: UserDefaults = DisplayPreferences.shared) {
        defaults.set(ids.sorted(), forKey: loginProvidersKey)
        defaults.removeObject(forKey: legacyLoginKey)
    }

    /// Records which providers in a refresh need signing in again.
    public static func update(from states: [ProviderState], defaults: UserDefaults = DisplayPreferences.shared) {
        setLoginRequiredProviderIDs(providersNeedingSignIn(states), defaults: defaults)
    }

    /// A provider needs signing in only when its own state reports an authentication failure; other providers'
    /// failures never count.
    public static func providersNeedingSignIn(_ states: [ProviderState]) -> Set<String> {
        Set(states.filter { $0.error == .unauthenticated }.map(\.providerID))
    }

    /// True when `providerID` needs signing in again.
    public static func loginRequired(for providerID: String,
                                     defaults: UserDefaults = DisplayPreferences.shared) -> Bool {
        loginRequiredProviderIDs(defaults: defaults).contains(providerID)
    }
}
