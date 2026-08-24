# Z-Blog 插件完整开发流程 v2.0

本流程是所有 Z-Blog PHP 插件开发、升级、修复、优化和重构任务的默认总控流程。

目标：用户只提出需求，ChatGPT 自动恢复项目状态、调用可用工具、组织本机 Codex 开发、实机测试、Git 版本管理、Notion 同步、插件文档和正式发布，不再逐步询问“下一步”，也不要求用户每次打开 Codex 或逐项确认。

## 固定职责

- ChatGPT：需求分析、项目恢复、PRD、任务拆分、工具调度、LOCAL-RUNNER 任务下发、结果检查和流程推进。
- 本地无人值守 Runner：从 GitHub Issue 领取任务，调用本机 Codex、运行本地 Z-Blog/PHP 测试、失败重试、Commit/Push、等待 CI 并回传结果。
- Codex：在 Runner 限定的真实工作树内读取代码、修改代码、分析真实错误并修复，不负责生产部署和 GitHub 发布。
- GitHub：源码唯一事实来源，同时承担本地任务队列、分支、Commit、PR、Tag、Release 和 CI 状态。
- Notion：保存项目状态、PRD、架构、数据库、重要 Hook、Bug、测试和发布记录。

本地无人值守执行器规范见：`codex/zblog-local-runner/README.md`。

## 自动触发

用户提出明确开发意图时自动进入本流程，例如：

- 开发这个插件
- 给某插件增加功能
- 修这个 Bug
- 开始开发 2.0
- 优化这个功能
- 你来设计下一版并直接开发

不要求用户重复已有项目信息，也不再逐阶段询问是否继续。

## 完整闭环

```text
用户提出需求 / ChatGPT 提出设计需求
→ 生成或恢复运行编号
→ 识别项目与任务类型
→ 读取 Notion 项目记录与开发规范
→ 读取 GitHub / 真实源码状态
→ 确认当前版本、分支、运行环境
→ 判断需求范围与风险
→ 更新 PRD / 开发任务
→ 确认 Hook、数据库、兼容方案和影响范围
→ 创建或选择开发分支
→ 需要本机实机阶段时创建 [LOCAL-RUNNER] GitHub Issue
→ Windows Runner 自动领取
→ Codex 修改真实本机工作树
→ 本地 PHP / Z-Blog / HTTP /可信实机测试
→ 失败则自动把真实错误交给 Codex 修复并复测
→ 通过后 Commit / Push
→ GitHub CI
→ CI 失败则 Runner 读取失败日志、Codex 修复、再复测和 Push
→ GitHub Issue 回传 SUCCESS / FAILED / BLOCKED
→ ChatGPT 核验真实 Commit / CI / Issue
→ 按风险补充安全 / 性能 / 兼容检查
→ 更新版本号、CHANGELOG 和插件文档
→ PR / 合并或发布准备
→ Notion 回写
→ 发布 Dry Run
→ Tag / GitHub Release / 正式 ZIP
→ 文档最终回写
→ 输出真实完成状态
```

## 运行编号

每次完整开发任务必须生成唯一运行编号：

```text
DEV-YYYYMMDD-NNN
```

运行编号至少关联：项目名称、当前版本、目标版本、任务类型、当前阶段、Notion 项目页/PRD、GitHub 仓库、开发分支、LOCAL-RUNNER Issue、最新 Commit、CI 状态、发布状态和阻塞项。

同一轮开发中断后恢复时沿用原运行编号。只有全新独立任务才创建新编号。

## 运行状态

运行状态至少使用：

```text
已识别
已恢复上下文
需求分析中
PRD已更新
本机任务已下发
本机开发中
本机测试中
修复中
CI验证中
发布准备中
已完成
外部阻塞
已取消
```

状态必须来自真实执行结果，不得仅因生成了计划、提示词或 Issue 而前移到“开发完成”。

## 上下文恢复

读取顺序：

