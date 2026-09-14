# Codex Global Intelligence Writeback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install a fail-closed, idempotent global Codex bootstrap that forces reusable X/external-link analyses through the Notion intelligence writeback contract before Codex may report success.

**Architecture:** Keep the full routing/writeback policy authoritative in Notion. Store only a short canonical bootstrap in Git, and install/update that bootstrap inside `$CODEX_HOME/AGENTS.md` with a Python tool that preserves unrelated user instructions. Verify the repository implementation with `unittest`, then run one real Codex→Notion→HANDOFF→ChatGPT acceptance test.

**Tech Stack:** Python 3 standard library, `unittest`, Codex `$CODEX_HOME/AGENTS.md`, Codex `~/.codex/config.toml`, Notion MCP/plugin.

**Spec:** `docs/superpowers/specs/2026-09-15-codex-global-intelligence-writeback-design.md`

## Global Constraints

- Notion `External Intelligence Writeback & Routing Contract v1.0` remains the canonical business contract.
- Existing `$CODEX_HOME/AGENTS.md` content outside the managed markers must be preserved.
- The installer must be idempotent.
- Partial/corrupt marker state must fail closed without modifying the file.
- The installer must not store OAuth tokens or silently rewrite `config.toml`.
- `ANALYSIS_DONE` is not a legal success terminal state for reusable external-intelligence tasks.
- The only legal success terminal state is `INTELLIGENCE_WRITEBACK_COMPLETE`.
- If Notion read/write or readback verification is unavailable, Codex must return `BLOCKED` rather than chat-only success.

---

### Task 1: Add the canonical global intelligence bootstrap

**Files:**
- Create: `codex/GLOBAL_INTELLIGENCE_ROUTER.md`
- Test: `tests/test_install_codex_global_router.py`

**Interfaces:**
- Consumes: Notion contract URL from the design spec.
- Produces: UTF-8 source text consumed verbatim by the installer as `canonical_block_source()`.

- [ ] **Step 1: Write the failing source-contract test**

Create `tests/test_install_codex_global_router.py` with a helper that imports `tools/install_codex_global_router.py` and a test that requires the canonical source file and mandatory fail-closed phrases:

```python
from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "install_codex_global_router.py"
SOURCE_PATH = ROOT / "codex" / "GLOBAL_INTELLIGENCE_ROUTER.md"


def load_module():
    if not MODULE_PATH.is_file():
        raise AssertionError("tools/install_codex_global_router.py is required")
    spec = importlib.util.spec_from_file_location("install_codex_global_router", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError("cannot load install_codex_global_router.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GlobalIntelligenceRouterTests(unittest.TestCase):
    def test_canonical_source_declares_writeback_gate(self):
        self.assertTrue(SOURCE_PATH.is_file())
        text = SOURCE_PATH.read_text(encoding="utf-8")
        self.assertIn("External Intelligence Writeback & Routing Contract v1.0", text)
        self.assertIn("INTELLIGENCE_WRITEBACK_COMPLETE", text)
        self.assertIn("BLOCKED", text)
        self.assertIn("ANALYSIS_DONE", text)
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
python -m unittest tests.test_install_codex_global_router.GlobalIntelligenceRouterTests.test_canonical_source_declares_writeback_gate -v
```

Expected: FAIL because the installer/source file does not yet exist.

- [ ] **Step 3: Create the canonical bootstrap source**

Create `codex/GLOBAL_INTELLIGENCE_ROUTER.md` with exactly one managed block:

```markdown
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
```

- [ ] **Step 4: Add the minimal source reader and rerun the test**

Create the initial `tools/install_codex_global_router.py` skeleton:

```python
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = ROOT / "codex" / "GLOBAL_INTELLIGENCE_ROUTER.md"
BEGIN_MARKER = "<!-- XINZHAO:GLOBAL_INTELLIGENCE_ROUTER:BEGIN -->"
END_MARKER = "<!-- XINZHAO:GLOBAL_INTELLIGENCE_ROUTER:END -->"


def canonical_block_source() -> str:
    return SOURCE_PATH.read_text(encoding="utf-8").strip() + "\n"
```

