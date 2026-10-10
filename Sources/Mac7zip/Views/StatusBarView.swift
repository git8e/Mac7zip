import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Text(statusLeading)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let version = model.engineVersion {
                Text(version)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: 22)
    }

    private var statusLeading: String {
        if !model.selectionSummary.isEmpty { return model.selectionSummary }
        return model.statusText
    }
}
