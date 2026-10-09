import SwiftUI

/// Mirrors the 7-Zip File Manager toolbar: up one level, add, extract, test,
/// delete, info.
struct ToolbarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            ToolButton(title: L("Open"), systemImage: "folder") {
                model.openFromPanel()
            }
            Divider().frame(height: 30)
            ToolButton(title: L("Up"), systemImage: "arrow.up", enabled: !model.currentFolder.isEmpty) {
                model.goUp()
            }
            Divider().frame(height: 30)
            ToolButton(title: L("Add"), systemImage: "plus.rectangle.on.folder") {
                model.beginAdd()
            }
            ToolButton(title: L("Extract"), systemImage: "arrow.down.doc", enabled: model.hasArchive) {
                model.beginExtractAll()
            }
            ToolButton(title: L("Test"), systemImage: "checkmark.seal", enabled: model.hasArchive) {
                model.testArchive()
            }
            ToolButton(title: L("Delete"), systemImage: "trash", enabled: model.hasArchive && !model.selection.isEmpty) {
                model.deleteSelected()
            }
            ToolButton(title: L("Info"), systemImage: "info.circle", enabled: model.hasArchive) {
                model.showInfo()
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
