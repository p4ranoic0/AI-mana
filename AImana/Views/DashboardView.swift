import AImanaCore
import SwiftUI
import UIKit

struct DashboardView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Regular width (iPad full screen, wide Split View / Stage Manager windows): cards go into a grid.
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State var model: DashboardViewModel
    @State private var page: SoftPage = .dashboard
    @State private var showSettings = false
    @State private var mode = DisplayPreferences.mode()
    @State private var style = DisplayPreferences.style()
    @State private var theme = AppearancePreferences.theme()
    @State private var accent = AppearancePreferences.accent()
    /// Debug aid: `-open-detail claude` pushes that provider's detail screen at launch.
    @State private var detailID: String?
    /// False until the user picks the file AImana for Mac publishes; the dashboard then shows the setup card.
    @State private var relayConnected = Self.isRelayConnected
    @State private var settingsDetent: PresentationDetent = .medium
    @State private var bottomBarHeight: CGFloat = 0

    var body: some View {
        NavigationStack {
            Group {
                if page == .dashboard {
                    dashboard
                } else {
                    CostsView(usages: model.states.compactMap(\.usage), bottomBarHeight: bottomBarHeight)
                        .refreshable { await model.refresh() }
                }
            }
            .background(SoftTheme.canvas(scheme))
            // The inset reserves the full bar height; spacing keeps the final card clear when scrolled to its end.
            .safeAreaInset(edge: .bottom, spacing: SoftTheme.Space.lg) {
                SoftBottomBar(page: $page, settingsPresented: showSettings, isRefreshing: model.isRefreshing,
                              refresh: { Task { await model.refresh() } },
                              settings: { showSettings = true })
                    // On a wide window the floating bar keeps its iPhone proportions instead of spanning the width.
                    .frame(maxWidth: isRegular ? AdaptiveLayout.bottomBarMaxWidth + 2 * SoftTheme.cardPadding
                                               : .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomBarHeight = $0 }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings, onDismiss: { relayConnected = Self.isRelayConnected }) {
                SettingsView(mode: $mode, style: $style, theme: $theme, accent: $accent) {
                    Task { await model.refresh() }
                }
                .presentationDetents([.medium, .large], selection: $settingsDetent)
                .presentationDragIndicator(.visible)
            }
            .onChange(of: mode) { _, value in
                DisplayPreferences.setMode(value)
                RefreshService.reloadWidgets()
                WatchSync.shared.resendSaved()
            }
            .onChange(of: style) { _, value in
                DisplayPreferences.setStyle(value)
                RefreshService.reloadWidgets()
            }
            .onChange(of: theme) { _, value in AppearancePreferences.setTheme(value) }
            .onChange(of: accent) { _, value in
                AppearancePreferences.setAccent(value)
                RefreshService.reloadWidgets()
            }
            .sensoryFeedback(.selection, trigger: mode)
            .sensoryFeedback(.selection, trigger: style)
            .sensoryFeedback(.success, trigger: model.successfulRefreshCount)
            .sensoryFeedback(.warning, trigger: model.warningTransitionCount)
            .navigationDestination(item: $detailID) { id in
                if let usage = model.states.first(where: { $0.providerID == id })?.usage {
                    ProviderDetailView(usage: usage, mode: mode)
                }
            }
            .task {
                await model.load()
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-open-detail"), args.indices.contains(i + 1) {
                    detailID = args[i + 1]
                }
                if args.contains("-open-costs") { page = .costs }
                // Debug aid for screenshots: `-open-settings` shows Settings full height.
                if args.contains("-open-settings") { settingsDetent = .large; showSettings = true }
            }
        }
        .fontDesign(.rounded)
        .tint(accent.color)
        .preferredColorScheme(theme.colorScheme)
    }

    private var dashboard: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SoftTheme.Space.lg) {
                    header
                    Picker("Headline", selection: $mode) {
                        ForEach(DisplayMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: isRegular ? 420 : .infinity)
                    .accessibilityLabel("Quota display mode")
                    .padding(.vertical, SoftTheme.Space.xs)

                    if model.states.isEmpty && !model.hasLoaded {
                        ProgressView("Loading usage…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SoftTheme.Space.xxl)
                    } else if model.states.allSatisfy({ $0.usage == nil }) {
                        if relayConnected {
                            emptyState
                        } else {
                            MacSetupCard {
                                relayConnected = Self.isRelayConnected
                                Task { await model.refresh() }
                            }
                        }
                    } else {
                        if let summary = OverviewSummary(usages: model.states.compactMap(\.usage), mode: mode) {
                            OverviewHero(summary: summary)
                        }
                        if isRegular {
                            LazyVGrid(columns: AdaptiveLayout.gridColumns(), alignment: .leading,
                                      spacing: SoftTheme.Space.lg) {
                                ForEach(model.states) { providerCard($0) }
                            }
                        } else {
                            ForEach(model.states) { providerCard($0) }
                        }
                    }
                }
                // Compact: maxWidth .infinity is what the stack already gets. Regular: a comfortable centred column.
                .frame(maxWidth: isRegular ? AdaptiveLayout.maxContentWidth : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SoftTheme.cardPadding)
                .padding(.top, SoftTheme.Space.xl)
                .padding(.bottom, SoftTheme.Space.xl + bottomBarHeight + SoftTheme.Space.lg)
                .id("dashboard-content")
            }
            .background(SoftTheme.canvas(scheme))
            .refreshable { await model.refresh() }
            .task(id: model.states.count) {
                guard ProcessInfo.processInfo.arguments.contains("-scroll-bottom"), !model.states.isEmpty else { return }
                await Task.yield()
                scroll.scrollTo("dashboard-content", anchor: .bottom)
            }
        }
    }

    private var isRegular: Bool { sizeClass == .regular }

    @ViewBuilder
    private func providerCard(_ state: ProviderState) -> some View {
        let animationsEnabled = !reduceMotion
        if state.usage == nil, state.error != nil, APIKeyProvider.isAPIKeyProvider(state.providerID) {
            // A rejected or revoked key leaves no data; show the card with its error instead of
            // dropping the provider silently.
            UsageCard(state: state, mode: mode, style: style, showChevron: false)
        } else if let usage = state.usage {
            NavigationLink {
                ProviderDetailView(usage: usage, mode: mode)
            } label: {
                UsageCard(state: state, mode: mode, style: style, showChevron: true)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Open details") { detailID = usage.providerID }
                Button("Copy summary") {
                    UIPasteboard.general.string = UsageSummary.text(for: usage)
                }
                Button("Refresh") {
                    Task { await model.refresh() }
                }
            } preview: {
                UsageCard(state: state, mode: mode, style: style, showChevron: false)
                    .frame(width: 330)
            }
            .scrollTransition(.animated, axis: .vertical) { content, phase in
                content.opacity(!animationsEnabled || phase.isIdentity ? 1 : 0.82)
                    .scaleEffect(!animationsEnabled || phase.isIdentity ? 1 : 0.98)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: SoftTheme.Space.xs) {
                BrandWordmark(font: .system(.largeTitle, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("Quota at a glance")
                    .softText(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Picker("Mode", selection: $mode) {
                    ForEach(DisplayMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Visual Style", selection: $style) {
                    ForEach(DisplayStyle.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Text("Display").softText(.caption).fontWeight(.semibold)
            }
            .accessibilityLabel("Quick display options")
        }
        .padding(.bottom, SoftTheme.Space.md)
    }

    private static var isRelayConnected: Bool {
        BookmarkRelaySource.connectedFileName != nil || AppEnvironment.hasRelayOverride
    }

    private var emptyState: some View {
        let relayUnavailable = model.states.contains { $0.error == .relayUnavailable }
        return ContentUnavailableView {
            Text(AppStrings.text(relayUnavailable ? "Mac relay unavailable" : "No usage data"))
        } description: {
            Text(AppStrings.text(relayUnavailable ? "Connect the relay file in Settings to see your quotas."
                                                  : "Connect the Mac relay or refresh to load your quotas."))
        } actions: {
            Button("Open Settings") { showSettings = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }
}
