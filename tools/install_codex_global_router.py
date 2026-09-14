from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Sequence

ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = ROOT / "codex" / "GLOBAL_INTELLIGENCE_ROUTER.md"
BEGIN_MARKER = "<!-- XINZHAO:GLOBAL_INTELLIGENCE_ROUTER:BEGIN -->"
END_MARKER = "<!-- XINZHAO:GLOBAL_INTELLIGENCE_ROUTER:END -->"


def canonical_block_source() -> str:
    return SOURCE_PATH.read_text(encoding="utf-8").strip() + "\n"


def resolve_codex_home(explicit: str | None = None) -> Path:
    if explicit:
        return Path(explicit).expanduser().resolve()
    env_home = os.environ.get("CODEX_HOME")
    if env_home:
        return Path(env_home).expanduser().resolve()
    return (Path.home() / ".codex").resolve()


def _marker_state(existing: str) -> tuple[int, int, bool]:
    begin_count = existing.count(BEGIN_MARKER)
    end_count = existing.count(END_MARKER)
    corrupt = begin_count != end_count or begin_count > 1
    if not corrupt and begin_count == 1:
        corrupt = existing.index(BEGIN_MARKER) > existing.index(END_MARKER)
    return begin_count, end_count, corrupt


def render_installed_agents(existing: str, block: str) -> tuple[str, str]:
    begin_count, _, corrupt = _marker_state(existing)
    if corrupt:
        raise ValueError("invalid managed marker state; refusing to modify AGENTS.md")

    canonical = block.strip() + "\n"
    if begin_count == 0:
        if not existing:
            return canonical, "created"
        separator = "" if existing.endswith("\n\n") else ("\n" if existing.endswith("\n") else "\n\n")
        return existing + separator + canonical, "appended"

    start = existing.index(BEGIN_MARKER)
    end = existing.index(END_MARKER, start) + len(END_MARKER)
    current = existing[start:end].strip() + "\n"
    if current == canonical:
        return existing, "unchanged"
    rendered = existing[:start] + canonical.rstrip("\n") + existing[end:]
    return rendered, "updated"


def install(codex_home: Path, dry_run: bool = False) -> dict[str, str | bool]:
    codex_home = Path(codex_home).expanduser().resolve()
    agents_path = codex_home / "AGENTS.md"
    existing = agents_path.read_text(encoding="utf-8") if agents_path.exists() else ""
    rendered, status = render_installed_agents(existing, canonical_block_source())
    changed = rendered != existing

    if changed and not dry_run:
        codex_home.mkdir(parents=True, exist_ok=True)
        agents_path.write_text(rendered, encoding="utf-8")

    return {
        "path": str(agents_path),
        "status": status,
        "changed": changed,
        "dry_run": dry_run,
    }


def check_installation(codex_home: Path) -> dict[str, object]:
    codex_home = Path(codex_home).expanduser().resolve()
    agents_path = codex_home / "AGENTS.md"
    config_path = codex_home / "config.toml"
    existing = agents_path.read_text(encoding="utf-8") if agents_path.exists() else ""

    begin_count, end_count, corrupt = _marker_state(existing)
    installed = not corrupt and begin_count == 1 and end_count == 1
    canonical_installed = False
    if installed:
        start = existing.index(BEGIN_MARKER)
        end = existing.index(END_MARKER, start) + len(END_MARKER)
        current = existing[start:end].strip()
        canonical_installed = current == canonical_block_source().strip()

    config_exists = config_path.exists()
    config_text = config_path.read_text(encoding="utf-8") if config_exists else ""
    config_lower = config_text.lower()
    mcp_signal = "[mcp_servers." in config_lower or "[plugins." in config_lower

    return {
        "agents_path": str(agents_path),
        "installed": installed,
        "canonical": canonical_installed,
        "corrupt_markers": corrupt,
        "config_path": str(config_path),
        "config_exists": config_exists,
        "mcp_config_signal": mcp_signal,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Install or verify the XinZhao global external-intelligence router in Codex AGENTS.md."
    )
    parser.add_argument("--codex-home", help="Override CODEX_HOME (default: env CODEX_HOME or ~/.codex).")
    parser.add_argument("--check", action="store_true", help="Verify the managed block and report MCP config signals.")
    parser.add_argument("--dry-run", action="store_true", help="Show the install result without writing AGENTS.md.")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    codex_home = resolve_codex_home(args.codex_home)

    try:
        if args.check:
            result = check_installation(codex_home)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0 if bool(result["canonical"]) else 1

        result = install(codex_home, dry_run=args.dry_run)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (OSError, UnicodeError, ValueError) as exc:
        result = {
            "status": "BLOCKED",
            "stage": "CODEX_GLOBAL_ROUTER_INSTALL",
            "error": str(exc),
            "codex_home": str(codex_home),
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
