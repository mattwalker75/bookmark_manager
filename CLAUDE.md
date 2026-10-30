# CLAUDE.md — working on Bookmark Manager

Read this before changing anything. `Docs/` has the detail.

## What it is
A Mac app (Swift + SwiftUI, macOS 14+, no Xcode project — SwiftPM + `BUILD_APP.sh`, modelled on
`../app_starter` and `../data_syncer`) that keeps Matt's bookmarks in **tabs › directories › sub-directories**,
each bookmark with a name, description, address, tags, a color code and an optional multi-line **secret**.
One window, a live search across every tab, export / validate / import as JSON. This Mac only. The person using
it is not a developer: every message is a plain sentence.

## Map
- `Sources/BookmarkManagerCore/` — no UI, tested on its own.
  - `Models.swift` — Library (maxDepth, colors, tabs) → Folder (a tab, directory or sub-directory: name, description,
    colorId, folders, bookmarks) → Bookmark (name, description, url, tags, colorId, hasSecret, secret). FolderPath
    (`[tabId, folderId…]`). Every rule that refuses something throws `BMError` with the sentence the window shows.
  - `Arrange.swift` — `Library.move(DragItem, to:before:)`: the ONE function for drag/drop and Move to…
  - `Search.swift` — `Library.search` (names, addresses, tags; directory names) → `SearchHit` with its path.
  - `Store.swift` (library.json, Home, `BOOKMARKMANAGER_HOME`), `SecretBox.swift` (AES-GCM secrets.enc + secret.key),
    `Transfer.swift` (export / `validate` / `apply` import), `Favicons.swift` (where a site's icon is; no network).
- `Sources/BookmarkManager/` — the app. `AppModel` drives the core (every change goes through `change { }`, which
  turns a refusal into a `Notice` and saves on success). `MainWindow` (SearchBar, TabBar, FolderTree, FolderDetail,
  BookmarkRow, SubfolderRow, drag/drop helpers), `SearchResults`, `Editors` (BookmarkEditor, FolderEditor,
  TabNameSheet, MoveSheet, ColorPills, DestinationPicker), `SecretWindow` (one NSWindow per bookmark),
  `SettingsView` (General, Color codes, Appearance, Export & import + ValidationSheet), `Browsers`, `Icons`
  (IconCache + IconFetcher), `Sample`. The look is App Starter's / Data Syncer's: `Design.swift`, `Themes.swift`,
  `AppearancePane.swift`, `PlainTextField.swift` are adapted copies (Themes adds `RGB.color`, drops the bundle light;
  AppearancePane reworded), `TextBox.swift` is ScriptEditor renamed — keep them in step.
- `Tests/BookmarkManagerCoreTests/` — XCTest against throwaway folders (`Scratch`) and a fixed `Sample` library.
  `Tests/BookmarkManagerTests/` — AppModel on a scratch `BOOKMARKMANAGER_HOME`.

## Rules that exist for a reason (Matt's decisions, Oct 28 2026)
1. **Design:** mockup layout A "Tabs on top, folder tree left" (canvas ERiAmhdr8tP9XothQ4xUe9); icon 2 "Tabbed
   folder" (`icon/icon.svg`). Keep it. Rows are **tinted** with their color code — no name pill on rows; the color's
   name shows only in the editor's pills and in Settings.
2. **Structure:** at least one tab always exists (`deleteTab` refuses the last one). Directory levels are
   `Library.maxDepth` (Settings → General; default 2 = directory + sub-directory; range 1…6); lowering it is refused
   while a deeper directory exists. Bookmarks live at a tab's top level or in any directory.
2a. **The folder tree collapses** (Matt, Oct 29 2026; tweaks canvas option A): a directory with sub-directories
    shows a chevron; its branch is open only while its id is in `AppSettings.expanded` (settings.json; pruned to
    existing directories at launch). Everything starts closed. `AppModel.select` → `reveal(path)` opens the
    directories ABOVE the selection (not the selection itself); Show in place on a directory opens its parent;
    `addFolder` opens the parent. The chevron is a Button outside the row's select tap. Closed with children, the
    count reads "3 · 2 dirs". The tab's top level always lists its directories.
3. **Delete only when empty:** a tab, directory or sub-directory with anything in it is refused with a sentence
   naming what is inside. Deleting a bookmark asks first (confirm buttons have no destructive role, Cancel is default).
4. **Order is manual** (drag and drop, Move to…); "Sort by name" sorts one directory once. Drop rules live in
   `Arrange.swift` only; views just report drops (`AppModel.drop`). A directory dropped on a bookmark row goes into that
   row's directory; a bookmark dropped on a row lands before it; tabs reorder by dragging along the tab bar.
5. **Opening:** a single click on the name opens it in the browser chosen in Settings → General (bundle id in
   settings.json; nil = the Mac's default; a vanished browser falls back with a notice). Right-click / the pencil edits.
   **A bookmark may name its own browser** (`Bookmark.browser`, Matt Oct 29 2026, mockup option A): an "Opens in" row in
   the editor only — NOTHING on the row and NO right-click "Open in" (Matt). `AppModel.browserChoice` picks it when
   installed, else the Settings browser with a one-time sentence.
5a. **The keyboard** (Matt, Oct 29 2026): `AppModel.focusId` is the row under ↑ ↓ (`keyboardRows` = the page's
    sub-directories then bookmarks, or the hits grouped by tab exactly as shown); Return `activateFocus`, Space the
    secret, ⌘L `copyFocusedAddress`, ⌘↑ `goUp` (the directory just left stays focused); Tabs menu ⌘1–9, ⌃Tab.
    `KeyboardDriver` is ONE local key monitor on the main window: nothing while a sheet is up or another text view
    has the cursor; in the search box only ↑ ↓ Return are taken. Focus clears on select / tab / typing. Rows carry
    `.id()` so the page scrolls to the focused row.
6. **Secrets: encrypted on disk, NOT the Keychain** (Matt, Oct 28 2026 — an ad-hoc-signed app would be asked again
   after every rebuild): `secrets.enc` + `secret.key` (0600), keyed by bookmark id, never in library.json. Multi-line.
   The secret window is select-to-copy only (no Copy button, Matt). `hasSecret` stays true when the text is blank
   (an import without secrets), so the row still shows the button and the editor asks for it. **The secret window
   sizes itself to its text** (Matt, Oct 29 2026): `SecretWindows.fittedSize` measures the lines in the window's own
   monospaced font plus the chrome, clamped to `floor` (420×180) and 60% × 70% of the screen; a changed secret
   refits only while the window is still the size it was given (a hand-resized one is left alone).
   **Hide-after and Touch ID** (Matt, Oct 29 2026): `SecretWindows.arm` closes a window after
   `settings.secretHideMinutes` (0 = never) of not being key, re-armed on `windowDidBecomeKey`; `AppModel.showSecret`
   goes through `SecretGate` (LocalAuthentication `.deviceOwnerAuthentication`) when `touchIDForSecrets` is on —
   one pass covers 60 s, a cancel says nothing, a window already open is just brought forward. NO password
   generator (Matt: secrets are not only passwords).
6a. **Secret-only items** (Matt, Oct 29 2026; mockup canvas UG7WKF8nLnByzTDEKbpewk — row A, editor B): a bookmark
    may have NO address when it has a secret (`Bookmark.isSecretOnly` = blank url; `cleaned` refuses blank url +
    no secret). It stays in the same list as every other bookmark (manual order, colors, drag, search by name/tags).
    Its row: a key tile (`DS.key`), a plain name that opens nothing, the button titled **"Secrets-Only"**
    (`secretButtonTitle`; "Secret" beside an address), "Secret only — no address" when there is no description; no
    Open / Copy address in its menu; `AppModel.open` on one shows the secret. The editor opens with a segmented
    **Web page / Secret only** picker; Secret only hides the Address row and the switch, clears the address on save,
    and refuses a NEW secret with nothing typed (an imported blank one may be edited). Validate: no address is a
    stop only when there is no secret either.
7. **Export** is one JSON (`ExportFile`: tabs, directories, bookmarks, colors, maxDepth). "Include the secrets" is a
   checkbox that **defaults OFF**; on, the file holds them decrypted and the pane says so. **Validate** lists every
   problem with its place (`Transfer.validate`, stops vs notes) and changes nothing; Import validates first, then
   Replace everything (confirmed) or Add its tabs (fresh ids). Replace without secrets keeps local secrets by id.
8. **Color codes:** in the library (so they export): 4 defaults, up to `ColorCode.maximum` (10), any color + name;
   removing one clears it everywhere (Remove always asks and says how many lose it). Tags are search-only, never shown on rows.
9. **Search** covers every tab, every word must match (name, address, tags; directory names — NOT descriptions);
   results are grouped by tab with the path; "Show in place" selects the directory and flashes the row (`highlightId`).
10. **Site icons** are fetched once per host into `<home>/icons/<host>.png` (`<host>_<port>.png` with a port) (any certificate accepted, http allowed via
    `NSAllowsArbitraryLoads` — on its own, see App Starter), a failure is remembered until relaunch, the link glyph
    is the fallback; Settings → General can turn fetching off. Nothing else touches the network. Review rules: only
    the site ROOT is ever requested (never a bookmark's path/query — http://router/reboot must not be visited);
    at most `IconCache.atOnce` (4) fetches run at once, the rest queue; the editor's icon is cache-only
    (`SiteIcon(fetch: false)`) so half-typed hosts are never looked up; an import warms nothing (rows fetch lazily);
    `SiteIcon` observes `IconCache` directly (an arriving icon redraws only the rows that show it).
    **The link check is the ONE deliberate full-address visit** (Matt, Oct 29 2026, mockup B): `LinkChecker` HEAD then
    GET (on 400/403/405/501), 5 at once, 8 s each, any certificate, first permanent redirect remembered; verdicts
    `LinkVerdict` (gone / moved / refused / failed / unreachable) kept in `linkcheck.json`; a row's mark applies only
    while its url is unchanged; a one-directory check merges into the old report; it runs ONLY by the Settings
    button, the directory menu, the Bookmarks menu, or the schedule `linkCheckDays` (default 0 = never; a due check
    runs 5 s after launch, `automatic`, and shows a banner instead of the sheet).
11. **Files are never lost:** a damaged library.json / unreadable secrets are moved aside (`*.unreadable-<date>`) and
    reported; a damaged library.json takes a COPY of secrets.enc with it (review: the next save would prune them).
    Saving is two-phase (review): secrets.enc gets old ∪ new, then library.json, then the prune — a failed library
    write loses no secret. Repeated ids are repaired on load and on import. Settings decode every field with a default.
11a. **Backups** (Matt, Oct 29 2026; mockup board "Backups"): `Backup` (core) writes ONE JSON `.bmbackup` with the
    library (secrets blank) + the secrets sealed with THIS MAC'S secret.key + optionally the key sealed with a
    passphrase (`PassphraseWrap`, PBKDF2 600k rounds); `BackupStore` lists / writes / `setKept` (kept + note live IN
    the file) / `prune(keep:)` (never a kept one, never an unreadable file). `AppModel.backUp` skips when
    `Backup.digest` is unchanged unless forced; schedule `BackupWhen` (default daily + quit, `AppDelegate.beforeQuit`);
    "Enable backups" is the label (Matt). Verify = `Backup.check` (Validate's checks + can the secrets open);
    Restore writes a KEPT "before restore" backup first, then goes through `importFile(.replace)` so the secrets are
    re-sealed with the current key. Fresh-Mac path: Restore from a file… → asks for the key file or the passphrase.
    "Save a copy of the secret key…" exists for that day. NO password generator anywhere.
12. **Text fields are `PlainTextField` / `Field`**, the secret is a `TextBox` (data_syncer rule 14b). Base text 14.
12a. **One copy at a time, and the disk is the truth** (review, Oct 28 2026): `AppDelegate` quits a second copy of the
    .app and brings the first forward; `LibraryStore` remembers library.json's size+date and refuses a save when
    something else wrote the file since (two copies on one home, a hand edit); `AppModel.change` puts the old
    library back when a save fails, so the window never shows what the disk doesn't hold. A refusal that belongs to
    the Settings window (directory levels) is shown there, inline (`AppModel.reason`), not as a notice behind it.
12b. **Addresses:** no scheme → https:// in front (but "two words" is refused); a space inside a real address is
    written as %20; javascript:, data:, vbscript:, blob: are refused as "not an address a browser should open".
    Names made only of blanks or invisible characters (zero-width space, Hangul filler) are refused.
12c. **The browser list** is apps that claim https: AND file: (every real browser; a terminal that claims https:
    doesn't) or are in `Browsers.known`; the Mac's default can still be any app. ⌘E / Rename Tab… / Sort are off
    while search results are showing (they would act on the hidden selection). A directory dropped on its own row
    is a silent no-op. Secret windows observe the model (look changes) and are refreshed after an import.
13. **Scripts:** BUILD_APP.sh / INSTALL_APP.sh like app_starter's; idempotent, plain-spoken. **Commits:** one per
    feature with a dated CHANGELOG entry; explicit `git add <paths>`; never push — Matt pushes.
14. **Testing:** `swift test`; never the real Application Support — `BOOKMARKMANAGER_HOME=<scratch>` for the app,
    `Scratch` in tests; tests set `icons.enabled = false`. Dev hooks: `BOOKMARKMANAGER_SAMPLE=1`,
    `BOOKMARKMANAGER_AUTOSHEET=…` (Docs/DEVELOPMENT.md). Prominent buttons look grey in screenshots of an inactive window.
