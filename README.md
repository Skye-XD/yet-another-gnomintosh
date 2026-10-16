# yet-another-gnomintosh

> *Forgive me, Father, for I have sinned.*
>
> It has been far too long since my last honest desktop. I took GNOME — a
> desktop with a clear, considered, deliberately un-Mac philosophy — and I
> dragged it, kicking and screaming, as close to macOS as I could. I forked
> eleven extensions. I patched a keyboard daemon. I taught Chrome to put its
> menus in a bar it was never meant to know about. I made the trash can *gulp*.
>
> I am not sorry. But I felt you should know.

This is one script that takes a stock **Fedora + GNOME** install and turns it
into what I have been living in: a top bar with real application menus, a
dock with a trash can you can throw files into, Launchpad, Spotlight, Mission
Control, Stage Manager, ⌘ as the Command key, and traffic lights on the left
where God intended.

It is not a theme pack. The theme is the least of it.

---

## The sins

### The look
- **WhiteSur** GTK theme (with the libadwaita/GTK4 variant), icons and cursors, dark by default.
- Traffic lights on the **left**: close, minimise, zoom.
- Rounded window corners everywhere, blur behind the panel and dock.
- The top bar on **every** monitor, not just the primary one.

### The menu bar (the big one)
- **Real application menus in the top bar.** GNOME apps get menus built from
  their own actions; LibreOffice exports its own; and Electron apps, Chrome,
  Firefox and Telegram hand over their *actual* menubars.
- Keyboard shortcuts shown beside menu items, macOS style: `⇧⌘N`, not `Ctrl+Shift+N`.
- The catch: Chromium/Electron only export menus under X11, so those apps are
  started through XWayland. `x11-menus` does this automatically — including
  for Electron apps you install *later* (a systemd path unit watches for them).

### The dock
- Dash to Dock, restyled to sit and behave like the macOS Dock.
- **Drag a file from Files (or the desktop) onto the trash and it goes in.**
  The dock slides up as you reach the edge, the can darkens while you hover,
  and it gulps. Undo works from Files.
- Delete anything any other way and the dock pops up while the file's icon
  arcs into the trash. Emptying the trash makes it squash.
- Genie-style minimise (magic lamp).
- Drag an app from Launchpad onto the dock to keep it there.

### Windows
- **Mission Control** (`⌃↑` / four-finger swipe up), **App Exposé** (`⌃↓` /
  swipe down) and **Show Desktop** (`⌃⌘↑`, `⌘D`, or click the wallpaper), with
  timing measured off a real Mac.
