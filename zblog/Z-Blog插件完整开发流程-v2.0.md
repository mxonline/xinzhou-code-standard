# Z-Blog 插件完整开发流程 v2.0

本流程是 Z-Blog PHP 插件开发、升级、修复、优化、重构和发布的默认总控流程。

目标只有一个：**用户提出需求后，ChatGPT 负责需求与状态总控，真实开发流程直接运行在能够访问代码仓库和终端的 Codex 工作区中；Codex 完成代码修改、本机实机验证、修复、Git/CI 和发布准备，用户不再逐步执行命令或手动管理 Codex。**

首选执行规范见：`zblog/Z-Blog-Codex工作区直接执行规范-v1.0.md`。

完整流程完成判定强制遵循：`zblog/Z-Blog完整开发流程硬门禁-v1.0.md`。

## 固定职责

- **ChatGPT：总控。** 恢复 Notion/GitHub 状态、分析用户需求或提出设计需求、生成/更新 PRD、确定技术边界与验收条件、判断风险、核验 Commit/CI/Release、回写 Notion。
- **Codex 工作区：真实执行。** 直接读取真实 Git 工作树和终端，修改源码、运行 PHP/测试、本机 Z-Blog/数据库/Nginx 验证、读取日志、失败自动修复、Commit/Push、处理 CI。
- **GitHub：代码事实来源。** 分支、Commit、PR、CI、Tag、Release 以 GitHub 和真实工作树为准。
- **Notion：长期项目状态。** 保存 PRD、关键技术决策、数据库/Hook变化、复杂故障、测试结论、发布记录。
- **Local Runner：可选辅助。** 只有在没有持续可用的 Codex 工作区、需要远程触发/定时批处理时使用；不再作为主开发链路。

## 一句话触发

用户可以直接说：

- “开发这个插件”
- “修这个 Bug”
- “开始开发 2.0”
- “给 xz_visit_stats 增加某功能”
- “你来设计下一版并直接开发”
- “运行 Z-Blog 插件完整开发流程 v2.0”

如果项目可识别，流程自动恢复，不逐阶段询问“下一步”。

## 完整闭环

```text
用户提出需求 / ChatGPT提出设计需求
→ 生成或恢复运行编号
→ 识别项目与任务类型
→ 读取 Notion 项目记录和开发规范
→ 读取 GitHub / 真实源码状态
→ 确认当前版本、分支、工作树和本机环境
→ 判断需求范围与风险
→ 更新 PRD / 验收条件
→ 确认 Hook、数据库、兼容方案和影响范围
→ Codex 进入真实项目工作区
→ 读取 AGENTS.md / PRD / 当前代码
→ 修改真实源码
→ 快速自动测试
→ 需要时直接执行本机 Z-Blog / PHP / 数据库 / Nginx 实机验证
→ 失败则读取真实错误、修复、复测
→ 按风险执行安全 / 性能 / 兼容检查
→ 检查 Diff / 敏感信息
→ Commit / Push 开发分支
→ GitHub CI
→ CI失败则读取日志、Codex本机修复、复测、再次Push
→ 更新版本号和插件文档
→ PR / 合并准备
→ Release Gate 判断
→ Notion阶段回写
→ 达到发布条件时执行发布 Dry Run
→ Tag / GitHub Release / 正式ZIP（仅发布条件满足时）
→ 发布后文档和Notion最终回写
→ 六项硬门禁检查
→ 输出真实完成状态
```

## 运行编号与状态

每次完整开发任务使用：

```text
DEV-YYYYMMDD-NNN
```

运行编号至少关联：项目、当前版本、目标版本、任务类型、当前阶段、Notion项目页/PRD、GitHub仓库、开发分支、最新Commit、CI状态、实机验证状态、发布状态和阻塞项。

同一任务中断后恢复使用原运行编号。

统一状态：

```text
已识别
已恢复上下文
需求分析中
PRD已更新
开发中
本机测试中
修复中
CI验证中
发布准备中
已完成
外部阻塞
已取消
```

状态只能来自真实执行结果。

## 阶段 0：恢复上下文

读取顺序：

