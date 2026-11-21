"""Tests that need no monitor: output parsers, QML load, installer syntax. Run: tests/run.sh"""
import os
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "app"))
import moncenter as m  # noqa: E402

AOC_CAPS = ("Unparsed capabilities string: (prot(monitor)type(LCD)model(24G2U)cmds(01 02 03)"
            "vcp(02 10 12 14(01 05 06 08 0B) 16 18 1A 60(01 0F 11 12 ) 86(01 02) AC AE)mccs_ver(2.2))")


class Parse(unittest.TestCase):
    def test_continuous_and_simple_values(self):
        v, model, serial = m.parse("   Monitor:   GSM:LG ULTRAGEAR:000TEST\nVCP 10 C 36 100\nVCP 14 SNC x03\n"
                                   "VCP AE C 31580 0\nVCP C9 CNC xff xff x03 x00\n")
        self.assertEqual(v, {"10": 36, "14": 3, "AE": 31580, "C9": "3.0"})
        self.assertEqual((model, serial), ("LG ULTRAGEAR", "000TEST"))

    def test_discrete_feature_reported_as_continuous(self):
        # AOC answers color preset (14) and volume (62) as CNC; the value is the last byte.
        v, *_ = m.parse("VCP 14 CNC x00 x0b x00 x05\nVCP 62 CNC x00 x64 x00 x4b\n")
        self.assertEqual(v, {"14": 5, "62": 75})

    def test_unreadable_features_are_skipped(self):
        v, *_ = m.parse("VCP 10 C 37 100\nVCP 8D ERR\nVCP C0 ERR\n")
        self.assertEqual(v, {"10": 37})


class Caps(unittest.TestCase):
    def test_aoc(self):
        caps = m.parse_caps(AOC_CAPS)
        self.assertEqual(caps["14"], [1, 5, 6, 8, 11])
        self.assertEqual(caps["60"], [1, 15, 17, 18])
        self.assertIn("AE", caps)
        self.assertNotIn("62", caps)
        self.assertNotIn("model", caps)

    def test_garbage(self):
        self.assertEqual(m.parse_caps(""), {})
        self.assertEqual(m.parse_caps("ddcutil: no display"), {})


class Qml(unittest.TestCase):
    def test_main_qml_loads(self):
        code = ("import sys; sys.path.insert(0, %r); import moncenter as m\n"
                "from PySide6.QtWidgets import QApplication\nfrom PySide6.QtQml import QQmlApplicationEngine\n"
                "from PySide6.QtQuickControls2 import QQuickStyle\nQQuickStyle.setStyle('Basic')\n"
                "a = QApplication([]); e = QQmlApplicationEngine(); ddc = m.Ddc()\n"
                "e.rootContext().setContextProperty('ddc', ddc); e.rootContext().setContextProperty('startHidden', False)\n"
                "e.load(%r); sys.exit(0 if e.rootObjects() else 1)\n") % (str(ROOT / "app"), str(ROOT / "app/Main.qml"))
        r = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True,
                           env={**os.environ, "QT_QPA_PLATFORM": "offscreen"}, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("Error", r.stderr)


class Installer(unittest.TestCase):
    def test_syntax_and_help(self):
        sh = str(ROOT / "install.sh")
        self.assertEqual(subprocess.run(["bash", "-n", sh]).returncode, 0)
        r = subprocess.run(["bash", sh, "--help"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0)
        self.assertIn("--uninstall", r.stdout)
        self.assertEqual(subprocess.run(["bash", sh, "--bogus"], capture_output=True).returncode, 2)


if __name__ == "__main__":
    unittest.main()
