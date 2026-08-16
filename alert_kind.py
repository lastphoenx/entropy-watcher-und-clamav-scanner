# -*- coding: utf-8 -*-
"""Reine Alert-Klassifikation für EntropyWatcher-Mails (kein I/O, keine Dritt-Deps)."""

from typing import Any, List, NamedTuple, Tuple

DEFAULT_MAIL_BURST_MIN = 25
ALERT_TAG_JUMP = "jump"
ALERT_TAG_ABS = "abs"
ALERT_TAG_BURST = "burst"
ALERT_TAG_AV = "av"
ALERT_TAG_ENTROPY = "entropy"


class AlertKind(NamedTuple):
    """Klassifikation einer Entropy-Alert-Mail."""
    kind: str
    tags: Tuple[str, ...]
    tag_block: str


def classify_entropy_alert(
    n_total: int,
    n_abs: int,
    n_jump: int,
    burst_min: int,
) -> AlertKind:
    """Baut Subject-Tags: jump → abs → burst. kind = jump gewinnt vor abs."""
    n_total = max(0, int(n_total))
    n_abs = max(0, int(n_abs))
    n_jump = max(0, int(n_jump))
    try:
        burst_min = int(burst_min)
    except (TypeError, ValueError):
        burst_min = 0

    tags: List[str] = []
    if n_jump > 0:
        tags.append(ALERT_TAG_JUMP)
    if n_abs > 0:
        tags.append(ALERT_TAG_ABS)
    if not tags:
        tags.append(ALERT_TAG_ENTROPY)
    if burst_min > 0 and n_total >= burst_min:
        tags.append(ALERT_TAG_BURST)

    if n_jump > 0:
        kind = ALERT_TAG_JUMP
    elif n_abs > 0:
        kind = ALERT_TAG_ABS
    else:
        kind = ALERT_TAG_ENTROPY

    tag_block = "".join(f"[{t}]" for t in tags)
    return AlertKind(kind=kind, tags=tuple(tags), tag_block=tag_block)


def kv_preamble(fields: List[Tuple[str, Any]]) -> str:
    """ASCII Key: value Block. Leere Werte als '-'."""
    lines = []
    for key, val in fields:
        if val is None or val == "":
            rendered = "-"
        else:
            rendered = str(val)
        lines.append(f"{key}: {rendered}")
    return "\n".join(lines)