Run the same unittest. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codex/GLOBAL_INTELLIGENCE_ROUTER.md tools/install_codex_global_router.py tests/test_install_codex_global_router.py
git commit -m "feat: add Codex global intelligence bootstrap"
```

---

### Task 2: Implement idempotent AGENTS.md installation

**Files:**
- Modify: `tools/install_codex_global_router.py`
- Modify: `tests/test_install_codex_global_router.py`

**Interfaces:**
- Produces: `resolve_codex_home(explicit: str | None = None) -> Path`
- Produces: `render_installed_agents(existing: str, block: str) -> tuple[str, str]`, where status is `created`, `appended`, `updated`, or `unchanged`.
- Produces: `install(codex_home: Path, dry_run: bool = False) -> dict[str, str | bool]`.

- [ ] **Step 1: Write failing preservation/idempotency/corruption tests**

Add tests:

```python
    def test_append_preserves_existing_content(self):
        runtime = load_module()
        existing = "# My Rules\nKeep this line.\n"
        block = runtime.canonical_block_source()
        rendered, status = runtime.render_installed_agents(existing, block)
        self.assertEqual(status, "appended")
        self.assertTrue(rendered.startswith(existing))
        self.assertIn(runtime.BEGIN_MARKER, rendered)
        self.assertIn(runtime.END_MARKER, rendered)

    def test_second_render_is_idempotent(self):
        runtime = load_module()
        block = runtime.canonical_block_source()
        first, _ = runtime.render_installed_agents("# Existing\n", block)
        second, status = runtime.render_installed_agents(first, block)
        self.assertEqual(status, "unchanged")
        self.assertEqual(second, first)

    def test_existing_managed_block_is_replaced_only(self):
        runtime = load_module()
        existing = (
            "before\n"
            + runtime.BEGIN_MARKER
            + "\nold\n"
            + runtime.END_MARKER
            + "\nafter\n"
        )
        rendered, status = runtime.render_installed_agents(existing, runtime.canonical_block_source())
        self.assertEqual(status, "updated")
        self.assertTrue(rendered.startswith("before\n"))
        self.assertTrue(rendered.endswith("after\n"))
        self.assertNotIn("\nold\n", rendered)

    def test_partial_marker_state_fails_closed(self):
        runtime = load_module()
        with self.assertRaisesRegex(ValueError, "partial managed marker"):
            runtime.render_installed_agents(runtime.BEGIN_MARKER + "\ncorrupt\n", runtime.canonical_block_source())
```

- [ ] **Step 2: Run tests and verify failure**

```bash
python -m unittest tests.test_install_codex_global_router -v
```

Expected: FAIL because the rendering functions do not exist.

- [ ] **Step 3: Implement resolution and managed-block rendering**

Add:

```python
import os


def resolve_codex_home(explicit: str | None = None) -> Path:
    if explicit:
        return Path(explicit).expanduser().resolve()
    env_home = os.environ.get("CODEX_HOME")
    if env_home:
        return Path(env_home).expanduser().resolve()
    return (Path.home() / ".codex").resolve()


def render_installed_agents(existing: str, block: str) -> tuple[str, str]:
    begin_count = existing.count(BEGIN_MARKER)
    end_count = existing.count(END_MARKER)
    if begin_count != end_count or begin_count > 1:
        raise ValueError("partial managed marker state; refusing to modify AGENTS.md")

    canonical = block.strip() + "\n"
    if begin_count == 0:
        if not existing:
            return canonical, "created"
        separator = "" if existing.endswith("\n\n") else ("\n" if existing.endswith("\n") else "\n\n")
        return existing + separator + canonical, "appended"

    start = existing.index(BEGIN_MARKER)
    end = existing.index(END_MARKER, start) + len(END_MARKER)
    old = existing[start:end].strip() + "\n"
    if old == canonical:
        return existing, "unchanged"
    return existing[:start] + canonical.rstrip("\n") + existing[end:], "updated"
```

- [ ] **Step 4: Implement file installation without destructive fallback**

Add:

```python

def install(codex_home: Path, dry_run: bool = False) -> dict[str, str | bool]:
    codex_home.mkdir(parents=True, exist_ok=True)
    agents_path = codex_home / "AGENTS.md"
    existing = agents_path.read_text(encoding="utf-8") if agents_path.exists() else ""
    rendered, status = render_installed_agents(existing, canonical_block_source())
    changed = rendered != existing
    if changed and not dry_run:
        agents_path.write_text(rendered, encoding="utf-8")
    return {
        "path": str(agents_path),
        "status": status,
        "changed": changed,
        "dry_run": dry_run,
    }
