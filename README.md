# AI Quota Activation v0.2

这是一个 Windows 通用 AI 配额点火器。它用一次极简、无工具、无文件修改的 CLI 请求，启动 Codex、Claude 或 Antigravity 的使用窗口，并可通过 Windows 任务计划程序执行 5 小时点火或每周点火。

默认一次点火以下三个 CLI：

- Codex CLI（`codex`）
- Claude Code CLI（`claude`）
- Google Antigravity CLI（`agy`）

也可以只选择其中一个或两个。通用引擎会逐个执行；某个 AI 失败不会阻止后面的 AI，最终任务会返回失败状态并把详情写入日志。

v0.2 使用互斥配额策略：同一个 AI 只能选择“5 小时点火”或“仅周点火”。已有 5 小时点火时不会再创建重复的周任务；只有没有 5 小时机制或主动不使用 5 小时任务的 AI 才进入周任务。

## 文件

```text
ai-quota-activate.ps1           # CLI 检测、点火、日志、唤醒归因和安全回睡
install-ai-quota-schedule.ps1   # 按互斥配额策略安装/更新 Windows 计划任务
VERSION                         # 当前版本号
tests/                          # 不请求真实模型、不注册真实任务的回归测试
logs/                           # 手动运行时生成（已忽略）
state/                          # 周额度冷却状态（已忽略）
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

默认把三个 AI 全部放入 5 小时组，每天在 `05:00`、`10:03`、`15:06`、`20:09` 本地时间点火；周任务不创建或禁用：

```powershell
pwsh -File .\install-ai-quota-schedule.ps1
```

如果 Antigravity 所在计划只有周额度，可将 Codex、Claude 放入 5 小时组，把 Antigravity 放入仅周组：

```powershell
pwsh -File .\install-ai-quota-schedule.ps1 `
  -FiveHourAI Codex,Claude `
  -WeeklyOnlyAI Antigravity
```

如果三个 AI 都只有周额度或只希望每周点火一次：

```powershell
pwsh -File .\install-ai-quota-schedule.ps1 `
  -FiveHourAI '' `
  -WeeklyOnlyAI Codex,Claude,Antigravity `
  -DayOfWeek Friday `
  -WeeklyTime 05:00
```

周任务默认每周五 `05:00`，与每天第一次 5 小时点火的时间一致。如果服务显示的是固定周重置时间，建议把 `-WeeklyTime` 设在实际重置时间之后几分钟。

两个参数不能包含同一个 AI；安装器会拒绝重叠配置。省略某一组时，已存在的对应任务会被禁用，防止旧任务继续重复点火。

只验证 CLI 和策略而不注册任务：

```powershell
pwsh -File .\install-ai-quota-schedule.ps1 `
  -FiveHourAI Codex,Claude `
  -WeeklyOnlyAI Antigravity `
  -CheckOnly
```

安装器会先检查所有被分配的 CLI。只有全部存在才会继续要求输入 Windows 账户密码并注册任务。这里必须输入账户密码，不能使用 Windows Hello PIN；密码由 Windows 任务计划程序用于在用户未登录或电脑睡眠时运行任务。

安装器使用 `-Force` 更新同名任务，因此再次运行相同命令即可修改配置。

## 模型选择

默认值：

- Codex：`gpt-6-luna`
- Claude：`haiku` 稳定别名
- Antigravity：不指定模型，使用 CLI 当前默认模型

可以在手动点火或安装任务时覆盖：

```powershell
pwsh -File .\install-ai-quota-schedule.ps1 `
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
