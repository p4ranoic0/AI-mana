import SwiftUI

struct SourceSettingsSection: View {
    let controller: RelayController
    var body: some View { DirectSourcesSection(controller: controller) }
}

struct SourceSettingsNote: View {
    let optionalProviders: [String]
    var body: some View { EmptyView() }
}
