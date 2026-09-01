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
