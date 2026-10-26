#!/usr/bin/env python3
"""MonCenter: a gaming-style DDC/CI control panel on top of ddcutil."""
import re
import sys
from pathlib import Path

from PySide6.QtCore import Property, QObject, QProcess, QTimer, Signal, Slot
from PySide6.QtGui import QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle

# shortcut: drives ddcutil's default (first) display only; add --display N when a second monitor appears.
READ_CMD = "ddcutil detect --terse && ddcutil getvcp 10 12 87 14 16 18 1A 60 62 8D AE C0 C9 --terse"


def parse(out):
    """Turn `ddcutil detect/getvcp --terse` output into ({code: value}, model, serial)."""
    values, model, serial = {}, "", ""
    for line in out.splitlines():
        if m := re.match(r"VCP (\w\w) C (\d+)", line):
            values[m[1]] = int(m[2])
        elif m := re.match(r"VCP (\w\w) SNC x(\w+)", line):
            values[m[1]] = int(m[2], 16)
        elif m := re.match(r"VCP C9 CNC \S+ \S+ x(\w+) x(\w+)", line):
            values["C9"] = f"{int(m[1], 16)}.{int(m[2], 16)}"
        elif m := re.match(r"\s*Monitor:\s+\w+:([^:]+):(.*)", line):
            model, serial = m[1], m[2]
    return values, model, serial


class Ddc(QObject):
    changed = Signal()

    def __init__(self):
        super().__init__()
        self._values, self._pending = {}, {}
        self._model = self._serial = self._error = ""
        self._queue, self._job = [], ""
        self._proc = QProcess(self)
        self._proc.finished.connect(self._done)
        self._timer = QTimer(self, singleShot=True, interval=150)
        self._timer.timeout.connect(self._flush)

    values = Property("QVariantMap", lambda s: s._values, notify=changed)
    model = Property(str, lambda s: s._model, notify=changed)
    serial = Property(str, lambda s: s._serial, notify=changed)
    error = Property(str, lambda s: s._error, notify=changed)
    busy = Property(bool, lambda s: s._proc.state() != QProcess.NotRunning, notify=changed)

    @Slot()
    def refresh(self):
        self._queue.append(("read", READ_CMD))
        self._next()

    @Slot(str, int)
    def set(self, code, value):
        self.apply({code: value})

    @Slot("QVariantMap")
    def apply(self, values):
        values = {k: int(v) for k, v in values.items()}
        self._values = {**self._values, **values}
        self._pending.update(values)
        self.changed.emit()
        self._timer.start()

    def _flush(self):
        if self._pending:
            args = " ".join(f"{k} {v}" for k, v in self._pending.items())
            self._pending = {}
            self._queue.append(("set", f"ddcutil setvcp {args}"))
        self._next()

    def _next(self):
        if self._proc.state() != QProcess.NotRunning or not self._queue:
            return
        self._job, cmd = self._queue.pop(0)
        self._proc.start("sh", ["-c", cmd])
        self.changed.emit()

    def _done(self, code, _status):
        out = bytes(self._proc.readAllStandardOutput()).decode(errors="replace")
        err = bytes(self._proc.readAllStandardError()).decode(errors="replace")
        self._error = "" if code == 0 else (err or out).strip() or "ddcutil failed"
        if code == 0 and self._job == "read":
            values, self._model, self._serial = parse(out)
            # Keep edits that haven't reached the monitor yet.
            self._values = {**values, **self._pending}
        self.changed.emit()
        self._next()


def selftest():
    values, model, serial = parse(
        "   Monitor:          GSM:LG ULTRAGEAR:000TEST00000\n"
        "VCP 10 C 36 100\nVCP 14 SNC x03\nVCP 1A C 50 100\n"
        "VCP AE C 31580 0\nVCP C9 CNC xff xff x03 x00\n"
    )
    assert values == {"10": 36, "14": 3, "1A": 50, "AE": 31580, "C9": "3.0"}, values
    assert (model, serial) == ("LG ULTRAGEAR", "000TEST00000")
    print("ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(selftest())
    QQuickStyle.setStyle("Basic")  # fully restylable controls
    app = QGuiApplication(sys.argv)
    app.setApplicationName("MonCenter")
    app.setOrganizationName("moncenter")
    app.setDesktopFileName("moncenter")
    if not QIcon.themeName():
        QIcon.setThemeName("breeze-dark")
    app.setWindowIcon(QIcon.fromTheme("video-display"))
    ddc = Ddc()
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("ddc", ddc)
    engine.load(Path(__file__).resolve().with_name("Main.qml"))
    if not engine.rootObjects():
        sys.exit(1)
    ddc.refresh()
    sys.exit(app.exec())
