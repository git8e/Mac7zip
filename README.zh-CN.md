# Mac7Zip

macOS 上的 7-Zip 图形界面 —— 复刻 **Windows 桌面版 7-Zip File Manager** 的界面与交互，
并直接复用**官方 7-Zip 引擎**（`7zz`）。双击压缩包即可浏览、单独解压某个文件或文件夹、
新建、测试——操作习惯与原版一致。

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
- **单独解压选中项**：只解压勾选的文件 / 文件夹，递归处理，自动折叠「父目录 + 子项」的重复选择
- **新建压缩包 / 添加到压缩包**：格式、压缩级别、固实压缩、密码、加密文件名、分卷大小
- **测试完整性**（Test）、**删除压缩包内条目**
- 拖拽打开、Finder「打开方式」、命令行传参
- 操作进度显示与取消

## 文件关联

macOS 默认在双击压缩包时自动解压。用 Mac7Zip 可以把压缩包改为**直接用 Mac7Zip 打开**，
而且不会在安装时偷偷抢占关联：

1. 打开 Mac7Zip，使用菜单 **关联 ▸ 用 Mac7Zip 默认打开压缩包**。
2. 之后双击 7z / zip / rar … 都会在 Mac7Zip 中打开浏览。

随时可以用 **关联 ▸ 恢复系统默认打开方式** 把关联交还给 macOS。

## 多语言

默认跟随系统语言（英文 / 简体中文），也可以在 **语言** 菜单中随时手动切换，立即生效。

## 安装

- macOS 13 或以上（Apple Silicon 与 Intel 均可，内置通用版 `7zz` 引擎）。
- 在 [Releases](https://github.com/git8e/Mac7Zip/releases) 下载 DMG，打开后把 **Mac7Zip.app** 拖入“应用程序”。
- 应用为 ad-hoc 签名，首次启动如提示不明开发者，请右键选择“打开”。

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

## 试用

`Samples/演示.7z` 是一个示例压缩包（含中文名与多层目录），可直接用来体验文件树与单独解压。

## 许可

- 7-Zip 引擎（`Vendor/7zz`）：© Igor Pavlov，GNU LGPL 许可，见 `THIRD_PARTY/7-Zip-License.txt`。
- 应用图标：7-Zip 官方图标，Wikimedia Commons 提供的矢量版，LGPL，见 `THIRD_PARTY/7-Zip-Icon-License.txt`。
- Mac7Zip 本身：源码见本仓库。