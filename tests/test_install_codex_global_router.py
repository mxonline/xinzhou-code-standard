from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "install_codex_global_router.py"
SOURCE_PATH = ROOT / "codex" / "GLOBAL_INTELLIGENCE_ROUTER.md"
README_PATH = ROOT / "README.md"


def load_module():
    if not MODULE_PATH.is_file():
        return None
    spec = importlib.util.spec_from_file_location("install_codex_global_router", MODULE_PATH)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GlobalIntelligenceRouterTests(unittest.TestCase):
    def require_runtime(self):
        runtime = load_module()
        self.assertIsNotNone(runtime, "tools/install_codex_global_router.py is required")
        return runtime

    def require_callable(self, runtime, name: str):
        self.assertTrue(hasattr(runtime, name), f"{name} is required")
        value = getattr(runtime, name)
        self.assertTrue(callable(value), f"{name} must be callable")
        return value

    def test_canonical_source_declares_writeback_gate(self):
        self.assertTrue(SOURCE_PATH.is_file(), "canonical global intelligence router source is required")
        text = SOURCE_PATH.read_text(encoding="utf-8")
        self.assertIn("External Intelligence Writeback & Routing Contract v1.0", text)
        self.assertIn("INTELLIGENCE_WRITEBACK_COMPLETE", text)
        self.assertIn("BLOCKED", text)
        self.assertIn("ANALYSIS_DONE", text)
        self.assertEqual(text.count("XINZHAO:GLOBAL_INTELLIGENCE_ROUTER:BEGIN"), 1)
        self.assertEqual(text.count("XINZHAO:GLOBAL_INTELLIGENCE_ROUTER:END"), 1)

    def test_canonical_source_makes_every_x_status_task_mandatory(self):
        text = SOURCE_PATH.read_text(encoding="utf-8")
        self.assertIn("Any task whose input or context contains an X/Twitter status URL is in scope", text)
        self.assertIn("before any final response", text)
        self.assertIn("Do not require the user to ask to save, persist, or write back", text)
        self.assertIn("analysis, recommendations, topic selection, or partial conclusions", text)
        self.assertIn("INTELLIGENCE_WRITEBACK_COMPLETE", text)
        self.assertIn("BLOCKED", text)

    def test_installer_exposes_canonical_source(self):
        runtime = self.require_runtime()
        reader = self.require_callable(runtime, "canonical_block_source")
        text = reader()
        self.assertEqual(text, SOURCE_PATH.read_text(encoding="utf-8").strip() + "\n")

    def test_append_preserves_existing_content(self):
        runtime = self.require_runtime()
        render = self.require_callable(runtime, "render_installed_agents")
        existing = "# My Rules\nKeep this line.\n"
        block = runtime.canonical_block_source()
        rendered, status = render(existing, block)
        self.assertEqual(status, "appended")
        self.assertTrue(rendered.startswith(existing))
        self.assertIn(runtime.BEGIN_MARKER, rendered)
        self.assertIn(runtime.END_MARKER, rendered)

    def test_second_render_is_idempotent(self):
        runtime = self.require_runtime()
        render = self.require_callable(runtime, "render_installed_agents")
        block = runtime.canonical_block_source()
        first, _ = render("# Existing\n", block)
        second, status = render(first, block)
        self.assertEqual(status, "unchanged")
        self.assertEqual(second, first)

    def test_existing_managed_block_is_replaced_only(self):
        runtime = self.require_runtime()
        render = self.require_callable(runtime, "render_installed_agents")
        existing = (
            "before\n"
            + runtime.BEGIN_MARKER
            + "\nold\n"
            + runtime.END_MARKER
            + "\nafter\n"
        )
        rendered, status = render(existing, runtime.canonical_block_source())
        self.assertEqual(status, "updated")
        self.assertTrue(rendered.startswith("before\n"))
        self.assertTrue(rendered.endswith("after\n"))
        self.assertNotIn("\nold\n", rendered)

    def test_partial_marker_state_fails_closed(self):
        runtime = self.require_runtime()
        render = self.require_callable(runtime, "render_installed_agents")
        with self.assertRaisesRegex(ValueError, "managed marker"):
            render(runtime.BEGIN_MARKER + "\ncorrupt\n", runtime.canonical_block_source())

    def test_duplicate_marker_state_fails_closed(self):
        runtime = self.require_runtime()
        render = self.require_callable(runtime, "render_installed_agents")
        corrupted = (
            runtime.BEGIN_MARKER
            + "\none\n"
            + runtime.END_MARKER
            + "\n"
            + runtime.BEGIN_MARKER
            + "\ntwo\n"
            + runtime.END_MARKER
        )
        with self.assertRaisesRegex(ValueError, "managed marker"):
            render(corrupted, runtime.canonical_block_source())

    def test_resolve_codex_home_prefers_explicit_then_environment(self):
        runtime = self.require_runtime()
        resolve = self.require_callable(runtime, "resolve_codex_home")
        with tempfile.TemporaryDirectory() as explicit_tmp, tempfile.TemporaryDirectory() as env_tmp:
            with patch.dict(os.environ, {"CODEX_HOME": env_tmp}, clear=False):
                self.assertEqual(resolve(explicit_tmp), Path(explicit_tmp).resolve())
                self.assertEqual(resolve(), Path(env_tmp).resolve())

    def test_install_creates_agents_and_preserves_unmanaged_content(self):
        runtime = self.require_runtime()
        install = self.require_callable(runtime, "install")
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            agents = home / "AGENTS.md"
            agents.write_text("# Existing global rules\nKeep me.\n", encoding="utf-8")
            result = install(home)
            text = agents.read_text(encoding="utf-8")
            self.assertTrue(result["changed"])
            self.assertEqual(result["status"], "appended")
            self.assertTrue(text.startswith("# Existing global rules\nKeep me.\n"))
            self.assertIn(runtime.BEGIN_MARKER, text)
            self.assertIn("INTELLIGENCE_WRITEBACK_COMPLETE", text)

    def test_install_is_idempotent(self):
        runtime = self.require_runtime()
        install = self.require_callable(runtime, "install")
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            first = install(home)
            first_text = (home / "AGENTS.md").read_bytes()
            second = install(home)
            second_text = (home / "AGENTS.md").read_bytes()
            self.assertTrue(first["changed"])
            self.assertFalse(second["changed"])
            self.assertEqual(second["status"], "unchanged")
            self.assertEqual(second_text, first_text)

    def test_dry_run_does_not_write(self):
        runtime = self.require_runtime()
        install = self.require_callable(runtime, "install")
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "nested-codex-home"
            result = install(home, dry_run=True)
            self.assertTrue(result["changed"])
            self.assertTrue(result["dry_run"])
            self.assertFalse((home / "AGENTS.md").exists())

    def test_corrupt_install_does_not_modify_agents(self):
        runtime = self.require_runtime()
        install = self.require_callable(runtime, "install")
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            agents = home / "AGENTS.md"
            original = runtime.BEGIN_MARKER + "\ncorrupt\n"
            agents.write_text(original, encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "managed marker"):
                install(home)
            self.assertEqual(agents.read_text(encoding="utf-8"), original)

    def test_check_reports_installed_and_config_signal(self):
        runtime = self.require_runtime()
        install = self.require_callable(runtime, "install")
        check = self.require_callable(runtime, "check_installation")
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            install(home)
            (home / "config.toml").write_text(
                '[mcp_servers.notion]\nurl = "https://example.invalid/mcp"\n', encoding="utf-8"
            )
            result = check(home)
            self.assertTrue(result["installed"])
            self.assertTrue(result["canonical"])
            self.assertFalse(result["corrupt_markers"])
            self.assertTrue(result["config_exists"])
            self.assertTrue(result["mcp_config_signal"])

    def test_check_does_not_claim_mcp_when_config_missing(self):
        runtime = self.require_runtime()
        check = self.require_callable(runtime, "check_installation")
        with tempfile.TemporaryDirectory() as tmp:
            result = check(Path(tmp))
            self.assertFalse(result["installed"])
            self.assertFalse(result["canonical"])
            self.assertFalse(result["config_exists"])
            self.assertFalse(result["mcp_config_signal"])

    def test_check_flags_partial_marker_corruption(self):
        runtime = self.require_runtime()
        check = self.require_callable(runtime, "check_installation")
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / "AGENTS.md").write_text(runtime.BEGIN_MARKER + "\nbroken\n", encoding="utf-8")
            result = check(home)
            self.assertFalse(result["canonical"])
            self.assertTrue(result["corrupt_markers"])

    def test_cli_check_exit_code_tracks_canonical_install(self):
        runtime = self.require_runtime()
        main = self.require_callable(runtime, "main")
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            self.assertEqual(main(["--codex-home", str(home), "--check"]), 1)
            self.assertEqual(main(["--codex-home", str(home)]), 0)
            self.assertEqual(main(["--codex-home", str(home), "--check"]), 0)

    def test_readme_documents_global_router_install(self):
        readme = README_PATH.read_text(encoding="utf-8")
        self.assertIn("Codex 全局外部情报回传", readme)
        self.assertIn("install_codex_global_router.py --check", readme)
        self.assertIn("INTELLIGENCE_WRITEBACK_COMPLETE", readme)
        self.assertIn("BLOCKED", readme)


if __name__ == "__main__":
    unittest.main()
