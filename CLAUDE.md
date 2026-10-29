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
3. **Delete only when empty:** a tab, directory or sub-directory with anything in it is refused with a sentence
   naming what is inside. Deleting a bookmark asks first (confirm buttons have no destructive role, Cancel is default).
4. **Order is manual** (drag and drop, Move to…); "Sort by name" sorts one directory once. Drop rules live in
   `Arrange.swift` only; views just report drops (`AppModel.drop`). A directory dropped on a bookmark row goes into that
   row's directory; a bookmark dropped on a row lands before it; tabs reorder by dragging along the tab bar.
5. **Opening:** a single click on the name opens it in the browser chosen in Settings → General (bundle id in
   settings.json; nil = the Mac's default; a vanished browser falls back with a notice). Right-click / the pencil edits.
6. **Secrets: encrypted on disk, NOT the Keychain** (Matt, Oct 28 2026 — an ad-hoc-signed app would be asked again
   after every rebuild): `secrets.enc` + `secret.key` (0600), keyed by bookmark id, never in library.json. Multi-line.
   The secret window is select-to-copy only (no Copy button, Matt). `hasSecret` stays true when the text is blank
   (an import without secrets), so the row still shows the button and the editor asks for it.
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
    is the fallback; Settings → General can turn fetching off. Nothing else touches the network.
11. **Files are never lost:** a damaged library.json / unreadable secrets are moved aside (`*.unreadable-<date>`) and
    reported; a damaged library.json takes a COPY of secrets.enc with it (review: the next save would prune them).
    Saving is two-phase (review): secrets.enc gets old ∪ new, then library.json, then the prune — a failed library
    write loses no secret. Repeated ids are repaired on load and on import. Settings decode every field with a default.
12. **Text fields are `PlainTextField` / `Field`**, the secret is a `TextBox` (data_syncer rule 14b). Base text 14.
13. **Scripts:** BUILD_APP.sh / INSTALL_APP.sh like app_starter's; idempotent, plain-spoken. **Commits:** one per
    feature with a dated CHANGELOG entry; explicit `git add <paths>`; never push — Matt pushes.
14. **Testing:** `swift test`; never the real Application Support — `BOOKMARKMANAGER_HOME=<scratch>` for the app,
    `Scratch` in tests; tests set `icons.enabled = false`. Dev hooks: `BOOKMARKMANAGER_SAMPLE=1`,
    `BOOKMARKMANAGER_AUTOSHEET=…` (Docs/DEVELOPMENT.md). Prominent buttons look grey in screenshots of an inactive window.
