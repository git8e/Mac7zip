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

// MARK: - Shared dialog pieces

/// A right-aligned label in a fixed-width column so the controls of a dialog
/// line up, mirroring the grid of the Windows 7-Zip dialogs.
private struct FormRow<Content: View>: View {
    let label: String
    var width: CGFloat = 150
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: width, alignment: .trailing)
            content()
        }
    }
}

/// A password field that can reveal its text, shared by the Add and Extract
/// dialogs.
private struct PasswordField: View {
    let placeholder: String
    @Binding var text: String
    let revealed: Bool
    var width: CGFloat = 190

    var body: some View {
        Group {
            if revealed {
                TextField(placeholder, text: $text)
            } else {
                SecureField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.roundedBorder)
        .frame(width: width)
    }
}

// MARK: - Extract

struct ExtractSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var destination = ""
    @State private var overwrite: OverwriteMode = .overwrite
    @State private var pathMode: ExtractPathMode = .fullPaths
    @State private var eliminateRoot = false
    @State private var useSubfolder = false
    @State private var subfolder = ""
    @State private var password = ""
    @State private var showPassword = false

    private let labelWidth: CGFloat = 185
    private let controlWidth: CGFloat = 210

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Extract")).font(.headline)

            Text(scopeText)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(L("Extract to:")).frame(width: labelWidth, alignment: .trailing)
                TextField(L("Destination folder"), text: $destination)
                    .textFieldStyle(.roundedBorder)
                Button(L("Browse…")) { chooseDestination() }
            }

            FormRow(label: L("Extract into subfolder:"), width: labelWidth) {
                HStack(spacing: 8) {
                    Toggle("", isOn: $useSubfolder)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                    TextField("", text: $subfolder)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: controlWidth)
                        .disabled(!useSubfolder)
                }
            }

            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 10) {
                    FormRow(label: L("Path mode:"), width: labelWidth) {
                        Picker("", selection: $pathMode) {
                            ForEach(ExtractPathMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: controlWidth)
                    }

                    Toggle(L("Eliminate duplication of root folder"), isOn: $eliminateRoot)

                    FormRow(label: L("Overwrite mode:"), width: labelWidth) {
                        Picker("", selection: $overwrite) {
                            ForEach(OverwriteMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: controlWidth)
                    }
                }
                .frame(width: labelWidth + 8 + controlWidth, alignment: .leading)

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        PasswordField(placeholder: L("Password"), text: $password, revealed: showPassword)
                        Toggle(L("Show Password"), isOn: $showPassword)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text(L("Password"))
                }
                .frame(width: 250)
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
        .frame(width: 745)
        .onAppear {
            destination = model.suggestedExtractDestination?.path ?? ""
            subfolder = model.archiveInfo?.url.deletingPathExtension().lastPathComponent ?? ""
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
        var target = URL(fileURLWithPath: destination)
        if useSubfolder, !subfolder.isEmpty {
            target.appendPathComponent(subfolder)
        }
        let pw = password.isEmpty ? nil : password
        dismiss()
        model.performExtract(
            destination: target,
            password: pw,
            overwrite: overwrite,
            pathMode: pathMode,
            eliminateRoot: eliminateRoot
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
    @State private var solidBlock: SolidBlockOption = .auto
    @State private var volume = ""
    @State private var password = ""
    @State private var password2 = ""
    @State private var showPassword = false
    @State private var encryptNames = false
    @State private var encryptionMethod: EncryptionMethod = .aes256
    @State private var method: String = ""
    @State private var dictionary: String = ""
    @State private var wordSize: String = ""
    @State private var threads: ThreadOption = .auto
    @State private var updateMode: UpdateMode = .addAndReplace
    @State private var pathMode: PathMode = .relative
    @State private var compressSharedFiles = false
    @State private var deleteAfterCompression = false
    @State private var parameters = ""
    @State private var errorMessage: String?

    private let labelWidth: CGFloat = 150
    private let controlWidth: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Add to Archive")).font(.headline)

            HStack(spacing: 8) {
                Text(L("Archive:")).frame(width: labelWidth, alignment: .trailing)
                TextField("", text: $archivePath)
                    .textFieldStyle(.roundedBorder)
                Button(L("Browse…")) { chooseArchive() }
            }

            HStack(alignment: .top, spacing: 32) {
                leftColumn
                rightColumn
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
                    .frame(height: 60)
                }
                .padding(4)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
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
        .frame(width: 820)
        .onAppear {
            archivePath = model.suggestedArchiveURL?.path ?? ""
            if let ext = model.suggestedArchiveURL?.pathExtension,
               let detected = ArchiveTypes.format(forExtension: ext) {
                format = detected
            }
            if let first = format.encryptionMethods.first {
                encryptionMethod = first
            }
        }
    }

    // MARK: Columns

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            FormRow(label: L("Archive format:"), width: labelWidth) {
                Picker("", selection: $format) {
                    ForEach(ArchiveFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .labelsHidden()
                .frame(width: controlWidth)
                .onChange(of: format) { _ in formatChanged() }
            }

            FormRow(label: L("Compression level:"), width: labelWidth) {
                Picker("", selection: $level) {
                    ForEach(CompressionLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .labelsHidden()
                .frame(width: controlWidth)
            }

            if !format.compressionMethods.isEmpty {
                FormRow(label: L("Compression method:"), width: labelWidth) {
                    Picker("", selection: $method) {
                        Text(L("Automatic")).tag("")
                        ForEach(format.compressionMethods, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: controlWidth)
                    .onChange(of: method) { _ in wordSize = "" }
                }

                FormRow(label: L("Dictionary size:"), width: labelWidth) {
                    Picker("", selection: $dictionary) {
                        Text(L("Automatic")).tag("")
                        ForEach(format.dictionarySizes, id: \.self) { size in
                            Text(size).tag(size)
                        }
                    }
                    .labelsHidden()
                    .frame(width: controlWidth)
                    .disabled(!dictionaryApplies)
                }

                if !wordSizeChoices.isEmpty {
                    FormRow(label: L("Word size:"), width: labelWidth) {
                        Picker("", selection: $wordSize) {
                            Text(L("Automatic")).tag("")
                            ForEach(wordSizeChoices, id: \.self) { size in
                                Text(size).tag(size)
                            }
                        }
                        .labelsHidden()
                        .frame(width: controlWidth)
                    }
                }
            }

            if format.supportsSolid {
                FormRow(label: L("Solid Block size:"), width: labelWidth) {
                    Picker("", selection: $solidBlock) {
                        ForEach(SolidBlockOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: controlWidth)
                }
            }

            FormRow(label: L("Number of CPU threads:"), width: labelWidth) {
                Picker("", selection: $threads) {
                    ForEach(ThreadOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: controlWidth)
            }

            if format.supportsMultiVolume {
                FormRow(label: L("Split to volumes:"), width: labelWidth) {
                    TextField(L("e.g. 100m"), text: $volume)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: controlWidth)
                }
            }

            FormRow(label: L("Parameters:"), width: labelWidth) {
                TextField("", text: $parameters)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: controlWidth)
                    .help(L("Extra switches passed to the engine, separated by spaces."))
            }
        }
        .frame(width: labelWidth + 8 + controlWidth, alignment: .leading)
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            FormRow(label: L("Update mode:"), width: labelWidth) {
                Picker("", selection: $updateMode) {
                    ForEach(UpdateMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: controlWidth)
            }

            FormRow(label: L("Path mode:"), width: labelWidth) {
                Picker("", selection: $pathMode) {
                    ForEach(PathMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: controlWidth)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(L("Compress shared files"), isOn: $compressSharedFiles)
                    Toggle(L("Delete files after compression"), isOn: $deleteAfterCompression)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(L("Options"))
            }

            if format.supportsPassword {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        FormRow(label: L("Enter password:"), width: 116) {
                            PasswordField(placeholder: "", text: $password, revealed: showPassword, width: 156)
                        }
                        FormRow(label: L("Reenter password:"), width: 116) {
                            PasswordField(placeholder: "", text: $password2, revealed: showPassword, width: 156)
                        }
                        Toggle(L("Show Password"), isOn: $showPassword)
                        FormRow(label: L("Encryption method:"), width: 116) {
                            Picker("", selection: $encryptionMethod) {
                                ForEach(format.encryptionMethods) { method in
                                    Text(method.title).tag(method)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 156)
                        }
                        Toggle(L("Encrypt file names"), isOn: $encryptNames)
                            .disabled(!format.supportsEncryptNames)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text(L("Encryption"))
                }
            }
        }
        .frame(width: labelWidth + 8 + controlWidth, alignment: .leading)
    }

    /// The `-md` switch only applies to LZMA/LZMA2 (7z) or LZMA (zip).
    private var dictionaryApplies: Bool {
        switch format {
        case .zip: return method == "LZMA"
        case .sevenZip: return method.isEmpty || method == "LZMA" || method == "LZMA2"
        default: return false
        }
    }

    /// Word-size values for the currently selected method.
    private var wordSizeChoices: [String] {
        var options = CreateOptions(format: format)
        options.method = method.isEmpty ? nil : method
        return options.wordSizeChoices
    }

    private func formatChanged() {
        method = ""
        dictionary = ""
        wordSize = ""
        solidBlock = .auto
        updateExtension()
        if !format.encryptionMethods.contains(encryptionMethod),
           let first = format.encryptionMethods.first {
            encryptionMethod = first
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
        if !password.isEmpty, password != password2 {
            errorMessage = L("Passwords do not match")
            return
        }
        errorMessage = nil
        let options = CreateOptions(
            format: format,
            level: level,
            password: password.isEmpty ? nil : password,
            encryptFileNames: encryptNames,
            solidBlock: solidBlock,
            volumeSize: volume.isEmpty ? nil : volume,
            method: method.isEmpty ? nil : method,
            dictionary: dictionary.isEmpty ? nil : dictionary,
            wordSize: wordSize.isEmpty ? nil : wordSize,
            encryptionMethod: format.supportsPassword ? encryptionMethod : nil,
            threads: threads,
            updateMode: updateMode,
            pathMode: pathMode,
            compressSharedFiles: compressSharedFiles,
            deleteAfterCompression: deleteAfterCompression,
            parameters: parameters.isEmpty ? nil : parameters
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
