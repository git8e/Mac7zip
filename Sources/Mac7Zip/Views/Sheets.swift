import SwiftUI
import AppKit

// MARK: - Password prompt

struct PasswordPromptView: View {
    let prompt: PasswordPrompt
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                Text(prompt.title).font(.headline)
            }
            Text(prompt.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField(L("Password"), text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("OK")) { submit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func submit() {
        let value = password
        dismiss()
        prompt.onSubmit(value)
    }
}

// MARK: - Extract

struct ExtractSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var destination = ""
    @State private var overwrite: OverwriteMode = .overwrite
    @State private var keepPaths = true
    @State private var usePassword = false
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Extract")).font(.headline)

            Text(scopeText)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(L("Extract to:")).frame(width: 64, alignment: .trailing)
                TextField(L("Destination folder"), text: $destination)
                    .textFieldStyle(.roundedBorder)
                Button(L("Browse…")) { chooseDestination() }
            }

            HStack(spacing: 8) {
                Text(L("Path mode:")).frame(width: 64, alignment: .trailing)
                Picker("", selection: $keepPaths) {
                    Text(L("Full paths")).tag(true)
                    Text(L("No paths")).tag(false)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            HStack(spacing: 8) {
                Text(L("Overwrite mode:")).frame(width: 64, alignment: .trailing)
                Picker("", selection: $overwrite) {
                    ForEach(OverwriteMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(L("Use password"), isOn: $usePassword)
                if usePassword {
                    SecureField(L("Password"), text: $password)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
            }

            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Extract")) { submit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear {
            destination = model.suggestedExtractDestination?.path ?? ""
        }
    }

    private var scopeText: String {
        if let items = model.pendingExtractItems {
            return LF("Will extract the selected %d items.", items.count)
        }
        return L("Will extract the entire contents of the archive.")
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Select")
        if panel.runModal() == .OK, let url = panel.url {
            destination = url.path
        }
    }

    private func submit() {
        let target = URL(fileURLWithPath: destination)
        let pw = usePassword && !password.isEmpty ? password : nil
        dismiss()
        model.performExtract(
            destination: target,
            password: pw,
            overwrite: overwrite,
            keepPaths: keepPaths
        )
    }
}

// MARK: - Add to archive

struct AddSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var archivePath = ""
    @State private var format: ArchiveFormat = .sevenZip
    @State private var level: CompressionLevel = .normal
    @State private var solid = true
    @State private var volume = ""
    @State private var usePassword = false
    @State private var password = ""
    @State private var encryptNames = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Add to Archive")).font(.headline)

            HStack(spacing: 8) {
                Text(L("Archive:")).frame(width: 72, alignment: .trailing)
                TextField("", text: $archivePath)
                    .textFieldStyle(.roundedBorder)
                Button(L("Browse…")) { chooseArchive() }
            }

            HStack(spacing: 8) {
                Text(L("Format:")).frame(width: 72, alignment: .trailing)
                Picker("", selection: $format) {
                    ForEach(ArchiveFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
                .onChange(of: format) { _ in updateExtension() }

                Text(L("Level:")).frame(width: 48, alignment: .trailing)
                Picker("", selection: $level) {
                    ForEach(CompressionLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }

            if format.supportsSolid {
                Toggle(L("Solid compression (better ratio, slightly slower for single files)"), isOn: $solid)
            }

            if format.supportsMultiVolume {
                HStack(spacing: 8) {
                    Text(L("Split to volumes:")).frame(width: 72, alignment: .trailing)
                    TextField(L("e.g. 100m, leave empty for a single file"), text: $volume)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
            }

            if format.supportsPassword {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(L("Use password"), isOn: $usePassword)
                    if usePassword {
                        SecureField(L("Password"), text: $password)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)
                        if format.supportsEncryptNames {
                            Toggle(L("Encrypt file names"), isOn: $encryptNames)
                        }
                    }
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LF("Sources (%d)", model.addSources.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(model.addSources, id: \.self) { url in
                                Text(url.lastPathComponent)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 70)
                }
                .padding(4)
            }

            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("OK")) { submit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            archivePath = model.suggestedArchiveURL?.path ?? ""
            if let ext = model.suggestedArchiveURL?.pathExtension,
               let detected = ArchiveTypes.format(forExtension: ext) {
                format = detected
            }
        }
    }

    private func chooseArchive() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = URL(fileURLWithPath: archivePath).lastPathComponent
        panel.canCreateDirectories = true
        panel.prompt = L("Save")
        if panel.runModal() == .OK, let url = panel.url {
            archivePath = url.path
        }
    }

    private func updateExtension() {
        var url = URL(fileURLWithPath: archivePath.isEmpty ? "Archive" : archivePath)
        url.deletePathExtension()
        archivePath = url.appendingPathExtension(format.fileExtension).path
    }

    private func submit() {
        let options = CreateOptions(
            format: format,
            level: level,
            password: usePassword && !password.isEmpty ? password : nil,
            encryptFileNames: encryptNames,
            solid: solid,
            volumeSize: volume.isEmpty ? nil : volume
        )
        let target = URL(fileURLWithPath: archivePath)
        dismiss()
        model.performCreate(archiveURL: target, options: options)
    }
}

// MARK: - Info

struct InfoSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Archive Information")).font(.headline)
            if let info = model.archiveInfo {
                infoRow(L("Path"), info.url.path)
                infoRow(L("Format"), info.format.isEmpty ? L("Unknown") : info.format)
                infoRow(L("Method"), info.method ?? "-")
                infoRow(L("Solid"), info.solid ? L("Yes") : L("No"))
                infoRow(L("Physical size"), Format.bytes(info.physicalSize))
                infoRow(L("Headers size"), Format.bytes(info.headersSize))
                infoRow(L("Blocks"), info.blocks.map(String.init) ?? "-")
                Divider()
                infoRow(L("Files"), "\(info.fileCount)")
                infoRow(L("Folders"), "\(info.folderCount)")
                infoRow(L("Unpacked size"), Format.bytes(info.totalSize))
            } else {
                Text(L("No archive open")).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(L("OK")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .frame(width: 96, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
    }
}

// MARK: - Rename

struct RenameSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Rename")).font(.headline)
            TextField(L("Name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("OK")) { submit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { name = model.renameTarget?.name ?? "" }
    }

    private func submit() {
        let value = name
        dismiss()
        model.performRename(to: value)
    }
}

// MARK: - Create folder / file

struct CreateEntrySheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.createKind.title).font(.headline)
            TextField(L("Name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("OK")) { submit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { name = model.createKind.placeholder }
    }

    private func submit() {
        let value = name
        dismiss()
        model.performCreateEntry(name: value)
    }
}

// MARK: - Properties (single item)

struct PropertiesSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Properties")).font(.headline)
            if let node = model.propertiesTarget {
                infoRow(L("Name"), node.name)
                infoRow(L("Path"), node.path)
                infoRow(L("Type"), node.typeDescription)
                infoRow(L("Size"), node.isDirectory ? "-" : Format.bytes(node.entry?.size))
                infoRow(L("Packed"), node.isDirectory ? "-" : Format.bytes(node.entry?.packedSize))
                infoRow(L("Modified"), Format.date(node.entry?.modified))
                infoRow(L("Attributes"), node.entry.map(Format.attributes) ?? "-")
                infoRow(L("CRC"), node.entry?.crc ?? "-")
                infoRow(L("Method"), node.entry?.method ?? "-")
                infoRow(L("Encrypted"), (node.entry?.encrypted ?? false) ? L("Yes") : L("No"))
            } else {
                Text(L("No item selected")).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(L("OK")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .frame(width: 96, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
    }
}
