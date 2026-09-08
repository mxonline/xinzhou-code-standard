# Global Runtime Contract v1 — Implementation Plan

Date: 2026-09-09

## Task 1 — Shared validator RED

- Add `tests/test_runtime_contract.py` with canonical-v1 and arthur-v2 fixtures.
- Lock failures for missing validator, identity mismatch, missing evidence refs, bad event sequence/revision, broken Arthur hash links, and manifest scanning.
- Add Linux CI workflow for the shared contract.
- Confirm tests fail for the missing implementation.

## Task 2 — Shared validator GREEN

- Implement `tools/runtime_contract.py` using Python stdlib only.
- Add `runtime-contract/README.md` and manifest schema/example.
- Add a machine-readable Video Factory canonical mirror at `runtime-contract/instances/video-factory-v1-production-first/` reflecting Notion Runtime revision 2 / Events seq 1-4 / Cold Start Run 07 evidence.
- Validate the mirror in shared CI without claiming executor auto-write.
- Open PR, review diff, require CI green, merge and capture immutable merge SHA.

## Task 3 — XinZhao Content integration

- Create isolated feature branch from current main.
- Add RED contract test requiring `runtime-contract.json` and shared-validator CI integration.
- Add manifest with `profile=canonical-v1`, `runtime_root=production/runtime`, `allow_empty_runtime_root=true`.
- Pin shared validator checkout to Task 2 merge SHA in `.github/workflows/content-quality.yml`.
- Run PR CI, review, merge, verify main CI on merge SHA.

## Task 4 — yfxxol integration

- Branch from current active `phase/p03-compatibility-contracts` so business phase does not advance.
- Add RED integration test for manifest/workflow.
- Add manifest pointing to `state/runtime/yfxxol-v1-rebuild-20260826` with `profile=canonical-v1`.
- Pin shared validator to Task 2 merge SHA in Project Guard.
- Require PR CI green, merge to the active phase branch, verify post-merge state remains P03_SCOPE_DELTA / P04 GATED.

## Task 5 — Arthur integration

- Branch from current main.
- Add RED integration test for manifest/workflow.
- Add manifest pointing to `production/resume-state.json`, `production/firmware-events.jsonl`, and the execution-scoped evidence index using `profile=arthur-v2`.
- Pin shared validator to Task 2 merge SHA in an existing state-contract workflow or a narrowly scoped new job.
- Do not add native state_revision and do not alter release/device gate semantics.
- Require CI green, merge, verify current gate remains PRE_FLASH / RESUME_SAFE unless independent real evidence changes it.

## Task 6 — Global control-plane closeout

- Update Notion Global Runtime Contract with shared-standard PR/merge SHA and each repo integration evidence.
- Update HANDOFF rows with `Machine Enforcement` evidence/result.
- Record Video Factory boundary: canonical mirror and shared CI enforced; production executor automatic writeback remains NOT VERIFIED until source/runtime evidence is accessible.
- Re-fetch Notion pages and repository main/active branches.

## Legal terminal

The rollout may close as:

`GLOBAL_RUNTIME_CONTRACT_MERGED / CONTENT_CI_ENFORCED / YFXXOL_CI_ENFORCED / ARTHUR_CI_ENFORCED / VIDEO_RUNTIME_MIRROR_CI_ENFORCED`

with the explicit factual boundary:

`VIDEO_EXECUTOR_AUTOWRITE = NOT VERIFIED`

Do not relabel that boundary as PASS without new external evidence.