1. 对应 Notion 项目页和已有 PRD。
2. Z-Blog 通用开发知识库与当前规范。
3. GitHub 当前仓库、默认分支、目标分支和真实源码。
4. 检查当前运行编号关联的 `[LOCAL-RUNNER]` Issue、Commit、PR、Actions、Release 和 CHANGELOG。
5. 当前聊天中的最新明确要求优先于旧记录。

Notion 与 GitHub 记录冲突时，以真实代码和最新明确决策为准，并回写修正长期记录。

## 中断恢复

当聊天中断、换新聊天、本机 Runner 中断或开发暂停后，恢复顺序：

```text
读取 Notion 当前状态
→ 恢复原运行编号
→ 读取 GitHub 当前分支
→ 读取 LOCAL-RUNNER Issue 状态
→ 读取最新 Commit / PR / CI
→ 对比未完成任务
→ 从上次真实断点继续
```

Windows Runner 同时保存本地任务状态。计划任务、Codex 或 Windows 异常中断后，只要任务 Issue 仍打开，下一轮可从同一运行编号和分支继续。

恢复时不得要求用户重新描述已经记录的完整需求，不重复已经完成的开发动作，不重复创建同一 PRD。

## 任务分类

自动判断任务属于新插件、新功能、Bug、性能优化、安全修复、数据库变更、重构、大版本升级或发布准备。

小 Bug 可走快速通道，不强制生成冗长 PRD。涉及架构、数据库、大版本、兼容性或多个模块时必须更新 PRD。

以下任务默认判定需要本机实机阶段：

- 大版本升级。
- 数据库创建、升级和迁移。
- Z-Blog Hook 真实触发。
- Nginx / PHP FastCGI 行为。
- 实际 HTTP 请求、Referer、UA、IP、状态码等采集。
- 后台页面和真实数据库查询。
- 仅靠 CI 无法验证的插件启用、升级、卸载、兼容和性能行为。

## 开发前确认

开发前必须确认：

- 当前插件版本和插件 ID
- 主要入口文件和 Hook
- 数据表与升级逻辑
- 受影响文件
- Z-Blog / PHP 兼容范围
- 是否影响现有数据
- 是否涉及权限、CSRF、SQL 或用户输入
- 本机 Runner 对该项目是否已配置
- 本地工作树、Git origin 和测试站是否与项目匹配

禁止未读取现有代码就整体重写插件。

## PRD 与 Codex 任务

复杂任务的 PRD 至少包含：当前问题、目标版本、本次目标、包含范围、不包含范围、修改模块、Hook 变化、数据库变化、兼容方案、验收标准和测试要求。

需要本机执行时，ChatGPT 根据 PRD 创建机器可读的 `[LOCAL-RUNNER]` GitHub Issue。任务只包含运行编号、项目、目标分支、目标、验收条件和 Commit 信息，不允许远程下发任意 Shell/PowerShell/PHP 命令。

Codex 必须基于真实项目状态开发，保持原有代码风格，优先 Z-Blog 原生机制，避免无意义封装和无必要文件。

## 本机无人值守开发

默认本机执行方式是 `Z-Blog 本地无人值守开发执行器 v1.0`：

```text
GitHub Issue 任务队列
→ Windows Task Scheduler
→ PowerShell Runner
→ codex exec
→ workspace-write
→ approval_policy=never
```

原则：

- 用户不需要打开 Codex Desktop。
- 普通本地代码编辑和测试不请求逐项批准。
- Codex 仅在插件工作树内拥有写权限，不启用常驻 `danger-full-access`。
- Git fetch/checkout/commit/push、GitHub Issue 和 CI 由 Runner 固定代码管理，不交给任务 Prompt 任意执行。
- Runner 只处理本机 `config.json` 白名单项目。
- Runner 不接受任务里的任意系统命令字段。
- 可信数据库/Nginx/Hook/实机验证脚本必须位于 Codex 可写工作树之外。
- 新任务要求工作树干净；已领取任务通过本地状态文件支持断点恢复。

本机 Runner 返回状态：

```text
[LOCAL-RUNNER][SUCCESS]
[LOCAL-RUNNER][FAILED]
[LOCAL-RUNNER][BLOCKED]
```

