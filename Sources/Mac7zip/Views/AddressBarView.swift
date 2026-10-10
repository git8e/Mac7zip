import SwiftUI

/// Path bar showing the current folder inside the archive. The path segment is
/// editable like the Windows 7-Zip address bar: type a folder and press Return
/// to jump there.
struct AddressBarView: View {
    @EnvironmentObject var model: AppModel

    @State private var path = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

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
                .help(info.url.path)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)

                TextField("", text: $path)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focused)
                    .onSubmit(commit)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(focused ? 1 : 0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(invalid ? Color.red : Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .frame(maxWidth: 520, alignment: .leading)

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
        .onAppear(perform: syncFromModel)
        .onChange(of: model.currentFolder) { _ in
            if !focused { syncFromModel() }
        }
        .onChange(of: model.archiveInfo?.url) { _ in
            syncFromModel()
        }
    }

    private func syncFromModel() {
        path = model.currentFolder
        invalid = false
    }

    private func commit() {
        if model.navigate(toPath: path) {
            invalid = false
            path = model.currentFolder
        } else {
            invalid = true
        }
    }
}
