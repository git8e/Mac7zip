# Mac7Zip

macOS 上的 7-Zip 图形界面 —— 复刻 **Windows 桌面版 7-Zip File Manager** 的界面与交互，
并直接复用**官方 7-Zip 引擎**（`7zz`）。双击压缩包即可浏览、单独解压某个文件或文件夹、
新建、测试——操作习惯与原版一致。

> **可能是世界上最好用、最稳定的 Mac 压缩 / 解压工具之一，而且完全免费、开源。**

[English README](README.md)

> 最新安装包请在 [Releases](https://github.com/git8e/Mac7Zip/releases) 页面下载（DMG）。

## 为什么要做这个

macOS 上的 7-Zip 只有命令行工具（`7zz`），没有图形界面：

- 不能预览压缩包里的文件树；
- 不能只解压其中某一个文件或文件夹；
- 新建 / 添加 / 测试都要手敲参数。

Mac7Zip 用原生 SwiftUI/AppKit 补上这一切，界面和操作习惯对标 Windows 版 7-Zip：
菜单栏、工具栏（添加 / 解压 / 测试 / 删除 / 信息）、地址栏、**左侧文件夹树 + 右侧明细列表**、状态栏。

## 功能

- **打开 / 浏览压缩包**：7z、zip、rar、tar、gz、bz2、xz、iso、wim、cab、rpm、deb、jar… （取决于引擎支持）
- **文件树预览**：左侧文件夹树 + 右侧带列（名称 / 大小 / 压缩后 / 修改时间 / 属性 / CRC / 方法 / 加密）的明细列表，双击进入子目录
- **三种视图模式**——图标 / 列表 / 详细信息——外加可折叠的文件夹树面板与**可编辑地址栏**（输入路径回车即可跳转）
- **列排序**（点击列头）与 **平铺视图**（一次列出全部条目）
- **打开压缩包内的文件**：双击自动解压并用默认程序打开（内嵌压缩包则在 Mac7Zip 内打开），另有 **在外部打开 / 查看 / 编辑**
- **右键菜单**与完整的 **文件 / 编辑 / 显示** 菜单（全选、取消选择、反向选择、选择列）
- 直接在压缩包内 **重命名** 与 **新建文件夹 / 新建文件**
- **复制到… / 移动到…**：把选中项导出到磁盘文件夹
- **单独解压选中项**：只解压勾选的文件 / 文件夹，递归处理，自动折叠「父目录 + 子项」的重复选择；支持路径模式（完整 / 无路径）、覆盖模式、*消除根目录重复*、密码与显示密码
- **新建压缩包 / 添加到压缩包**：格式、压缩级别、压缩方法、字典大小、CPU 线程数、固实压缩、更新模式（添加并替换 / 更新并添加 / 仅更新 / 同步）、路径模式、分卷大小、密码 + 加密文件名、*压缩后删除源文件*
- **测试完整性**（Test）、**删除压缩包内条目**、**校验和**（CRC32 / CRC64 / SHA1 / SHA256 / BLAKE2sp）
- 拖拽打开、把压缩包内条目**拖到外部**即解压、Finder「打开方式」、命令行传参
- 操作进度显示与取消

## 与同类工具对比

Mac7Zip 最大的优势就是**价格：完全免费且开源**。下面是它与 macOS 上常见压缩 / 解压工具的对比（价格取自各官方页面，2026 年 10 月）：

| 工具 | 价格 | 开源 | 原生 macOS 界面 | 官方 7-Zip 引擎 | 创建 / 更新 7z | 免解压浏览压缩包 |
| --- | --- | --- | --- | --- | --- | --- |
| **Mac7Zip** | **免费** | ✅ | ✅ | ✅ 官方 `7zz` | ✅ | ✅ |
| 7-Zip 官方（macOS） | 免费 | ✅ LGPL | ❌ 仅命令行 `7zz` | ✅ | ✅（命令行） | ❌ |
| macOS 自带「归档实用工具」 | 免费（系统自带） | ❌ | ✅ 仅解压 | ❌ | ❌ | ❌ |
| The Unarchiver | 免费 | ❌ | ✅ 仅解压 | ❌ | ❌ | ⚠️ 有限 |
| Keka | 官网免费 / Mac App Store $6.49 | ❌ | ✅ | ❌ | ✅ | ✅ |
| Bandizip for Mac | $21.99 | ❌ | ✅ | ❌ | ✅ | ✅ |
| BetterZip 6 | $35（一次性买断） | ❌ | ✅ | ❌ | ✅ | ✅ |
| WinZip Mac | 付费（按年订阅） | ❌ | ✅ | ❌ | ❌（仅 Zip/ZipX） | ✅ |

**性价比，先看价格**

- **价格优势**：完全免费、开源——不用购买、不用订阅。上表其余几款要么付费（Keka App Store $6.49、Bandizip $21.99、BetterZip $35、WinZip Mac 按年订阅），要么免费但只能解压 / 只能命令行。
- **完整图形界面**：原生 SwiftUI/AppKit 文件管理器窗口（文件夹树 + 明细列表、三种视图模式、可编辑地址栏）——官方 7-Zip 在 macOS 上根本没有图形界面。
- **始终最新的 7-Zip**：直接调用官方 `7zz` 引擎，7z/LZMA2 支持与格式覆盖始终跟随上游 7-Zip。
- **直接操作压缩包**：免解压浏览、打开 / 重命名 / 新建 / 删除单个条目、把条目拖出即解压。

> 「官方 7-Zip 引擎」指直接调用 Igor Pavlov 官方发布的 `7zz`/`7z` 二进制。价格为各官方页面（2026 年 10 月）整理，可能随时调整。各产品名称与商标归其各自所有者所有。

## 文件关联

macOS 默认在双击压缩包时自动解压。用 Mac7Zip 可以把压缩包改为**直接用 Mac7Zip 打开**，
而且不会在安装时偷偷抢占关联：

1. 打开 Mac7Zip，使用菜单 **关联 ▸ 用 Mac7Zip 默认打开压缩包**。
2. 之后双击 7z / zip / rar … 都会在 Mac7Zip 中打开浏览。

随时可以用 **关联 ▸ 恢复系统默认打开方式** 把关联交还给 macOS。

## 多语言

默认跟随系统语言（英文 / 简体中文），也可以在 **语言** 菜单中随时手动切换，立即生效。

## 安装

Mac7Zip 以 DMG 形式发布。**系统要求：** macOS 13 或以上——Apple Silicon 与 Intel 均可（内置通用版 `7zz` 引擎）。

1. **下载**：在 [Releases](https://github.com/git8e/Mac7Zip/releases) 页面下载最新的 `Mac7Zip-<版本>.dmg`。
2. **打开 DMG**（双击）。会弹出一个安装窗口：左边是 Mac7Zip 图标，右边是 **Applications（应用程序）** 文件夹快捷方式，中间的箭头提示你该怎么做。
3. **安装**：把 **Mac7Zip** 拖到 **Applications** 文件夹上即完成安装。
4. **推出**：装好后把 DMG 拖到废纸篓推出，不再需要它。
5. **启动**：在「应用程序」中打开 Mac7Zip。首次启动时，由于应用为 ad-hoc 签名（尚未公证），macOS 可能会拦截，请任选一种方式放行：
   - 在「应用程序」中 **按住 Control 点击（右键）Mac7Zip → 打开 → 再点「打开」**；或
   - 打开 **系统设置 ▸ 隐私与安全性**，在下方 Mac7Zip 提示处点 **仍要打开**。

首次成功打开后，以后就可以正常双击启动了。

> **提示「Mac7Zip 已损坏，无法打开」？** 这只是下载被 macOS 打了隔离标记。执行一次下面的命令去掉标记，再打开即可：
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/Mac7Zip.app
> ```
>
> 请只对本仓库 Releases 页面下载的版本执行此操作。

想自己构建？见下方 [构建与运行](#构建与运行)。

## 构建与运行

需要 macOS 13+ 与 Xcode 命令行工具（Swift 6）。

```bash
make build   # 编译
make run     # 直接运行（使用 Vendor/7zz）
make app     # 打包成 build/Mac7Zip.app
make dmg     # 打包并生成 build/Mac7Zip-1.0.dmg
open build/Mac7Zip.app
```

如果 `Vendor/7zz` 不存在：

```bash
make engine  # 从官方 GitHub 下载（Scripts/fetch_engine.sh）
```

## 架构

```
Sources/Mac7Zip/
  Engine/     对官方 7zz 的封装：进程调用、-slt 解析、进度计数、密码识别
  Models/     数据模型与目录树构建
  State/      AppModel：导航、选择、解压/压缩/测试/删除
  Views/      SwiftUI 外壳 + NSOutlineView / NSTableView 封装
Vendor/7zz    官方 7-Zip 引擎（通用二进制）
Resources/    应用图标 + en.lproj / zh-Hans.lproj 语言文件
Scripts/      打包与引擎下载脚本
Tests/        引擎与视图模型层测试
```

关键实现说明：

- **不重写压缩算法**：所有压缩 / 解压 / 测试都调用 `7zz`，功能与格式支持跟随官方引擎。
- **文件树**：用 `7zz l -slt`（机器可读）列出条目，解析后构建目录树。
- **进度**：用 `-bb1` 的「每个文件一行」输出计数得到进度与当前文件名。
- **加密包不会卡死**：子进程的 stdin 固定接到 `/dev/null`，再根据输出文本判断「需要密码 / 密码错误」，弹出密码框重试。

## 测试

```bash
swift test
```

覆盖：引擎定位、创建 / 列表 / **单独解压指定文件** / 测试、加密包密码处理、`-slt` 解析、以及驱动界面的导航与选择逻辑。

## 诊断（无需图形界面）

```bash
./build/Mac7Zip.app/Contents/MacOS/Mac7Zip --check-engine
./build/Mac7Zip.app/Contents/MacOS/Mac7Zip --list /path/to/archive.7z
./build/Mac7Zip.app/Contents/MacOS/Mac7Zip --strings          # 查看当前语言下的字符串
```

## 许可

- 7-Zip 引擎（`Vendor/7zz`）：© Igor Pavlov，GNU LGPL 许可，见 `THIRD_PARTY/7-Zip-License.txt`。
- 应用图标：7-Zip 官方图标，Wikimedia Commons 提供的矢量版，LGPL，见 `THIRD_PARTY/7-Zip-Icon-License.txt`。
- Mac7Zip 本身：MIT 许可，见 `LICENSE`。