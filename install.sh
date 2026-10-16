#!/usr/bin/env bash
# yet-another-gnomintosh: turn a stock Fedora GNOME into a reasonable facsimile
# of a Mac. Run as your normal user; it asks for sudo where it must.
#
#   ./install.sh                 everything except the opt-in parts
#   ./install.sh --list          show the steps
#   ./install.sh --only a,b      run just these steps
#   ./install.sh --skip a,b      run everything but these
#   ./install.sh --with-login-screen   also restyle the GDM login screen
#   ./install.sh --with-hibernate-fix  power off normally after hibernating
#
# Every step is safe to re-run. A full `dconf dump /` is saved before any
# setting is touched, and replaced extensions are moved aside, not deleted --
# both under ~/.local/share/yet-another-gnomintosh/backups.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/yet-another-gnomintosh"
# Everything below derives from XDG_DATA_HOME, so a test run can point it at a
# scratch directory and leave the real desktop alone.
SRC="$DATA/src"
BACKUPS="$DATA/backups/$(date +%Y-%m-%d_%H%M%S)"
USERDATA="${XDG_DATA_HOME:-$HOME/.local/share}"
EXT="$USERDATA/gnome-shell/extensions"
GH="https://github.com"
KEYD_TAG="v2.6.0"
# Third-party code is pinned to the commit this was tested against; bump these
# deliberately. gdm-extension's installer runs as root.
WHITESUR_GTK=d5782652d412137e26fb8ff55b55a5572e4c6995
WHITESUR_ICONS=73d8040da51a9ed74e47c7366e7e9ff437601a5c
WHITESUR_CURSORS=e190baf618ed95ee217d2fd45589bd309b37672b
GDM_EXTENSION=f7c249e91f40ba8d293338085708938b9cc00b55

STEPS=(preflight packages theme forks stock-extensions keyd x11-menus settings apps)
OPTIONAL=(login-screen hibernate-fix)

# ---------------------------------------------------------------------------
# The extensions. Forks live under Skye-XD with a renamed UUID (so
# extensions.gnome.org can never "update" them back to stock); each is built
# from its skye/install branch.
#   repo | branch | how to build
FORKS="
oramic-launcher|skye/install|npm-dist
blur-my-shell|skye/v72-install|make-zip
multi-monitors-bar_fapv2|skye/install|copy
macos-window-manager|skye/install|copy
desktop-icons-ng|skye/install|meson
global-menu-for-gnome|skye/install|copy
rounded-window-corners|skye/install|npm-tsc
NexStage|skye/install|make-install
kiwi-kemma|skye/install|copy
compiz-alike-magic-lamp-effect|skye/install|copy
gnome-shell-extension-pip-on-top|skye/install|copy
"

# Unpatched, installed straight from extensions.gnome.org so they keep updating.
STOCK_EXTENSIONS="
dash-to-dock@micxgx.gmail.com
user-theme@gnome-shell-extensions.gcampax.github.com
weatherornot@somepaulo.github.io
rudra@narkagni
kiwimenu@kemma
wiggly@mojarch
hibernate-status@dromi
"

ENABLED_EXTENSIONS=(
  user-theme@gnome-shell-extensions.gcampax.github.com
  appindicatorsupport@rgcjonas.gmail.com
  compiz-alike-magic-lamp-effect@skye-xd.github.io
  dash-to-dock@micxgx.gmail.com
  weatherornot@somepaulo.github.io
  rudra@narkagni
  oramic-launcher@skye-xd.github.io
  blur-my-shell@skye-xd.github.io
  multi-monitors-bar@skye-xd.github.io
  globalmenu@skye-xd.github.io
  kiwimenu@kemma
  wiggly@mojarch
  kiwi@skye-xd.github.io
  gtk4-ding@skye-xd.github.io
  macos-window-manager@skye-xd.github.io
  keyd@keyd.rvaiya.github.com
  hibernate-status@dromi
  rounded-window-corners@skye-xd.github.io
  nexstage@skye-xd.github.io
  pip-on-top@skye-xd.github.io
)

