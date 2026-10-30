# Bookmark Manager — development

## Layout
```
Sources/BookmarkManagerCore/   Models · Arrange · Search · Store · SecretBox · Transfer · Favicons · Version
Sources/BookmarkManager/       BookmarkManagerApp (+ AppDelegate) · AppModel · MainWindow (SearchBar, TabBar, FolderTree,
                               FolderDetail, SubfolderRow, BookmarkRow, SiteIcon, DropGap, EndDrop) · SearchResults
                               Editors (BookmarkEditor, ColorPills, DestinationPicker, FolderEditor, TabNameSheet, MoveSheet)
                               SecretWindow · SettingsView (GeneralPane, ColorCodesPane, TransferPane, ValidationSheet)
                               Browsers · Icons (IconCache, IconFetcher) · Sample
                               Design · Themes · AppearancePane · PlainTextField · TextBox   ← adapted from App Starter (Themes adds
                                                              RGB.color and drops the bundle light; AppearancePane reworded; TextBox = ScriptEditor), keep in step
Tests/BookmarkManagerCoreTests/  Models · Arrange · Search · Store · Transfer · Favicon tests · Helpers (Scratch, Sample)
Tests/BookmarkManagerTests/      AppModelTests (on a scratch BOOKMARKMANAGER_HOME)
icon/                          icon.svg (Tabbed folder) → make_icns.sh → BookmarkManager.icns (committed)
```

## Build and test
```bash
swift build          # debug build of everything
swift test           # 48 tests, a few seconds
./BUILD_APP.sh       # build/Bookmark Manager.app (release, ad-hoc signed)
```

## How it fits together
`Library` is a value: every change is a mutating method that throws `BMError` when refused (`addFolder`,
`deleteTab`, `move`, `setMaxDepth`…). `AppModel.change { lib in … }` runs one on a copy, keeps it only when it
went through, saves (`LibraryStore.save`: secrets to `secrets.enc` first, then `library.json`) and fixes the
selection. A refusal becomes a `Notice` (an alert) — or, in the editors, is tried on a copy first and shown in
the sheet. Views never touch disks.

`FolderPath` (`[tabId, folderId, …]`) names a folder; `selectedPath` is what the right-hand page shows.
Drag tokens are `bookmark:<uuid>` / `folder:<uuid>` (`DragItem`) and `tab:<uuid>` (the tab bar only).
Search is computed on demand from `query` (`Library.search`), cheap for a few thousand bookmarks.

Secret windows are plain `NSWindow`s kept in `SecretWindows` (one per bookmark id), fed through a `SecretHolder`
so an edit updates an open window and a delete closes it.

Site icons: `IconCache.image(for:fetch:)` answers from memory or `<home>/icons/<host>.png`, else queues one fetch
(at most `atOnce` = 4 running; `IconFetcher`: the site ROOT's HTML — never the bookmark's path — →
`Favicons.candidates` → first picture that decodes, scaled to 64 px PNG). A host that fails is skipped until the
next launch. `SiteIcon` observes the cache directly; the editor passes `fetch: false`.

Saving: `LibraryStore` remembers library.json's size and date; `save` refuses when the file changed underneath
(another copy, a hand edit) and `AppModel.change` then puts the old library back. `AppDelegate` keeps one copy of
the .app running.

## Where things are kept
`Home.folder()` = `~/Library/Application Support/Bookmark Manager/`, or `$BOOKMARKMANAGER_HOME`.
`library.json` (`{"app":"Bookmark Manager","library":{…}}`, secrets blank) · `secrets.enc` (AES-GCM,
`{bookmarkId: text}`) · `secret.key` (32 random bytes, 0600) · `settings.json` (appearance, accent, themes,
activeThemeId, browser bundle id, fetchIcons, `expanded` = the directory ids whose branch is open in the tree,
`secretHideMinutes` (0 = never), `touchIDForSecrets`, `linkCheckDays` 0/7/30) · `linkcheck.json` (the last link check: when, how many, the problems with the address they had) · `icons/<host>.png` (`<host>_<port>.png` for a non-standard port).

The export file is `{"app":"Bookmark Manager","version":1,"exportedAt":…,"secretsIncluded":bool,"library":{…}}`
with the library exactly as in library.json (plus the secrets when included).

## Development hooks (harmless when unset)
- `BOOKMARKMANAGER_HOME=<folder>` — use a scratch folder instead of Application Support. **Always** for trying things.
- `BOOKMARKMANAGER_SAMPLE=1` — with an empty home, fill in example tabs and bookmarks (`Sample.swift`).
- `BOOKMARKMANAGER_AUTOSHEET=newBookmark | editBookmark | newFolder | editFolder | newTab | move | secret |
  search:<text> | settings[:general|colors|appearance|transfer]` — open that sheet / window a second after launch
  (`newSecret` opens the bookmark editor with Secret only picked; `secret:<name prefix>` opens that bookmark's secret
  window, e.g. `secret:Backup` for the long sample secret; `keys:125,125,36` posts those key codes to the main
  window like real presses — 125 ↓, 126 ↑, 36 Return, 49 Space). Several steps run a second apart when separated
  by `;`: `search:admin;keys:125,125`. `linkreport` puts a made-up link report over the sample (marks + banner), `linkreport:sheet` also opens the sheet, `linkcheck` runs a real check.

Screenshots: run `.build/debug/BookmarkManager` with those variables, then `screencapture -x -l <window id>`
(after `caffeinate -u -t 1`; the window ids from `CGWindowListCopyWindowInfo`, owner `BookmarkManager`).
Prominent buttons draw grey while the window is not the active one.

## Adding a setting
App-level (the browser, the look): `AppSettings` in AppModel.swift — add the field, decode it with
`decodeIfPresent` and a default, show it in SettingsView. Library-level (something an export should carry, like
the color codes or the levels): `Library` in Models.swift, with a default in `init(from:)` and a check in
`Transfer.validate`.
