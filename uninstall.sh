#!/usr/bin/env bash
# Undo yet-another-gnomintosh. Repentance, in shell.
#
#   ./uninstall.sh                  extensions off, keyd off, X11 launchers gone,
#                                   settings back to the snapshot taken at install
#   ./uninstall.sh --login-screen   also put the GDM login screen back to stock
#   ./uninstall.sh --hibernate-fix  also drop the hibernate power-off tweak
#   ./uninstall.sh --keep-settings  leave your current settings alone
#
# Forked extensions are moved to the backups folder, not deleted. WhiteSur's
# libadwaita files in ~/.config/gtk-4.0 go (they style every GTK4 app); the
# rest of WhiteSur stays installed, harmless unselected -- remove
# ~/.themes/WhiteSur* and ~/.local/share/icons/WhiteSur* by hand if wanted.
set -euo pipefail

USERDATA="${XDG_DATA_HOME:-$HOME/.local/share}"
DATA="$USERDATA/yet-another-gnomintosh"
EXT="$USERDATA/gnome-shell/extensions"
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
# The keyd step's first-run folder records what was there before the first
# install (it can be empty) and marks that the step ran at all; without it,
# whatever keyd setup is here is the user's own and stays. Once restored the
# folder is retired, so a later reinstall takes a fresh backup instead of
# trusting this one -- and losing whatever changed in between.
kb=$(ls -1d "$DATA"/backups/*/keyd 2>/dev/null | head -1 || true)
if [ -n "$kb" ]; then
  if systemctl is-enabled keyd >/dev/null 2>&1; then sudo systemctl disable --now keyd; fi
  sudo rm -f /etc/keyd/default.conf /etc/keyd/macos-ctrl
  restored=0
  for f in "$kb"/default.conf "$kb"/macos-ctrl; do
    if [ -f "$f" ]; then sudo install -m644 "$f" "/etc/keyd/${f##*/}"; restored=1; fi
  done
  if [ -f "$kb/.was-enabled" ]; then sudo systemctl enable --now keyd; fi
  if [ "$restored" = 1 ]; then
    note "your previous keyd config is back in /etc/keyd"
  else
    note "stopped; Super is plain Super again (the binary stays in /usr/local)"
  fi
  # The per-application mapper's config and the keyd group, as before install.
  if [ -f "$kb/app.conf" ]; then
    mkdir -p "$HOME/.config/keyd"
    cp -a "$kb/app.conf" "$HOME/.config/keyd/app.conf"
  else
    rm -f "$HOME/.config/keyd/app.conf"
    rmdir "$HOME/.config/keyd" 2>/dev/null || true
  fi
  if [ ! -f "$kb/.was-in-group" ] && id -nG "$USER" | grep -qw keyd; then
    sudo gpasswd -d "$USER" keyd >/dev/null && note "left the keyd group (from the next login)"
  fi
  rm -rf "$EXT/keyd@keyd.rvaiya.github.com" "$HOME/.local/bin/macos-ctrl"
  mv "$kb" "$kb.restored"
else
  note "the keyd step never ran; left alone"
fi

