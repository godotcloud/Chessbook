# LichessCN — Lichess iOS 原生客户端（支持研习实时中文翻译 & SideStore 签名安装）

本项目是基于 **纯原生 SwiftUI** 开发的 iOS 客户端，完整对接 [Lichess Official API](https://lichess.org/api)，内置 **多源免配置大模型/神经翻译引擎 + 国际象棋专业术语词库**，并配备基于 [XcodeGen](https://github.com/yonaskolb/xcodegen) 的 **GitHub Actions 自动构建工作流**，一键生成可直接导入 [SideStore](https://sidestore.io/) 签名安装的 `.ipa` 安装包与软件源 JSON。

## 核心功能模块

1. **导入/浏览研习与实时中文翻译 (`StudyBrowserView.swift`)**
   - 支持直接输入任意 Lichess Study 链接或 8 位 ID（例如 `https://lichess.org/study/YtBYXc3m`）、粘贴原始 PGN 文本，或从内置精选研习库一键加载。
   - **走子同步实时翻译**：点击前进/后退浏览棋谱时，自动提取每一步的英文/外文棋评注解（`{ ... }`），实时翻译为符合国际象棋规范的简体中文，支持**中英双语对照**与**一键批量预翻译全章**。
   - **原生绘制研习战术标记**：完整解析 PGN 中的 `[%cal ...]` 彩色战术箭头与 `[%csl ...]` 关键格高亮圆圈，在原生 SwiftUI 棋盘上精准渲染。

2. **多源免配置免费翻译引擎 (`ChessTranslationService.swift`)**
   - 无需注册或填写任何 API Key，内置 5 级自动容灾翻译链，可在顶部菜单或设置页随时切换：
     - **Pollinations AI 大模型 ([Pollinations.ai](https://github.com/pollinations/pollinations))**：免 Key 调用兼容 OpenAI 协议的大模型接口，内置国际象棋特级大师系统提示词，精准翻译复杂长句。
     - **Lingva 开源神经翻译 ([Lingva Translate](https://github.com/thedaviddelta/lingva-translate))**：开源免 Key 的 Google 翻译前端代理，支持多实例自动切换。
     - **MyMemory 协作翻译 API ([MyMemory API](https://mymemory.translated.net/doc/spec.php))**：免费免注册 REST 翻译接口。
     - **GTX 极速神经直连 + 国际象棋专业术语前后置处理器**：在机器翻译前后自动保护代数记谱法（如 `1. e4`, `Nf3`, `Qxf7#`），并修正国际象棋专业术语（如 `Pin` -> `牵制`、`Fork` -> `捉双`、`Skewer` -> `串击`、`Zugzwang` -> `楚茨文克(迫移)`、`Fianchetto` -> `侧翼象`、`Passed pawn` -> `通路兵`）。
     - **iOS 原生系统翻译 ([Apple Translation Framework](https://developer.apple.com/documentation/translation))**：在 iOS 17.4+ 设备上支持一键呼出系统级离线翻译面板。

3. **战术谜题训练 (`PuzzleTrainingView.swift`)**
   - 对接 Lichess `/api/puzzle/daily` 与 `/api/puzzle/next` 接口，支持自动演示对手应着、一步战术箭头提示，以及战术主题标签中文翻译（如 `backRankMate` -> `底线杀`、`deflection` -> `引离`）。

4. **在线对局与 Lichess TV (`OnlinePlayView.swift`)**
   - 支持配置 Lichess Personal Access Token 发起云端 Stockfish AI 对局（1–8 级）与在线走子同步（`/api/board/game/{id}/move/{uci}`），同时提供免登录快速对弈以及 **Lichess TV 顶级大师实时对局同步**（`/api/tv/feed`）。

5. **Stockfish 云端引擎与大师开局库分析 (`EngineAnalysisView.swift`)**
   - 对接 Lichess `/api/cloud-eval`（实时显示 Centipawn / 杀棋步数评估条与前 3 条 Multi-PV 最佳主变）及 `https://explorer.lichess.ovh/masters`（历代大师开局胜平负统计与 ECO 开局名称实时中文翻译）。

## 使用 GitHub Actions 自动编译并通过 SideStore 签名安装

1. **上传至 GitHub 仓库**
   - 将本项目全部文件推送到你的 GitHub 仓库（确保包含 `.github/workflows/build-sidestore-ipa.yml` 与 `project.yml`）。
2. **触发自动构建**
   - 每次推送到 `main` 分支，或在 GitHub 仓库页面点击 **Actions** -> **Build Unsigned IPA for SideStore** -> **Run workflow**，GitHub Actions 会在 `macos-15` 虚拟环境上自动通过 [XcodeGen](https://github.com/yonaskolb/xcodegen) 生成 Xcode 工程、编译 Release 版 `.app`、使用 `ldid` 进行伪签名（Fake-sign）并打包为 `LichessCN-SideStore.ipa`。
3. **在 iPhone 上使用 SideStore 签名安装**
   - **方法一（直接导入 IPA）**：在 GitHub Actions 构建详情页的 **Artifacts** 或仓库的 **Releases** 页面下载 `LichessCN-SideStore.ipa` 到 iPhone「文件」App，打开 [SideStore](https://sidestore.io/) -> **My Apps** -> 点击左上角 `+` 号选择 `LichessCN-SideStore.ipa` 即可自动完成个人证书重签名并安装。
   - **方法二（添加自建 SideStore 软件源）**：构建产物中会自动生成 `sidestore-source.json` 并发布到 GitHub Releases，你可以复制其 Release 直链添加到 SideStore 的 **Sources** 中，实现后续版本一键更新。
