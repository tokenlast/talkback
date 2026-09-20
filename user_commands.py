"""Exact plain-text phrase mappings. No eval, shell commands, or recursive macros."""
from __future__ import annotations

import os
from pathlib import Path
import re


def phrase_key(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip().rstrip(".! ").casefold()


def parse_commands(text: str) -> dict[str, str]:
    if len(text.encode("utf-8")) > 65536:
        raise ValueError("Command list exceeds 64 KB")
    result = {}
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.count("=>") != 1:
            raise ValueError(f"Command line {number}: use phrase => command")
        phrase, command = (part.strip() for part in line.split("=>", 1))
        key = phrase_key(phrase)
        if not key or not command or len(phrase) > 200 or len(command) > 500:
            raise ValueError(f"Command line {number}: empty or too long")
        if key in result:
            raise ValueError(f"Command line {number}: duplicate phrase")
        result[key] = command
    return result


def load_commands() -> dict[str, str]:
    path = os.environ.get("TALKBACK_COMMANDS_FILE")
    if not path:
        return {}
    file = Path(path)
    if not file.exists():
        return {}
    with file.open(encoding="utf-8") as handle:
        return parse_commands(handle.read(65537))


def remove_wake_phrase(text: str, wake: str) -> str | None:
    if not wake.strip():
        return text
    match = re.match(r"^\s*" + re.escape(wake.strip()) + r"(?:[,.:!\s]+)(.+)$", text, re.I)
    return match[1] if match else None
