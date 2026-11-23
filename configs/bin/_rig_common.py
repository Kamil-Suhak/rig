#!/usr/bin/env python3
"""Shared utilities for Rig Python CLIs."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ANSI_CODES = {
    "cyan": "\033[36m",
    "darkcyan": "\033[36m",
    "green": "\033[32m",
    "yellow": "\033[33m",
    "darkyellow": "\033[33m",
    "red": "\033[31m",
    "magenta": "\033[35m",
    "darkgray": "\033[90m",
    "gray": "\033[90m",
    "white": "\033[37m",
    "bold": "\033[1m",
    "dim": "\033[2m",
    "reset": "\033[0m",
}

LEGACY_FLAG_MAP = {
    "-files": "--files",
    "-full": "--full",
    "-stat": "--stat",
    "-commits": "--commits",
    "-fetch": "--fetch",
    "-nofetch": "--no-fetch",
    "-all": "--all",
    "-ignored": "--ignored",
    "-depth": "--depth",
    "-maxdepth": "--max-depth",
    "-ignorewhitespace": "--ignore-whitespace",
    "-quiet": "--quiet",
    "-includecommand": "--include-command",
    "-ctx": "--ctx",
    "-high": "--high",
    "-keephistory": "--keep-history",
    "-archived": "--archived",
    "-code": "--code",
    "-vs": "--vs",
    "-whatif": "--what-if",
    "-help": "--help",
    "-choices": "--choices",
    "-instructions": "--instructions",
    "-engine": "--engine",
}


def should_use_color(stream=None) -> bool:
    """Return True if ANSI color escapes should be emitted on stream."""
    if os.environ.get("NO_COLOR"):
        return False
    if os.environ.get("FORCE_COLOR") or os.environ.get("CLICOLOR_FORCE"):
        return True
    target = stream or sys.stdout
    return hasattr(target, "isatty") and target.isatty()


def ctext(text: str, color: str | None = None, *, force: bool = False) -> str:
    """Wrap text in ANSI color escapes when supported."""
    if not color:
        return text
    code = ANSI_CODES.get(color.lower())
    if not code:
        return text
    if not force and not should_use_color():
        return text
    return f"{code}{text}{ANSI_CODES['reset']}"


def badge(tag: str, tag_color: str, msg: str, msg_color: str | None = None) -> None:
    """Print a colored `[tag] msg` line."""
    print(f"{ctext(f'[{tag}]', tag_color)} {ctext(msg, msg_color)}")


def normalize_legacy_flags(argv: list[str], extra_map: dict[str, str] | None = None) -> list[str]:
    """Translate legacy PascalCase single-dash PowerShell flags to POSIX `--kebab` flags."""
    mapping = dict(LEGACY_FLAG_MAP)
    if extra_map:
        mapping.update({k.lower(): v for k, v in extra_map.items()})
    out: list[str] = []
    stop_translating = False
    for token in argv:
        if stop_translating:
            out.append(token)
            continue
        if token == "--":
            stop_translating = True
            out.append(token)
            continue
        # Handle `-Flag:Value` or `-Flag=Value` syntax
        if token.startswith("-") and not token.startswith("--"):
            for sep in (":", "="):
                if sep in token:
                    head, tail = token.split(sep, 1)
                    mapped = mapping.get(head.lower())
                    if mapped:
                        out.append(f"{mapped}={tail}")
                        break
            else:
                out.append(mapping.get(token.lower(), token))
        else:
            out.append(token)
    return out


def is_wsl() -> bool:
    """Return True when running inside Windows Subsystem for Linux."""
    if os.environ.get("WSL_DISTRO_NAME") or os.environ.get("WSL_INTEROP"):
        return True
    try:
        return "microsoft" in Path("/proc/version").read_text(encoding="utf-8", errors="ignore").lower()
    except OSError:
        return False


def _clipboard_backend_read() -> str | None:
    env_file = os.environ.get("RIG_CLIPBOARD_FILE")
    if env_file:
        p = Path(env_file)
        return p.read_text(encoding="utf-8", errors="replace") if p.is_file() else None

    candidates: list[list[str]] = []
    if shutil.which("wl-paste"):
        candidates.append(["wl-paste", "--no-newline"])
    if shutil.which("xclip"):
        candidates.append(["xclip", "-selection", "clipboard", "-o"])
    if shutil.which("xsel"):
        candidates.append(["xsel", "--clipboard", "--output"])
    if shutil.which("pbpaste"):
        candidates.append(["pbpaste"])
    if is_wsl() or os.name == "nt":
        ps = shutil.which("powershell.exe") or (
            "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
            if Path("/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe").is_file()
            else None
        )
        if ps:
            candidates.append([ps, "-NoProfile", "-Command", "Get-Clipboard -Raw"])

    for cmd in candidates:
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
            if res.returncode == 0:
                return res.stdout
        except OSError:
            continue
    return None


def read_clipboard() -> str | None:
    """Read UTF-8 text from the active system or test clipboard."""
    return _clipboard_backend_read()


def write_clipboard(text: str) -> bool:
    """Write UTF-8 text to the active system or test clipboard."""
    env_file = os.environ.get("RIG_CLIPBOARD_FILE")
    if env_file:
        p = Path(env_file)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8", newline="\n")
        return True

    candidates: list[list[str]] = []
    if shutil.which("wl-copy"):
        candidates.append(["wl-copy"])
    if shutil.which("xclip"):
        candidates.append(["xclip", "-selection", "clipboard"])
    if shutil.which("xsel"):
        candidates.append(["xsel", "--clipboard", "--input"])
    if shutil.which("pbcopy"):
        candidates.append(["pbcopy"])
    if is_wsl() or os.name == "nt":
        clip = shutil.which("clip.exe") or (
            "/mnt/c/Windows/System32/clip.exe"
            if Path("/mnt/c/Windows/System32/clip.exe").is_file()
            else None
        )
        if clip:
            candidates.append([clip])

    for cmd in candidates:
        try:
            res = subprocess.run(cmd, input=text, text=True, encoding="utf-8", capture_output=True)
            if res.returncode == 0:
                return True
        except OSError:
            continue
    return False


_ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")


def transform_clipboard_text(
    text: str,
    *,
    trim: bool = False,
    single_line: bool = False,
    strip_ansi: bool = False,
) -> str:
    """Apply shared string transformations for copy and paste."""
    out = text
    if strip_ansi:
        out = _ANSI_ESCAPE_RE.sub("", out)
    if single_line:
        out = " ".join(out.splitlines())
    if trim:
        out = out.strip()
    return out


def run_git(args: list[str], cwd: Path | str | None = None) -> subprocess.CompletedProcess[str]:
    """Run git and capture decoded UTF-8 stdout/stderr."""
    cmd = ["git"]
    if cwd is not None:
        cmd.extend(["-C", str(cwd)])
    cmd.extend(args)
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")


def git_root(cwd: Path | str | None = None) -> Path | None:
    """Return top-level git worktree path or None if not in a repo."""
    res = run_git(["rev-parse", "--show-toplevel"], cwd=cwd)
    if res.returncode != 0:
        return None
    val = res.stdout.strip()
    return Path(val) if val else None


def resolve_rig_root() -> Path:
    """Return repository root containing configs/bin."""
    env_root = os.environ.get("RIG_ROOT")
    if env_root and Path(env_root).is_dir():
        return Path(env_root)
    return Path(__file__).resolve().parent.parent.parent


def resolve_state_home() -> Path:
    """Return active RIG local state directory."""
    if os.environ.get("RIG_STATE_HOME"):
        return Path(os.environ["RIG_STATE_HOME"]).expanduser()
    xdg = os.environ.get("XDG_STATE_HOME")
    base = Path(xdg).expanduser() if xdg else Path.home() / ".local" / "state"
    return base / "rig"


def resolve_project_roots_file() -> Path:
    """Return path to project-roots file."""
    if os.environ.get("RIG_PROJECT_ROOTS"):
        return Path(os.environ["RIG_PROJECT_ROOTS"]).expanduser()
    return resolve_state_home() / "project-roots"


def read_config_lines(path: Path) -> list[str]:
    """Read non-empty non-comment lines from a config file."""
    if not path.is_file():
        return []
    out: list[str] = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            out.append(line)
    return out


def resolve_workspace_chain(root: str | Path, workspace: str) -> list[str]:
    """Resolve workspace inheritance chain from parent(s) to child via workspace.json `extends`."""
    root_path = Path(root)
    ws_dir = root_path / "workspaces"
    chain: list[str] = []
    visiting: set[str] = set()
    visited: set[str] = set()

    def _visit(name: str) -> None:
        if name in visited:
            return
        if name in visiting:
            raise ValueError(f"Workspace inheritance cycle detected involving '{name}'.")
        visiting.add(name)
        meta_path = ws_dir / name / "workspace.json"
        if meta_path.is_file():
            try:
                meta = json.loads(meta_path.read_text(encoding="utf-8", errors="replace"))
            except json.JSONDecodeError as exc:
                raise ValueError(f"Invalid JSON in {meta_path}: {exc}") from exc
            extends = meta.get("extends")
            parents = [extends] if isinstance(extends, str) else list(extends or [])
            for parent in parents:
                if parent and isinstance(parent, str):
                    _visit(parent)
        visiting.remove(name)
        visited.add(name)
        chain.append(name)

    _visit(workspace)
    return chain


def resolve_workspace_vault(root: str | Path, workspace: str) -> Path:
    """Resolve Obsidian vault path from RIG_NOTES_VAULT or workspace.json `vault` along inheritance chain."""
    env_vault = os.environ.get("RIG_NOTES_VAULT")
    if env_vault:
        return Path(os.path.expandvars(env_vault)).expanduser()
    ws_dir = Path(root) / "workspaces"
    for ws in reversed(resolve_workspace_chain(root, workspace)):
        meta_path = ws_dir / ws / "workspace.json"
        if meta_path.is_file():
            try:
                meta = json.loads(meta_path.read_text(encoding="utf-8", errors="replace"))
            except json.JSONDecodeError:
                continue
            vault_raw = meta.get("vault")
            if vault_raw and isinstance(vault_raw, str):
                return Path(os.path.expandvars(vault_raw)).expanduser()
    return Path.home() / "notes"


def resolve_workset_config(root: str | Path, workspace: str) -> dict:
    """Resolve merged `workset` settings from workspace.json along inheritance chain."""
    merged: dict = {
        "dir_mode": "flat",
        "parent_mode": "note",
        "parent_note": "Worksets",
        "statuses": ["todo", "wip", "blocked", "done"],
        "default_status": "wip",
    }
    ws_dir = Path(root) / "workspaces"
    for ws in resolve_workspace_chain(root, workspace):
        meta_path = ws_dir / ws / "workspace.json"
        if meta_path.is_file():
            try:
                meta = json.loads(meta_path.read_text(encoding="utf-8", errors="replace"))
            except json.JSONDecodeError:
                continue
            ws_cfg = meta.get("workset")
            if isinstance(ws_cfg, dict):
                merged.update(ws_cfg)
    return merged


DECIDE_DEFAULT_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/decisions"


def call_gemini_decisions(
    input_data: object,
    questions: dict[str, dict[str, object]],
    *,
    api_key: str,
    dry_run: bool = False,
    timeout: float = 30.0,
) -> dict:
    """Call Gemini Decisions API with global weekly quota & input-size guards."""
    max_chars = int(os.environ.get("RIG_DECIDE_MAX_CHARS", "12000"))
    max_bytes = int(os.environ.get("RIG_DECIDE_MAX_BYTES", str(25 * 1024 * 1024)))
    weekly_limit = int(os.environ.get("RIG_DECIDE_WEEKLY_LIMIT", "200"))

    if isinstance(input_data, str) and len(input_data) > max_chars:
        raise RuntimeError(f"Decide input exceeds {max_chars} chars ({len(input_data)}).")

    payload_bytes = json.dumps({"model": "gemini-decision-1", "input": input_data, "questions": questions}).encode("utf-8")
    if len(payload_bytes) > max_bytes:
        raise RuntimeError(f"Decide payload exceeds {max_bytes} bytes ({len(payload_bytes)}).")

    state_root = Path(os.environ.get("RIG_STATE_HOME") or (Path.home() / ".local" / "state" / "rig")).expanduser()
    usage_file = state_root / "decide-usage.json"
    from datetime import date

    week_key = date.today().strftime("%G-W%V")
    usage = {"week": week_key, "count": 0}
    if usage_file.is_file():
        try:
            loaded = json.loads(usage_file.read_text(encoding="utf-8"))
            if loaded.get("week") == week_key:
                usage["count"] = int(loaded.get("count", 0))
        except (OSError, ValueError):
            pass

    if usage["count"] >= weekly_limit:
        raise RuntimeError(f"Weekly Gemini Decisions limit reached ({usage['count']}/{weekly_limit} for {week_key}).")

    if dry_run:
        return {"dry_run": True, "answers": {k: {"choice": "dry-run", "confidence": 1.0} for k in questions}}

    import urllib.error
    import urllib.request

    endpoint = os.environ.get("RIG_DECIDE_ENDPOINT") or DECIDE_DEFAULT_ENDPOINT
    req = urllib.request.Request(
        endpoint,
        data=payload_bytes,
        method="POST",
        headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = json.loads(resp.read().decode("utf-8", errors="replace"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"HTTP {exc.code}: {detail}") from exc

    usage["count"] += 1
    try:
        usage_file.parent.mkdir(parents=True, exist_ok=True)
        usage_file.write_text(json.dumps(usage, indent=2) + "\n", encoding="utf-8")
    except OSError:
        pass
    return body