```

- [ ] **Step 5: Run tests**

```bash
python -m unittest tests.test_install_codex_global_router -v
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add tools/install_codex_global_router.py tests/test_install_codex_global_router.py
git commit -m "feat: install global Codex router idempotently"
```

---

### Task 3: Add check mode and MCP diagnostics

**Files:**
- Modify: `tools/install_codex_global_router.py`
- Modify: `tests/test_install_codex_global_router.py`

**Interfaces:**
- Produces: `check_installation(codex_home: Path) -> dict[str, object]`.
- CLI exit code: `0` when installed and canonical; `1` when not installed/corrupt. MCP config diagnostic is reported separately and does not cause the installer to invent configuration.

- [ ] **Step 1: Write failing diagnostic tests**

Add:

```python
    def test_check_reports_installed_and_config_signal(self):
        runtime = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            runtime.install(home)
            (home / "config.toml").write_text('[mcp_servers.notion]\nurl = "https://example.invalid/mcp"\n', encoding="utf-8")
            result = runtime.check_installation(home)
            self.assertTrue(result["installed"])
            self.assertTrue(result["canonical"])
            self.assertTrue(result["config_exists"])
            self.assertTrue(result["mcp_config_signal"])

    def test_check_does_not_claim_mcp_when_config_missing(self):
        runtime = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            result = runtime.check_installation(Path(tmp))
            self.assertFalse(result["installed"])
            self.assertFalse(result["config_exists"])
            self.assertFalse(result["mcp_config_signal"])
```

- [ ] **Step 2: Run tests and verify failure**

```bash
python -m unittest tests.test_install_codex_global_router -v
```

Expected: FAIL because `check_installation` does not exist.

- [ ] **Step 3: Implement deterministic check**

Add:

```python

def check_installation(codex_home: Path) -> dict[str, object]:
    agents_path = codex_home / "AGENTS.md"
    config_path = codex_home / "config.toml"
    existing = agents_path.read_text(encoding="utf-8") if agents_path.exists() else ""
    canonical = canonical_block_source().strip()
    installed = BEGIN_MARKER in existing and END_MARKER in existing
    canonical_installed = installed and canonical in existing
    config_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
    mcp_signal = "[mcp_servers." in config_text or "[plugins." in config_text
    return {
        "agents_path": str(agents_path),
        "installed": installed,
        "canonical": canonical_installed,
        "config_path": str(config_path),
        "config_exists": config_path.exists(),
        "mcp_config_signal": mcp_signal,
    }
