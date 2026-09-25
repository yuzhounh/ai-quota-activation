# AI Quota Activation

这是一个 Windows 通用 AI 配额点火器。它用一次极简、无工具、无文件修改的 CLI 请求，启动 Codex、Claude 或 Antigravity 的使用窗口，并可通过 Windows 任务计划程序执行 5 小时点火或每周点火。

默认一次点火以下三个 CLI：

- Codex CLI（`codex`）
- Claude Code CLI（`claude`）
- Google Antigravity CLI（`agy`）

也可以只选择其中一个或两个。通用引擎会逐个执行；某个 AI 失败不会阻止后面的 AI，最终任务会返回失败状态并把详情写入日志。

## 文件

```text
ai-quota-activate.ps1           # CLI 检测、点火、日志、唤醒归因和安全回睡
install-ai-quota-schedule.ps1   # 安装/更新 5 小时或每周 Windows 计划任务
logs/                           # 手动运行时生成（已忽略）
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

## 安装 5 小时点火任务

默认每天在 `05:00`、`10:03`、`15:06`、`20:09` 本地时间点火三个 AI：

```powershell
pwsh -File .\install-ai-quota-schedule.ps1 -Cycle FiveHour
```

自定义 AI 和时间：

```powershell
pwsh -File .\install-ai-quota-schedule.ps1 `
  -Cycle FiveHour `
  -AI Codex,Claude `
  -Times 05:00,10:03,15:06,20:09
```

## 安装每周点火任务

默认每周五 `08:00` 点火三个 AI：

```powershell
pwsh -File .\install-ai-quota-schedule.ps1 -Cycle Weekly
```

自定义星期、时间和任务名称：

```powershell
pwsh -File .\install-ai-quota-schedule.ps1 `
  -Cycle Weekly `
  -DayOfWeek Monday `
  -WeeklyTime 07:30 `
  -TaskName 'My Weekly AI Activation'
```

安装器会先检查所有选中的 CLI。只有全部存在才会继续要求输入 Windows 账户密码并注册计划任务。这里必须输入账户密码，不能使用 Windows Hello PIN；密码由 Windows 任务计划程序用于在用户未登录或电脑睡眠时运行任务。

安装器使用 `-Force` 更新同名任务，因此再次运行相同命令即可修改配置。

## 模型选择

默认值：

- Codex：`gpt-6-luna`
- Claude：`haiku` 稳定别名
- Antigravity：不指定模型，使用 CLI 当前默认模型

可以在手动点火或安装任务时覆盖：

```powershell
pwsh -File .\install-ai-quota-schedule.ps1 `
  -Cycle Weekly `
  -CodexModel gpt-6-luna `
  -ClaudeModel haiku `
  -AntigravityModel '<agy models 显示的模型名>'
```

传入空字符串可让 Codex 或 Claude 也使用各自 CLI 的默认模型：

```powershell
pwsh -File .\ai-quota-activate.ps1 -CodexModel '' -ClaudeModel '' -DryRun
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
- 只有 Windows 唤醒事件能归因到当前计划任务，并且用户空闲时间达到阈值时，脚本才会安排回睡。
- 如果电脑原本就在运行，或者用户有近期键鼠活动，脚本会保持电脑唤醒。

## 查看日志和任务

```powershell
Get-ScheduledTask -TaskName 'AI Quota 5h Activation'
Get-ScheduledTaskInfo -TaskName 'AI Quota 5h Activation'
Get-Content "$env:LOCALAPPDATA\AIQuotaActivation\logs\five-hour\activation-$(Get-Date -Format yyyy-MM-dd).log"
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

## 扩展新的 AI

新增适配器只需在 `ai-quota-activate.ps1` 的三个位置增加同名分支：

1. `$supportedProviders`：允许的名称。
2. `Get-ProviderMetadata`：命令名、常见路径和安装提示。
3. `Get-ActivationArguments`：该 CLI 的无副作用、非交互调用参数。

唤醒、日志、失败隔离和自动回睡逻辑无需复制。
