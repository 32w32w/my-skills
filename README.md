# my-skills

个人可复用技能集合。

## Visual Art Director

[查看技能内容](skills/visual-art-director/SKILL.md)

用于参考图分析、艺术指导、设计评价，以及插画、绘本、海报、PPT、报告和网页的视觉协调。

这是独立编写的指令型技能。仓库不直接捆绑其他项目的技能、字体或图片；需要时，可通过下面的整套安装器从原项目下载。使用技能本身不会触发安装。

## 整套安装到 Codex

配套安装入口为 [`install.ps1`](install.ps1)，一次安装以下五个技能：

1. Visual Art Director
2. Canvas Design
3. Frontend Design
4. Theme Factory
5. Visual Design Foundations

在 Windows PowerShell 5.1 或 PowerShell 7 中运行。先用 GitHub CLI 下载本仓库；以下命令适用于当前目录还没有 `my-skills` 文件夹的情况：

```powershell
gh repo clone 32w32w/my-skills
.\my-skills\install.ps1 -WhatIf
```

第二行只预览安装计划，不下载或创建文件。确认计划后正式执行：

```powershell
.\my-skills\install.ps1
```

如果已经下载了仓库，直接在仓库文件夹中运行 `./install.ps1` 即可。使用最新入口前，先在干净的仓库副本中更新代码。若系统执行策略阻止脚本，请先阅读并信任脚本，再按本机管理要求允许此次执行；安装器不会改变系统执行策略。

默认安装到用户目录下的 `.agents/skills`。默认模式也会检查 `.codex/skills` 和 `$CODEX_HOME/skills`，避免为已存在的同名技能再装一份。指定目录时只检查该目录，便于为单个项目单独安装：

```powershell
.\my-skills\install.ps1 -Destination .\my-project\.agents\skills
```

安装行为：

- 已存在的同名目录直接跳过，保留现有版本和修改；同名文件会报错，不覆盖。
- 根据 [`design-suite.lock.json`](design-suite.lock.json) 固定的提交版本下载，并核对归档的 SHA256。
- 只提取指定技能及许可证，不导入整个上游插件或运行上游脚本。保留字体、主题预览和参考资料。
- 下载、校验和准备全部成功后才写入目标目录。完成安装后检查技能选择器；未出现时按客户端提示刷新或重启。
- 这不是更新器。跳过的已有版本不保证与锁定版本相同；需要更换版本时应先备份并自行处理现有目录。

断网复用已下载的归档时，可使用 `-ArchiveDirectory <目录> -Offline`。文件名必须是 `<source.id>-<source.ref>.zip`，且仍须通过锁文件中的校验。不要直接执行来自未知来源的安装脚本。

## 只安装主技能

如果不需要整套安装，仍可在支持技能安装器的 Codex 中请求：

```text
$skill-installer 请从 GitHub 仓库 32w32w/my-skills 安装 skills/visual-art-director 目录中的技能。
```

这条请求只安装 Visual Art Director，**不会自动执行整套安装器**。也可以将完整的 `skills/visual-art-director` 文件夹复制到项目的 `.agents/skills/` 中。

保存到 GitHub 本身不会完成 Codex 或 ChatGPT 的安装。ChatGPT 原生 Skills 或插件的导入要求，取决于账号权限与当前官方功能；向聊天发送链接只提供来源，不等于安装。

## 可选协作技能

以下链接列出协作来源。整套安装器按锁定版本从这些项目下载，而不是跟随 `main` 自动更新：

- [Canvas Design](https://github.com/anthropics/skills/tree/main/skills/canvas-design)：静态艺术与海报。
- [Frontend Design](https://github.com/anthropics/skills/tree/main/skills/frontend-design)：网页与界面。
- [Theme Factory](https://github.com/anthropics/skills/tree/main/skills/theme-factory)：配色与字体主题。
- [Visual Design Foundations](https://github.com/wshobson/agents/tree/main/plugins/ui-design/skills/visual-design-foundations)：字体、色彩、间距与图标体系。

图像生成、演示文稿制作与科研绘图使用所在环境可用的对应工具。这个技能提供艺术指导与复核流程，不会改变底层模型能力。

## 验证安装器

```powershell
.\tests\install.Tests.ps1
```

测试在临时目录构造本地归档，覆盖预览、重复安装、资源和许可证保留、校验失败、目录穿越、符号链接、文件冲突及无效清单，不安装到实际用户技能目录。
