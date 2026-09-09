from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXECUTION_ID = "video-factory-v1-production-first"
BASE = ROOT / "runtime-contract" / "instances" / EXECUTION_ID
MANIFEST = ROOT / "runtime-contract" / "video-factory.runtime-contract.json"


class VideoFactoryAuthorityTests(unittest.TestCase):
    def test_git_is_the_only_machine_authority(self):
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        state = json.loads((BASE / "state.json").read_text(encoding="utf-8"))

        self.assertEqual(manifest["machine_authority"], "git")
        self.assertEqual(manifest["canonical_repository"], "mxonline/xinzhou-code-standard")
        self.assertEqual(manifest["canonical_runtime_root"], f"runtime-contract/instances/{EXECUTION_ID}")
        self.assertFalse(manifest["executor_autowrite_verified"])
        self.assertTrue(manifest["projection_paths"])
        self.assertTrue(all(str(item).startswith("Notion:") for item in manifest["projection_paths"]))

        self.assertEqual(state["execution_id"], EXECUTION_ID)
        self.assertEqual(state["machine_authority"], "git")
        self.assertEqual(state["projection_role"], "notion_handoff_projection_only")
        self.assertEqual(state["executor_autowrite_status"], "NOT_VERIFIED")
        self.assertEqual(state["current_stage"], "GOLDEN_CASE_E2E_REGRESSION")
        self.assertEqual(state["next_action"], "RUN_GOLDEN_CASE_E2E_REGRESSION")
        self.assertEqual(state["video_status"], "RC")

    def test_authority_routing_is_evidence_backed_and_does_not_advance_production(self):
        state = json.loads((BASE / "state.json").read_text(encoding="utf-8"))
        evidence = json.loads((BASE / "evidence" / "index.json").read_text(encoding="utf-8"))
        events = [json.loads(line) for line in (BASE / "events.jsonl").read_text(encoding="utf-8").splitlines() if line.strip()]

        self.assertGreaterEqual(state["state_revision"], 3)
        refs = {item["id"]: item for item in evidence["items"]}
        self.assertIn("git-canonical-authority", refs)
        self.assertEqual(refs["git-canonical-authority"]["result"], "PASS")
        self.assertEqual(events[-1]["event"], "GIT_CANONICAL_AUTHORITY_PROMOTED")
        self.assertFalse(events[-1]["data"]["production_gate_advanced"])
        self.assertEqual(events[-1]["data"]["next_action"], state["next_action"])
        self.assertIn("GOLDEN_CASE_E2E_REGRESSION", state["pending_gates"])
        self.assertIn("VIDEO_READY", state["pending_gates"])
        self.assertIn("V1_RELEASE_GATE_20_REAL_TASKS", state["pending_gates"])


if __name__ == "__main__":
    unittest.main()