1. Notion 对应项目页和 PRD；
2. Z-Blog 开发规范；
3. GitHub 当前仓库、默认/目标分支和真实源码；
4. 必要时读取 Issue、PR、Actions、Release、CHANGELOG；
5. 当前聊天最新明确要求优先。

Notion 与 GitHub 不一致时，以真实代码和最新明确决定为准，并修正长期记录。

## 中断恢复

换聊天、Codex中断或开发暂停后：

```text
读取 Notion 当前状态
→ 恢复原运行编号
→ 读取 GitHub 当前分支 / Commit / PR / CI
→ Codex读取真实工作树状态
→ 对比未完成任务
→ 从真实断点继续
```

不得要求用户重新描述已经记录的完整需求，不重复已完成动作。

## 阶段 1：任务分类

自动判断：

- 新插件
- 新功能
- Bug
- 性能优化
- 安全修复
- 数据库变更
- 重构
- 大版本升级
- 发布准备

小 Bug 走快速通道；架构、数据库、大版本、兼容性、多模块任务必须更新 PRD。

## 阶段 2：开发前确认

必须读取真实项目后确认：

- 插件 ID 与当前版本；
- 入口文件和 Hook；
- 数据表与升级逻辑；
- 受影响模块；
- Z-Blog/PHP兼容范围；
- 是否影响历史数据；
- 权限、CSRF、SQL、用户输入风险；
- Codex 工作区是否能直接访问所需终端和本机测试环境。

禁止未读现有代码就整体重写插件。

## 阶段 3：PRD 与 Codex 任务

复杂任务 PRD 至少包含：当前问题、目标版本、目标、范围、不包含范围、修改模块、Hook变化、数据库变化、兼容方案、验收标准、测试要求。

ChatGPT 输出的任务应让 Codex 在**当前真实工作区**直接执行，不要求用户复制到另一个中间 Runner。

Codex 进入仓库后必须优先读取项目 `AGENTS.md` 和真实当前状态。

## 阶段 4：Codex 直接开发

默认原则：

- Codex 直接修改真实项目工作树；
- 不修改 `zb_system`；
- 优先 Z-Blog 官方 Hook/API/模板机制；
- 不为了“看起来高级”增加无意义抽象；
- 修改范围尽量收敛；
- 数据库升级兼容旧数据；
- 普通可逆开发动作不逐项询问用户。

只有真实工作树发生修改并有可验证结果时，才叫“已执行”。

## 阶段 5：快速自动测试

默认高价值检查：

- `git diff --check`；
- PHP语法；
- 当前功能核心测试；
- PHPUnit（存在且相关时）；
- JS语法（JS变更时）；
- 权限/CSRF/SQL/敏感信息检查（相关时）。

失败自动：

```text
读取真实错误
→ 定位原因
→ 修改
→ 重跑相关测试
```

PHPStan、Semgrep、完整 PHPUnit 套件按项目和风险使用，不作为所有小修改的固定阻断门槛。

## 阶段 6：本机 Z-Blog 实机验证

以下情况默认必须实机：

- 大版本升级；
- 数据库创建/升级/迁移/索引；
- Hook生命周期；
- 插件安装、启用、停用、卸载；
- 后台页面、AJAX、权限；
- Nginx/PHP FastCGI 行为；
- IP、UA、Referer、状态码、蜘蛛等真实请求采集；
- 统计/采集性能；
- CI 无法还原的兼容行为。

Codex应直接使用当前工作区可访问的本机环境执行：

```text
真实 Z-Blog
+ PHP CLI
+ 本地数据库
+ Nginx/PHP日志
+ HTTP请求
```

CI通过不能替代必须的实机验收。

项目应提供统一入口（例如 `scripts/local-verify.ps1`）和 `docs/TESTING.md`，让 Codex 在同一终端连续开发、验证、修复。

## 阶段 7：风险驱动检查

- SQL/权限/上传/外部请求：加强安全检查；
- 高频 Hook、日志、统计聚合：性能检查；
- 公共函数/架构/大版本：回归；
- PHP/Z-Blog兼容变化：兼容矩阵；
- 正式发布：发布级检查。

## 阶段 8：Git 与 CI

开发完成后 Codex/工作流直接推进：

