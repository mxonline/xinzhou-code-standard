# Z-Blog 本地无人值守开发执行器 v1.0

本执行器用于把《Z-Blog 插件完整开发流程 v2.0》中的“本机 Codex / 实机验证”阶段自动化。

目标不是让 Codex 获得整台 Windows 的无限权限，而是在指定 Z-Blog 测试项目内实现：任务领取 → 真实代码修改 → 本地测试 → 失败修复 → Git Commit / Push → GitHub CI → 结果回传，全程不要求用户逐条确认。

## 架构

```text
ChatGPT / v2.0 总控
→ GitHub 创建 [LOCAL-RUNNER] 任务 Issue
→ Windows Task Scheduler 每分钟启动 Runner
→ Runner 读取允许的项目配置
→ 检查 Git / GitHub / Codex / PHP
→ 同步目标仓库和开发分支
→ codex exec（approval_policy=never + workspace-write）
→ 本地 PHP / PHPUnit / 可信实机脚本 / HTTP 测试
→ 失败：把真实错误交给 Codex 修复并复测
→ 通过：Commit + Push
→ 等待 GitHub Actions
→ CI 失败：读取失败日志，再交给 Codex 修复
→ CI 通过：GitHub Issue 回写结果并关闭
→ ChatGPT 读取 Commit / CI / Issue 结果
→ Notion 同步
→ 继续 v2.0 发布流程
```

## 为什么任务队列使用 GitHub Issue

- ChatGPT 当前可以直接创建 GitHub Issue，因此可以真实下发本机任务。
- Windows Runner 通过已登录的 `gh` CLI 拉取任务，不需要额外服务器。
- Issue 天然保留运行编号、需求、结果、Commit 和 CI 证据。
- 不在源码主分支里写“任务文件”，避免任务队列污染插件代码历史。

任务 Issue 标题必须以 `[LOCAL-RUNNER]` 开头，正文必须包含 `XINZHOU_LOCAL_RUNNER_TASK_V1` 标记和 JSON 任务块。

## 安全边界

1. Runner 只处理 `config.json` 中显式允许的项目。
2. 任务不能下发任意 Shell / PowerShell / PHP 命令。
3. PHP lint、PHPUnit、HTTP Smoke 由 Runner 固定逻辑执行；涉及数据库、Nginx、Hook 等扩展验证时，只调用本机配置指定的“可信测试脚本”。
4. 可信测试脚本必须位于 Codex 可写工作树之外，Runner 会拒绝执行工作树内部的 PowerShell 实机脚本，避免通过测试脚本绕过沙箱。
5. Codex 使用 `workspace-write`，不使用 `danger-full-access`。
6. Codex 不负责 Git Push；Git / GitHub 操作由 Runner 固定逻辑执行。
7. Runner 启动新任务前要求工作树干净，避免覆盖人工未提交修改；中断任务使用本地状态文件恢复。
8. 分支必须匹配本机配置的允许前缀。
9. 不允许自动修改生产数据库、生产网站或 Z-Blog `zb_system` 核心。
10. 本执行器面向本地测试站；线上部署仍属于单独的高风险阶段。

## 文件

- `runner-v1.ps1`：正式主执行器。
- `install.ps1`：首次安装、预检和 Windows 计划任务注册。
- `config.example.json`：本机项目、测试、重试和 CI 配置示例。
- `task.example.json`：ChatGPT 下发任务时使用的任务结构。
- `codex-config.example.toml`：Codex 无人值守 Profile 示例。

## 一次性准备

本机需要已有：

- Git
- GitHub CLI (`gh`) 且已登录
- Codex CLI 且已登录
- PHP CLI
- 本地 Z-Blog 测试站
- 目标插件目录本身是可正常 fetch / push 的 Git 工作树

首次只需要完成一次认证。Runner 不保存 GitHub Token、Codex Token、数据库密码或 Z-Blog 后台密码。

## 安装

在本仓库目录执行：

```powershell
cd codex\zblog-local-runner
Copy-Item .\config.example.json .\config.json
notepad .\config.json
.\install.ps1 -ConfigPath .\config.json
```

安装脚本会：