# ---------------------------------------------------------------------------
say()  { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m    ! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m    x %s\033[0m\n' "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

backup_dir() { mkdir -p "$BACKUPS"; printf '%s' "$BACKUPS"; }

# Fetch one ref of a repo into $SRC/<name>, shallow. The ref may be a branch,
# a tag or a commit SHA (GitHub serves any of them to a shallow fetch).
fetch() { # url name [ref]
  local url=$1 ref=${3:-HEAD} dir="$SRC/$2"
  if [ ! -d "$dir/.git" ]; then
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
  fi
  git -C "$dir" remote set-url origin "$url"
  git -C "$dir" fetch -q --depth 1 origin "$ref"
  git -C "$dir" -c advice.detachedHead=false checkout -q -f FETCH_HEAD
  printf '%s' "$dir"
}

uuid_of() { # rounded-window-corners keeps its metadata under resources/
  local m="$1/metadata.json"
  [ -f "$m" ] || m="$1/resources/metadata.json"
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["uuid"])' "$m"
}

# Move an existing install of this UUID aside before replacing it.
set_aside() {
  local uuid=$1
  if [ -d "$EXT/$uuid" ]; then
    mv "$EXT/$uuid" "$(backup_dir)/extension-$uuid"
  fi
}

# Install an extension zip (extensions.gnome.org or a `gnome-extensions pack`).
install_zip() { # zip expected-uuid
  local zip=$1 uuid
  uuid=$(unzip -p "$zip" metadata.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["uuid"])')
  # The uuid becomes a path; never trust it further than the one asked for.
  [ "$uuid" = "$2" ] || die "$zip claims to be '$uuid', expected '$2'"
  set_aside "$uuid"
  mkdir -p "$EXT/$uuid"
  unzip -oq "$zip" -d "$EXT/$uuid"
  [ -d "$EXT/$uuid/schemas" ] && glib-compile-schemas "$EXT/$uuid/schemas"
  printf '%s' "$uuid"
}

copy_extension() { # srcdir uuid
  local from=$1 uuid=$2
  set_aside "$uuid"
  mkdir -p "$EXT/$uuid"
  rsync -a --exclude '.git*' --exclude node_modules --exclude tests \
        --exclude '*.md' --exclude '*.sh' "$from/" "$EXT/$uuid/"
  if [ -d "$EXT/$uuid/schemas" ]; then glib-compile-schemas "$EXT/$uuid/schemas"; fi
}

# ---------------------------------------------------------------------------
step_preflight() {
  say "Checking this is the kind of system it was made on"
  [ "$(id -u)" -ne 0 ] || die "run as your normal user, not root"
  local id; id=$(. /etc/os-release && echo "$ID")
  [ "$id" = fedora ] || warn "made on Fedora 44; '$id' is untested -- package names will differ"
  has gnome-shell || die "GNOME Shell is not installed"
  local v; v=$(gnome-shell --version | awk '{print int($3)}')
  [ "$v" -ge 50 ] || warn "made on GNOME 50; GNOME $v is untested"
  [ "${XDG_SESSION_TYPE:-}" = wayland ] || warn "made for a Wayland session; you are in '${XDG_SESSION_TYPE:-unknown}'"
  sudo -v || die "sudo is needed for packages, keyd and the login screen"
  note "Fedora $(. /etc/os-release && echo "$VERSION_ID"), GNOME $v -- carrying on"
}

step_packages() {
  say "Installing build tools and dependencies"
  sudo dnf install -y git rsync curl unzip zip make gcc kernel-headers \
    meson ninja-build gettext nodejs npm sassc glib2-devel libxml2 \
    python3 python3-pillow libnotify pipewire-utils dconf \
    gnome-extensions-app gnome-shell-extension-appindicator
}

step_theme() {
  say "Installing the WhiteSur theme, icons and cursors"
  local d
  d=$(fetch "$GH/vinceliuice/WhiteSur-gtk-theme.git" WhiteSur-gtk-theme "$WHITESUR_GTK")
  # -l also writes the libadwaita (GTK4) variant into ~/.config/gtk-4.0, after
  # deleting these entries there with no backup of its own (its backup line is
  # commented out). Keep what the user had; uninstall puts the first copy back.
  # Only on the first run: a re-run would save WhiteSur's own files, and that
  # backup must never be the one uninstall restores. The folder is made even
  # when there is nothing to save -- it marks "the theme step ran", so
  # uninstall leaves ~/.config/gtk-4.0 alone after --skip theme.
  local gtk4="$HOME/.config/gtk-4.0" e
  if ! ls -d "$DATA"/backups/*/gtk-4.0 >/dev/null 2>&1; then
    mkdir -p "$(backup_dir)/gtk-4.0"
    for e in gtk.css gtk-dark.css gtk-Light.css gtk-Dark.css assets windows-assets; do
      if [ -e "$gtk4/$e" ] || [ -L "$gtk4/$e" ]; then cp -a "$gtk4/$e" "$BACKUPS/gtk-4.0/"; fi
    done
    note "previous ~/.config/gtk-4.0 theme files (if any) saved to $BACKUPS/gtk-4.0"
  fi
  (cd "$d" && ./install.sh -c dark -c light -l >/dev/null)
  d=$(fetch "$GH/vinceliuice/WhiteSur-icon-theme.git" WhiteSur-icon-theme "$WHITESUR_ICONS")
  (cd "$d" && ./install.sh >/dev/null)
  d=$(fetch "$GH/vinceliuice/WhiteSur-cursors.git" WhiteSur-cursors "$WHITESUR_CURSORS")
  (cd "$d" && ./install.sh >/dev/null)
}

build_fork() { # dir how
  local dir=$1 how=$2 uuid
  uuid=$(uuid_of "$dir")
  case "$how" in
    copy)
      copy_extension "$dir" "$uuid" ;;
    make-install)
      set_aside "$uuid"
      mkdir -p "$EXT/$uuid"
      make -s -C "$dir" install PREFIX="$EXT" >/dev/null ;;
    make-zip)
      set_aside "$uuid"
      make -s -C "$dir" build >/dev/null
      install_zip "$dir/build/$uuid.shell-extension.zip" "$uuid" >/dev/null ;;
    meson)
      set_aside "$uuid"
      rm -rf "$dir/_build"
      meson setup "$dir/_build" "$dir" \
        --prefix="$(dirname "$USERDATA")" --datadir="$(basename "$USERDATA")" >/dev/null
      meson install --quiet -C "$dir/_build" >/dev/null
      # Meson also installs a schema, a .desktop file and an icon outside the
      # extension; its log is how uninstall finds exactly those.
      mkdir -p "$DATA" && cp "$dir/_build/meson-logs/install-log.txt" "$DATA/ding-meson-install.log"
      # Meson puts the schema in glib-2.0/schemas; keep a copy beside the
      # extension too, where getSettings() looks first.
      mkdir -p "$EXT/$uuid/schemas"
      cp "$dir"/schemas/*.gschema.xml "$EXT/$uuid/schemas/"
      glib-compile-schemas "$EXT/$uuid/schemas" ;;
    npm-dist)
      (cd "$dir" && npm ci --silent && npm run -s build >/dev/null)
      cp -r "$dir/schemas" "$dir/metadata.json" "$dir/stylesheet.css" "$dir/dist/"
      copy_extension "$dir/dist" "$uuid" ;;
    npm-tsc)
      (cd "$dir" && npm ci --silent && rm -rf _build && npx tsc --outDir _build)
      cp -r "$dir/resources/." "$dir/_build/"
      (cd "$dir/src" && find . -type f ! -name '*.ts' -exec cp --parents {} ../_build/ \;)
      copy_extension "$dir/_build" "$uuid" ;;
    *) die "unknown build '$how'" ;;
  esac
  # Ship the licence with every build; not every build system copies it.
  local f
  for f in "$dir"/LICENSE* "$dir"/COPYING*; do
    if [ -f "$f" ] && [ ! -e "$EXT/$uuid/${f##*/}" ]; then cp "$f" "$EXT/$uuid/"; fi
  done
  note "$uuid"
}

