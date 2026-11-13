# HTML 编辑（HTMLPad）

一个极简的 iOS 原生 App：**打开、编辑、保存 HTML 文件**，带语法高亮、一键预览、最近文件。
用 SwiftUI + WKWebView 写，工程只有几百行代码，**不需要 Mac**——用 GitHub Actions 的 macOS
机器云端编译成 `.ipa`，再用 Sideloadly / AltStore 侧载到 iPhone。

---

## 一、功能

| 功能 | 说明 |
| --- | --- |
| 打开文件 | 系统「文件」选择器，支持原地打开（可直接写回原文件），HTML / CSS / JS / JSON / TXT / MD 等 |
| 编辑 | 等宽字体、HTML 语法高亮、Tab 缩进、Cmd+S 保存（外接键盘） |
| 保存 | 覆盖保存回原文件；「另存为」写入 App 自己的目录 |
| 预览 | 全屏 WKWebView 渲染当前页面，相对路径的 CSS / 图片都能加载 |
| 最近文件 | 记录最近 12 个文件（安全书签，重启 App 仍可打开） |
| 其它 | 新建空白页、代码片段插入（h1/p/a/img/列表/表格/注释）、导出分享、退到后台自动保存 |
| 中文编码 | 读取时自动尝试 UTF-8 → GB18030 → UTF-16 → Latin-1，中文老网页不会乱码 |

三个打开文件的入口：

1. App 左上角「打开」按钮 → 选择文件；
2. 「文件」App → 我的 iPhone → **HTML 编辑**（App 目录，可读写）；
3. 在「文件」App 或其它 App 里长按 html 文件 → 共享 → **HTML 编辑**。

---

## 二、云端编译出 ipa（不用 Mac，约 5 分钟）

### 1. 把整个文件夹上传到 GitHub

在 GitHub 新建一个仓库（Private 也可以），然后：

- **网页方式（最简单）**：仓库首页 → `Add file` → `Upload files` → 把本文件夹里
  **所有内容**（包括隐藏的 `.github` 文件夹）拖进去 → `Commit changes`。
- 或者用 GitHub Desktop 提交推送。

> 关键：`.github/workflows/` 目录必须一起上传，否则 Actions 不会跑。
>
> 额度提示：公开仓库的 macOS 构建完全免费；私有仓库会用掉免费额度（每月 2000 分钟，
> macOS 按 10 倍折算 ≈ 200 分钟），本项目一次编译约 3~6 分钟，够跑几十次。

### 2. 等它自动编译

上传后打开仓库的 **Actions** 标签页：

- 会自动出现 `Build unsigned IPA` 任务（也可以在 Actions 页面点 `Run workflow` 手动触发）；
- 第一次大约 5~10 分钟（要装 Homebrew 依赖 + 生成工程 + 编译）；
- 绿色勾 ✅ 表示成功，红色叉 ❌ 点进去看日志，最下面一般能看到具体报错。

### 3. 下载 ipa

进入成功的任务页面 → 页面底部 **Artifacts** → 下载 `HTMLPad-unsigned-ipa`，
解压得到 **`HTMLPad-unsigned.ipa`**。

> 它是**未签名**的 ipa，不能直接装到 iPhone，必须经过你自己的 Apple ID 重新签名后才装得上——这就是下一步。

---

## 三、侧载到 iPhone

### 方案 A：Sideloadly（Windows 用户推荐）

