# Codex execution handoff for Issue #10

Source task: https://github.com/mxonline/xinzhou-code-standard/issues/10

Executor: Codex

Implement Issue #10 on this branch.

Requirements:
- Add a canonical machine-readable ChatGPT↔Codex execution-boundary contract in this authority repo.
- Reuse the existing global router / installer / tests / CI. Do not create a parallel workflow.
- ChatGPT role: classify/route; read Source of Truth/HANDOFF; decompose and dispatch; read Codex result; verify evidence; decide next action.
- Codex role: actual code/file changes; shell/PowerShell/Python; Agent-Reach/OpenCLI/local tools; tests; fixes; commits/PR updates; durable evidence.
- Once delegated, ChatGPT must not silently duplicate the same execution.
- COMPLETE/VERIFIED requires durable Codex evidence readback. Missing/invalid evidence => BLOCKED.
- Add regression tests that fail if the role boundary, evidence gate, BLOCKED behavior, or no-duplicate-execution rule is weakened.
- Run the existing Global Runtime Contract test suite.
- Report changed paths, commit SHA, CI run URL/ID, and readback evidence.
- Remove this temporary handoff file before the PR is considered ready to merge.

Do not merely describe the change. Implement it, test it, and push the changes to this PR branch.
