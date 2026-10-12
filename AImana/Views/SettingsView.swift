import AImanaCore
import SwiftUI
import UniformTypeIdentifiers

/// Connects the app to the relay file published by the user's computer.
struct SettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var mode: DisplayMode
    @Binding var style: DisplayStyle
    @Binding var theme: AppearanceTheme
    @Binding var accent: AppearanceAccent
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var connectedFile = BookmarkRelaySource.connectedFileName
    @State private var showPicker = false
    @State private var errorMessage: String?
    @State private var refreshInterval = RefreshPreferences.interval()
    @State private var liveActivitiesEnabled = LiveActivityPreferences.isEnabled()
    /// Where the computer got each provider's numbers, from the last saved snapshot.
    @State private var sources = Self.savedSources()
    /// Debug aid for screenshots: `-open-notifications` opens the Notifications screen directly.
    @State private var showNotifications = ProcessInfo.processInfo.arguments.contains("-open-notifications")
    /// Debug aid for screenshots: `-open-more-providers` (or `-open-api-key <id>`) opens More providers directly.
    @State private var showMoreProviders = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(DisplayMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Visual Style", selection: $style) {
                        ForEach(DisplayStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Display")
                } footer: {
                    Text("Colour and low-quota warnings always follow what remains.")
                }
                .listRowBackground(SoftTheme.peach.opacity(scheme == .dark ? 0.13 : 0.20))
                Section("Appearance") {
                    Picker("Theme", selection: $theme) {
                        ForEach(AppearanceTheme.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Accent color", selection: $accent) {
                        ForEach(AppearanceAccent.allCases) { option in
                            Label {
                                Text(option.title)
                            } icon: {
                                Image(systemName: "circle.fill").foregroundStyle(option.color)
                            }
                            .tag(option)
                        }
                    }
                }
                .listRowBackground(SoftTheme.pink.opacity(scheme == .dark ? 0.12 : 0.17))
                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }
                }
                .listRowBackground(SoftTheme.yellow.opacity(scheme == .dark ? 0.10 : 0.18))
                Section("Live Activities") {
                    Toggle("Live Activity during active sessions", isOn: $liveActivitiesEnabled)
                        .onChange(of: liveActivitiesEnabled) { _, value in
                            LiveActivityPreferences.setEnabled(value)
                            onChanged()
                        }
                }
                .listRowBackground(SoftTheme.olive.opacity(scheme == .dark ? 0.10 : 0.18))
                Section {
                    Picker("Refresh interval", selection: $refreshInterval) {
                        ForEach(RefreshInterval.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Updates")
                } footer: {
                    Text("Widgets show what your computer published the last time AImana ran, with how old it is. iOS decides when AImana can refresh in the background.")
                }
                .listRowBackground(SoftTheme.olive.opacity(scheme == .dark ? 0.14 : 0.18))
                .onChange(of: refreshInterval) { _, interval in
                    RefreshPreferences.setInterval(interval)
                    RefreshService.schedule()
                    RefreshService.reloadWidgets()   // their next reload follows the new interval
                }
                Section {
                    MoreProvidersLink(onChanged: onChanged)
                } footer: {
                    Text("GitHub Copilot, OpenRouter, DeepSeek, Moonshot (Kimi) and xAI, with your own API key.")
                }
                .listRowBackground(SoftTheme.yellow.opacity(scheme == .dark ? 0.10 : 0.18))
                Section {
                    if let connectedFile {
                        Text(connectedFile)
                        ForEach(sources, id: \.name) { item in
                            VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
                                Text(verbatim: item.name)
                                Text(item.caption).softText(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button("Choose a different file…") { showPicker = true }
                        Button("Disconnect", role: .destructive) {
                            BookmarkRelaySource.disconnect()
                            self.connectedFile = nil
                            onChanged()
                        }
                    } else {
                        Button("Choose relay file…") { showPicker = true }
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                } header: {
                    Text("Your computer")
                } footer: {
                    Text("AImana for Mac, or usage-relay on Windows and Linux, publishes usage-relay.json to a synced folder (iCloud Drive or OneDrive). Choose that file once.")
                }
                .listRowBackground(SoftTheme.blue.opacity(scheme == .dark ? 0.12 : 0.20))
                .id("relay")
            }
            // Outside the Form: SwiftUI ignores navigation destinations declared inside lazy containers.
            .navigationDestination(isPresented: $showMoreProviders) { MoreProvidersView(onChanged: onChanged) }
            .navigationDestination(isPresented: $showNotifications) { NotificationSettingsView() }
            .onAppear {
                let launchArgs = ProcessInfo.processInfo.arguments
                if launchArgs.contains("-open-more-providers") || launchArgs.contains("-open-api-key") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showMoreProviders = true }
                }
                // Debug aid for screenshots: `-settings-scroll-relay` jumps to the relay section.
                if ProcessInfo.processInfo.arguments.contains("-settings-scroll-relay") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo("relay", anchor: .top) }
                }
            }
            }
            .scrollContentBackground(.hidden)
            .background(SoftTheme.canvas(scheme))
            .fontDesign(.rounded)
            .softText(.body)
            .hardTopScrollEdge()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        try BookmarkRelaySource.connect(to: url)
                        connectedFile = BookmarkRelaySource.connectedFileName
                        errorMessage = nil
                        sources = []   // a different computer may report different sources; shown again next time
                        onChanged()
                    } catch {
                        errorMessage = AppStrings.text("Could not access that file.")
                    }
                case .failure:
                    errorMessage = AppStrings.text("Could not open the file picker result.")
                }
            }
        }
    }

    private static func savedSources() -> [(name: String, caption: String)] {
        guard BookmarkRelaySource.connectedFileName != nil else { return [] }
        return AppGroup.snapshotStore().load().compactMap { info in
            info.source.map { (name: info.providerName, caption: $0.caption) }
        }
    }
}
