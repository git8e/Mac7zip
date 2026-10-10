# Mac7zip

A native macOS GUI for 7-Zip — a faithful remake of the **Windows 7-Zip File Manager**, powered by the **official 7-Zip engine** (`7zz`). Double-click an archive and browse it, extract a single file or a folder, create or test archives — all with the familiar 7-Zip layout.

> **Possibly one of the best and most stable macOS archiver tools in the world — and it is completely free and open source.**

[简体中文说明](README.zh-CN.md)

> **Download** the latest build from the [Releases](https://github.com/git8e/Mac7zip/releases) page (DMG).

## Why

7-Zip on macOS only ships the command line tool (`7zz`):

- you cannot preview the file tree inside an archive;
- you cannot extract just one file or folder;
- create / add / test all require typing manual arguments.

Mac7zip adds a native SwiftUI/AppKit interface that mirrors the Windows 7-Zip File Manager: menu bar, toolbar (Add / Extract / Test / Delete / Info), path bar, **folder tree on the left + details list on the right**, and a status bar.

## Features

- **Open / browse archives**: 7z, zip, rar, tar, gz, bz2, xz, iso, wim, cab, rpm, deb, jar… (anything the 7-Zip engine supports)
- **File tree preview**: folder tree on the left, a details list with the familiar columns (Name / Size / Packed / Modified / Attributes / CRC / Method / Encrypted) on the right; double-click to enter a folder
- **Three view modes** — Icons, List and Details — plus a collapsible folder-tree panel and an **editable address bar** (type a folder and press Return to jump)
- **Sortable columns** (click a header) and a **Flat View** that lists every item at once
- **Open files inside an archive**: double-click extracts and opens with the default app (nested archives open inside Mac7zip), plus **Open Outside / View / Edit**
- **Right-click context menu** and full **File / Edit / View** menus (Select All, Deselect All, Invert Selection, column chooser)
- **Rename** items and **Create Folder / Create File** directly inside an archive
- **Copy To… / Move To…** the selected items out to a folder on disk
- **Extract selected items only**: pick files or folders, recursively handled, with redundant "parent + child" selections automatically collapsed; path mode (full / no paths), overwrite mode, *eliminate duplication of root folder*, password with show-password
- **New archive / add to archive**: format, compression level, compression method, dictionary size, CPU threads, solid mode, update mode (add & replace / update & add / freshen / synchronize), path mode, volumes, password + file-name encryption, and *delete files after compression*
- **Test integrity**, **delete items inside an archive**, and **Checksum** (CRC32 / CRC64 / SHA1 / SHA256 / BLAKE2sp)
- Drag & drop to open, drag an item **out** of the archive to extract it, Finder "Open With", opening archives from the command line
- Operation progress with cancel

## How it compares

Mac7zip's biggest advantage is the **price: it is completely free and open source**. Here it is next to the most common macOS archivers (prices taken from each vendor's official page, October 2026):

| Tool | Price | Open source | Native macOS GUI | Official 7-Zip engine | Create / update 7z | Browse inside archives |
| --- | --- | --- | --- | --- | --- | --- |
| **Mac7zip** | **Free** | ✅ | ✅ | ✅ official `7zz` | ✅ | ✅ |
| 7-Zip (official, macOS) | Free | ✅ (LGPL) | ❌ CLI only (`7zz`) | ✅ | ✅ (CLI) | ❌ |
| macOS Archive Utility | Free (system) | ❌ | ✅ extract only | ❌ | ❌ | ❌ |
| The Unarchiver | Free | ❌ | ✅ extract only | ❌ | ❌ | ⚠️ limited |
| Keka | Free (website) / $6.49 (Mac App Store) | ❌ | ✅ | ❌ | ✅ | ✅ |
| Bandizip for Mac | $21.99 | ❌ | ✅ | ❌ | ✅ | ✅ |
| BetterZip 6 | $35 (one-time) | ❌ | ✅ | ❌ | ✅ | ✅ |
| WinZip Mac | Paid (annual subscription) | ❌ | ✅ | ❌ | ❌ (Zip/ZipX) | ✅ |

**Why Mac7zip wins on value**

- **Price first**: free of charge and open source — no purchase and no subscription. Every alternative above is either paid (Keka $6.49 on the App Store, Bandizip $21.99, BetterZip $35, WinZip Mac billed yearly) or free but extract-only / command-line.
- **Full graphical experience**: a native SwiftUI/AppKit file-manager window (folder tree + details list, three view modes, editable address bar) — the official 7-Zip on macOS has no GUI at all.
- **Always the latest 7-Zip**: it drives the official `7zz` engine, so 7z/LZMA2 support and format coverage track upstream 7-Zip exactly.
- **Work inside archives**: browse without extracting, open / rename / create / delete single items, and drag items out to extract them.

