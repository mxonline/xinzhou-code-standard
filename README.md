# 新肇代码开发规范

用于管理新肇数码相关项目的代码开发标准。

目标：让 AI 辅助开发保持真实项目开发质量，同时优先保证开发效率、安全性和可维护性。

## 开发前置 Reuse Gate

所有适合检索官方方案、成熟开源项目、可复用组件或现有架构的开发任务，在进入 PRD / 架构设计和 Codex 实现前，默认先执行：

`codex/REUSE_GATE.md`

Reuse Gate 固定输出 `USE / REUSE / FORK / BUILD` 之一，并检查许可证、维护状态、CI / 测试、安全、依赖健康度、技术栈与运行环境兼容性、二次开发成本和长期维护成本。Star 数仅作为辅助信号，不代替维护与兼容性判断。

## Z-Blog 插件默认流程

所有 Z-Blog PHP 插件开发、升级、修复、优化和重构任务，默认执行：

`zblog/Z-Blog插件完整开发流程-v2.0.md`

流程验收标准：

`zblog/Z-Blog插件完整开发流程-v2.0-验收规范.md`

核心原则：用户提出需求后，由 ChatGPT 自动恢复项目状态、生成或恢复运行编号、读取 Notion 与 GitHub、生成或更新 PRD、调度 Codex / 可用开发工具、运行测试、处理失败和 CI、支持中断恢复、同步 Notion，并在正式发布前执行发布 Dry Run，不再逐步询问“下一步”。

## Codex 全局外部情报回传

本仓库提供 Codex 全局外部情报路由的受管 bootstrap 与安装器。完整业务规则仍以 Notion 的 `External Intelligence Writeback & Routing Contract v1.0` 为 Source of Truth。

安装或更新 `$CODEX_HOME/AGENTS.md` 中的受管路由块：

```bash
python tools/install_codex_global_router.py
python tools/install_codex_global_router.py --check
```

默认 `$CODEX_HOME` 为 `~/.codex`；可使用环境变量 `CODEX_HOME` 或 `--codex-home` 覆盖。安装器只维护 `XINZHAO:GLOBAL_INTELLIGENCE_ROUTER` 标记之间的内容，不覆盖其它全局规则；标记损坏时会 fail closed。

安装器不会保存 OAuth 凭据，也不会自动改写 `config.toml`。`--check` 只报告 AGENTS 安装状态和 MCP/plugin 配置信号。Notion 工具不可读写、认证失败、写入失败或回读验证失败时，Codex 必须返回 `BLOCKED`，不能把聊天中的“分析完成”当成回传成功。

真实验收必须新开一个 Codex 任务并粘贴一条真实提示词相关 X 链接。只有 Notion 外部情报库完成幂等写入、Global Intelligence HANDOFF 与目标 Project HANDOFF 都更新，并且回读验证一致后，任务才允许返回 `INTELLIGENCE_WRITEBACK_COMPLETE`。

## 通用核心流程

需求识别 → GitHub / 官方生态检索 → Reuse Gate → 运行编号 → 项目文档与真实源码读取 → 影响范围判断 → PRD / 架构设计 → 开发实现 → 快速自动测试 → 故障恢复 → 风险驱动检查 → Git / CI → 文档同步 → 发布 Dry Run → 发布准备

## 适用项目

- Z-Blog插件
- Z-Blog主题
- PHP项目
- 网站功能开发
- Codex辅助开发项目

## 工具链原则

工具按项目和风险启用，不把所有重型检查设为每次必跑：

- PHP 语法检查：默认高价值基础检查
- PHPUnit：存在可测核心逻辑时使用
- PHPStan：按项目与风险启用
- Semgrep：安全敏感变更时优先启用
- GitHub Actions：仓库已配置时执行自动化验证

小修改优先快速、安全完成；数据库、安全、架构、大版本和正式发布任务自动升级检查强度。

## v2.0 稳定版门槛

至少完成四轮真实演练：快速通道、标准功能开发、中断恢复 + 故障恢复、发布 Dry Run。

验收总分 30 分，27 分以上方可标记稳定；“状态真实性”“高风险保护”“中断恢复”任一为 0 分时不得通过。
