# Z-Blog 完整开发流程硬门禁 v1.0

本规范是《Z-Blog 插件完整开发流程 v2.0》的强制收口规则。任何任务只要声明“运行完整开发流程”，就必须逐项经过以下 6 个 Gate；不得因为代码已写完、Commit 已 Push 或 CI 已通过而提前宣布完整流程完成。

机器恢复状态同时遵循 `zblog/Z-Blog无人值守开发Runtime-State-v1.0.md`。Canonical Runtime 只负责记录当前执行位置、Gate evidence 与 next action，不能制造 Git/CI/实机/Release/Notion 事实。

## 六项硬门禁

```text
[1] Notion Context       PASS / BLOCKED
[2] Codex Development    PASS / BLOCKED
[3] Local Runtime        PASS / NOT REQUIRED / BLOCKED
[4] GitHub CI            PASS / NOT REQUIRED / BLOCKED
[5] Release Gate         PASS / NOT READY / BLOCKED
[6] Notion Writeback     PASS / BLOCKED

FINAL: COMPLETE / INCOMPLETE
RELEASE: RELEASED / NOT RELEASED
```

任何非 `PENDING` Gate 结果都必须绑定可验证 evidence。Runtime 中使用 `evidence:<id>` 时，该引用必须能在同一 `DEV-YYYYMMDD-NNN` 的 evidence index 中解析；否则该 Gate 无效并进入状态验证。

### Gate 1：Notion Context

PASS 必须有真实证据证明：

- 已读取对应项目页、当前 PRD、运行编号或最近开发状态；
- 已确认当前任务与旧记录是否冲突；
- 本轮开发开始状态已写入或已有可验证的持续记录；
- Canonical Runtime 与 Notion 当前项目/PRD 关联已建立或恢复。

无法访问 Notion、未恢复项目状态、未建立本轮上下文时必须是 `BLOCKED`。

### Gate 2：Codex Development

PASS 必须有真实代码执行证据：

- Codex 已在真实工作树读取当前代码；
- 本轮要求的代码修改已经完成；
- Diff 已检查，无无关修改和敏感信息；
- 快速测试已执行并有结果；
- Runtime 记录的 branch/head SHA 与真实 Git 已 reconcile。

只有方案、提示词、PRD、Runtime 状态文字、未执行命令或预期结果时不得 PASS。

### Gate 3：Local Runtime

涉及以下任一内容时必须 PASS，不能用 CI 替代：

- 大版本升级；
- 数据库创建、升级、迁移、索引；
- Z-Blog Hook 生命周期；
- 安装、启用、停用、卸载；
- 后台页面、AJAX、权限；
- Nginx/PHP FastCGI；
- IP、UA、Referer、状态码、蜘蛛、访问采集；
- CI 无法真实还原的运行时行为。

PASS 必须来自真实本机 Z-Blog、数据库、HTTP、日志或对应自动实机脚本的执行证据。

`NOT REQUIRED` 只允许文档修改、纯静态配置或完全被快速测试覆盖的独立纯函数变更，并必须写明为什么不需要实机，同时绑定该判断 evidence。

本应实机但缺少登录态、数据库权限或测试环境时必须 `BLOCKED`。

### Gate 4：GitHub CI

仓库配置 CI 时，PASS 必须对应当前目标 Commit/PR 的真实 Actions 结果。

**CI PASS 必须与当前 Runtime `head_sha` 精确一致。** 产生新 Commit 后，旧 SHA 的 CI PASS 自动失效，必须重新验证；禁止用旧 Run、旧 PR head 或“之前绿过”继续推进。

CI 失败时必须读取失败日志、修复、本地复测、再次 Push，直到 PASS 或确认外部阻塞。

只有仓库确实没有 CI，或本轮任务明确不适用 CI，才允许 `NOT REQUIRED`，并说明原因和 evidence。

### Gate 5：Release Gate

此节点永远不能跳过。

- `PASS`：达到当前正式版本发布条件，Release Dry Run 通过，可以或已经进入 Tag / GitHub Release / 正式 ZIP。
- `NOT READY`：当前只是中间 Phase、功能批次或尚未达到正式版本发布条件。必须明确记录“已检查 Release Gate，但当前不发布”的原因并绑定 evidence。
- `BLOCKED`：本应发布但存在版本冲突、实机未通过、CI 未通过、迁移风险、文档不一致、打包问题等阻断项。

