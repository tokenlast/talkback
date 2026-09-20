"""Conservative, on-device command admission. Never logs ambient transcripts.

This is an intent filter, not speaker identification: a recording saying an
accepted command is indistinguishable from a person saying it.
"""
from __future__ import annotations

import re

_NUMBERS = dict(zip(
    "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty".split(),
    range(21),
))
_NUMBER = "(?:" + "|".join(_NUMBERS) + ")"
_NEGATED_OR_DISCUSSION = re.compile(
    r"\b(?:not|don't|dont|do not|never|without|unless|if|maybe|perhaps|should|would|could|"
    r"said|says|say|saying|example|means|mean|remember|yesterday|tomorrow|later|cancel|"
    r"actually|instead|but|because|whether|why|how)\b", re.I,
)
_COMMAND = re.compile(
    r"^(?:turn|mute|unmute|solo|unsolo|arm|disarm|lower|raise|increase|decrease|reduce|boost|"
    r"pan|set|rename|play|stop|start|resume|continue|record|undo|redo|capture|tap|"
    r"enable|disable|fold|unfold|launch|quantize|quantise|double|duplicate|"
    r"add|insert|load|open|put|drop|throw|create|make)\b", re.I,
)


def admit_voice(text: object) -> str | None:
    if not isinstance(text, str) or not 1 <= len(text) <= 500:
        return None
    value = re.sub(r"\s+", " ", text.replace("’", "'")).strip()
    # A quoted command or a question about an operation is not an instruction.
    if any(char in value for char in ('"', '“', '”', '?')):
        return None
    value = re.sub(r"[.!]+$", "", value).strip()
    value = re.sub(r"^(?:(?:okay|ok|hey talkback|talkback|please)[, ]+)+", "", value, flags=re.I)
    value = re.sub(r"^(?:can you|could you|would you)\s+", "", value, flags=re.I)
    value = re.sub(r"\btrakt\s+(?=\w)", "track ", value, flags=re.I)
    if _NEGATED_OR_DISCUSSION.search(value) or not _COMMAND.match(value):
        return None
    value = re.sub(rf"\b(track|clip|scene|bar|slot)\s+({_NUMBER})\b",
                   lambda m: m[1] + " " + str(_NUMBERS[m[2].lower()]), value, flags=re.I)
    value = re.sub(rf"\b({_NUMBER})(?=\s+(?:decibels?|d\s*b|percent|bpm)\b)",
                   lambda m: str(_NUMBERS[m[1].lower()]), value, flags=re.I)
    value = re.sub(r"\b(?:decibels?|d\s+b)\b", "dB", value, flags=re.I)
    value = re.sub(r"\bminus\s+(?=\d+(?:\.\d+)?\s*dB\b)", "-", value, flags=re.I)
    # Arm first. Executing record before arm can lose the beginning of a take.
    match = re.fullmatch(r"start recording[, ]+(?:and )?arm (.+)", value, re.I)
    if match:
        value = f"arm {match[1]} and start recording"
    return value
