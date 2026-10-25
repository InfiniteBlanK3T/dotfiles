# Desktop snapshots

These files are **snapshots**, not an automation target. Nothing here is applied by
`bootstrap.sh`.

- `extensions.txt` — GNOME Shell extension IDs.
- `flatpaks.txt` — installed Flatpak application IDs.

## Create a snapshot

```bash
gnome-extensions list > gui/extensions.txt
flatpak list --app --columns=application > gui/flatpaks.txt
```

## dconf

A full `dconf` dump can contain account identifiers, email addresses, proxy settings, and
recent-file paths. It is **gitignored** (`gui/dconf.ini`) and must not be published.

If you want a private snapshot:

```bash
dconf dump / > gui/dconf.ini
```

To restore it manually on a machine you control:

```bash
dconf load / < gui/dconf.ini
```

`dconf load` replaces whole subtrees without merging. Review the file first; a bad restore can
break input sources, keyboard layout, and display scaling. Prefer restoring only specific
paths, for example:

```bash
dconf load /org/gnome/desktop/interface/ < gui/interface.ini
```

GNOME extensions are version-sensitive. Install them manually and verify the shell version
before enabling anything at login.
