from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "runtime_contract.py"


def load_module():
    if not MODULE_PATH.is_file():
        raise AssertionError("tools/runtime_contract.py must implement Global Runtime Contract v1")
    spec = importlib.util.spec_from_file_location("runtime_contract", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError("cannot load runtime_contract.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RuntimeContractTests(unittest.TestCase):
    def canonical_state(self):
        return {
            "schema_version": 1,
            "execution_id": "exec-001",
            "status": "IN_PROGRESS",
            "current_stage": "STAGE_2",
            "last_verified_stage": "STAGE_1",
            "pending_gates": ["stage2"],
            "blocked": None,
            "next_action": "RUN_STAGE_2",
            "state_revision": 2,
            "gates": {
                "baseline": {"status": "PASS", "evidence": ["evidence:baseline-1"]},
                "stage2": {"status": "PENDING", "evidence": []},
            },
            "updated_at": "2026-09-09T00:00:00Z",
        }

    def canonical_evidence(self):
        return {
            "schema_version": 1,
            "execution_id": "exec-001",
            "items": [
                {
                    "id": "baseline-1",
                    "execution_id": "exec-001",
                    "type": "test",
                    "result": "PASS",
                    "ref": "test:baseline",
                    "observed_at": "2026-09-09T00:00:00Z",
                }
            ],
        }

    def canonical_events(self):
        return [
            {"seq": 1, "execution_id": "exec-001", "state_revision": 1, "event": "CREATED", "time": "2026-09-09T00:00:00Z", "data": {}},
            {"seq": 2, "execution_id": "exec-001", "state_revision": 2, "event": "ADVANCED", "time": "2026-09-09T00:01:00Z", "data": {}},
        ]

    def arthur_state(self):
        return {
            "schema_version": 2,
            "execution_id": "arthur-run-001",
            "status": "RESUME_SAFE",
            "current_gate": "PRE_FLASH",
            "next_action": "PRE_FLASH",
            "gates": [
                {"gate_id": "BUILD", "status": "PASS", "evidence_refs": ["evidence:build-1"]},
                {"gate_id": "PRE_FLASH", "status": "NOT_STARTED", "evidence_refs": []},
            ],
        }

    def arthur_evidence(self):
        return {
            "schema_version": 1,
            "execution_id": "arthur-run-001",
            "evidence": [
                {"evidence_id": "build-1", "gate_id": "BUILD", "result": "PASS", "ref": "github-actions:1", "observed_at": "2026-09-09T00:00:00Z"}
            ],
        }

    def arthur_events(self):
        return [
            {"seq": 1, "event": "LEDGER_INITIALIZED", "time": "2026-09-09T00:00:00Z", "prev_hash": "GENESIS", "event_hash": "a" * 64, "data": {}},
            {"seq": 2, "event": "RESUME_STATE_CHANGED", "time": "2026-09-09T00:01:00Z", "prev_hash": "a" * 64, "event_hash": "b" * 64, "data": {}},
        ]

    def test_valid_canonical_bundle_passes(self):
        runtime = load_module()
        result = runtime.validate_bundle(
            profile="canonical-v1",
            state=self.canonical_state(),
            events=self.canonical_events(),
            evidence_index=self.canonical_evidence(),
            expected_execution_id="exec-001",
        )
        self.assertTrue(result["valid"], result["conflicts"])

    def test_canonical_identity_mismatch_fails_closed(self):
        runtime = load_module()
        evidence = self.canonical_evidence()
        evidence["execution_id"] = "other"
        result = runtime.validate_bundle("canonical-v1", self.canonical_state(), self.canonical_events(), evidence, "exec-001")
        self.assertFalse(result["valid"])
        self.assertTrue(any("EXECUTION_ID" in item for item in result["conflicts"]))

    def test_missing_explicit_evidence_reference_fails(self):
        runtime = load_module()
        state = self.canonical_state()
        state["gates"]["baseline"]["evidence"] = ["evidence:missing"]
        result = runtime.validate_bundle("canonical-v1", state, self.canonical_events(), self.canonical_evidence(), "exec-001")
        self.assertFalse(result["valid"])
        self.assertIn("EVIDENCE_REF_MISSING:missing", result["conflicts"])

    def test_bad_event_sequence_or_future_revision_fails(self):
        runtime = load_module()
        events = self.canonical_events()
        events[1]["seq"] = 1
        events[1]["state_revision"] = 3
        result = runtime.validate_bundle("canonical-v1", self.canonical_state(), events, self.canonical_evidence(), "exec-001")
        self.assertFalse(result["valid"])
        self.assertTrue(any("EVENT_SEQ" in item for item in result["conflicts"]))
        self.assertTrue(any("EVENT_STATE_REVISION" in item for item in result["conflicts"]))

    def test_canonical_evidence_shape_with_evidence_id_is_supported(self):
        runtime = load_module()
        evidence = {
            "schema_version": 1,
            "execution_id": "exec-001",
            "evidence": [
                {"evidence_id": "baseline-1", "result": "PASS", "ref": "test:baseline", "observed_at": "2026-09-09T00:00:00Z"}
            ],
        }
        result = runtime.validate_bundle("canonical-v1", self.canonical_state(), self.canonical_events(), evidence, "exec-001")
        self.assertTrue(result["valid"], result["conflicts"])

    def test_valid_arthur_legacy_bundle_passes_without_state_revision(self):
        runtime = load_module()
        result = runtime.validate_bundle("arthur-v2", self.arthur_state(), self.arthur_events(), self.arthur_evidence(), "arthur-run-001")
        self.assertTrue(result["valid"], result["conflicts"])

    def test_arthur_hash_link_and_pass_evidence_are_enforced(self):
        runtime = load_module()
        events = self.arthur_events()
        events[1]["prev_hash"] = "c" * 64
        state = self.arthur_state()
        state["gates"][0]["evidence_refs"] = ["evidence:missing"]
        result = runtime.validate_bundle("arthur-v2", state, events, self.arthur_evidence(), "arthur-run-001")
        self.assertFalse(result["valid"])
        self.assertTrue(any("HASH_CHAIN" in item for item in result["conflicts"]))
        self.assertIn("EVIDENCE_REF_MISSING:missing", result["conflicts"])

    def _write_json(self, path: Path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def _write_events(self, path: Path, events):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(json.dumps(event, ensure_ascii=False) + "\n" for event in events), encoding="utf-8")

    def test_manifest_explicit_bundle_validates(self):
        runtime = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._write_json(root / "runtime/state.json", self.canonical_state())
            self._write_events(root / "runtime/events.jsonl", self.canonical_events())
            self._write_json(root / "runtime/evidence/index.json", self.canonical_evidence())
            manifest = {
                "contract_version": "global-runtime-v1",
                "project": "fixture",
                "profile": "canonical-v1",
                "bundles": [{
                    "execution_id": "exec-001",
                    "state": "runtime/state.json",
                    "events": "runtime/events.jsonl",
                    "evidence": "runtime/evidence/index.json",
                }],
                "projection_paths": [],
            }
            self._write_json(root / "runtime-contract.json", manifest)
            result = runtime.validate_manifest(root, root / "runtime-contract.json")
            self.assertTrue(result["valid"], result)
            self.assertEqual(result["validated_bundles"], 1)

    def test_manifest_scans_runtime_root_and_can_allow_empty(self):
        runtime = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            runtime_root = root / "production/runtime"
            runtime_root.mkdir(parents=True)
            manifest = {
                "contract_version": "global-runtime-v1",
                "project": "dynamic",
                "profile": "canonical-v1",
                "runtime_root": "production/runtime",
                "allow_empty_runtime_root": True,
                "projection_paths": [],
            }
            self._write_json(root / "runtime-contract.json", manifest)
            result = runtime.validate_manifest(root, root / "runtime-contract.json")
            self.assertTrue(result["valid"], result)
            self.assertEqual(result["validated_bundles"], 0)

            bundle = runtime_root / "article-1"
            state = self.canonical_state()
            state["execution_id"] = "article-exec-1"
            evidence = self.canonical_evidence()
            evidence["execution_id"] = "article-exec-1"
            for item in evidence["items"]:
                item["execution_id"] = "article-exec-1"
            events = self.canonical_events()
            for event in events:
                event["execution_id"] = "article-exec-1"
            self._write_json(bundle / "state.json", state)
            self._write_events(bundle / "events.jsonl", events)
            self._write_json(bundle / "evidence/index.json", evidence)
            result = runtime.validate_manifest(root, root / "runtime-contract.json")
            self.assertTrue(result["valid"], result)
            self.assertEqual(result["validated_bundles"], 1)

    def test_path_escape_in_manifest_is_rejected(self):
        runtime = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = {
                "contract_version": "global-runtime-v1",
                "project": "bad",
                "profile": "canonical-v1",
                "bundles": [{"execution_id": "exec-001", "state": "../state.json", "events": "events.jsonl", "evidence": "evidence.json"}],
            }
            self._write_json(root / "runtime-contract.json", manifest)
            result = runtime.validate_manifest(root, root / "runtime-contract.json")
            self.assertFalse(result["valid"])
            self.assertTrue(any("PATH_ESCAPE" in item for item in result["conflicts"]))


if __name__ == "__main__":
    unittest.main()
