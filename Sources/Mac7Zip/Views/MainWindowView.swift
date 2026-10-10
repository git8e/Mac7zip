import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var localization = Localization.shared
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView()
            Divider()
            AddressBarView()
            Divider()

            ZStack {
                if model.showTreePanel {
                    HSplitView {
                        FolderTreeView()
                            .frame(minWidth: 170, idealWidth: 230, maxWidth: 440)
                        contentView
                            .frame(minWidth: 420)
                    }
                } else {
                    contentView
                }
                if !model.hasArchive && !model.isLoading {
                    EmptyStateView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            StatusBarView()
        }
        .frame(minWidth: 840, minHeight: 520)
        .overlay(alignment: .top) {
            if model.isBusy, let progress = model.progress {
                ProgressOverlay(title: progress.title, detail: progress.detail, fraction: progress.fraction)
            } else if model.isLoading {
                ProgressOverlay(title: L("Opening…"), detail: "", fraction: nil)
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [6]))
                    .padding(6)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
        .sheet(item: $model.passwordPrompt) { prompt in
            PasswordPromptView(prompt: prompt)
        }
        .sheet(isPresented: $model.showExtractSheet) {
            ExtractSheet()
        }
        .sheet(isPresented: $model.showAddSheet) {
            AddSheet()
        }
        .sheet(isPresented: $model.showInfoSheet) {
            InfoSheet()
        }
        .sheet(isPresented: $model.showRenameSheet) {
            RenameSheet()
        }
        .sheet(isPresented: $model.showCreateSheet) {
            CreateEntrySheet()
        }
        .sheet(isPresented: $model.showPropertiesSheet) {
            PropertiesSheet()
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(L("OK")))
            )
        }
        .onAppear {
            model.loadVersionIfNeeded()
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch model.viewMode {
        case .icons:
            IconGridView()
        case .list, .details:
            DetailsListView()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                model.open(url: url)
            }
        }
        return true
    }
}
