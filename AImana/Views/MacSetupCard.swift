import AImanaCore
import SwiftUI
import UniformTypeIdentifiers

/// First-run card shown while no relay file is connected: how the Mac and the iPhone fit together, and the picker
/// for the file AImana for Mac publishes.
struct MacSetupCard: View {
    @Environment(\.colorScheme) private var scheme
    let onConnected: () -> Void
    @State private var showPicker = false
    @State private var errorMessage: String?

    private static let steps = [
        "Install AImana for Mac and open it.",
        "It publishes your usage to iCloud Drive, in the AImana folder.",
        "Choose usage-relay.json from that folder here.",
    ]

    private static var description: String {
        "AImana reads Claude Code, Codex and costs from AImana for Mac."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SoftTheme.Space.lg) {
            VStack(alignment: .leading, spacing: SoftTheme.Space.sm) {
                Text("Set up AImana for Mac")
                    .softText(.headline)
                Text(AppStrings.text(Self.description))
                    .softText(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: SoftTheme.Space.md) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: SoftTheme.Space.md) {
                        Text(verbatim: "\(index + 1)")
                            .softText(.caption).fontWeight(.semibold)
                            .monospacedDigit()
                            .frame(width: 22, height: 22)
                            .background(SoftTheme.blue.opacity(scheme == .dark ? 0.30 : 0.55), in: Circle())
                            .accessibilityHidden(true)
                        Text(AppStrings.text(step))
                            .softText(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Button {
                showPicker = true
            } label: {
                Text("Choose relay file…")
                    .softText(.body).fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SoftTheme.Space.xs)
            }
            .buttonStyle(.borderedProminent)

            if let errorMessage {
                Text(errorMessage)
                    .softText(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(SoftTheme.cardPadding)
        .softSurface(tint: SoftTheme.blue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    try BookmarkRelaySource.connect(to: url)
                    errorMessage = nil
                    onConnected()
                } catch {
                    errorMessage = AppStrings.text("Could not access that file.")
                }
            case .failure:
                errorMessage = AppStrings.text("Could not open the file picker result.")
            }
        }
    }
}