1. 检查 `git`、`gh`、`codex`、`php`。
2. 检查 GitHub CLI 登录状态。
3. 检查配置文件中的本地项目目录与 Git origin。
4. 在 `~/.codex/config.toml` 中追加 `zblog_unattended` Profile（如果尚不存在）。
5. 调用 `runner-v1.ps1 -Preflight` 做一次真实预检。
6. 注册 `XinZhao ZBlog Local Runner` Windows 计划任务，每分钟运行一次 `runner-v1.ps1 -Once`。

安装完成后不需要打开 Codex 桌面窗口。

## Codex 权限模型

Runner 使用独立 Profile：

```toml
[profiles.zblog_unattended]
approval_policy = "never"
sandbox_mode = "workspace-write"
model_reasoning_effort = "high"
```

`never` 的含义是无人值守任务中不弹出命令批准；超出沙箱的操作直接失败并返回 Codex，而不是请求用户点确认。

不要把本 Runner 改成 `danger-full-access` 常驻运行。

## 任务格式

示例任务：

```json
{
  "schema_version": 1,
  "run_id": "DEV-20260825-001",
  "project": "xz_visit_stats",
  "mode": "develop",
  "target_branch": "feature/visit-stats-v2.0",
  "objective": "开发访问统计插件 2.0 的实时访客统计与后台总览第一批功能。",
  "acceptance_criteria": [
    "旧版访问记录可继续读取",
    "后台无 PHP Fatal/Warning/Notice",
    "本地核心测试通过"
  ],
  "commit_message": "feat: start visit stats 2.0 core",
  "auto_commit": true,
  "auto_push": true
}
```

任务中不存在 `commands` 字段。即使 Issue 被错误编辑，也不能远程让 Runner 直接执行任意系统命令。

## 默认验证链

Runner 按项目配置执行：

1. PHP 全量语法检查（排除 vendor）。
2. PHPUnit（存在且项目配置启用时）。
3. 本机可信测试脚本（配置时）。
4. 本地站 HTTP Smoke Test（启用时）。
5. Git diff / 状态检查。
6. Commit / Push。
7. GitHub Actions（启用时）。

访问统计插件 2.0 所需的数据库升级、Hook 触发、真实访问写入、蜘蛛 UA、Referer、Nginx/PHP 日志等实机验证，应逐步沉淀到 `%USERPROFILE%\.xinzhou-zblog-runner\tests\xz_visit_stats.ps1` 之类的可信脚本，由 Runner 固定调用。该脚本位于插件工作树之外，Codex 只能根据测试结果修代码，不能修改测试规则本身。

## 自动修复

本地验证失败时：

```text
真实失败输出
→ 生成 repair prompt
→ Codex 在同一工作树修复
→ 重新运行完整本地验证
```

默认最多 3 次本地尝试。

Push 后如果 GitHub Actions 失败：

```text
读取 gh run --log-failed
→ Codex 修复
→ 本地复测
→ 新 Commit / Push
→ 再次等待 CI
```

CI 自动修复次数由 `config.json` 控制。

## 中断恢复

Runner 会为正在处理的 Issue 保存本地状态文件。Windows 重启、计划任务中断或 Codex 进程异常退出后，只要 Issue 仍为打开状态，下一轮会识别同一个运行编号、分支和尝试次数，从当前真实工作树继续，而不是重新覆盖项目。

## 失败状态

最终仍失败时，Runner 会：

- 尽量把当前修改保存到当前开发分支的 WIP Commit 并 Push（不会合并 main）。
- 在任务 Issue 回写真实错误、分支和 Commit。
- 将 Issue 关闭为已处理但失败。
- 本地日志保留完整输出。

ChatGPT 后续读取该 Issue 后，应把状态记为“失败 / 待自动重试或设计调整”，不得标记为完成。

## 与 v2.0 的衔接

以后总控流程中的本机阶段变为：

```text
ChatGPT 生成/更新 PRD
→ 创建 LOCAL-RUNNER Issue
→ 本机执行器自动开发和实机测试
→ GitHub 回传结果
→ ChatGPT 核验 Commit / CI
→ Notion 回写
→ 后续 Release Dry Run / 发布
```

只有以下情况才需要人工介入：

- GitHub / Codex 首次登录或登录失效。
- Windows 权限阻止计划任务、PHP、Nginx 或文件访问。
- 本地工作树存在无法自动处理的人工未提交修改。
- 需求涉及生产数据、线上覆盖或其他不可逆操作。

普通插件开发、Bug 修复、测试失败和 CI 修复不应再要求用户打开 Codex 或逐次确认。
