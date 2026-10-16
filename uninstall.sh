#!/usr/bin/env bash
# Undo yet-another-gnomintosh. Repentance, in shell.
#
#   ./uninstall.sh                  extensions off, keyd off, X11 launchers gone,
#                                   settings back to the snapshot taken at install
#   ./uninstall.sh --login-screen   also put the GDM login screen back to stock
#   ./uninstall.sh --hibernate-fix  also drop the hibernate power-off tweak
#   ./uninstall.sh --keep-settings  leave your current settings alone
#
# Forked extensions are moved to the backups folder, not deleted. WhiteSur stays
# installed (it is harmless when unused); remove ~/.themes/WhiteSur* and
# ~/.local/share/icons/WhiteSur* by hand if you want it gone.
set -euo pipefail

DATA="${XDG_DATA_HOME:-$HOME/.local/share}/yet-another-gnomintosh"
EXT="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"
OUT="$DATA/backups/uninstalled-$(date +%Y-%m-%d_%H%M%S)"

say()  { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }

login=0 hibernate=0 keep=0
for a in "$@"; do
  case "$a" in
    --login-screen) login=1 ;;
    --hibernate-fix) hibernate=1 ;;
    --keep-settings) keep=1 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option $a" >&2; exit 1 ;;
  esac
done
mkdir -p "$OUT"

say "Settings"
if [ "$keep" = 1 ]; then
  note "left as they are"
else
  snapshot=$(ls -1d "$DATA"/backups/*/dconf-before.ini 2>/dev/null | head -1 || true)
  if [ -n "$snapshot" ]; then
    dconf dump / > "$OUT/dconf-at-uninstall.ini"
    # `dconf load` only adds keys, so clear what the installer wrote first.
    for p in /org/gnome/shell/extensions/ /org/gnome/desktop/wm/keybindings/ \
             /org/gnome/desktop/wm/preferences/ /org/gnome/desktop/interface/ \
             /org/gnome/mutter/ /org/gnome/shell/keybindings/ \
             /org/gnome/settings-daemon/plugins/media-keys/; do
      dconf reset -f "$p"
    done
    # The installer also set these two outside those paths. A snapshot taken
    # on a fresh system has neither key, so loading it would leave them set.
    gsettings reset org.gnome.shell enabled-extensions
    gsettings reset org.gnome.shell disable-extension-version-validation
    dconf load / < "$snapshot"
    note "restored $snapshot (current settings saved in $OUT)"
  else
    gsettings reset org.gnome.shell enabled-extensions
    gsettings reset org.gnome.shell disable-extension-version-validation
    note "no snapshot found; just turned the extensions off"
  fi
fi

say "Forked extensions"
for d in "$EXT"/*@skye-xd.github.io; do
  [ -d "$d" ] || continue
  mv "$d" "$OUT/"
  note "moved $(basename "$d") to $OUT"
done

say "keyd"
if systemctl is-enabled keyd >/dev/null 2>&1; then
  sudo systemctl disable --now keyd
  sudo rm -f /etc/keyd/default.conf /etc/keyd/macos-ctrl
  note "stopped; Super is plain Super again (the binary stays in /usr/local)"
fi
rm -rf "$EXT/keyd@keyd.rvaiya.github.com" "$HOME/.local/bin/macos-ctrl"

say "X11 launchers for the global menu"
systemctl --user disable --now x11-menus.path x11-menus.service >/dev/null 2>&1 || true
rm -f "$HOME/.config/systemd/user/x11-menus.path" "$HOME/.config/systemd/user/x11-menus.service"
for f in "$HOME"/.local/share/applications/*.desktop; do
  grep -q '^X-GlobalMenu-Source=' "$f" 2>/dev/null && rm -f "$f" && note "removed $(basename "$f")"
done
rm -f "$HOME/.local/bin/x11-menus"
# Take back only what was added: the x11 socket, Telegram's QT_QPA_PLATFORM and
# the registrar bus name. `--nosocket=x11` would instead *deny* x11, even to an
# app whose own manifest asks for it.
revert_flatpak_override() { # app-id
  python3 -I - "$HOME/.local/share/flatpak/overrides/$1" <<'PY'
import configparser, os, sys
path = sys.argv[1]
if not os.path.exists(path):
    sys.exit()
kf = configparser.ConfigParser(interpolation=None, delimiters=('=',))
kf.optionxform = str
kf.read(path)
if kf.has_option('Context', 'sockets'):
    keep = [s for s in kf['Context']['sockets'].split(';') if s and s != 'x11']
    if keep:
        kf['Context']['sockets'] = ';'.join(keep) + ';'
    else:
        kf.remove_option('Context', 'sockets')
for section, key in (('Environment', 'QT_QPA_PLATFORM'),
                     ('Session Bus Policy', 'com.canonical.AppMenu.Registrar')):
    if kf.has_section(section):
        kf.remove_option(section, key)
for section in [s for s in kf.sections() if not kf[s]]:
    kf.remove_section(section)
if kf.sections():
    with open(path, 'w') as f:
        kf.write(f, space_around_delimiters=False)
else:
    os.remove(path)
PY
}
grants="$HOME/.config/x11-menus/flatpak-grants"
for app in org.telegram.desktop $(cat "$grants" 2>/dev/null); do
  revert_flatpak_override "$app" && note "flatpak $app: our x11 override taken back"
done
rm -f "$grants"

if [ "$login" = 1 ]; then
  say "Login screen"
  sudo systemctl disable --now gdm-wallpaper-sync.path gdm-monitors-sync.path >/dev/null 2>&1 || true
  sudo rm -f /etc/systemd/system/gdm-{wallpaper,monitors}-sync.{path,service} \
             /usr/local/bin/gdm-wallpaper-sync /usr/local/bin/gdm-monitors-sync
  pristine=/usr/local/share/gdm-wallpaper-sync/theme-orig.gresource
  if [ -f "$pristine" ]; then
    sudo install -m644 "$pristine" /usr/share/gnome-shell/gnome-shell-theme.gresource
    sudo rm -rf /usr/local/share/gdm-wallpaper-sync
  fi
  sudo rm -rf /usr/local/share/gnome-shell/extensions/gdm-extension@pratap.fastmail.fm
  sudo rm -f /etc/dconf/db/gdm.d/99-gdm-extension
  if [ -f "$DATA/created-gdm-profile" ]; then
    sudo rm -f /etc/dconf/profile/gdm
    rm -f "$DATA/created-gdm-profile"
  fi
  sudo dconf update
  sudo systemctl daemon-reload
  note "stock login screen from the next time it starts"
fi

if [ "$hibernate" = 1 ]; then
  say "Hibernate"
  sudo rm -f /etc/systemd/sleep.conf.d/hibernate-mode.conf
  note "back to the firmware's own power-off"
fi

say "Absolved. Log out and back in to finish."
