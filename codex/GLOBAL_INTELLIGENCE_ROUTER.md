<!-- XINZHAO:GLOBAL_INTELLIGENCE_ROUTER:BEGIN -->
## Global External Intelligence Writeback

When a task reads and analyzes an X/Twitter or other external link and produces reusable analysis, `ANALYSIS_DONE` is intermediate, not complete.

Before reporting success:

1. Use the available Notion MCP/plugin to read `External Intelligence Writeback & Routing Contract v1.0`:
   https://app.notion.com/p/3db887d364328194b629e5dbe20c62b6?pvs=204
2. Execute that contract exactly: idempotent External Intelligence upsert, Project Key routing, Global/Project HANDOFF update, and readback verification.
3. Report success only after the contract reaches `INTELLIGENCE_WRITEBACK_COMPLETE`.
4. If Notion read/write capability, authentication, upsert, HANDOFF update, or readback verification is unavailable/fails, return `BLOCKED` with the failed stage. Never fabricate a Notion record URL, writeback state, or HANDOFF state.
5. Prompt/提示词/Agent/ChatGPT/Claude/Codex/LLM/AI-workflow topics use the contract's default `prompt-analysis` route unless the Project Router adds other targets.

Do not duplicate the full Notion schema here. Notion remains the Source of Truth for routing and writeback semantics.
<!-- XINZHAO:GLOBAL_INTELLIGENCE_ROUTER:END -->
