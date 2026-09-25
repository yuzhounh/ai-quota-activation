<p align="center">
  <img src="assets/ai-quota-activation-logo.png" alt="AI Quota Activation logo" width="220">
</p>

# AI Quota Activation

> Windows 通用 AI 配额点火与计划唤醒引擎，自动化激活 Codex、Claude、Antigravity 额度窗口与回睡管理。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)]()
[![PowerShell](https://img.shields.io/badge/PowerShell-%3E%3D%207.4-blue.svg)]()

AI Quota Activation 是一个专为 Windows 设计的通用 AI 配额点火器。它用一次极简、无工具、无文件修改的 CLI 沙箱请求，启动 Codex、Claude 或 Google Antigravity 的使用窗口，并可通过 Windows 任务计划程序执行 5 小时点火或每周定时点火。

默认一次点火以下三个 CLI：

- **Codex CLI** (`codex`)
- **Claude Code CLI** (`claude`)
- **Google Antigravity CLI** (`agy`)

也可以只选择其中一个或两个。通用引擎会逐个执行；某个 AI 失败不会阻止后面的 AI，最终任务会返回失败状态并把详情写入日志。

v0.4 使用互斥配额策略：同一个 AI 只能选择“5 小时点火”或“仅周点火”。已有 5 小时点火时不会再创建重复的周任务；只有没有 5 小时机制或主动不使用 5 小时任务的 AI 才进入周任务。默认 5 小时组为 Claude、Antigravity，周组为 Codex。

## 亮点特性 (Features)

* **极简无副作用点火**: 采用一次极简、无工具调用、无文件修改的沙箱 CLI 请求，安全激活使用窗口。
* **多模型与轻量化支持**: 默认适配轻量级模型（Codex `gpt-5.6-luna`、Claude `haiku`、Antigravity `gemini-3.8-flash-low`），最大化节约 Token 与配额消耗。
* **互斥与智能重置调度**: 支持 5 小时周期点火与每周点火互斥策略，自动对齐周配额刷新时间并实现持久化冷却重试。
* **智能唤醒与安全回睡**: 精确归因 Windows 定时唤醒事件与用户空闲状态，点火完成后自动回睡，避免额外电量消耗。
* **故障隔离与全面审计**: 独立捕获各 CLI 状态与错误码，单个 AI 失败不影响后续激活，完整记录详细运维日志。

## 目录结构 (Repository Structure)

```text
.
├── assets/                         # 项目静态资源与 Logo
│   └── ai-quota-activation-logo.png
├── tests/                          # 回归测试套件（模拟 CLI 与任务计划）
├── .gitignore                      # Git 忽略配置
├── ai-quota-activate.ps1           # CLI 检测、点火、日志、唤醒归因和安全回睡
├── install-ai-quota-schedule.ps1   # 按互斥配额策略安装/更新 Windows 计划任务
├── LICENSE                         # 开源协议
├── README.md                       # 项目说明文档
└── VERSION                         # 当前版本号
```

计划任务使用的脚本和日志会部署到：

```text
%LOCALAPPDATA%\AIQuotaActivation\
```

## 前置要求

1. Windows 10/11。
2. PowerShell 7.4 或更高版本，命令为 `pwsh.exe`。
3. 至少安装并登录准备点火的 AI CLI。

检查默认三个 CLI：

```powershell
pwsh -File .\ai-quota-activate.ps1 -CheckOnly
```

或者只检查选中的 CLI：

```powershell
pwsh -File .\ai-quota-activate.ps1 -AI Codex,Claude -CheckOnly
```

如果缺少 CLI，脚本会停止并显示相应安装命令和官方文档地址。安装完成后，请先在普通终端中交互式启动一次 CLI 并完成登录：

```powershell
codex
claude
agy
```

默认安装命令如下：

```powershell
npm install -g @openai/codex@latest
npm install -g @anthropic-ai/claude-code
irm https://antigravity.google/cli/install.ps1 | iex
```

## 先做无消耗演练

`-DryRun` 会完成 CLI 检测并显示将要执行的命令，但不会请求任何 AI，也不会让电脑睡眠：

```powershell
pwsh -File .\ai-quota-activate.ps1 -DryRun -NetworkWaitSeconds 0 -PostWaitSeconds 0
```

只演练部分 AI：

```powershell
pwsh -File .\ai-quota-activate.ps1 -AI Codex,Antigravity -DryRun
```

## 手动点火

手动点火默认不会因为普通终端运行而误判为计划任务唤醒；加上 `-NoSleep` 可以明确禁止本次自动回睡：

```powershell
pwsh -File .\ai-quota-activate.ps1 `
  -AI Codex,Claude,Antigravity `
  -NetworkWaitSeconds 0 `
  -PostWaitSeconds 0 `
  -NoSleep
```

这会产生真实的模型请求，并消耗少量配额。

## 配置点火策略

默认策略符合主流订阅与限额结构：
- **5 小时点火组**（`Claude, Antigravity`）：每天在 `05:00`、`10:03`、`15:06`、`20:09` 本地时间点火。
- **仅周点火组**（`Codex`）：每周五 `08:08` 点火一次（适用于周五 08:00 额度恢复的 GPT Pro 订阅，在恢复后稍候点火）。

直接执行即可安装默认策略：

```powershell
pwsh -File .\install-ai-quota-schedule.ps1
```

如需自定义分组，例如仅使用 5 小时点火且无需周点火：

```powershell
pwsh -File .\install-ai-quota-schedule.ps1 `
  -FiveHourAI Claude,Antigravity `
  -WeeklyOnlyAI ''
```

如果三个 AI 都只有周额度或只希望每周点火一次：

```powershell
pwsh -File .\install-ai-quota-schedule.ps1 `
  -FiveHourAI '' `
  -WeeklyOnlyAI Codex,Claude,Antigravity `
  -DayOfWeek Friday `
  -WeeklyTime 08:08
```

周任务默认每周五 `08:08`（首次于 10 月 2 日 08:08 触发）。也可以显式传入具体日期时间，如 `-WeeklyTime '2026-10-02 08:08'`。如果服务显示的是固定周重置时间，建议把 `-WeeklyTime` 设在实际重置时间之后几分钟（避开额度刷新延迟）。

两个参数不能包含同一个 AI；安装器会拒绝重叠配置。省略某一组时，已存在的对应任务会被禁用，防止旧任务继续重复点火。

只验证 CLI 和策略而不注册任务：

```powershell
pwsh -File .\install-ai-quota-schedule.ps1 -CheckOnly
```

安装器会先检查所有被分配的 CLI。只有全部存在才会继续要求输入 Windows 账户密码并注册任务。这里必须输入账户密码，不能使用 Windows Hello PIN；密码由 Windows 任务计划程序用于在用户未登录或电脑睡眠时运行任务。

安装器使用 `-Force` 更新同名任务，因此再次运行相同命令即可修改配置。

## 模型选择

点火引擎默认已内置各 AI 消耗最低的轻量级模型，最大程度节约配额与 token：
- **Codex**: `gpt-5.6-luna`（ChatGPT 订阅支持的 Luna 轻量模型）
- **Claude**: `haiku`（`claude-haiku-4-5` 轻量模型）
- **Antigravity**: `gemini-3.8-flash-low`（Gemini 3.8 Flash 低推理开销模式）

如有特殊需要，仍可在手动点火或安装任务时显式指定不同模型进行覆盖：

```powershell
pwsh -File .\install-ai-quota-schedule.ps1 `
  -CodexModel gpt-5.6-luna `
  -ClaudeModel haiku `
  -AntigravityModel gemini-3.8-flash-low
```

## 自定义 CLI 路径

自动检测范围包括 PATH、npm 全局包装器以及三个 CLI 在 Windows 上的常见安装目录。也可以显式指定：

```powershell
pwsh -File .\install-ai-quota-schedule.ps1 `
  -CodexPath 'C:\path\to\codex.exe' `
  -ClaudePath 'C:\path\to\claude.exe' `
  -AntigravityPath 'C:\path\to\agy.exe'
```

## 安全与睡眠逻辑

- 点火提示词只要求回复 `OK`。
- Codex 使用临时会话和只读沙箱。
- Claude 禁用工具、扩展、MCP、会话持久化和权限提示，并使用受限/计划模式。
- Antigravity 使用非交互打印、计划模式和沙箱，并禁用斜杠命令。
- 如果输出明确表示周额度耗尽并带有恢复时间，脚本会把时间写入 `state`，恢复前的计划触发只记录并跳过，不再请求模型。
- 到达恢复时间后，下一次正常计划触发会重新点火并清除冷却状态。
- 如果额度错误没有提供可解析的恢复时间，脚本不会猜测一周，而是在下一次正常计划触发时做一次保底重试。
- 账户级 credits/overage 可能让请求在基础额度耗尽后继续产生付费使用；如果不希望付费兜底，需要在相应 AI 账户中关闭该设置。
- 只有 Windows 唤醒事件能归因到当前计划任务，并且用户空闲时间达到阈值时，脚本才会安排回睡。
- 如果电脑原本就在运行，或者用户有近期键鼠活动，脚本会保持电脑唤醒。

## 查看日志和任务

```powershell
Get-ScheduledTask -TaskName 'AI Quota 5h Activation'
Get-ScheduledTaskInfo -TaskName 'AI Quota 5h Activation'
Get-Content "$env:LOCALAPPDATA\AIQuotaActivation\logs\five-hour\activation-$(Get-Date -Format yyyy-MM-dd).log"
Get-ChildItem "$env:LOCALAPPDATA\AIQuotaActivation\state"
```

每周任务默认名为 `AI Quota Weekly Activation`，日志目录为 `logs\weekly`。

## 卸载计划任务

```powershell
Unregister-ScheduledTask -TaskName 'AI Quota 5h Activation' -Confirm:$false
Unregister-ScheduledTask -TaskName 'AI Quota Weekly Activation' -Confirm:$false
```

如需同时删除已部署脚本和日志，可在确认目录内容后删除：

```powershell
Remove-Item -LiteralPath "$env:LOCALAPPDATA\AIQuotaActivation" -Recurse -Force
```

## 回归测试

以下测试使用本地假 CLI 和模拟的 Windows 任务计划命令，不会请求真实模型，也不会注册真实任务：

```powershell
pwsh -File .\tests\test-v0.2.ps1
pwsh -File .\tests\test-installer-v0.2.ps1
```

## 扩展新的 AI

新增适配器只需在 `ai-quota-activate.ps1` 的三个位置增加同名分支：

1. `$supportedProviders`：允许的名称。
2. `Get-ProviderMetadata`：命令名、常见路径和安装提示。
3. `Get-ActivationArguments`：该 CLI 的无副作用、非交互调用参数。

唤醒、日志、失败隔离和自动回睡逻辑无需复制。

## 版本历史

- `v0.1`：Codex、Claude、Antigravity 通用点火引擎和独立周期安装器。
- `v0.2`：互斥的 5 小时/仅周配额策略；周额度耗尽后的持久化冷却与恢复后重试。
- `v0.3`：开箱即用轻量模型点火（Luna, Haiku, Flash）；默认分离 5 小时组（Claude, Antigravity）与周点火组（Codex）；支持智能起跑时间与精准周重置对齐；修复 Antigravity CLI 调用参数。
- `v0.4`：加入项目 Logo，并在个人主页 Vibes 项目区展示。

## 开源协议 (License)

本项目遵循 [MIT](LICENSE) 开源协议。

