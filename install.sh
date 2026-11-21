#!/usr/bin/env bash
# MonCenter installer: checks and installs dependencies, sets up DDC/CI access, installs the app for
# the current user and tells you what your monitor supports. Safe to re-run.
#
#   ./install.sh               install or update
#   ./install.sh --no-deps     skip package installation
#   ./install.sh --widget      also install the KDE Plasma 6 panel widget
#   ./install.sh --uninstall   remove everything this script installed
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/moncenter"
BIN="$HOME/.local/bin/moncenter"
DESKTOP="${XDG_DATA_HOME:-$HOME/.local/share}/applications/moncenter.desktop"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/moncenter.desktop"

deps=1 widget=0 uninstall=0
for a in "$@"; do
  case "$a" in
    --no-deps) deps=0 ;;
    --widget) widget=1 ;;
    --uninstall) uninstall=1 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown option: $a (try --help)" >&2; exit 2 ;;
  esac
done

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m  %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

if ((uninstall)); then
  say "Removing MonCenter"
  pkill -f "$PREFIX/moncenter.py" 2>/dev/null || true
  rm -rf "$PREFIX"; rm -f "$BIN" "$DESKTOP" "$AUTOSTART"
  have kpackagetool6 && kpackagetool6 -t Plasma/Applet -r org.andrei.ddcpanel >/dev/null 2>&1 || true
  echo "Done. System packages and /etc/modules-load.d/i2c-dev.conf were left alone."
  exit 0
fi

[[ $EUID -ne 0 ]] || die "Run as your normal user, not root. sudo is used only where needed."

# --- dependencies -----------------------------------------------------------------------------
pyside_ok() { python3 -c 'import PySide6.QtQml, PySide6.QtWidgets, PySide6.QtDBus' 2>/dev/null; }

install_pkgs() {
  local sudo=""; have sudo && sudo=sudo
  if have pacman; then
    # PySide6 is in the official repos on current Arch/CachyOS, and in the AUR on older setups.
    $sudo pacman -S --needed --noconfirm ddcutil i2c-tools python glib2 2>/dev/null || $sudo pacman -S --needed ddcutil i2c-tools python glib2
    pyside_ok || $sudo pacman -S --needed --noconfirm pyside6 2>/dev/null \
      || { have yay && yay -S --needed pyside6; } \
      || { have paru && paru -S --needed pyside6; } || true
  elif have apt-get; then
    $sudo apt-get install -y ddcutil i2c-tools python3 python3-pyside6.qtqml python3-pyside6.qtwidgets \
      python3-pyside6.qtdbus python3-pyside6.qtquick python3-pyside6.qtnetwork libglib2.0-bin \
      || $sudo apt-get install -y ddcutil i2c-tools python3 python3-pyside6 libglib2.0-bin
  elif have dnf; then
    $sudo dnf install -y ddcutil i2c-tools python3 python3-pyside6 glib2
  elif have zypper; then
    $sudo zypper install -y ddcutil i2c-tools python3 python3-pyside6 glib2-tools
  else
    warn "Unknown package manager. Install ddcutil, i2c-tools, pyside6 and gdbus yourself, then re-run with --no-deps."
  fi
}

if ((deps)); then
  if have ddcutil && pyside_ok && have gdbus; then
    say "Dependencies already installed"
  else
    say "Installing dependencies (ddcutil, pyside6, gdbus)"
    install_pkgs
  fi
fi
have ddcutil || die "ddcutil is missing"
pyside_ok || die "PySide6 (QtQml, QtWidgets, QtDBus) is missing for $(python3 -V)"
have gdbus || warn "gdbus not found: global shortcuts and on-screen popups will be unavailable"

# --- DDC/CI access ------------------------------------------------------------------------------
if ! ls /dev/i2c-* >/dev/null 2>&1; then
  say "Loading the i2c-dev kernel module"
  sudo modprobe i2c-dev || warn "could not load i2c-dev"
fi
if [[ ! -e /etc/modules-load.d/i2c-dev.conf ]] && ! grep -rqs '^i2c[-_]dev' /etc/modules-load.d /usr/lib/modules-load.d 2>/dev/null; then
  say "Making i2c-dev load at boot"
  echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
fi

detect() { ddcutil detect --terse 2>&1 || true; }
out="$(detect)"
if ! grep -q '^Display' <<<"$out"; then
  # No display found: usually missing permissions on /dev/i2c-*.
  if ! [[ -r /dev/i2c-0 && -w /dev/i2c-0 ]] 2>/dev/null && ! id -nG | grep -qw i2c; then
    say "Giving your user access to /dev/i2c-* (group i2c)"
    getent group i2c >/dev/null || sudo groupadd -r i2c
    sudo usermod -aG i2c "$USER"
    echo 'KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"' | sudo tee /etc/udev/rules.d/45-i2c.rules >/dev/null
    sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=i2c-dev || true
    warn "Log out and back in so the new group applies, then run ./install.sh again."
  fi
fi

# --- install ------------------------------------------------------------------------------------
say "Installing to $PREFIX"
mkdir -p "$PREFIX" "$(dirname "$BIN")" "$(dirname "$DESKTOP")"
install -m 755 "$SRC/app/moncenter.py" "$PREFIX/moncenter.py"
install -m 644 "$SRC/app/Main.qml" "$PREFIX/Main.qml"
ln -sf "$PREFIX/moncenter.py" "$BIN"
sed "s|^Exec=.*|Exec=$BIN|" "$SRC/app/moncenter.desktop" > "$DESKTOP"
have update-desktop-database && update-desktop-database "$(dirname "$DESKTOP")" 2>/dev/null || true
# Keep the autostart entry pointing at the installed copy if the user enabled it.
[[ -e "$AUTOSTART" ]] && printf '[Desktop Entry]\nType=Application\nName=MonCenter\nIcon=video-display\nExec="%s" --tray\n' "$PREFIX/moncenter.py" > "$AUTOSTART"

if ((widget)); then
  if have kpackagetool6; then
    say "Installing the Plasma panel widget"
    kpackagetool6 -t Plasma/Applet -i "$SRC/package" 2>/dev/null || kpackagetool6 -t Plasma/Applet -u "$SRC/package"
  else
    warn "kpackagetool6 not found: skipping the widget (needs KDE Plasma 6)"
  fi
fi

case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "$HOME/.local/bin is not in your PATH; use the start menu entry or add it." ;; esac

# --- verify and report on the monitor ---------------------------------------------------------
say "Self-test"
python3 -I "$PREFIX/moncenter.py" --selftest

say "Monitors"
out="$(detect)"
if grep -q '^Display' <<<"$out"; then
  grep -E '^Display|Monitor:|DRM_connector|I2C bus' <<<"$out" | sed 's/^ */   /'
  n=$(grep -c '^Display' <<<"$out")
  ((n > 1)) && warn "$n displays found; MonCenter controls only the first one."
  caps="$(ddcutil capabilities --terse 2>/dev/null || true)"
  feats=""
  for pair in "10:brightness" "12:contrast" "87:sharpness" "14:color presets" "16:RGB gain" "60:input select" "62:volume" "8D:mute"; do
    grep -qE "[( ]${pair%%:*}[( )]" <<<"$caps" && feats+="${pair#*:}, "
  done
  echo "   MonCenter will show: ${feats%, }"
else
  warn "No DDC/CI monitor detected. Check the cable (DP/HDMI, not an adapter or dock), enable DDC/CI in the monitor's OSD, and see 'ddcutil environment'."
fi

say "Installed. Run 'moncenter' or open it from the start menu."
