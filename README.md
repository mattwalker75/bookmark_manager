# Bookmark Manager

A Mac app that keeps your bookmarks in **tabs**, **directories** and **sub-directories** — with a description,
tags, a color code and, when you need one, a **secret** on each bookmark.

- **Tabs** across the top (at least one, renameable). Each tab holds bookmarks and directories; a directory can
  hold sub-directories (two levels by default; change it in Settings).
- A **bookmark** has a name, an optional description (shown under the name), the address, optional tags (for the
  search only), an optional color code, and an optional multi-line secret — a user name, a password, a token,
  blank lines between — kept encrypted on this Mac and shown in its own window only when you click **Secret** (or press Space on the row).
- **Directories** have an optional description and color too. A tab or directory can only be deleted once it is
  empty, so a full one is never deleted by accident.
- **Search** at the top: every word must be found in a bookmark's name, address or tags (or a directory's name),
  in any tab. Each result shows where it lives; **Show in place** jumps there.
- Click a name (or press Return on the row) to open it in the browser you chose in Settings — or the one that
  bookmark names. Drag rows between directories and tabs.
- **Color codes** (Settings): give colors a meaning — red = Important — and mark bookmarks and directories with
  them; the row gets a light wash of the color.
- A bookmark can also be a **secret only** — no address at all (a passphrase, the Wi-Fi password): same list, a key
  for an icon, a **Secrets-Only** button. A bookmark may name its own browser ("Opens in", in the editor).
- **Secret windows** size themselves to their text, hide themselves after a few minutes (Settings), and can ask for
  **Touch ID** first (Settings).
- **Directories collapse** in the folder tree with chevrons, and remember what you left open.
- **The keyboard**: ↑ ↓ walk the rows, Return opens, Space shows a secret, ⌘L copies the address, ⌘↑ goes up,
  ⌘1 … ⌘9 switch tabs.
- **Check links**: ask every address (or one directory's) once and see which are gone, moved or didn't answer,
  with marks on the rows; an optional weekly or monthly schedule.
- **Backups** (Settings → Backups): dated backup files of everything, secrets sealed with this Mac's key (or in
  plain text if you choose), written daily and on quit, kept versions that never age out, Verify, Restore — and a
  way back in on a new Mac with the key file or a passphrase.
- **Export** everything as one `.json` file (secrets only when you tick the box); **Validate** a file to see what
  is wrong with it, with where; **Import** replaces everything or adds the file's tabs beside yours.

## Install

```bash
./INSTALL_APP.sh          # checks the tools, runs the tests, builds, moves the app to /Applications
```

Then open **Bookmark Manager** from Applications. `./INSTALL_APP.sh --help` lists the options (`--check`,
`--to DIR`, `--copy` to keep a copy in build/, `--sign`, `--skip-tests`…). Run it again after pulling new code;
your bookmarks stay in `~/Library/Application Support/Bookmark Manager/`.

## More

- [Docs/USER_GUIDE.md](Docs/USER_GUIDE.md) — tabs, directories, bookmarks, secrets, the keyboard, search, colors, link checks, Settings, backups, export and import
- [Docs/SCRIPTS.md](Docs/SCRIPTS.md) — INSTALL_APP.sh, BUILD_APP.sh, signing
- [Docs/DEVELOPMENT.md](Docs/DEVELOPMENT.md) — how it is built, where things are kept, tests, development hooks
- [CHANGELOG.md](CHANGELOG.md)
