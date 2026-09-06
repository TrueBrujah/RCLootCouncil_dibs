#!/usr/bin/env python3
"""Shared helpers for Spec-Kit Python wrappers.

These wrappers delegate to the canonical PowerShell scripts used in this repo.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def _repo_root_from_here() -> Path:
    # .specify/scripts/python/common.py -> repo root is 3 parents up
    return Path(__file__).resolve().parents[3]


def run_ps_script(ps_script_name: str) -> int:
    repo_root = _repo_root_from_here()
    script_path = repo_root / ".specify" / "scripts" / "powershell" / ps_script_name
    if not script_path.exists():
        sys.stderr.write(f"ERROR: Missing PowerShell script: {script_path}\n")
        return 1

    cmd = ["pwsh", "-File", str(script_path), *sys.argv[1:]]
    completed = subprocess.run(cmd, cwd=str(repo_root), check=False)
    return int(completed.returncode)