ChatGPT 必须读取真实 Issue 回传、Commit 和 CI 后才能更新对应运行状态。

## 代码开发原则

- 不直接修改 `zb_system` 核心文件。
- 优先使用官方 Hook / API / 模板机制。
- 保持代码简单、可维护。
- 修改范围尽量局限在当前需求。
- 数据库升级必须兼容旧版本数据。
- 高风险操作必须可回滚或有明确保护。

只有真实工具或 LOCAL-RUNNER 返回可验证修改结果后，才可以标记为“已执行”。

## 快速自动测试

默认阻断检查只保留高价值项目：

- PHP 语法检查
- 本次功能核心测试
- 受影响数据库创建 / 升级检查
- 插件启用、停用及必要升级路径检查
- 关键 Hook 触发检查
- PHP Fatal / Warning / Notice 和 SQL 错误检查
- 后台写操作权限与 CSRF 检查
- 敏感信息误提交检查

Runner 默认执行 PHP lint、可用的 PHPUnit、可信实机测试脚本和 HTTP Smoke Test。项目需要更深验证时，把固定测试能力建设到 Runner 的可信测试区，而不是通过远程 Issue 下发任意命令。

失败时自动执行：定位错误 → 修改代码 → 重跑相关测试，直到通过或确认外部阻塞。

不要求每轮截图，截图只用于最终 UI 验收或视觉问题。

## 故障恢复

普通可修复故障不等待用户确认，自动进入恢复闭环：

```text
检测失败
→ 读取真实本地错误 / CI 日志
→ 定位原因
→ Codex 修改代码
→ 重跑相关本地测试
→ Commit / Push
→ 再次验证 CI
→ GitHub Issue 回传
→ 更新运行状态与 Notion
```

仅允许在测试分支或测试环境进行故障注入验收，例如 PHP 语法错误、测试断言失败或可恢复的 CI 失败。禁止在生产数据库或生产文件中故意制造故障。

发现错误后不得在未读取日志的情况下猜测原因，修复后必须复测，未通过不得标记完成。

## 风险驱动检查

不再把所有重型检查设为每次必跑：

- SQL、权限、文件上传、外部请求：加强安全检查。
- 高频 Hook、日志、统计聚合：增加性能检查。
- 公共函数、架构、大版本：增加回归测试。
- PHP / Z-Blog 兼容变化：增加兼容矩阵。
- 正式发布前：执行发布级完整检查。

PHPStan、Semgrep、完整 PHPUnit 套件按项目和风险启用，不作为所有小修改的固定阻断门槛。

## Git 与 CI

开发完成后自动推进：

1. 检查 diff 和敏感文件。
2. 更新版本号和 CHANGELOG。
3. Commit。
4. Push 到开发分支。
5. 运行仓库已有 CI。
6. CI 失败则读取日志、修复、本地复测并再次 Push。
7. 达到条件后进入 PR / 合并 / Tag / Release。

当本机 Runner 已启用时，3～6 可由 Runner 在同一任务内闭环，不需要用户逐条操作。

涉及合并主分支、正式 Release、覆盖线上文件等高影响动作时，按权限和风险规则执行。

## Notion 同步

Notion 从需求进入时就参与，需记录：

- 运行编号与当前阶段
- 当前版本和状态
- PRD / 需求变化
- LOCAL-RUNNER Issue 与本机执行状态
- 重要技术决策
- 数据库和 Hook 变化
- 复杂 Bug 原因和修复
- 本地测试与 CI 结果
- Commit / PR / Release
- 下一版本待办

普通代码 Diff 不复制到 Notion。

## 插件文档与发布准备

正式版本必须按 `zblog/Z-Blog插件发布文档规范-v1.0.md` 维护真实插件文档，包括：

- `plugin.xml`
- `README.md`
- `docs/CHANGELOG.md`
- `docs/VERSION.md`
- `docs/RELEASE_NOTES_vX.Y.Z.md`
- 必要时升级/迁移说明

