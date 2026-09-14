# Codex Global Intelligence Writeback Design

## Authority

The canonical business contract remains the Notion page `External Intelligence Writeback & Routing Contract v1.0`:

- Contract: https://app.notion.com/p/3db887d364328194b629e5dbe20c62b6?pvs=204
- Global Intelligence HANDOFF: https://app.notion.com/p/3db887d36432816d81fdc3e826190f97?pvs=204
- External Intelligence database: https://app.notion.com/p/ba791ed84a7c42888c238baa657c0e1a?pvs=204
- Project Router Registry: https://app.notion.com/p/1b211a58eb1849d0b1883a4ec80bac75?pvs=204
- Prompt Analysis HANDOFF: https://app.notion.com/p/3da887d3643281ad9784f8b7ee6b96b6?pvs=204

This repository stores the Codex bootstrap and installer only. It does not duplicate the full Notion routing contract.

## Problem

Codex can finish an X/external-link analysis without persisting the result to Notion. ChatGPT then cannot recover the analysis through Project Router Registry, Global Intelligence HANDOFF, or the target project's HANDOFF.

`ANALYSIS_DONE` must therefore stop being a legal terminal state for reusable external-intelligence work.

## Architecture

Use two layers:

1. **Canonical bootstrap in Git**: `codex/GLOBAL_INTELLIGENCE_ROUTER.md` contains a short, stable Codex instruction that points to the Notion contract and defines fail-closed completion behavior.
2. **Global Codex installation**: `tools/install_codex_global_router.py` installs or updates that bootstrap inside `$CODEX_HOME/AGENTS.md` between deterministic markers. Existing user instructions outside the managed block are preserved.

Codex currently aggregates `$CODEX_HOME/AGENTS.md` before project-local AGENTS files, so this gives the writeback rule global scope while still allowing more-specific project instructions to coexist.

## Managed Block

The installer owns only the text between:

```text
<!-- XINZHAO:GLOBAL_INTELLIGENCE_ROUTER:BEGIN -->
...
<!-- XINZHAO:GLOBAL_INTELLIGENCE_ROUTER:END -->
```

Rules:

- If neither marker exists, append the managed block.
- If both markers exist in the correct order, replace only the managed block.
- If only one marker exists, fail closed and do not modify the file.
- Running the installer twice with unchanged source must produce byte-identical `AGENTS.md` content.
- Preserve existing newline style where practical; UTF-8 is canonical for newly created files.

## Codex Runtime Contract

For an X/Twitter or other external-link task that produces reusable analysis, the global bootstrap tells Codex to:

1. Read the Notion `External Intelligence Writeback & Routing Contract v1.0` through an available Notion MCP/plugin before declaring success.
2. Follow the Notion contract rather than duplicating its schema in AGENTS.md.
3. Treat `ANALYSIS_DONE` as intermediate only.
4. Require the Notion flow to reach `INTELLIGENCE_WRITEBACK_COMPLETE` before reporting success.
5. If Notion read/write capability is unavailable, authentication fails, or write/readback verification fails, return `BLOCKED` with the failing stage. Never fabricate a record URL or completion state.
6. For Prompt/提示词/Agent/ChatGPT/Claude/Codex/LLM/AI-workflow topics, rely on the Notion contract's default `prompt-analysis` routing.

## MCP Boundary

The installer does not store OAuth tokens and does not silently rewrite `~/.codex/config.toml`.

It provides `--check` diagnostics that verify:

- the global AGENTS managed block is installed;
- `~/.codex/config.toml` exists when present;
- configuration text contains at least one MCP/plugin-related section only as a diagnostic signal.

Actual MCP authentication remains owned by Codex. The first end-to-end acceptance run must prove that Codex can read and write the Notion workspace. If Notion tooling is missing, the correct outcome is `BLOCKED`, not fallback to chat-only output.

## Files

- `codex/GLOBAL_INTELLIGENCE_ROUTER.md`: canonical managed block source.
- `tools/install_codex_global_router.py`: install/update/check CLI.
- `tests/test_install_codex_global_router.py`: unit tests for preservation, idempotency, corruption detection, CODEX_HOME resolution, and diagnostics.
- `README.md`: operator instructions and acceptance test.

## Acceptance Criteria

Repository-level acceptance:

1. All existing tests pass.
2. New installer tests pass.
3. Installing into an empty temp CODEX_HOME creates `AGENTS.md` with the canonical block.
4. Installing into a pre-existing AGENTS preserves unrelated content.
5. A second install is idempotent.
6. A one-marker-corrupted AGENTS fails without modification.
7. `--check` reports installed/not-installed deterministically.

Real end-to-end acceptance, performed from the user's real Codex environment:

1. Run installer against the actual `$CODEX_HOME`.
2. Start a fresh Codex task with a real prompt-related X link.
3. Codex analyzes the source.
4. External Intelligence contains exactly one record for the X status ID/source URL.
5. `回传来源=Codex` and `写回状态=COMPLETE`.
6. Global Intelligence HANDOFF points to that record.
7. Prompt Analysis HANDOFF can recover the same record when the topic routes to `prompt-analysis`.
8. A ChatGPT Project can read the record through Project Router without the X link being pasted again.

Until all eight real acceptance checks pass, the system remains `IN_PROGRESS`; it must not be reported as fully complete.
