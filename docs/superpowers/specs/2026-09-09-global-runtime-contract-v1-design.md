# Global Runtime Contract v1 — Design

Date: 2026-09-09
Status: APPROVED FOR IMPLEMENTATION

## Goal

Provide one portable, machine-enforced Runtime Contract for long-running XinZhao workflows without replacing each project's business workflow, release gates, migration gates, device gates, or domain-specific state engine.

The contract standardizes four persisted facts:

1. Runtime State — accepted execution snapshot.
2. Runtime Events — append-only execution history.
3. Evidence Index — proof identities/references for accepted claims.
4. HANDOFF / Projection — human/control-plane projection, never a competing machine authority.

## Non-goals

- Do not force mature projects to rename every domain field.
- Do not create a fourth external state service.
- Do not make State strings factual authority over Git, CI, device, local runtime, file, Notion, video/QA, or other real observations.
- Do not advance any business gate merely because the Runtime Contract validates.

## Shared validator

`tools/runtime_contract.py` in `mxonline/xinzhou-code-standard` is the single validator implementation. Projects consume it pinned to an immutable shared-standard merge SHA.

Projects define a small `runtime-contract.json` manifest rather than copying validator code.

Manifest v1:

```json
{
  "contract_version": "global-runtime-v1",
  "project": "project-name",
  "profile": "canonical-v1",
  "bundles": [
    {
      "execution_id": "stable-execution-id",
      "state": "path/to/state.json",
      "events": "path/to/events.jsonl",
      "evidence": "path/to/evidence/index.json"
    }
  ],
  "runtime_root": null,
  "allow_empty_runtime_root": false,
  "projection_paths": []
}
```

`runtime_root` supports dynamic per-execution stores such as article production. If used, each child directory that contains `state.json` is a bundle with sibling `events.jsonl` and `evidence/index.json`. An empty root may be explicitly allowed only when the project has no persisted live execution in Git at that moment; future committed bundles are still validated automatically.

## Profiles

### canonical-v1

Used by new canonical Runtime implementations such as XinZhao Content v2.1, yfxxol rebuild, and the Video Factory canonical mirror.

Required common state fields:

- `execution_id`
- `status`
- `current_stage`
- `last_verified_stage`
- `pending_gates`
- `blocked`
- `next_action`
- `state_revision` (integer >= 1)

Common invariants:

- State, Evidence and execution-aware Events share execution identity.
- Events are ordered by a strictly increasing positive integer `seq`.
- Event `state_revision`, when present, is positive and cannot exceed current State revision.
- Evidence IDs are unique.
- Every explicit `evidence:<id>` reference found in State must resolve in the same Evidence Index.
- Gate objects with accepted terminal statuses (`PASS`, `VERIFIED`, `GATED`, `BLOCKED`, `FAILED`) must include resolvable evidence when they expose an evidence field.
- Runtime validation cannot mint a business PASS.

Evidence collections may use either `items[].id` or `evidence[].evidence_id`; the validator normalizes both existing shapes.

### arthur-v2

Legacy-compatible adapter for XinZhaoWrt's already deployed state engine.

Required State fields:

- `schema_version == 2`
- `execution_id`
- `status`
- `current_gate`
- `next_action`
- `gates`

Compatibility rules:

- Native `state_revision` is not required and must not be invented.
- Firmware ledger events need not contain `execution_id`; identity is scoped by the explicit manifest bundle and execution-scoped evidence directory.
- Ledger `seq` must be strictly increasing.
- `prev_hash` must link to the previous `event_hash`; first event must use `GENESIS`.
- `event_hash`/`prev_hash` must be non-empty; the existing Arthur control-plane remains responsible for cryptographic recomputation.
- Gate `PASS` evidence refs must resolve to the execution-scoped Evidence Index.

This adapter validates global conformance without rewriting Arthur's proven release/device flow.

## Failure semantics

Validator exits non-zero and prints machine-readable JSON when any invariant fails. Recommended actions:

- missing bundle -> `BOOTSTRAP_RUNTIME_STATE`
- malformed/identity/evidence/event conflict -> `VERIFY_RUNTIME_STATE`
- projection drift is reported by project-specific resume logic, not silently treated as authority

## CI integration

Each code repository adds a manifest and a CI step that:

1. checks out the project;
2. checks out `mxonline/xinzhou-code-standard` at one immutable merge SHA into a temporary directory;
3. runs `python <standard>/tools/runtime_contract.py validate --root . --manifest runtime-contract.json`.

The shared standard itself validates its tests and the Video Factory canonical mirror.

## Video Factory boundary

No production Video Factory source repository is currently accessible through the connected GitHub account. Therefore v1 can machine-validate a canonical mirror of its Notion Runtime State/Events/Evidence in the shared standard repository and prove cold-recovery consistency. It must not claim that the real production executor automatically writes Runtime updates after every Stage/Shot until that executor repository or equivalent runtime evidence becomes accessible.
