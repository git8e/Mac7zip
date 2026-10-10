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

/// A flat, Windows-style progress bar drawn from primitives, so its thickness is
/// predictable on macOS (the platform `ProgressView` renders as a thin line).
/// Pass `nil` for an animated indeterminate bar.
struct ProgressBar: View {
    var fraction: Double?
    var height: CGFloat = 12

    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor))
                if let fraction {
                    Capsule(style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: max(0, min(1, fraction)) * width)
                } else {
                    Capsule(style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: width * 0.3)
                        .offset(x: phase * width * 1.3 - width * 0.3)
                        .onAppear {
                            phase = 0
                            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                                phase = 1
                            }
                        }
                }
            }
        }
        .frame(height: height)
    }
}

/// Centered progress dialog shown while an operation runs, styled after the
/// Windows 7-Zip progress window: an opaque panel with the operation title, the
/// current file, a full-width progress bar, the file count and a Cancel button.
struct ProgressOverlay: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let detail: String
    let fraction: Double?
    var processed: Int = 0
    var total: Int = 0

    private let width: CGFloat = 440

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            progressSection

            HStack {
                Spacer()
                Button(L("Cancel")) { model.cancelCurrentOperation() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: width)
        .background(
            Color(nsColor: .windowBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 22, y: 10)
    }

    @ViewBuilder
    private var progressSection: some View {
        if let fraction {
            VStack(alignment: .leading, spacing: 6) {
                ProgressBar(fraction: fraction)
                HStack {
                    if total > 0 {
                        Text(LF("Files: %d / %d", processed, total))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            ProgressBar(fraction: nil)
        }
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
