from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable

CONTRACT_VERSION = "global-runtime-v1"
PROFILES = {"canonical-v1", "arthur-v2"}
HEX64 = re.compile(r"^[0-9a-fA-F]{64}$")
ACCEPTED_GATE_STATUSES = {"PASS", "VERIFIED", "GATED", "BLOCKED", "FAILED"}


def _conflict(result: list[str], code: str) -> None:
    if code not in result:
        result.append(code)


def _evidence_ids(index: dict[str, Any]) -> set[str]:
    ids: set[str] = set()
    collections = []
    if isinstance(index.get("items"), list):
        collections.append((index["items"], "id"))
    if isinstance(index.get("evidence"), list):
        collections.append((index["evidence"], "evidence_id"))
    for items, key in collections:
        for item in items:
            if isinstance(item, dict) and isinstance(item.get(key), str) and item[key]:
                ids.add(item[key])
    return ids


def _walk_strings(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from _walk_strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk_strings(child)


def _explicit_evidence_refs(state: dict[str, Any]) -> set[str]:
    refs: set[str] = set()
    for value in _walk_strings(state):
        if value.startswith("evidence:") and len(value) > len("evidence:"):
            refs.add(value.split(":", 1)[1])
    return refs


def _validate_sequence(events: list[dict[str, Any]], conflicts: list[str]) -> None:
    previous: int | None = None
    for event in events:
        seq = event.get("seq") if isinstance(event, dict) else None
        if not isinstance(seq, int) or seq < 1:
            _conflict(conflicts, "EVENT_SEQ_INVALID")
            continue
        if previous is not None and seq <= previous:
            _conflict(conflicts, "EVENT_SEQ_NOT_STRICTLY_INCREASING")
        previous = seq


def _validate_evidence_identity(
    evidence_index: dict[str, Any], expected_execution_id: str, conflicts: list[str]
) -> set[str]:
    if evidence_index.get("execution_id") != expected_execution_id:
        _conflict(conflicts, "EVIDENCE_EXECUTION_ID_MISMATCH")
    ids = _evidence_ids(evidence_index)
    all_items: list[dict[str, Any]] = []
    for key in ("items", "evidence"):
        value = evidence_index.get(key)
        if isinstance(value, list):
            all_items.extend(item for item in value if isinstance(item, dict))
    seen: set[str] = set()
    for item in all_items:
        item_id = item.get("id") or item.get("evidence_id")
        if not isinstance(item_id, str) or not item_id:
            _conflict(conflicts, "EVIDENCE_ID_MISSING")
            continue
        if item_id in seen:
            _conflict(conflicts, f"EVIDENCE_ID_DUPLICATE:{item_id}")
        seen.add(item_id)
        item_execution = item.get("execution_id")
        if item_execution is not None and item_execution != expected_execution_id:
            _conflict(conflicts, f"EVIDENCE_ITEM_EXECUTION_ID_MISMATCH:{item_id}")
    return ids


def _check_refs(refs: Iterable[str], ids: set[str], conflicts: list[str]) -> None:
    for ref in refs:
        if ref not in ids:
            _conflict(conflicts, f"EVIDENCE_REF_MISSING:{ref}")


def _validate_canonical(
    state: dict[str, Any], events: list[dict[str, Any]], evidence_index: dict[str, Any], expected_execution_id: str
) -> dict[str, Any]:
    conflicts: list[str] = []
    required = (
        "execution_id", "status", "current_stage", "last_verified_stage", "pending_gates",
        "blocked", "next_action", "state_revision",
    )
    for field in required:
        if field not in state:
            _conflict(conflicts, f"STATE_FIELD_MISSING:{field}")
    if state.get("execution_id") != expected_execution_id:
        _conflict(conflicts, "STATE_EXECUTION_ID_MISMATCH")
    revision = state.get("state_revision")
    if not isinstance(revision, int) or revision < 1:
        _conflict(conflicts, "STATE_REVISION_INVALID")
        revision = 0
    if not isinstance(state.get("pending_gates"), list):
        _conflict(conflicts, "PENDING_GATES_INVALID")

    ids = _validate_evidence_identity(evidence_index, expected_execution_id, conflicts)
    _check_refs(_explicit_evidence_refs(state), ids, conflicts)
    _validate_sequence(events, conflicts)

    for event in events:
        if not isinstance(event, dict):
            _conflict(conflicts, "EVENT_NOT_OBJECT")
            continue
        if event.get("execution_id") != expected_execution_id:
            _conflict(conflicts, "EVENT_EXECUTION_ID_MISMATCH")
        event_revision = event.get("state_revision")
        if not isinstance(event_revision, int) or event_revision < 1 or event_revision > revision:
            _conflict(conflicts, "EVENT_STATE_REVISION_INVALID")

    gates = state.get("gates")
    if isinstance(gates, dict):
        for gate_name, gate in gates.items():
            if not isinstance(gate, dict):
                continue
            status = gate.get("status")
            if status in ACCEPTED_GATE_STATUSES:
                refs = gate.get("evidence")
                if refs is None:
                    refs = gate.get("evidence_refs")
                if not isinstance(refs, list) or not refs:
                    _conflict(conflicts, f"GATE_EVIDENCE_REQUIRED:{gate_name}")
                else:
                    normalized = [ref.split(":", 1)[1] for ref in refs if isinstance(ref, str) and ref.startswith("evidence:")]
                    if len(normalized) != len(refs):
                        _conflict(conflicts, f"GATE_EVIDENCE_REF_INVALID:{gate_name}")
                    _check_refs(normalized, ids, conflicts)

    return {"valid": not conflicts, "profile": "canonical-v1", "execution_id": expected_execution_id, "conflicts": conflicts}


def _validate_arthur(
    state: dict[str, Any], events: list[dict[str, Any]], evidence_index: dict[str, Any], expected_execution_id: str
) -> dict[str, Any]:
    conflicts: list[str] = []
    if state.get("schema_version") != 2:
        _conflict(conflicts, "ARTHUR_SCHEMA_VERSION_MISMATCH")
    for field in ("execution_id", "status", "current_gate", "next_action", "gates"):
        if field not in state:
            _conflict(conflicts, f"STATE_FIELD_MISSING:{field}")
    if state.get("execution_id") != expected_execution_id:
        _conflict(conflicts, "STATE_EXECUTION_ID_MISMATCH")

    ids = _validate_evidence_identity(evidence_index, expected_execution_id, conflicts)
    _validate_sequence(events, conflicts)
    previous_hash = "GENESIS"
    for event in events:
        if not isinstance(event, dict):
            _conflict(conflicts, "EVENT_NOT_OBJECT")
            continue
        if event.get("prev_hash") != previous_hash:
            _conflict(conflicts, "ARTHUR_HASH_CHAIN_PREV_MISMATCH")
        event_hash = event.get("event_hash")
        if not isinstance(event_hash, str) or not HEX64.fullmatch(event_hash):
            _conflict(conflicts, "ARTHUR_EVENT_HASH_INVALID")
        else:
            previous_hash = event_hash

    gates = state.get("gates")
    if not isinstance(gates, list):
        _conflict(conflicts, "ARTHUR_GATES_INVALID")
    else:
        for gate in gates:
            if not isinstance(gate, dict):
                continue
            gate_id = str(gate.get("gate_id", "UNKNOWN"))
            status = gate.get("status")
            refs = gate.get("evidence_refs", [])
            if status in ACCEPTED_GATE_STATUSES:
                if not isinstance(refs, list) or not refs:
                    _conflict(conflicts, f"GATE_EVIDENCE_REQUIRED:{gate_id}")
                else:
                    normalized = [ref.split(":", 1)[1] for ref in refs if isinstance(ref, str) and ref.startswith("evidence:")]
                    if len(normalized) != len(refs):
                        _conflict(conflicts, f"GATE_EVIDENCE_REF_INVALID:{gate_id}")
                    _check_refs(normalized, ids, conflicts)

    return {"valid": not conflicts, "profile": "arthur-v2", "execution_id": expected_execution_id, "conflicts": conflicts}


def validate_bundle(
    profile: str,
    state: dict[str, Any],
    events: list[dict[str, Any]],
    evidence_index: dict[str, Any],
    expected_execution_id: str,
) -> dict[str, Any]:
    if profile == "canonical-v1":
        return _validate_canonical(state, events, evidence_index, expected_execution_id)
    if profile == "arthur-v2":
        return _validate_arthur(state, events, evidence_index, expected_execution_id)
    return {"valid": False, "profile": profile, "execution_id": expected_execution_id, "conflicts": [f"PROFILE_UNSUPPORTED:{profile}"]}


def _safe_path(root: Path, relative: str, conflicts: list[str]) -> Path | None:
    candidate = (root / relative).resolve()
    resolved_root = root.resolve()
    try:
        candidate.relative_to(resolved_root)
    except ValueError:
        _conflict(conflicts, f"PATH_ESCAPE:{relative}")
        return None
    return candidate


def _read_json(path: Path, conflicts: list[str], label: str) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        _conflict(conflicts, f"{label}_MISSING:{path}")
        return None
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        _conflict(conflicts, f"{label}_INVALID:{exc}")
        return None
    if not isinstance(value, dict):
        _conflict(conflicts, f"{label}_NOT_OBJECT")
        return None
    return value


def _read_events(path: Path, conflicts: list[str]) -> list[dict[str, Any]] | None:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        _conflict(conflicts, f"EVENTS_MISSING:{path}")
        return None
    events: list[dict[str, Any]] = []
    for number, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            _conflict(conflicts, f"EVENT_JSON_INVALID_LINE:{number}")
            continue
        if not isinstance(value, dict):
            _conflict(conflicts, f"EVENT_NOT_OBJECT_LINE:{number}")
            continue
        events.append(value)
    return events


def _bundle_from_paths(root: Path, profile: str, spec: dict[str, Any]) -> dict[str, Any]:
    conflicts: list[str] = []
    execution_id = spec.get("execution_id")
    if not isinstance(execution_id, str) or not execution_id:
        return {"valid": False, "conflicts": ["MANIFEST_EXECUTION_ID_REQUIRED"]}
    paths = {}
    for key in ("state", "events", "evidence"):
        relative = spec.get(key)
        if not isinstance(relative, str) or not relative:
            _conflict(conflicts, f"MANIFEST_PATH_REQUIRED:{key}")
            continue
        safe = _safe_path(root, relative, conflicts)
        if safe is not None:
            paths[key] = safe
    if conflicts:
        return {"valid": False, "execution_id": execution_id, "conflicts": conflicts}
    state = _read_json(paths["state"], conflicts, "STATE")
    events = _read_events(paths["events"], conflicts)
    evidence = _read_json(paths["evidence"], conflicts, "EVIDENCE")
    if conflicts or state is None or events is None or evidence is None:
        return {"valid": False, "execution_id": execution_id, "conflicts": conflicts}
    result = validate_bundle(profile, state, events, evidence, execution_id)
    result["paths"] = {key: str(value.relative_to(root.resolve())) for key, value in paths.items()}
    return result


def validate_manifest(root: Path | str, manifest_path: Path | str) -> dict[str, Any]:
    root_path = Path(root).resolve()
    manifest_file = Path(manifest_path)
    if not manifest_file.is_absolute():
        manifest_file = (root_path / manifest_file).resolve()
    conflicts: list[str] = []
    try:
        manifest_file.relative_to(root_path)
    except ValueError:
        return {"valid": False, "validated_bundles": 0, "conflicts": [f"PATH_ESCAPE:{manifest_file}"]}
    manifest = _read_json(manifest_file, conflicts, "MANIFEST")
    if manifest is None:
        return {"valid": False, "validated_bundles": 0, "conflicts": conflicts}
    if manifest.get("contract_version") != CONTRACT_VERSION:
        _conflict(conflicts, "CONTRACT_VERSION_MISMATCH")
    profile = manifest.get("profile")
    if profile not in PROFILES:
        _conflict(conflicts, f"PROFILE_UNSUPPORTED:{profile}")
    results: list[dict[str, Any]] = []

    bundles = manifest.get("bundles", [])
    if bundles is not None and not isinstance(bundles, list):
        _conflict(conflicts, "MANIFEST_BUNDLES_INVALID")
        bundles = []
    for spec in bundles:
        if not isinstance(spec, dict):
            _conflict(conflicts, "MANIFEST_BUNDLE_NOT_OBJECT")
            continue
        results.append(_bundle_from_paths(root_path, str(profile), spec))

    runtime_root = manifest.get("runtime_root")
    if runtime_root is not None:
        if not isinstance(runtime_root, str) or not runtime_root:
            _conflict(conflicts, "RUNTIME_ROOT_INVALID")
        else:
            root_dir = _safe_path(root_path, runtime_root, conflicts)
            if root_dir is not None:
                if not root_dir.exists():
                    _conflict(conflicts, f"RUNTIME_ROOT_MISSING:{runtime_root}")
                elif not root_dir.is_dir():
                    _conflict(conflicts, f"RUNTIME_ROOT_NOT_DIRECTORY:{runtime_root}")
                else:
                    state_files = sorted(path for path in root_dir.glob("*/state.json") if path.is_file())
                    if not state_files and not manifest.get("allow_empty_runtime_root", False):
                        _conflict(conflicts, "RUNTIME_ROOT_EMPTY")
                    for state_path in state_files:
                        execution_dir = state_path.parent
                        state = _read_json(state_path, conflicts, "STATE")
                        if state is None:
                            continue
                        execution_id = state.get("execution_id")
                        if not isinstance(execution_id, str) or not execution_id:
                            _conflict(conflicts, f"STATE_EXECUTION_ID_MISSING:{execution_dir.name}")
                            continue
                        spec = {
                            "execution_id": execution_id,
                            "state": str(state_path.relative_to(root_path)),
                            "events": str((execution_dir / "events.jsonl").relative_to(root_path)),
                            "evidence": str((execution_dir / "evidence/index.json").relative_to(root_path)),
                        }
                        results.append(_bundle_from_paths(root_path, str(profile), spec))

    for result in results:
        if not result.get("valid"):
            for item in result.get("conflicts", []):
                _conflict(conflicts, f"BUNDLE:{result.get('execution_id', 'unknown')}:{item}")

    return {
        "valid": not conflicts,
        "contract_version": CONTRACT_VERSION,
        "project": manifest.get("project"),
        "profile": profile,
        "validated_bundles": len(results),
        "bundles": results,
        "conflicts": conflicts,
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate Global Runtime Contract v1")
    sub = parser.add_subparsers(dest="command", required=True)
    validate = sub.add_parser("validate")
    validate.add_argument("--root", default=".")
    validate.add_argument("--manifest", required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    result = validate_manifest(Path(args.root), Path(args.manifest))
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["valid"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