step_forks() {
  say "Building the forked extensions (the ones with the sins in them)"
  local repo branch how dir
  while IFS='|' read -r repo branch how; do
    [ -n "$repo" ] || continue
    dir=$(fetch "$GH/Skye-XD/$repo.git" "$repo" "$branch")
    build_fork "$dir" "$how"
  done <<< "$FORKS"
}

step_stock_extensions() {
  say "Installing the untouched extensions from extensions.gnome.org"
  local v uuid zip
  v=$(gnome-shell --version | awk '{print int($3)}')
  zip=$(mktemp --suffix=.zip)
  while read -r uuid; do
    [ -n "$uuid" ] || continue
    if curl -fsSL -o "$zip" \
        "https://extensions.gnome.org/download-extension/$uuid.shell-extension.zip?shell_version=$v"; then
      install_zip "$zip" "$uuid" >/dev/null && note "$uuid"
    else
      warn "could not download $uuid for GNOME $v -- install it by hand"
    fi
  done <<< "$STOCK_EXTENSIONS"
  rm -f "$zip"
}

step_keyd() {
  say "Building keyd so Super behaves like Command"
  local d
  d=$(fetch "$GH/rvaiya/keyd.git" keyd "$KEYD_TAG")
  git -C "$d" checkout -q -- .
  for p in "$REPO"/patches/keyd/*.patch; do
    git -C "$d" apply "$p"
  done
  # Upstream's extension stops at GNOME 49; it works on 50.
  sed -i 's/"49"\]/"49", "50"]/' "$d/data/gnome-extension-45/metadata.json"
  make -s -C "$d" >/dev/null
  sudo make -s -C "$d" install >/dev/null

  # Check the config before it goes anywhere: checked in place, a rejected one
  # was left for the next keyd restart. The include resolves beside the file.
  local chk; chk=$(mktemp -d)
  cp "$REPO/config/keyd/default.conf" "$chk/"
  cp "$REPO/config/keyd/macos-ctrl.on" "$chk/macos-ctrl"
  keyd check "$chk/default.conf" >/dev/null || { rm -rf "$chk"; die "keyd rejected its config"; }
  rm -rf "$chk"
  # Someone who already uses keyd keeps their config and its on/off state;
  # uninstall puts both back. First run only, for the same reason as the
  # theme backup: a re-run would save this installer's own config.
  local f
  if ! ls -d "$DATA"/backups/*/keyd >/dev/null 2>&1; then
    mkdir -p "$(backup_dir)/keyd"
    for f in default.conf macos-ctrl; do
      if sudo test -e "/etc/keyd/$f"; then
        # shellcheck disable=SC2024  # reading a root file into one we own
        sudo cat "/etc/keyd/$f" > "$BACKUPS/keyd/$f"
      fi
    done
    if systemctl is-enabled keyd >/dev/null 2>&1; then touch "$BACKUPS/keyd/.was-enabled"; fi
    if [ -e "$HOME/.config/keyd/app.conf" ]; then cp -a "$HOME/.config/keyd/app.conf" "$BACKUPS/keyd/app.conf"; fi
    if id -nG "$USER" | grep -qw keyd; then touch "$BACKUPS/keyd/.was-in-group"; fi
  fi
  sudo install -d /etc/keyd
  sudo install -m644 "$REPO/config/keyd/default.conf" /etc/keyd/default.conf
  sudo install -m644 "$REPO/config/keyd/macos-ctrl.on" /etc/keyd/macos-ctrl
  # The per-application mapper talks to keyd over a socket owned by group keyd,
  # so the group has to exist before keyd starts and creates that socket.
  getent group keyd >/dev/null || sudo groupadd keyd
  sudo usermod -aG keyd "$USER"
  sudo systemctl enable --now keyd
  sudo systemctl restart keyd
  mkdir -p "$HOME/.config/keyd"
  install -m644 "$REPO/config/keyd/app.conf" "$HOME/.config/keyd/app.conf"

  set_aside keyd@keyd.rvaiya.github.com
  mkdir -p "$EXT/keyd@keyd.rvaiya.github.com"
  cp "$d"/data/gnome-extension-45/* "$EXT/keyd@keyd.rvaiya.github.com/"

  # macos-ctrl on|off flips macOS-style Control (Ctrl+A/E/K... as text editing).
  mkdir -p "$DATA/keyd" "$HOME/.local/bin"
  cp "$REPO"/config/keyd/macos-ctrl.{on,off} "$DATA/keyd/"
  install -m755 "$REPO/bin/macos-ctrl" "$HOME/.local/bin/macos-ctrl"
  note "Super+C/V/Q/W/... now reach apps as Ctrl; 'macos-ctrl off' if Ctrl editing annoys you"
}

step_x11_menus() {
  say "Teaching Electron, Chrome and Firefox to put their menus in the top bar"
  install -Dm755 "$REPO/bin/x11-menus" "$HOME/.local/bin/x11-menus"
  install -Dm644 -t "$HOME/.config/systemd/user" "$REPO"/systemd/user/x11-menus.{path,service}
  systemctl --user daemon-reload
  systemctl --user enable --now x11-menus.path >/dev/null
  systemctl --user enable x11-menus.service >/dev/null
  "$HOME/.local/bin/x11-menus" sync
}

step_settings() {
  say "Applying settings"
  dconf dump / > "$(backup_dir)/dconf-before.ini"
  note "previous settings saved to $BACKUPS/dconf-before.ini"
  dconf load / < "$REPO/config/desktop.dconf"
  dconf load /org/gnome/shell/extensions/ < "$REPO/config/extensions.dconf"
  # Rudra and hibernate-status still only declare GNOME 49.
  gsettings set org.gnome.shell disable-extension-version-validation true
  local list
  list=$(printf "'%s', " "${ENABLED_EXTENSIONS[@]}")
  gsettings set org.gnome.shell enabled-extensions "[${list%, }]"
}

step_apps() {
  say "Nudging individual apps"
  # Telegram (flatpak): X11 so its menubar reaches the global menu.
  if flatpak info org.telegram.desktop >/dev/null 2>&1; then
    flatpak override --user --socket=x11 --env=QT_QPA_PLATFORM=xcb org.telegram.desktop
    note "Telegram: X11 mode (turn on Settings > Notifications > native notifications)"
  fi
  # VS Code draws its own menu unless it uses a native title bar.
  local vs="$HOME/.config/Code/User/settings.json"
  if [ -d "$HOME/.config/Code" ] || has code; then
    mkdir -p "$(dirname "$vs")"
    [ -s "$vs" ] || echo '{}' > "$vs"
    if ! grep -q '"window.titleBarStyle"' "$vs"; then
      cp "$vs" "$(backup_dir)/vscode-settings.json"
      # The marker comment (VS Code reads JSONC) is how uninstall finds it. It
      # ends the line: whatever followed the `{` (a `}`, or a whole one-line
      # file) goes on the next, or the comment would swallow it.
      sed -i '0,/{/{s//{\n    "window.titleBarStyle": "native", \/\/ yet-another-gnomintosh\n/;s/\n$//}' "$vs"
      note "VS Code: native title bar, so its menu goes to the top bar"
    fi
  fi
  # Firefox only exports its menubar with this pref (and X11, via x11-menus).
  # The flatpak keeps its profiles under ~/.var/app; x11-menus covers it too.
  local prof
  for prof in "$HOME"/.config/mozilla/firefox/*.default* "$HOME"/.mozilla/firefox/*.default* \
              "$HOME"/.var/app/org.mozilla.firefox/{config/mozilla,.mozilla}/firefox/*.default*; do
    [ -d "$prof" ] || continue
    grep -qs 'widget.gtk.global-menu.enabled' "$prof/user.js" ||
      printf '// yet-another-gnomintosh: menubar in the top bar\nuser_pref("widget.gtk.global-menu.enabled", true);\n' >> "$prof/user.js"
  done
}

step_login_screen() {
  say "Restyling the login screen (opt-in)"
  warn "this edits what the login screen loads. If it ever comes up broken:"
  warn "Ctrl+Alt+F3, log in, and run: $REPO/uninstall.sh --login-screen"
  local others
  others=$(sudo grep -l 'enabled-extensions' /etc/dconf/db/gdm.d/* 2>/dev/null | grep -v 99-gdm-extension || true)
  [ -z "$others" ] || die "other files in /etc/dconf/db/gdm.d also set enabled-extensions ($others); only one may"

  local d
  d=$(fetch "$GH/pratap-panabaka/gse-gdm-extension.git" gse-gdm-extension "$GDM_EXTENSION")
  # Its installer writes /etc/dconf/profile/gdm when there is none; remember
  # that, so uninstall removes only a profile this put there.
  local had_profile=0
  [ -e /etc/dconf/profile/gdm ] && had_profile=1
  (cd "$d" && sudo ./install.sh >/dev/null)
  if [ "$had_profile" = 0 ] && [ -e /etc/dconf/profile/gdm ]; then
    mkdir -p "$DATA" && touch "$DATA/created-gdm-profile"
  fi

  sudo install -m755 "$REPO/login-screen/gdm-wallpaper-sync" /usr/local/bin/gdm-wallpaper-sync
  sudo install -m755 "$REPO/login-screen/gdm-monitors-sync" /usr/local/bin/gdm-monitors-sync
  local u
  for u in gdm-wallpaper-sync.path gdm-wallpaper-sync.service gdm-monitors-sync.path gdm-monitors-sync.service; do
    sed "s#@HOME@#$HOME#g" "$REPO/login-screen/$u" | sudo tee "/etc/systemd/system/$u" >/dev/null
  done
  sudo systemctl daemon-reload
  sudo systemctl enable --now gdm-wallpaper-sync.path gdm-monitors-sync.path >/dev/null
  sudo systemctl start gdm-wallpaper-sync.service
  # A single-monitor setup may have no monitors.xml; not an error (and as a
  # function's last command a failed test would stop the install under set -e).
  if [ -f "$HOME/.config/monitors.xml" ]; then sudo systemctl start gdm-monitors-sync.service; fi
  note "your wallpaper, display layout and the lock screen's glass now carry over to the login screen"
}

step_hibernate_fix() {
  say "Making hibernate actually power off (opt-in)"
  grep -q disk /sys/power/state || die "this kernel cannot hibernate; set up a swap area big enough first"
  sudo install -d /etc/systemd/sleep.conf.d
  printf '# yet-another-gnomintosh: power off normally (S5) after writing the\n# hibernation image instead of ACPI S4, which some laptops never finish.\n[Sleep]\nHibernateMode=shutdown\n' |
    sudo tee /etc/systemd/sleep.conf.d/hibernate-mode.conf >/dev/null
}

# ---------------------------------------------------------------------------
usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

only=() skip=() extra=()
while [ $# -gt 0 ]; do
  case "$1" in
    --list) printf 'steps: %s\nopt-in: %s\n' "${STEPS[*]}" "${OPTIONAL[*]}"; exit 0 ;;
    --only) IFS=, read -ra only <<< "${2:?}"; shift ;;
    --skip) IFS=, read -ra skip <<< "${2:?}"; shift ;;
    --with-login-screen) extra+=(login-screen) ;;
    --with-hibernate-fix) extra+=(hibernate-fix) ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option $1 (try --help)" ;;
  esac
  shift
done

for s in "${skip[@]}"; do
  declare -F "step_${s//-/_}" >/dev/null || die "no such step: $s"
done
run=()
if [ ${#only[@]} -gt 0 ]; then run=("${only[@]}"); else run=("${STEPS[@]}" "${extra[@]}"); fi
for s in "${run[@]}"; do
  for k in "${skip[@]}"; do [ "$s" = "$k" ] && continue 2; done
  fn="step_${s//-/_}"
  declare -F "$fn" >/dev/null || die "no such step: $s"
  "$fn"
done

say "Done. Forgive us both."
note "Log out and back in: GNOME only loads new extensions at login."
note "Backups: $DATA/backups"