1. 检查 Diff、无关文件和敏感信息；
2. 更新必要版本/CHANGELOG；
3. Commit；
4. Push 开发分支；
5. CI；
6. CI失败则读取日志、本机修复、复测、再次Push；
7. 达到发布条件后进入 PR/合并/Release。

普通开发分支 Commit/Push 不需要用户逐项确认。

## 阶段 9：Notion 持续同步

同步：

- 运行编号与状态；
- PRD变化；
- 数据库/Hook/重要架构；
- 复杂故障；
- 本机实机测试；
- Commit/PR/CI/Release；
- 下一版本待办。

不复制普通代码 Diff。

## 阶段 10：插件文档

正式版本按 `zblog/Z-Blog插件发布文档规范-v1.0.md` 维护：

- `plugin.xml`
- `README.md`
- `docs/CHANGELOG.md`
- `docs/VERSION.md`
- `docs/RELEASE_NOTES_vX.Y.Z.md`
- 必要的升级/迁移说明

文档必须是真实维护者写法，和真实代码、测试、CI、实机状态一致；未验证内容不得写成已通过。

## 阶段 11：Release Dry Run

检查：

- 版本一致性；
- 安装/升级/迁移；
- 必要实机验收；
- CI；
- 发布包结构；
- 密钥/日志/缓存/开发文件排除；
- Tag、Release Notes、ZIP名；
- Notion发布记录预检查。

只能输出：

```text
可发布
```

或：

```text
不可发布：具体阻塞项
```

## 阶段 12：正式发布

Dry Run通过后：

```text
合并目标分支
→ Tag
→ GitHub Release
→ 正式ZIP
→ README / VERSION / CHANGELOG / Release Notes 最终回写
→ Notion发布记录
→ 已发布
```

默认“发布”指 GitHub Release + 正式 ZIP + 文档同步，不包含 Z-Blog 应用中心或生产部署，除非用户明确要求。

## 自动执行原则

在能够访问仓库和终端的 Codex 工作区中，普通开发默认连续执行，不反复要求用户确认。

只在以下情况暂停：

- 缺少关键凭据/权限；
- 当前环境无法访问必须资源；
- 涉及生产数据/生产部署/不可逆操作；
- 需求存在会导致高风险错误的重大歧义。

## 状态真实性

必须严格区分：

- **已执行**：真实工作树/命令/测试/Commit/CI/记录可验证；
- **已规划**：只有计划/PRD/命令；
- **外部阻塞**：当前环境无法完成。

生成提示词、脚本或计划不等于已经在 Codex、本机或 GitHub执行。

## 快速通道

```text
读取真实代码
→ 最小修复
→ 相关测试
→ Commit / CI
→ 必要时Notion回写
```

数据库迁移、安全写操作和正式发布不得绕过必要实机/发布门槛。

## Local Runner 兼容说明

已有 `codex/zblog-local-runner` 保留为可选辅助工具，不再是本流程默认架构。只有远程触发、定时批处理或没有持续Codex工作区时才考虑使用。

当 Codex 已经直接拥有真实工作树和终端时，禁止为了“自动化”再机械增加一层 Runner。

## 强制六项硬门禁

每次声明“运行完整开发流程”时，结束前必须原样给出：

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

判定规则：

- 任意 Gate 为 `BLOCKED`，`FINAL` 必须为 `INCOMPLETE`；
- 没有真实 Evidence 的 `PASS` 无效；
- 本应实机验证时，CI 通过不能替代 Local Runtime PASS；
- 中间 Phase 暂不发布时，Release Gate 必须为 `NOT READY` 并说明原因，不能省略；
- Notion Context 与 Notion Writeback 都是硬门禁；
- 只有 Tag、GitHub Release、正式 ZIP 已真实创建，才能写 `RELEASE: RELEASED`。

## 完成标准

一次开发只有在这些状态都明确后才闭环：

- 运行编号；
- 需求/PRD；
- 真实代码状态；
- 快速测试；
- 必要本机实机测试；
- Git/CI；
- Release Gate；
- Notion前置恢复与最终回写；
- 六项硬门禁最终判定。

完整规则以 `zblog/Z-Blog完整开发流程硬门禁-v1.0.md` 为准。
