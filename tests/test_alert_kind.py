# -*- coding: utf-8 -*-
"""stdlib-unittest für classify_entropy_alert (keine Dritt-Deps)."""

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from alert_kind import classify_entropy_alert, kv_preamble


class TestClassifyEntropyAlert(unittest.TestCase):
    def test_single_abs(self):
        k = classify_entropy_alert(1, 1, 0, 25)
        self.assertEqual(k.kind, "abs")
        self.assertEqual(k.tag_block, "[abs]")

    def test_single_jump(self):
        k = classify_entropy_alert(1, 0, 1, 25)
        self.assertEqual(k.kind, "jump")
        self.assertEqual(k.tag_block, "[jump]")

    def test_fifteen_abs_only(self):
        k = classify_entropy_alert(15, 15, 0, 25)
        self.assertEqual(k.kind, "abs")
        self.assertEqual(k.tag_block, "[abs]")

    def test_fifteen_mixed(self):
        k = classify_entropy_alert(15, 12, 6, 25)
        self.assertEqual(k.kind, "jump")
        self.assertEqual(k.tag_block, "[jump][abs]")

    def test_burst_with_jumps(self):
        k = classify_entropy_alert(40, 31, 12, 25)
        self.assertEqual(k.kind, "jump")
        self.assertEqual(k.tag_block, "[jump][abs][burst]")

    def test_burst_boundary_inclusive(self):
        k = classify_entropy_alert(25, 25, 0, 25)
        self.assertEqual(k.kind, "abs")
        self.assertEqual(k.tag_block, "[abs][burst]")

    def test_just_below_burst(self):
        k = classify_entropy_alert(24, 24, 0, 25)
        self.assertEqual(k.kind, "abs")
        self.assertEqual(k.tag_block, "[abs]")

    def test_burst_disabled(self):
        k = classify_entropy_alert(100, 100, 0, 0)
        self.assertEqual(k.kind, "abs")
        self.assertEqual(k.tag_block, "[abs]")

    def test_defensive_empty(self):
        k = classify_entropy_alert(0, 0, 0, 25)
        self.assertEqual(k.kind, "entropy")
        self.assertEqual(k.tag_block, "[entropy]")

    def test_negative_inputs_clamped(self):
        k = classify_entropy_alert(-3, -1, -1, -5)
        self.assertEqual(k.kind, "entropy")
        self.assertEqual(k.tag_block, "[entropy]")

    def test_subject_spacing(self):
        k = classify_entropy_alert(15, 12, 6, 25)
        subject = f"[NAS-EntropyWatcher] {k.tag_block} 15 neue verdächtige Datei(en) auf pi-nas"
        self.assertEqual(
            subject,
            "[NAS-EntropyWatcher] [jump][abs] 15 neue verdächtige Datei(en) auf pi-nas",
        )

    def test_kv_preamble_empty_as_dash(self):
        text = kv_preamble([
            ("Alert-Kind", "jump"),
            ("Max-Jump-Delta", None),
            ("Source", ""),
        ])
        self.assertEqual(
            text,
            "Alert-Kind: jump\nMax-Jump-Delta: -\nSource: -",
        )


if __name__ == "__main__":
    unittest.main()
