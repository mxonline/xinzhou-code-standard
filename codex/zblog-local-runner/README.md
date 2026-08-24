# Z-Blog 本地无人值守开发执行器 v1.0

> 当前定位：**可选辅助工具，不再是《Z-Blog 插件完整开发流程 v2.0》的默认主链路。**

主流程现在优先采用：

```text
ChatGPT 总控
→ 能直接访问真实 Git 工作树和终端的 Codex 工作区
→ 本机 Z-Blog / PHP / 数据库 / Nginx 实机验证
→ Git / CI / Release
```

详见：

- `zblog/Z-Blog插件完整开发流程-v2.0.md`
- `zblog/Z-Blog-Codex工作区直接执行规范-v1.0.md`

## 什么时候还需要 Local Runner

只有在下面这些场景才考虑使用本工具：

- Codex 不能持续运行在目标工作区，但需要远程触发本机任务；
- 需要 Windows 计划任务定时执行；
- 需要 GitHub Issue 作为远程任务队列；
- 需要特殊无人值守批处理或状态轮询。

如果 Codex 已经直接运行在能够访问真实插件工作树和终端的环境中，**不要为了自动化再额外套一层 Runner**。

## 原始能力

本工具仍保留以下实验/辅助能力：

```text
GitHub Issue 任务
→ Windows Task Scheduler
→ PowerShell Runner
→ Codex CLI
→ 本地测试
→ Commit / Push
→ CI
→ Issue 回传
```

它不属于当前默认插件开发必经步骤。

## 安全边界

如仍使用 Runner：

- 只允许白名单项目；
- 不接收远程任意 Shell 命令；
- 不修改生产数据库或生产站；
- 不修改 `zb_system`；
- 不使用常驻 `danger-full-access`；
- 不把计划、Prompt 或任务 Issue 当成已经完成的开发结果。

## 文件

- `runner-v1.ps1`
- `install.ps1`
- `config.example.json`
- `task.example.json`
- `codex-config.example.toml`

这些文件保留用于兼容和后续实验，不再代表 v2.0 的默认架构。