文档必须基于真实代码、Diff、测试、CI 和版本状态，用插件维护者的自然写法；不得把待验证、计划中或未执行内容写成已完成，不使用空泛 AI 式“全面优化”“显著提升”等文案。

同时检查安装/升级逻辑、发布包文件、敏感文件排除、Tag/Release 信息和 Notion 发布记录。

代码完成与正式发布分开记录。

## 发布 Dry Run

进入正式 Tag、Release 或部署前必须进行发布 Dry Run。Dry Run 不创建正式 Release、不覆盖线上文件、不修改生产数据库。

至少检查：

- `plugin.xml` 插件 ID 与版本号
- README / VERSION / CHANGELOG / Release Notes 一致性
- 安装 / 升级 / 数据库迁移逻辑
- 卸载策略
- 发布包目录结构
- `.git`、日志、缓存、临时文件排除
- 密钥、Token、密码和数据库配置排除
- PHP 语法检查
- 发布级核心功能测试
- 必要的本机实机验收
- Tag 名称与 Release Notes 准备
- Notion 发布记录预检查

Dry Run 结果只能是：

```text
可发布
```

或：

```text
不可发布：阻塞项列表
```

只有 Dry Run 通过后，才允许进入正式 Tag / GitHub Release 阶段。

## 正式发布边界

除非用户另行明确要求，本流程中的“正式发布”默认指：

```text
合并 main
→ Tag
→ GitHub Release
→ 正式 ZIP
→ README / VERSION / CHANGELOG / Release Notes 最终回写
→ Notion 发布记录
```

默认不包含上传 Z-Blog 应用中心，也不自动覆盖线上网站。

## 自动执行与暂停条件

能通过当前工具或已安装 LOCAL-RUNNER 完成的步骤直接执行，不反复询问。

以下情况才暂停并明确标记阻塞：

- GitHub / Codex 首次认证或认证失效。
- Windows 权限阻止计划任务、文件、PHP/Nginx 或本地测试环境。
- 本地工作树存在无法安全覆盖的人工未提交修改。
- 缺少必须的服务器权限或关键凭据。
- 涉及删除生产数据、覆盖线上数据库等不可逆高风险操作。
- 本地 Runner 尚未完成首次安装或当前离线，且本次任务必须做实机验证。

“当前聊天不能直接控制本机 Codex”本身不再是正常暂停理由；Runner 已安装时，应自动通过 GitHub Issue 下发本机任务。

## 禁止模拟执行

必须区分：

- 已执行：有真实工具、LOCAL-RUNNER Issue、Commit、CI、文件或记录可验证。
- 已规划：只生成方案、任务或命令，尚未真实执行。
- 外部待执行：本机 Runner 未安装/离线、需要服务器或其他当前未连接环境完成。

创建了 LOCAL-RUNNER Issue 只能说明“本机任务已下发”，不能在收到真实结果前写成“本机开发完成”。

## 快速通道

明确的小 Bug、小范围 CSS / JS / PHP 修复可缩短为：

```text
读取真实代码 → 修复 / LOCAL-RUNNER → 相关测试 → Commit / CI → 必要时回写 Notion
```

数据库迁移、安全相关写操作和正式发布检查不能使用快速通道跳过。

## 流程验收

本流程的正式验收规范见：`zblog/Z-Blog插件完整开发流程-v2.0-验收规范.md`。

本地无人值守能力还必须单独验证：

1. Runner Preflight 通过。
2. GitHub Issue 能被本机自动领取。
3. Codex 在 `never + workspace-write` 下无需人工确认完成代码修改。
4. 本地测试失败能够自动修复并复测。
5. Commit / Push 能真实回传。
6. CI 失败能够读取真实日志并自动进入修复轮次。
7. Windows/Runner 中断后可以恢复同一运行编号。

## 完成标准

一次开发任务只有在以下状态都明确后才算闭环：

- 运行编号明确
- 需求状态明确
- 真实代码状态明确
- 本机实机状态明确（需要时）
- 测试结果明确
- Git / CI 状态明确
- Notion 状态明确
- 插件文档状态明确
- 发布状态明确