- **Stage Manager**, vertical, revealed on hover.
- Picture-in-picture windows (Chrome, Spotify's mini player) stay on top.
- Desktop icons, done properly.

### The keyboard
- **⌘ is Command.** `⌘C`, `⌘V`, `⌘Q`, `⌘W`, `⌘T`… reach apps as you'd expect,
  via [keyd](https://github.com/rvaiya/keyd) built from source with two fixes.
- `⌃A`/`⌃E`/`⌃K`/`⌃B`/`⌃F` edit text like they do on a Mac. Hate it?
  `macos-ctrl off`.
- `⇧⌘3` / `⇧⌘4` / `⇧⌘5` screenshots, `⌘H`/`⌘M` hide, `⌃⌘Q` lock,
  `⌘Space` Spotlight (Rudra), `F4` or a pinch for Launchpad (Ormic).
- The terminal keeps real `Ctrl`, because some of us still need `Ctrl+C`.

### Opt-in, because even I have limits
- `--with-login-screen` — the GDM login screen gets your wallpaper, your
  display layout, and the same translucent glass as the lock screen.
- `--with-hibernate-fix` — makes hibernate actually power the machine off on
  laptops whose firmware never finishes ACPI S4 (mine didn't).

---

## Requirements

- **Fedora 44** with **GNOME 50**, in a **Wayland** session. That is what it was
  made and tested on. Other versions and distros will be warned about and may
  well work; package names in particular will need adjusting.
- A normal user with `sudo`.
- An internet connection (it clones repos and talks to extensions.gnome.org).

## Install

```bash
git clone https://github.com/Skye-XD/yet-another-gnomintosh.git
cd yet-another-gnomintosh
./install.sh
```

Then **log out and back in** — GNOME only picks up new extensions at login.

| Option | What it does |
|---|---|
| `--list` | Show the steps |
| `--only a,b` | Run just these steps (e.g. `--only settings`) |
| `--skip a,b` | Run everything except these (e.g. `--skip keyd`) |
| `--with-login-screen` | Also restyle the login screen |
| `--with-hibernate-fix` | Also fix hibernate power-off |

Steps, in order: `preflight`, `packages`, `theme`, `forks`, `stock-extensions`,
`keyd`, `x11-menus`, `settings`, `apps`. Every one is safe to re-run.

Before touching a single setting it saves a full `dconf dump /`, and any
extension it replaces is moved aside rather than deleted, all under
`~/.local/share/yet-another-gnomintosh/backups`.

### A few things to do by hand
- **Chrome:** Settings → Appearance → Theme → **GTK**, so its window buttons
  follow the theme and sit on the left.
- **Telegram:** Settings → Advanced → **Use system window frame**, and
  Settings → Notifications → **native notifications** (its own popups land off
  screen in X11 mode).

## Uninstall

```bash
./uninstall.sh                     # the lot, settings back to before install
./uninstall.sh --login-screen      # also restore the stock login screen
./uninstall.sh --hibernate-fix     # also drop the hibernate tweak
```

---

## Penance (known limitations)

- **X11 for menus.** Apps that hand over their menus run under XWayland. With
  fractional scaling their text is very slightly softer. If you'd rather not,
  `x11-menus remove <app>` puts any one of them back.
- **Not every app obeys the traffic lights.** Apps that draw their own title
  bars decide for themselves; Tauri apps in particular hard-code theirs.
- **Files thinks a drop on the dock trash missed**, because as far as it can
  tell nothing accepted it. The files still go to the trash (and undo works);
  the shell hides the drag icon so it doesn't fly home.
- **Dash to Dock is stock**, and occasionally trips over itself after a big
  package install. Logging out fixes it.
- **keyd puts you in its group.** Per-app key mapping talks to keyd over a
  socket only the `keyd` group may use, so the install adds you to it. That
  means anything running as you can have keyd type keystrokes anywhere,
  including into other apps, the lock screen and a root console. It's how
  keyd's per-app mapper is designed upstream. If that trade isn't for you,
  install with `--skip keyd`; uninstall takes you out of the group again.
- It's tuned to my taste and my hardware. That's rather the point of a confession.

## What's in the box, and whose work it really is

Most of this is other people's excellent software, which I then sinned upon.
The patched ones live as forks under renamed UUIDs (so extensions.gnome.org
can never quietly "update" them back), each built from its `skye/install` branch:

| Does | Fork | Upstream |
|---|---|---|
| Launchpad | [oramic-launcher](https://github.com/Skye-XD/oramic-launcher) | [oliwebd/oramic-launcher](https://github.com/oliwebd/oramic-launcher) |
| Blur | [blur-my-shell](https://github.com/Skye-XD/blur-my-shell) | [aunetx/blur-my-shell](https://github.com/aunetx/blur-my-shell) |
| Top bar on every monitor | [multi-monitors-bar_fapv2](https://github.com/Skye-XD/multi-monitors-bar_fapv2) | [FrederykAbryan/multi-monitors-bar_fapv2](https://github.com/FrederykAbryan/multi-monitors-bar_fapv2) |
| Mission Control, Exposé, Show Desktop | [macos-window-manager](https://github.com/Skye-XD/macos-window-manager) | [theDavidCoen/three-finger-show-desktop](https://github.com/theDavidCoen/three-finger-show-desktop) |
| Desktop icons | [desktop-icons-ng](https://github.com/Skye-XD/desktop-icons-ng) | [smedius/desktop-icons-ng](https://gitlab.com/smedius/desktop-icons-ng) |
| Global menu | [global-menu-for-gnome](https://github.com/Skye-XD/global-menu-for-gnome) | [ShiroOSL/global-menu-for-gnome](https://github.com/ShiroOSL/global-menu-for-gnome) |
| Rounded corners | [rounded-window-corners](https://github.com/Skye-XD/rounded-window-corners) | [flexagoon/rounded-window-corners](https://github.com/flexagoon/rounded-window-corners) |
| Stage Manager | [NexStage](https://github.com/Skye-XD/NexStage) | [NexVar/NexStage](https://github.com/NexVar/NexStage) |
| Dock styling, trash, panel | [kiwi-kemma](https://github.com/Skye-XD/kiwi-kemma) | [kem-a/kiwi-kemma](https://github.com/kem-a/kiwi-kemma) |
| Genie minimise | [compiz-alike-magic-lamp-effect](https://github.com/Skye-XD/compiz-alike-magic-lamp-effect) | [hermes83/compiz-alike-magic-lamp-effect](https://github.com/hermes83/compiz-alike-magic-lamp-effect) |
| PiP on top | [gnome-shell-extension-pip-on-top](https://github.com/Skye-XD/gnome-shell-extension-pip-on-top) | [Rafostar/gnome-shell-extension-pip-on-top](https://github.com/Rafostar/gnome-shell-extension-pip-on-top) |

Installed untouched from extensions.gnome.org: Dash to Dock, User Themes,
Weather or Not, Rudra, Kiwi Menu, Wiggly, Hibernate Status; AppIndicator from
Fedora. Plus [WhiteSur](https://github.com/vinceliuice) by vinceliuice,
[keyd](https://github.com/rvaiya/keyd) by rvaiya, and the
[GDM extension](https://github.com/pratap-panabaka/gse-gdm-extension) by
pratap-panabaka. Thank you all. I'm sorry about what I did to your code.

## License

The scripts and configuration here are MIT. Every extension and theme it
installs keeps its own licence.

*Go in peace. Your Mac is waiting.*
