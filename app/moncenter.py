#!/usr/bin/env python3
"""MonCenter: a gaming-style DDC/CI control panel on top of ddcutil."""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

from PySide6.QtCore import (Q_ARG, SLOT, Property, QMetaObject, QObject, QProcess, QStandardPaths, QTimer,
                            Signal, Slot)
from PySide6.QtDBus import QDBusConnection
from PySide6.QtGui import QAction, QActionGroup, QIcon
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

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


def gdbus(dest, path, method, *args, wait=True):
    """Call a session D-Bus method; args are GVariant text. gdbus marshals the int arrays that QtDBus from Python can't."""
    cmd = ["gdbus", "call", "--session", "--dest", dest, "--object-path", path, "--method", method, *args]
    try:
        if not wait:
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
        return subprocess.run(cmd, capture_output=True, timeout=3).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def osd(text):
    """Plasma's on-screen popup, the one volume and brightness keys use."""
    gdbus("org.kde.plasmashell", "/org/kde/osdService", "org.kde.osdService.showText",
          '"video-display"', json.dumps(text), wait=False)


# Meta+Alt+1..N for the modes. Qt key codes: Meta 0x10000000, Alt 0x08000000, '0' 0x30.
MODE_KEY_BASE = 0x10000000 | 0x08000000 | 0x30


class Shortcuts(QObject):
    """Global shortcuts through KDE's kglobalaccel; users can rebind them in System Settings > Shortcuts."""
    pressed = Signal(int)

    def __init__(self, names):
        super().__init__()
        kga = ("org.kde.kglobalaccel", "/kglobalaccel")
        for i, name in enumerate(names):
            aid = json.dumps(["moncenter", f"mode-{i}", "MonCenter", f"{name} mode"])
            keys = f"@ai [{MODE_KEY_BASE + i + 1}]"
            # flags: IsDefault (8) sets the default; then 0 loads the user's own binding if they changed it.
            if not (gdbus(*kga, "org.kde.KGlobalAccel.doRegister", aid)
                    and gdbus(*kga, "org.kde.KGlobalAccel.setShortcut", aid, keys, "uint32 8")
                    and gdbus(*kga, "org.kde.KGlobalAccel.setShortcut", aid, keys, "uint32 0")):
                print("moncenter: global shortcuts unavailable (needs KDE's kglobalaccel)", file=sys.stderr)
                return
        QDBusConnection.sessionBus().connect("org.kde.kglobalaccel", "/component/moncenter",
                                             "org.kde.kglobalaccel.Component", "globalShortcutPressed",
                                             self, SLOT("_pressed(QString,QString,qlonglong)"))

    @Slot(str, str, "qlonglong")
    def _pressed(self, _component, action, _timestamp):
        if action.startswith("mode-"):
            self.pressed.emit(int(action[5:]))


AUTOSTART = Path(QStandardPaths.writableLocation(QStandardPaths.GenericConfigLocation)) / "autostart/moncenter.desktop"


def set_autostart(on):
    if not on:
        AUTOSTART.unlink(missing_ok=True)
        return
    AUTOSTART.parent.mkdir(parents=True, exist_ok=True)
    AUTOSTART.write_text("[Desktop Entry]\nType=Application\nName=MonCenter\nIcon=video-display\n"
                         f'Exec="{Path(__file__).resolve()}" --tray\n')


def selftest():
    values, model, serial = parse(
        "   Monitor:          GSM:LG ULTRAGEAR:000TEST00000\n"
        "VCP 10 C 36 100\nVCP 14 SNC x03\nVCP 1A C 50 100\n"
        "VCP AE C 31580 0\nVCP C9 CNC xff xff x03 x00\n"
    )
    assert values == {"10": 36, "14": 3, "1A": 50, "AE": 31580, "C9": "3.0"}, values
    assert (model, serial) == ("LG ULTRAGEAR", "000TEST00000")
    print("ok")


def main():
    tray_only = "--tray" in sys.argv  # autostart: stay in the tray
    QQuickStyle.setStyle("Basic")  # fully restylable controls
    app = QApplication(sys.argv)
    app.setApplicationName("MonCenter")
    app.setOrganizationName("moncenter")
    app.setDesktopFileName("moncenter")
    if not QIcon.themeName():
        QIcon.setThemeName("breeze-dark")
    app.setWindowIcon(QIcon.fromTheme("video-display"))

    # One instance: a second launch asks the running one to show its window, then exits.
    socket_name = f"moncenter-{os.getuid()}"
    probe = QLocalSocket()
    probe.connectToServer(socket_name)
    if probe.waitForConnected(300):
        if not tray_only:
            probe.write(b"show")
            probe.waitForBytesWritten(300)
        return 0
    QLocalServer.removeServer(socket_name)
    server = QLocalServer()
    server.listen(socket_name)

    has_tray = QSystemTrayIcon.isSystemTrayAvailable()
    app.setQuitOnLastWindowClosed(not has_tray)  # with a tray, closing the window keeps shortcuts working

    ddc = Ddc()
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("ddc", ddc)
    engine.rootContext().setContextProperty("startHidden", tray_only and has_tray)
    engine.load(Path(__file__).resolve().with_name("Main.qml"))
    if not engine.rootObjects():
        return 1
    win = engine.rootObjects()[0]
    names = [m["name"] for m in win.property("modes").toVariant()]

    def show():
        win.show()
        win.raise_()
        win.requestActivate()

    def select_mode(i):
        QMetaObject.invokeMethod(win, "selectMode", Q_ARG("QVariant", i))
        osd(f"{names[i]} mode")

    server.newConnection.connect(lambda: (server.nextPendingConnection(), show()))
    shortcuts = Shortcuts(names)
    shortcuts.pressed.connect(select_mode)

    if has_tray:
        menu = QMenu()
        menu.addAction(QIcon.fromTheme("video-display"), "Open MonCenter", show)
        menu.addSeparator()
        group = QActionGroup(menu)
        mode_actions = []
        for i, name in enumerate(names):
            a = QAction(f"{name}\tMeta+Alt+{i + 1}", group, checkable=True)
            a.triggered.connect(lambda _=False, i=i: select_mode(i))
            menu.addAction(a)
            mode_actions.append(a)
        menu.addSeparator()
        login = menu.addAction("Start at login")
        login.setCheckable(True)
        login.setChecked(AUTOSTART.exists())
        login.toggled.connect(set_autostart)
        menu.addAction(QIcon.fromTheme("application-exit"), "Quit", app.quit)
        menu.aboutToShow.connect(lambda: mode_actions[win.property("currentMode")].setChecked(True))

        tray = QSystemTrayIcon(QIcon.fromTheme("video-display"))
        tray.setToolTip("MonCenter")
        tray.setContextMenu(menu)
        tray.activated.connect(lambda r: (win.hide() if win.isVisible() else show())
                               if r == QSystemTrayIcon.Trigger else None)
        tray.show()

    ddc.refresh()
    return app.exec()


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(selftest())
    sys.exit(main())
