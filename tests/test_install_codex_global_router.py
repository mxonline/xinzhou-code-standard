from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = ROOT / "codex" / "GLOBAL_INTELLIGENCE_ROUTER.md"


class GlobalIntelligenceRouterTests(unittest.TestCase):
    def test_canonical_source_declares_writeback_gate(self):
        self.assertTrue(SOURCE_PATH.is_file(), "canonical global intelligence router source is required")
        text = SOURCE_PATH.read_text(encoding="utf-8")
        self.assertIn("External Intelligence Writeback & Routing Contract v1.0", text)
        self.assertIn("INTELLIGENCE_WRITEBACK_COMPLETE", text)
        self.assertIn("BLOCKED", text)
        self.assertIn("ANALYSIS_DONE", text)


if __name__ == "__main__":
    unittest.main()
