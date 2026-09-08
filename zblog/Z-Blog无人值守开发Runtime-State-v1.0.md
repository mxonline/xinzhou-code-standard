# Z-Blog 无人值守开发 Runtime State v1.0

本规范定义 Z-Blog 完整开发流程的机器执行状态合同。它只解决“当前 DEV Run 做到哪里、如何跨中断恢复、哪些 Gate 有真实证据”这三个问题，不建立第二套开发流程，也不替代 Notion、GitHub、Codex 或本机实机验证。

## 1. 运行编号

每轮完整开发任务使用：

```text
DEV-YYYYMMDD-NNN
```

同一任务中断后必须继续使用原运行编号，不因换聊天、Codex 重启、Windows 重启或 Runner 中断重新编号。

## 2. Canonical Runtime Bundle

支持无人值守恢复的项目应将机器执行状态持久化为同一逻辑合同：

```text
<runtime-root>/<execution_id>/state.json
<runtime-root>/<execution_id>/events.jsonl
<runtime-root>/<execution_id>/evidence/index.json
```

项目可自行决定 `<runtime-root>` 的仓库路径；推荐 `.development/runtime`。不得要求所有仓库复制某个具体项目的实现脚本或目录结构，只要求语义合同一致。

### state.json

至少包含：

- `schema_version`
- `execution_id`
- `project`
- `repository`
- `current_version`
- `target_version`
- `task_type`
- `status`
- `current_phase`
- `next_action`
- `state_revision`
- `branch`
- `base_branch`
- `head_sha`
- `pr_number` / `pr_url`
- `ci`
- `gates`
- `blocked`
- `notion` refs
- `created_at`
- `updated_at`

### events.jsonl

append-only 事件账本；每条事件至少绑定：

- `seq`
- `execution_id`
- `state_revision`
- `event`
- `phase`
- `time`
- `data`

`seq` 必须单调递增，旧事件不得被 runtime helper 重写。

### evidence/index.json

只保存轻量证据身份和引用，不复制 Notion 正文、Actions 日志、数据库内容或发布包本体。每项至少包含：

- `id`
- `execution_id`
- `type`
- `result`
- `ref`
- `observed_at`
- 可选 `sha` / `run_id` / `details`

Runtime 中引用的 `evidence:<id>` 必须能在同一 execution 的 evidence index 中解析。

## 3. 权威边界

Canonical Runtime State 是“机器恢复执行位置”的权威，但不能制造事实。

当状态文字与真实外部事实冲突时，以下真实事实优先：

1. 当前 Git 工作树、分支、Commit；
2. 当前 PR 和与精确 head SHA 绑定的 GitHub Actions；
3. 真实本机 Z-Blog、PHP、数据库、HTTP、日志和实机脚本；
4. 真实 Tag、GitHub Release、正式 ZIP；
5. Notion 真实读取/回写结果；
6. Runtime State 中的状态文字。

冲突必须 fail closed，进入验证或 reconciliation，不得靠聊天上下文猜测。

## 4. 六项硬门禁保持不变

Runtime 只承载现有六 Gate：

```text
[1] Notion Context
[2] Codex Development
[3] Local Runtime
[4] GitHub CI
[5] Release Gate
[6] Notion Writeback
```

允许状态继续遵循《Z-Blog完整开发流程硬门禁-v1.0.md》：

- 普通 Gate：`PENDING / PASS / BLOCKED`
- Local Runtime、GitHub CI：另允许 `NOT_REQUIRED`
- Release Gate：另允许 `NOT_READY`

任一非 `PENDING` Gate 都必须绑定真实 evidence；没有 evidence 的 PASS 无效。

## 5. Resume 合同

中断恢复至少执行：

```text
load state
→ load evidence
→ load events
→ validate execution_id / revision / event sequence / evidence refs
→ reconcile current Git branch + head SHA
→ validate current-head CI evidence
→ restore Notion/PRD context
→ determine exactly one next action
```

如果 Runtime 缺失，应显式 `BOOTSTRAP_RUNTIME`；如果 identity/evidence/revision/gate 冲突，应 `VERIFY_RUNTIME_STATE`；如果 Git/CI 已漂移，应 `RECONCILE_GIT` 或重新验证 CI，而不是复用旧 PASS。

## 6. CI 精确 SHA 绑定

GitHub CI PASS 只有在证据对应当前目标 `head_sha` 时可复用。任何新 Commit 都会使旧 SHA 的 CI 证据变成 stale，流程必须重新进入 GitHub CI Gate。

## 7. 完成与发布分离

`FINAL: COMPLETE` 只表示当前开发任务/Phase 的六 Gate 已合法闭环。

中间阶段可以：

```text
Release Gate = NOT READY
FINAL = COMPLETE
RELEASE = NOT RELEASED
```

只有真实 Tag + GitHub Release + 正式 ZIP 都存在且 Release Gate = PASS，才允许：

```text
RELEASE = RELEASED
```

## 8. Legacy 状态文件

历史 `.codex-state.json`、任务队列、旧 Runner 或聊天记忆可以作为兼容输入，但不得与 canonical Runtime 竞争执行权威。新项目不应再新增第四套持久化状态服务。

## 9. 参考实现

`mxonline/zblogplugin-xz_visit_stats` 已实现一套参考落地：

```text
.development/runtime/<execution_id>/state.json
.development/runtime/<execution_id>/events.jsonl
.development/runtime/<execution_id>/evidence/index.json
scripts/dev_runtime.py
scripts/dev-flow.ps1
```

这是参考实现，不是要求其他 Z-Blog 仓库机械复制的唯一实现。其他项目可以使用不同语言/脚本，只要满足本合同和六项硬门禁。
