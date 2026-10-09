import SwiftUI

/// Path bar showing the current folder inside the archive, with clickable
/// breadcrumb segments.
struct AddressBarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "archivebox")
                .foregroundStyle(.secondary)

            if let info = model.archiveInfo {
                Button {
                    model.goRoot()
                } label: {
                    Text(info.url.lastPathComponent)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)

                ForEach(Array(model.breadcrumb.enumerated()), id: \.offset) { index, component in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Button(component) {
                        model.go(to: index)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if !info.format.isEmpty {
                    Text(info.format.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(L("No archive open"))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
