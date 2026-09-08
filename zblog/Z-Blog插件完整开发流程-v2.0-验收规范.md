# Z-Blog 插件完整开发流程 v2.0 验收规范

本规范用于验证 `Z-Blog插件完整开发流程-v2.0.md` 是否真正可执行，而不只是文档完整。

目标：用户只提出需求后，流程能够自动恢复上下文、调用可用工具、推进开发、处理失败、恢复中断、完成发布准备，并且全程区分“已执行 / 已规划 / 外部待执行”。

无人值守机器恢复状态的验收同时遵循 `zblog/Z-Blog无人值守开发Runtime-State-v1.0.md`。

## 1. 验收原则

验收分为五类：

1. 静态完整性
2. 自动触发与运行编号
3. 中断恢复
4. 故障恢复
5. 发布 Dry Run

所有验收都必须保留可验证证据，例如 Notion 页面、GitHub 文件、Commit、CI 状态、日志、测试输出或发布包清单。

禁止以“已生成命令、已生成提示词、已写计划、已写 Runtime 状态”代替真实执行结果。

## 2. 运行编号规范

每次进入完整开发流程时，为本轮任务生成唯一运行编号：

```text
DEV-YYYYMMDD-NNN
```

示例：

```text
DEV-20260824-001
```

运行编号至少关联：

- 项目名称
- 当前版本
- 目标版本
- 任务类型
- 当前阶段
- Notion 项目页 / PRD
- GitHub 仓库
- 开发分支
- 最新 Commit
- CI 状态
- 发布状态
- 阻塞项

同一轮开发中断后恢复时继续使用原运行编号，不重新创建。

只有用户提出全新独立开发任务时才创建新的运行编号。

## 2.1 Runtime Bundle 验收

支持无人值守恢复的项目必须为同一 `DEV-YYYYMMDD-NNN` 提供等价的：

```text
state.json
events.jsonl
evidence/index.json
```

验收点：

- `state.json` 有 `execution_id`、`state_revision`、`branch`、`head_sha`、六 Gate 和 `next_action`；
- `events.jsonl` append-only，`seq` 单调递增；
- `evidence/index.json` 与同一 execution 绑定；
- Runtime 中所有 `evidence:<id>` 可解析；
- 同一任务冷恢复不重新生成 run id；
- Git/CI 与 Runtime 冲突时 fail closed，而不是继续执行；
- GitHub CI PASS 只能在 exact-head SHA 一致时复用；
- 旧聊天记忆、旧 Runner 状态或历史 `.codex-state.json` 不能单独覆盖 Canonical Runtime。

项目可以用不同语言和路径实现，不要求复制某个参考仓库的具体脚本。

## 3. 状态机

每轮运行至少使用以下状态之一：

```text
已识别
已恢复上下文
需求分析中
PRD已更新
开发中
测试中
修复中
CI验证中
发布准备中
已完成
外部阻塞
已取消
```

状态更新必须来自真实执行结果。

## 4. 静态完整性验收

检查主流程是否覆盖：

- 自动触发
- Canonical Runtime / DEV run
- Runtime state/events/evidence
- Notion 项目恢复
- GitHub / 真实代码读取
- 当前版本 / 分支确认
- exact-head CI reconciliation
- 需求分类
- 快速通道
- PRD 更新
- Hook / 数据库 /兼容分析
- 代码开发
- 自动测试
- 测试失败自动修复
- 风险驱动安全 / 性能 / 兼容检查
- Git / CI
- 版本号与 CHANGELOG
- Notion 回写
- 发布准备
- 中断恢复
- 故障恢复
- 发布 Dry Run
- 禁止模拟执行

任一核心模块缺失，静态完整性验收失败。

## 5. 自动触发验收

测试输入示例：

```text
给 xz_visit_stats 增加来源 URL 完整记录
```

预期行为：

```text
识别项目
→ 生成运行编号
→ bootstrap Canonical Runtime
→ 自动读取 Notion
→ 自动读取 GitHub / 真实代码
→ 确认当前版本 / branch / head SHA
→ 判断任务规模和风险
→ 自动推进后续流程
```

失败条件：

- 要求用户重复已经存在的项目信息
- 在正常流程中询问“是否继续”“要不要下一步”
- 未读取真实项目状态就直接给开发方案
- 创建了 Run 但没有持久化可恢复 state/events/evidence

## 6. 快速通道验收

选择一个低风险、小范围修改，例如后台文案、CSS 或单点 PHP Bug。

预期流程：

```text
读取真实代码
→ 确认影响范围
→ 修改
→ 相关高价值测试
→ Commit / CI
→ 必要时回写 Notion
```

快速通道不得强制跑完整 PHPStan、Semgrep、完整 PHPUnit，除非风险判断认为需要。

数据库迁移、安全相关写操作、重大架构变化、正式发布不得使用快速通道规避必要检查。

## 7. 标准功能开发验收

选择一个会真实影响功能但风险可控的需求。

必须验证：

