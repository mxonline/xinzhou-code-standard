# Development Reuse Gate

Status: ACTIVE SPEC
Updated: 2026-09-02

This gate runs before PRD/architecture and before Codex implementation for supported development work. Its purpose is to avoid unnecessary greenfield development while preserving security, compatibility and maintainability.

## Standard order

`Requirement -> GitHub / official ecosystem research -> Reuse Gate -> PRD / architecture -> implementation -> real validation -> CI -> release -> project state update`

Do not skip directly from requirement to code when a mature official or open-source option may already solve the problem.

## Required research targets

Search in this order where relevant:

1. Official project / vendor solution
2. Mature open-source project with compatible stack
3. Reusable library, component, module or workflow
4. Maintained fork matching the target environment
5. Reference-only architecture or algorithm

Stars are only a secondary signal. Prefer recent maintenance, healthy releases/commits, functioning CI/tests, suitable licensing and environment compatibility.

## Evaluation dimensions

Every serious candidate must be checked for:

- License compatibility
- Recent maintenance activity
- Commit / release recency
- Issue / pull-request maintenance quality
- CI and automated test state
- Known security risks
- Dependency health
- Technical-stack compatibility
- Runtime / deployment-environment compatibility
- Integration effort
- Secondary-development effort
- Long-term maintenance cost
- Lock-in / migration risk

## Decision values

A Reuse Gate ends with exactly one primary decision:

### USE
Use the mature solution directly with minimal integration.

Choose USE when it satisfies the requirement, its license/security/maintenance profile is acceptable, and custom work would add no meaningful product value.

### REUSE
Reuse selected components, libraries, workflows, data models, algorithms or UI patterns while keeping the current project architecture.

Choose REUSE when parts are strong but the full project is not an appropriate direct dependency.

### FORK
Fork and maintain a compatible upstream project when the product needs meaningful changes but the upstream foundation is still the best technical baseline.

Choose FORK only after explicitly accepting future upstream-sync and maintenance cost.

### BUILD
Build the capability in the existing project because no candidate passes the gate or integration/fork cost is worse than a focused implementation.

BUILD is not the default. Record why USE, REUSE and FORK were rejected.

## Required output

Before implementation, record at minimum:

- Requirement / problem statement
- Search scope
- Candidate projects / official options
- Relevant URLs and versions/commits
- License conclusion
- Maintenance conclusion
- Security/dependency conclusion
- Compatibility conclusion
- Integration and maintenance cost
- Final decision: USE / REUSE / FORK / BUILD
- Reusable parts selected
- Rejected candidates and short reasons
- Risks that must be handled in PRD/implementation

## Project-specific guidance

### Z-Blog / PHP

Prefer mature Z-Blog plugins, official APIs, established PHP libraries and compatible data/query/UI patterns. Do not blindly copy heavy architectures into a small plugin. Reuse data models/query strategies/UI ideas only when they fit the project.

### OpenWrt / firmware

Prefer a same-device, same-target/profile and recent known-good baseline. Prefer recently successful CI and verified artifacts over popularity. Reuse upstream ImageBuilder/SDK/official build mechanisms before inventing a custom build system.

### Website rebuilds

Prefer stable frameworks/components/design-system patterns that match the existing stack and deployment environment. Do not rewrite a working subsystem merely because a newer framework exists.

### Agent / automation / video systems

Prefer official provider SDKs/skills and mature orchestration components where possible. Keep provider layers replaceable and avoid binding the core system to a single model/provider when the product requirement does not require it.

## Gate relationship to later stages

Reuse Gate does not replace:

- PRD or architecture design
- Security review
- Tests / CI
- Real-device or real-environment validation
- Release Gate
- HANDOFF / state recovery

It only determines the best implementation starting point.

## Failure rule

If evidence is incomplete, mark the gate as `VERIFYING` or `BLOCKED`; do not manufacture a USE/REUSE/FORK/BUILD conclusion. If a previously selected dependency becomes unmaintained, insecure or incompatible, rerun the gate before major follow-up work.

## 意图对齐与 TDD 执行方法（2026-10-12）

本节属于既有开发流程的执行方法，不增加 Phase、Gate、Runtime、发布权限或新的成功终点。项目专属规范优先，Reuse Gate 仍按原顺序实施。情报来源：[X 分析](https://app.notion.com/p/3f6887d3643281609529f5ae7b7b55ff)，方法复用不代表提效已经得到实测证明。

- **需求契约**：恢复当前 Source of Truth、Runtime、真实 Git/CI 及证据。沿用原任务/Issue/PR 记录 `goal`、`in_scope`、`out_of_scope`、`protected_invariants`、`acceptance_examples`、`expected_diff`、`existing_terminal`，优先复用项目中已回答的需求决策。
- **测试先行**：可执行的代码行为变更，先有能因目标行为而失败的测试（RED），最小修改通过（GREEN），复核重构及相关回归测试。文档/契约阶段只形成可审查的验收案例和证据要求，不能冒充已执行 RED/GREEN。
- **最小变更**：逐项对照预期 diff 和受保护功能。继续继承没有被关联变更失效的已验证证据，不为让测试变绿而扩大需求或降低验收。
- **受控修复**：只围绕真实失败日志、根因和最小修复迭代。同一失败没有进展时停止重复尝试，依据本项目的恢复机制输出证据和唯一 next_action。
- **终态回读**：单元测试通过或 CI 绿色只代表对应检查通过。最终成功必须验证项目原定义的交付/发布/实机终态，回读 Git、Runtime、产物和业务输出证据，不预填 PASS/COMPLETE。

项目边界：yfxxol 网站重构保持 P02/P03/P03.5 scope delta 与 P04 门禁，会员关系、旧 URL、附件、迁移与回滚作为验收案例；Arthur 保持固件 Release 与独立真实设备验证的边界，不新增自动刷机授权；新肇数码 v2.1 保持 Stage01–21 及 READY_TO_PUBLISH 的既有交付定义。通用执行方法不得覆盖这些项目约束。

