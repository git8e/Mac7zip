import SwiftUI

/// A 7-Zip style toolbar button: icon above a small caption.
struct ToolButton: View {
    let title: String
    let systemImage: String
    var enabled: Bool = true
    var showsCaption: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .regular))
                if showsCaption {
                    Text(title).font(.system(size: 10))
                }
            }
            .frame(width: showsCaption ? 58 : 40, height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.6))
        .disabled(!enabled)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering && enabled ? Color.secondary.opacity(0.14) : Color.clear)
        )
        .onHover { hovering = $0 && enabled }
        .help(title)
    }
}

/// Progress HUD shown while an operation runs.
struct ProgressOverlay: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let detail: String
    let fraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(title).font(.system(size: 12, weight: .medium))
            }
            if let fraction {
                ProgressView(value: fraction)
                    .frame(width: 320)
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().progressViewStyle(.linear).frame(width: 320)
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 320, alignment: .leading)
            }
            HStack {
                Spacer()
                Button(L("Cancel")) { model.cancelCurrentOperation() }
                    .controlSize(.small)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2))
        )
        .shadow(radius: 12)
        .padding(.top, 44)
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "archivebox")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("Mac7zip")
                .font(.title2.weight(.semibold))
            Text(L("Open an archive, or drop one onto the window"))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    model.openFromPanel()
                } label: {
                    Label(L("Open Archive"), systemImage: "folder")
                }
                Button {
                    model.beginAdd()
                } label: {
                    Label(L("New Archive"), systemImage: "plus")
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