say "GTK4 (libadwaita) theme"
# WhiteSur styles every libadwaita app from here whatever theme is selected,
# so it does not stay "harmless when unused" like the rest of WhiteSur.
# Only if the theme step ever ran (its first-run folder marks that): after
# --skip theme the files there are the user's own. Retired once restored,
# like keyd's.
gtk4="$HOME/.config/gtk-4.0"
gb=$(ls -1d "$DATA"/backups/*/gtk-4.0 2>/dev/null | head -1 || true)
if [ -n "$gb" ]; then
  for e in gtk.css gtk-dark.css gtk-Light.css gtk-Dark.css assets windows-assets; do
    if [ -e "$gtk4/$e" ] || [ -L "$gtk4/$e" ]; then mv "$gtk4/$e" "$OUT/gtk-4.0-$e"; fi
  done
  mkdir -p "$gtk4"
  cp -a "$gb"/. "$gtk4"/
  mv "$gb" "$gb.restored"
  note "WhiteSur's libadwaita files moved to $OUT; what was there before put back"
else
  note "theme step never ran; ~/.config/gtk-4.0 left alone"
fi

say "X11 launchers for the global menu"
systemctl --user disable --now x11-menus.path x11-menus.service >/dev/null 2>&1 || true
rm -f "$HOME/.config/systemd/user/x11-menus.path" "$HOME/.config/systemd/user/x11-menus.service"
for f in "$HOME"/.local/share/applications/*.desktop; do
  grep -q '^X-GlobalMenu-Source=' "$f" 2>/dev/null && rm -f "$f" && note "removed $(basename "$f")"
done
rm -f "$HOME/.local/bin/x11-menus"
# Hand-made overrides that `x11-menus sync --adopt` moved aside come back.
for b in "$DATA"/backups/*.pre-x11-menus; do
  [ -e "$b" ] || continue
  did=${b##*/}; did=${did%.pre-x11-menus}
  if [ ! -e "$USERDATA/applications/$did" ]; then
    mv "$b" "$USERDATA/applications/$did" && note "restored your $did"
  fi
done

say "Desktop icons' files outside its extension"
# Meson's own record of what it installed: the schema, .desktop and icon.
log="$DATA/ding-meson-install.log"
if [ -f "$log" ]; then
  while IFS= read -r f; do
    case "$f" in
      "#"*|"$EXT"/*) continue ;;
      "$USERDATA"/*) if [ -f "$f" ] || [ -L "$f" ]; then rm -f "$f"; fi ;;
    esac
  done < "$log"
  if [ -d "$USERDATA/glib-2.0/schemas" ]; then glib-compile-schemas "$USERDATA/glib-2.0/schemas"; fi
  rm -f "$log"
  note "removed"
fi
update-desktop-database "$USERDATA/applications" 2>/dev/null || true

say "App settings"
vs="$HOME/.config/Code/User/settings.json"
if [ -f "$vs" ] && grep -q '"window.titleBarStyle": "native", // yet-another-gnomintosh' "$vs"; then
  sed -i '/"window.titleBarStyle": "native", \/\/ yet-another-gnomintosh/d' "$vs"
  note "VS Code: title bar setting removed"
fi
for prof in "$HOME"/.config/mozilla/firefox/*.default* "$HOME"/.mozilla/firefox/*.default* \
              "$HOME"/.var/app/org.mozilla.firefox/{config/mozilla,.mozilla}/firefox/*.default*; do
  [ -f "$prof/user.js" ] && grep -qx '// yet-another-gnomintosh: menubar in the top bar' "$prof/user.js" || continue
  sed -i '\#^// yet-another-gnomintosh: menubar in the top bar$#{N;d}' "$prof/user.js"
  # Firefox copies user.js prefs into prefs.js, and rewrites that on exit.
  if pgrep -u "$USER" -x firefox >/dev/null; then
    note "Firefox: close it, then remove widget.gtk.global-menu.enabled in about:config"
  else
    sed -i '/^user_pref("widget\.gtk\.global-menu\.enabled", true);$/d' "$prof/prefs.js" 2>/dev/null || true
    note "Firefox: global menu pref removed"
  fi
done
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
  theme=/usr/share/gnome-shell/gnome-shell-theme.gresource
  if [ -f "$pristine" ]; then
    # Only if the theme there is still the one the sync built: after a
    # gnome-shell update the package's newer theme is in place, and the saved
    # copy would put an older one back.
    built=$(sed -n 's/^built=//p' /usr/local/share/gdm-wallpaper-sync/stamp 2>/dev/null || true)
    if [ -n "$built" ] && [ "$built" = "$(sha256sum "$theme" | cut -d' ' -f1)" ]; then
      sudo install -m644 "$pristine" "$theme"
    else
      note "the login theme is not the synced one any more (a gnome-shell update replaced it); left as it is"
    fi
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