> "Official 7-Zip engine" means calling the `7zz`/`7z` binary released by Igor Pavlov. Prices are taken from each vendor's official site (October 2026) and may change. All product names and trademarks belong to their respective owners.

## File association

By default macOS extracts an archive when you double-click it. With Mac7zip you can make archive files **open in the app instead** — and it never steals the association silently:

1. Open Mac7zip, then use the menu **Associate ▸ Open Archives with Mac7zip by Default**.
2. Double-clicking a 7z/zip/rar/… file now opens it in Mac7zip for browsing.

Use **Associate ▸ Restore System Default Handlers** at any time to hand the associations back to macOS.

## Languages

The app follows your system language by default (English / Simplified Chinese), and you can switch manually at any time from the **Language** menu — the change applies immediately.

## Install

Mac7zip ships as a DMG. **Requirements:** macOS 13 or later — both Apple Silicon and Intel are supported (a universal `7zz` engine is bundled).

1. **Download** the latest `Mac7zip-<version>.dmg` from the [Releases](https://github.com/git8e/Mac7zip/releases) page.
2. **Open the DMG** (double-click it). A window opens with the Mac7zip icon on the left and an **Applications** shortcut on the right, with an arrow telling you what to do.
3. **Install** — drag **Mac7zip** onto **Applications**.
4. **Eject** the DMG when you are done (drag it to the Trash); you no longer need it.
5. **Launch** it from *Applications*. The first time, because the app is ad-hoc signed (not notarised yet), macOS may refuse to open it. Do one of these:
   - **Control-click (right-click) Mac7zip** in *Applications* → **Open** → **Open** again; or
   - open **System Settings ▸ Privacy & Security**, scroll down and click **Open Anyway** next to the Mac7zip message.

After the first successful launch you can open it normally.

> **"Mac7zip is damaged and can't be opened"?** That message just means macOS quarantined the download. Remove the flag once, then reopen:
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/Mac7zip.app
> ```
>
> Only do this for a build you downloaded from this repository's Releases page.

Prefer to build it yourself? See [Build from source](#build-from-source) below.

## Build from source

Requires macOS 13+ and the Xcode command line tools (Swift 6).

```bash
make build   # compile
make run     # run from source (uses Vendor/7zz)
make app     # assemble build/Mac7zip.app
make dmg     # assemble + create build/Mac7zip-1.1.0.dmg
open build/Mac7zip.app
```

If `Vendor/7zz` is missing:

```bash
make engine  # downloads the official engine (Scripts/fetch_engine.sh)
```

## Architecture

```
Sources/Mac7zip/
  Engine/     Wraps the official 7zz: process calls, -slt parsing, progress, password detection
  Models/     Data models and the directory tree builder
  State/      AppModel: navigation, selection, extract/compress/test/delete
  Views/      SwiftUI shell + NSOutlineView / NSTableView bridges
Vendor/7zz      Official 7-Zip engine (universal binary)
Resources/      App icon + en.lproj / zh-Hans.lproj localization tables
Scripts/        Build, packaging and engine download scripts
Tests/          Engine and view-model tests (Swift Testing)
```

Key implementation notes:

- **No rewrites of compression algorithms**: every compress / extract / test is delegated to `7zz`, so format support always follows the official engine.
- **File tree**: `7zz l -slt` (machine readable) output is parsed and turned into a directory tree.
- **Progress**: the `-bb1` "one line per file" output drives the progress bar and current-file label.
- **Encrypted archives never hang**: the child process stdin is always wired to `/dev/null`; "password required / wrong password" is detected from the output text and a password sheet is shown to retry.

## Tests

```bash
swift test
```

Covers: engine location, create / list / **extract a single file** / test, encrypted-archive password handling, `-slt` parsing, and the navigation/selection logic that drives the UI.

## Diagnostics (no GUI required)

```bash
./build/Mac7zip.app/Contents/MacOS/Mac7zip --check-engine
./build/Mac7zip.app/Contents/MacOS/Mac7zip --list /path/to/archive.7z
./build/Mac7zip.app/Contents/MacOS/Mac7zip --strings          # localized strings
```

## License

- 7-Zip engine (`Vendor/7zz`): © Igor Pavlov, licensed under the GNU LGPL — see `THIRD_PARTY/7-Zip-License.txt`.
- App icon: the official 7-Zip icon, vectorised for Wikimedia Commons — LGPL — see `THIRD_PARTY/7-Zip-Icon-License.txt`.
- Mac7zip itself: MIT licensed — see `LICENSE`.