`NOT READY` 不等于漏掉 Release；它表示 Release 节点已经真实判断过。

只有真实 Tag + GitHub Release + 正式 ZIP 三类发布事实都存在时，才允许最终 `RELEASE: RELEASED`。

### Gate 6：Notion Writeback

PASS 必须在本轮结束前把真实状态写回 Notion，至少包括：

- 运行编号 / 当前 Phase；
- 已完成内容；
- 本机实机验证结论；
- Git 分支、Commit、PR、CI；
- Runtime revision / 当前 next action 或终态；
- Release Gate 结果；
- 未完成项、风险和下一步。

完整流程收口时应回读或以工具结果确认写入真实落盘。代码和 CI 已完成但 Notion 未回写，本 Gate 仍为 `BLOCKED`。

## Runtime 一致性前置条件

在 FINAL 判定前必须确认：

- 仍使用原 `DEV-YYYYMMDD-NNN`，没有因为中断重复创建同一任务 Run；
- `state_revision >= 1` 且当前 snapshot 可解析；
- `events.jsonl` sequence 单调连续；
- evidence index 与同一 execution 绑定；
- Gate 引用的 evidence 均可解析；
- Runtime branch/head 与真实 Git 已 reconcile；
- GitHub CI PASS 若存在，绑定当前 exact head SHA；
- Runtime 与真实外部证据冲突时已进入 `VERIFY_RUNTIME_STATE` / `RECONCILE_GIT` 或对应重新验证，而不是继续猜测执行。

任一关键一致性冲突未解决时，不得 `FINAL: COMPLETE`。

## FINAL 判定规则

`FINAL: INCOMPLETE` 的强制条件：

- 任意 Gate 为 `BLOCKED`；
- 本应实机但 Local Runtime 未 PASS；
- 仓库有 CI 但当前 Commit/PR 未验证；
- GitHub CI evidence 不是当前 exact head SHA；
- Notion 前置恢复或最终回写缺失；
- Release Gate 被跳过，没有 PASS / NOT READY / BLOCKED 的明确判断；
- Runtime identity/revision/events/evidence 关键冲突尚未解决。

`FINAL: COMPLETE` 仅表示**当前开发任务或 Phase 的完整闭环已经完成**，要求：

- Gate 1 PASS；
- Gate 2 PASS；
- Gate 3 PASS 或合法 NOT REQUIRED；
- Gate 4 PASS 或合法 NOT REQUIRED；
- Gate 5 PASS 或 NOT READY；
- Gate 6 PASS；
- 没有任何 BLOCKED；
- Canonical Runtime 与当前真实 Git/CI/evidence 一致。

只有正式 Tag / GitHub Release / 正式 ZIP 已真实创建，才能另外写：

```text
RELEASE: RELEASED
```

否则统一为：

```text
RELEASE: NOT RELEASED
```

## 强制结束报告

每次“完整开发流程”结束时，ChatGPT/Codex 必须原样输出一份 Gate 摘要，不得省略：

```text
FULL DEVELOPMENT FLOW GATE

[1] Notion Context       PASS / BLOCKED
    Evidence: ...
[2] Codex Development    PASS / BLOCKED
    Evidence: ...
[3] Local Runtime        PASS / NOT REQUIRED / BLOCKED
    Evidence: ...
[4] GitHub CI            PASS / NOT REQUIRED / BLOCKED
    Evidence: ...
[5] Release Gate         PASS / NOT READY / BLOCKED
    Evidence: ...
[6] Notion Writeback     PASS / BLOCKED
    Evidence: ...

FINAL: COMPLETE / INCOMPLETE
RELEASE: RELEASED / NOT RELEASED
```

没有 Evidence 的 PASS 无效。

## 禁止事项

- 禁止把“代码完成”写成“完整流程完成”。
- 禁止把“CI 通过”当作数据库/Hook/运行时实机通过。
- 禁止复用旧 head SHA 的 CI PASS。
- 禁止用 Runtime 状态文字替代真实执行 evidence。
- 禁止 Runtime 与真实 Git/CI 冲突时靠聊天记忆猜测继续。
- 禁止跳过 Notion 前置恢复或最终回写。
- 禁止因为当前 Phase 不发布就省略 Release Gate；必须写 `NOT READY` 和原因。
- 禁止用计划、提示词、待执行命令替代真实证据。