1. 电脑装 [iTunes](https://www.apple.com/itunes/)（必须是**苹果官网版**，Microsoft Store 版不行）
   和 [Sideloadly](https://sideloadly.io/)。
2. iPhone 用数据线连电脑，手机上点「信任此电脑」。
3. 打开 Sideloadly：把 `HTMLPad-unsigned.ipa` 拖进 **IPA** 框，
   `Apple ID` 填你的 Apple ID，点 **Start**，输入 Apple ID 密码（App 专用密码更稳）。
4. 完成后手机会出现「HTML 编辑」图标。

### 方案 B：AltStore / SideStore（能自动续签，推荐长期用）

1. 用 AltStore 官网的 AltServer 把 AltStore 装到 iPhone；
2. AltStore 里 `My Apps` → 左上角 `+` → 选择 ipa 文件 → 输入 Apple ID 完成签名安装；
3. 之后每 7 天在 AltStore 里点 `Refresh All` 续签一次即可（保持 AltServer 在同一 Wi-Fi 下的电脑上运行）。

> 免费 Apple ID 的限制：**同一时间最多 3 个自签 App，证书 7 天过期**。
> 过期后 App 打不开，用 Sideloadly / AltStore 重签一次就行，数据不会丢。
> 付费开发者账号（$99/年）可以 1 年，也能直接在自己 Mac 的 Xcode 里装。

---

## 四、装好后第一次打开

1. iOS 16 及以上要开启开发者模式：
   **设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启手机 → 确认**。
2. 首次运行如果提示「不受信任的开发者」：
   **设置 → 通用 → VPN 与设备管理 → 开发者 App → 你的 Apple ID → 信任**。
3. 打开 App，点左上角文件夹图标选一个 html 文件，改完点右下角「保存」（或 `⋯ → 另存为`）。

---

## 五、想改成自己的东西

| 想改什么 | 改哪里 |
| --- | --- |
| 显示名称（桌面图标下的名字） | `HTMLPad/HTMLPad/Info.plist` 的 `CFBundleDisplayName` |
| Bundle ID（和别人的 App 冲突时改） | `project.yml` 里 `PRODUCT_BUNDLE_IDENTIFIER` |
| 版本号 | `project.yml` 里 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` |
| App 图标 | 替换 `HTMLPad/HTMLPad/Assets.xcassets/AppIcon.appiconset/` 里的 png（或改 `tools/make_icons.py` 后重新生成） |
| 编辑器配色 / 字号 / 高亮规则 | `HTMLPad/HTMLPad/editor.html` 里的 CSS 和 `TOKEN` 正则 |

改完提交到 GitHub，Actions 会自动重新编译出新的 ipa。

### 本地有 Mac 的话

```bash
brew install xcodegen
xcodegen generate            # 生成 HTMLPad.xcodeproj
open HTMLPad.xcodeproj       # 用 Xcode 直接跑 / 真机签名
```

---

## 六、目录结构

```
HTMLPad/
├─ .github/workflows/
│  ├─ build-ipa.yml           # 云端编译未签名 ipa（默认用这个）
│  └─ build-signed-ipa.yml    # 可选：用自己的开发者证书签名导出
├─ project.yml                # XcodeGen 工程描述（.xcodeproj 由它生成，不用提交）
├─ tools/make_icons.py        # 生成全部尺寸 App 图标
└─ HTMLPad/
   ├─ HTMLPadApp.swift        # App 入口，处理「用 HTML 编辑打开」
   ├─ ContentView.swift       # 顶栏 / 状态栏 / 各弹窗
   ├─ EditorWebView.swift     # WKWebView 容器 + 原生↔JS 桥
   ├─ AppModel.swift          # 文档状态：打开 / 保存 / 另存为 / 最近文件
   ├─ FileIO.swift            # 安全作用域读写 + 多种编码回退
   ├─ DocumentPicker.swift    # 系统文件选择器（原地打开）
   ├─ PreviewSheet.swift      # 预览窗口
   ├─ SaveAsSheet.swift       # 另存为
   ├─ ShareSheet.swift        # 导出分享
   ├─ editor.html             # 编辑器本体（HTML 高亮 + 输入逻辑）
   ├─ Info.plist              # 支持打开的文件类型、文件 App 共享等
   └─ Assets.xcassets/        # 图标
```

---

## 七、可选：用自己的开发者证书签名

`build-signed-ipa.yml` 是给我自己/付费开发者账号用的：把 `.p12` 证书、`.mobileprovision`
转成 base64 存进仓库 Secrets，就能在云端直接导出**已签名**的 ipa（不需要再 Sideloadly）。
需要的 Secret 名字和生成命令写在那个 workflow 文件开头的注释里。

---

## 八、常见问题

**Actions 报 `xcodegen: command not found`？**
`brew install xcodegen` 那一步失败了（偶发网络问题），重新跑一次 workflow 即可。

**报 `No signing certificate found` / `requires a development team`？**
说明走了签名流程。默认的 `build-ipa.yml` 已加 `CODE_SIGNING_ALLOWED=NO`，如果还报，
检查是不是用了 `build-signed-ipa.yml`。

**Sideloadly 安装失败 `Unable to install ...`？**
多半是免费 Apple ID 已有 3 个自签 App，先在 AltStore 删掉一个；或者 bundle id 被别人占用了，
改一下 `project.yml` 的 `PRODUCT_BUNDLE_IDENTIFIER` 再编译。

**保存时提示「保存失败」？**
有些第三方文件提供者（如某些网盘）只给只读权限。用 `⋯ → 另存为` 存到「我的 iPhone → HTML 编辑」，
或用 `⋯ → 导出 / 分享文件` 发回原 App。

**预览里图片 / 样式没出来？**
预览按当前文件所在目录解析相对路径。请把 html 和它引用的 css/图片放在同一个文件夹里再打开。

**大文件卡？**
超过 40 万字符会自动关闭语法高亮（仍可正常编辑保存），保证不卡输入。

---

## 九、许可

代码随意使用、修改、再分发。