- 原运行编号或新运行编号明确
- Runtime Bundle 可冷恢复
- Notion 项目状态恢复成功
- GitHub 真实源码读取成功
- PRD 更新成功
- 影响文件明确
- Hook / 数据库变化明确
- 代码真实修改
- 自动测试真实运行
- 失败时自动修复
- Git Commit 可验证
- CI 可验证且与当前 head SHA 精确一致
- Notion 回写可验证
- state revision / events / evidence 与真实 checkpoint 一致

流程不得依赖用户逐步发送“下一步”。

## 8. 中断恢复测试

### 测试方法

在开发进行到任意中间阶段时结束当前聊天、换新聊天、重启 Codex 或重启开发环境。

用户只输入：

```text
继续开发 xz_visit_stats
```

### 预期恢复顺序

```text
读取原运行编号 Runtime Bundle
→ 校验 state_revision / event seq / evidence refs
→ 读取 GitHub 当前分支 / Commit / PR / CI
→ reconcile 当前 head SHA 与 CI evidence
→ 读取 Notion 当前状态 / PRD
→ 对比未完成 Gate / next action
→ 从上次真实断点继续
```

### 通过标准

- 不要求用户重新描述完整需求
- 不重复创建同一个 PRD
- 不重复已经完成的开发动作
- 不丢失原运行编号
- 可以准确指出“已完成 / 未完成 / 当前阻塞”
- stale CI 不会被误复用
- Runtime 与真实 Git 冲突时不会猜测继续

如果无法恢复本机 Codex 工作树，必须明确标为“外部待执行”或 BLOCKED，但仍应恢复 Runtime、Notion 与 GitHub 可见状态。

## 9. 故障恢复测试

### 测试方法

只允许在测试分支或测试环境制造安全、可逆的故障，例如：

- PHP 语法错误
- 单元测试断言失败
- CI 配置中的可恢复测试失败
- Runtime 中记录一个旧 head SHA，验证 reconciliation

禁止在生产数据库或生产文件中故意制造故障。

### 预期行为

```text
检测失败
→ 自动读取错误日志 / CI 日志 / Runtime conflict
→ 定位原因
→ 修改代码或 reconcile state
→ 重跑相关测试
→ Commit
→ 再次验证当前 head CI
→ 更新 evidence / event / state revision / Notion
```

### 失败条件

- 发现普通可修复错误后询问“是否修复”
- 没有读取日志就猜测原因
- 修复后不复测
- 把尚未修复的状态标记为通过
- 新 Commit 后继续复用旧 SHA 的 CI PASS
- Runtime evidence 不可解析却继续推进

## 10. 发布 Dry Run

发布 Dry Run 不创建正式 Release、不覆盖线上文件、不修改生产数据库。

必须检查：

- `plugin.xml` 插件 ID 与版本号
- CHANGELOG
- 安装逻辑
- 升级逻辑
- 数据库迁移
- 卸载策略
- 发布包目录结构
- 文件白名单 / 黑名单
- `.git` 排除
- 日志、缓存、临时文件排除
- 密钥 / Token / 密码 /数据库配置排除
- 测试文件是否需要排除
- PHP 语法检查
- 发布级核心功能测试
- Tag 名称准备
- Release Notes 准备
- Notion 发布记录预检查

Dry Run 输出必须给出：

```text
可发布
或
不可发布：阻塞项列表
```

只有 Dry Run 通过，才允许进入正式 Tag / Release / 部署阶段。

## 11. 真实执行证据

每轮验收输出至少包含：

```text
运行编号：DEV-YYYYMMDD-NNN
项目：
当前版本：
目标版本：
分支：
最新 Commit：
Runtime revision：
CI：
Notion：
测试：
发布状态：
当前阶段：
阻塞项：
```

没有证据的步骤不得写成“已完成”。

## 12. 评分标准

每项 0 到 2 分：

- 自动触发
- 上下文恢复
- Runtime 持久化与证据一致性
- 真实代码读取
- 任务分类
- PRD / 影响分析
- 自动开发
- 自动测试
- 故障恢复
- Git / CI
- Notion 同步
- 中断恢复
- 发布 Dry Run
- 状态真实性
- 开发效率
- 高风险保护

总分 32 分。

评级：

- 29-32：稳定，可作为默认流程
- 25-28：可用，但需修补
- 20-24：流程存在明显断点
- 0-19：不应作为默认自动开发流程

其中“状态真实性”“高风险保护”“中断恢复”“Runtime 持久化与证据一致性”任一为 0 分，即使总分达标也不得评为稳定。

## 13. v2.0 最终验收矩阵

正式确认 v2.0 完善前至少完成四轮真实演练：

1. 快速通道测试
2. 标准功能开发测试
3. 中断恢复 + 故障恢复测试
4. 发布 Dry Run

四轮全部通过后，将 v2.0 标记为“稳定”。

若任一轮失败，记录失败阶段、原因、修正措施，并更新主流程后重新验收对应测试。