```

- [ ] **Step 4: Add CLI**

Use `argparse` with:

```text
--codex-home PATH
--check
--dry-run
```

Default action is install. Print one JSON object to stdout with `json.dumps(result, ensure_ascii=False, indent=2)`. Exit `1` only for `--check` when `canonical` is false or for a caught fail-closed installation error.

- [ ] **Step 5: Run tests and a temp-directory smoke test**

```bash
python -m unittest tests.test_install_codex_global_router -v
python tools/install_codex_global_router.py --codex-home .tmp-codex-router --dry-run
python tools/install_codex_global_router.py --codex-home .tmp-codex-router
python tools/install_codex_global_router.py --codex-home .tmp-codex-router --check
```

Expected: unittest PASS; install creates the managed block; check reports `installed=true`, `canonical=true`.

- [ ] **Step 6: Commit**

```bash
git add tools/install_codex_global_router.py tests/test_install_codex_global_router.py
git commit -m "feat: verify Codex router and MCP diagnostics"
```

---

### Task 4: Document operator installation and real acceptance procedure

**Files:**
- Modify: `README.md`
- Test: `tests/test_install_codex_global_router.py`

**Interfaces:**
- Operator command: `python tools/install_codex_global_router.py`
- Verification command: `python tools/install_codex_global_router.py --check`

- [ ] **Step 1: Add a failing documentation assertion**

Add:

```python
    def test_readme_documents_global_router_install(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("Codex 全局外部情报回传", readme)
        self.assertIn("install_codex_global_router.py --check", readme)
        self.assertIn("INTELLIGENCE_WRITEBACK_COMPLETE", readme)
```

- [ ] **Step 2: Run the test and verify failure**

```bash
python -m unittest tests.test_install_codex_global_router.GlobalIntelligenceRouterTests.test_readme_documents_global_router_install -v
```

Expected: FAIL until README is updated.

- [ ] **Step 3: Add README section**

Document:

```markdown
## Codex 全局外部情报回传

安装/更新 `$CODEX_HOME/AGENTS.md` 中的受管路由块：

```bash
python tools/install_codex_global_router.py
python tools/install_codex_global_router.py --check
```

默认 `$CODEX_HOME` 为 `~/.codex`；可用环境变量 `CODEX_HOME` 或 `--codex-home` 覆盖。

安装器不会写 OAuth 凭据，也不会自动改写 `config.toml`。`--check` 只报告 MCP/plugin 配置信号。Notion 工具不可读写时，Codex 必须返回 `BLOCKED`。

真实验收：开启一个全新的 Codex 任务，粘贴一条提示词相关 X 链接。只有 Notion 外部情报库、Global Intelligence HANDOFF、目标 Project HANDOFF 完成写入并回读验证后，任务才允许返回 `INTELLIGENCE_WRITEBACK_COMPLETE`。
```

- [ ] **Step 4: Run all repository tests**

```bash
python -m unittest discover -s tests -v
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add README.md tests/test_install_codex_global_router.py
git commit -m "docs: add Codex global router installation"
```

---

### Task 5: Install into the real Codex home and perform end-to-end acceptance

**Files:**
- Modify outside Git repository: `$CODEX_HOME/AGENTS.md` via the installer only.
- Read-only diagnostic: `$CODEX_HOME/config.toml`.
- External systems: Codex, Notion External Intelligence, Global Intelligence HANDOFF, target Project HANDOFF.

**Interfaces:**
- Input: one real prompt-related X URL.
- Success token: `INTELLIGENCE_WRITEBACK_COMPLETE`.
- Failure token: `BLOCKED` plus failing stage.

- [ ] **Step 1: Run repository verification immediately before real installation**

```bash
python -m unittest discover -s tests -v
```

Expected: zero failures/errors.

- [ ] **Step 2: Install into the real Codex home**

```bash
python tools/install_codex_global_router.py
python tools/install_codex_global_router.py --check
```

Expected: `canonical=true`. Record the actual `agents_path`, `config_path`, and MCP diagnostic output as evidence.

- [ ] **Step 3: Inspect configured MCP servers from Codex**

```bash
codex mcp list
```

Expected: a Notion-capable MCP/plugin is available. If absent, stop with `BLOCKED: NOTION_MCP_UNAVAILABLE`; do not continue to a false success.

- [ ] **Step 4: Start a fresh Codex task with a real prompt-related X link**

Prompt shape:

```text
分析这条 X 链接并按当前全局外部情报回传规则执行完整闭环：
<REAL_X_URL>

不要把“分析完成”当终点。只有 Notion 写入、Global/Project HANDOFF 更新和回读验证全部通过后，才能返回 INTELLIGENCE_WRITEBACK_COMPLETE；否则返回 BLOCKED 和失败步骤。
```

- [ ] **Step 5: Verify Notion External Intelligence record**

Check that the X status ID/source URL has exactly one record and that:

```text
平台 = X
回传来源 = Codex
写回状态 = COMPLETE
Source ID = <status-id>
路由范围 = TARGETED (for prompt topic)
目标项目Key contains prompt-analysis
record_url is real and fetchable
```

- [ ] **Step 6: Verify both HANDOFF layers**

Global Intelligence HANDOFF must point to the same record URL. For a prompt-related X, `X Intelligence HANDOFF｜提示词分析` must also point to the same record URL/source ID.

- [ ] **Step 7: Verify cross-Project recovery from ChatGPT**

From a matching ChatGPT Project, request:

```text
读取 Codex 最新一条 X 分析
```

Expected: ChatGPT resolves the record through Project Router/HANDOFF without requiring the X URL to be pasted again.

- [ ] **Step 8: Only then mark the global writeback state VERIFIED**

Update Notion `Global Intelligence / Codex X` from `IN_PROGRESS` to `VERIFIED`, clear its blocker, and record the real X Source ID, Notion record URL, and verification timestamp as evidence.

---

## Self-Review

- Spec coverage: installer preservation, idempotency, fail-closed corruption behavior, MCP boundary, success/failure terminal states, prompt routing, repository tests, real Notion acceptance, and cross-Project recovery are all mapped to tasks.
- Placeholder scan: no implementation step uses TBD/TODO or unspecified error handling.
- Type consistency: `resolve_codex_home`, `canonical_block_source`, `render_installed_agents`, `install`, and `check_installation` signatures are stable across tasks.
