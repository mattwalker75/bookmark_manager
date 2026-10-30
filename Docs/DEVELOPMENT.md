# Bookmark Manager — development

## Layout
```
Sources/BookmarkManagerCore/   Models · Arrange · Search · Store · SecretBox · Transfer · Favicons · Backup (BackupFile,
                               PassphraseWrap, Backup, BackupStore) · Version
Sources/BookmarkManager/       BookmarkManagerApp (+ AppDelegate) · AppModel · MainWindow (KeyboardDriver, SearchBar, TabBar,
                               FolderTree, TreeBranch, TreeRow, FolderDetail, SubfolderRow, BookmarkRow, SiteIcon, DropGap, EndDrop)
                               SearchResults · Editors (BookmarkEditor, BrowserPicker, ColorPills, DestinationPicker, FolderEditor,
                               TabNameSheet, MoveSheet) · SecretWindow · SecretGate (Touch ID) · LinkCheck (LinkVerdict, LinkReport,
                               LinkChecker) · LinkCheckView (LinkReportSheet, LinkBanner) · SettingsView (GeneralPane, ColorCodesPane,
                               TransferPane, ValidationSheet) · BackupsView (BackupsPane, BackupCheckSheet, KeepSheet, PassphraseSheet)
                               Browsers · Icons (IconCache, IconFetcher) · Sample
                               Design · Themes · AppearancePane · PlainTextField · TextBox   ← adapted from App Starter (Themes adds
                                                              RGB.color and drops the bundle light; AppearancePane reworded; TextBox = ScriptEditor), keep in step
Tests/BookmarkManagerCoreTests/  Models · Arrange · Search · Store · Transfer · Favicon · Backup · ReviewFix tests · Helpers (Scratch, Sample)
Tests/BookmarkManagerTests/      AppModel, LinkCheck, BackupModel and the review tests (each on a scratch BOOKMARKMANAGER_HOME;
                                 Home.folder() refuses the real folder under xctest anyway); TinyHTTP / SlowHTTP serve 127.0.0.1 only
icon/                          icon.svg (Tabbed folder) → make_icns.sh → BookmarkManager.icns (committed)
```

## Build and test
```bash
swift build          # debug build of everything
swift test           # 126 tests, under a minute
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
so an edit updates an open window and a delete closes it. `fittedSize` sizes a new window to its text (wrapped
rows counted) between a floor and 60 % × 70 % of the screen; a changed secret refits a window still at that size.
Each holder has a hide timer (`arm`) wound from the last click, key or scroll in the window (one event monitor
for all secret windows); changing the minutes re-arms every open window. `SecretGate` asks Touch ID (or the Mac's
password) before `showSecret` when Settings say so; one pass covers 60 s; one prompt at a time.

Site icons: `IconCache.image(for:fetch:)` answers from memory or `<home>/icons/<host>.png`, else queues one fetch
(at most `atOnce` = 4 running; `IconFetcher`: the site ROOT's HTML — never the bookmark's path — →
`Favicons.candidates` → first picture that decodes, scaled to 64 px PNG). A host that fails is skipped until the
next launch. `SiteIcon` observes the cache directly; the editor passes `fetch: false`.

Saving: `LibraryStore` remembers library.json's size and date; `save` refuses when the file changed underneath
(another copy, a hand edit) and `AppModel.change` then puts the old library back, keeps the arrow-key focus on the
page and drops closed branches of deleted directories. A successful save also runs `backupAfterChangeIfDue` (the
"after every change" setting, at most once an hour, tried or not). `AppDelegate` keeps one copy of the .app
running and runs `beforeQuit` (the quit-time backup; a failure holds the quit with Quit Anyway / Cancel).

Link check: `LinkChecker` asks HEAD then GET (on 400/403/405/501), five at a time, 8 s each, reading headers only
(`URLSession.bytes` then `invalidateAndCancel`); the `Watcher` delegate accepts any certificate, records the first
301/308 target, follows only http(s), never https→http (`.downgraded`), and answers no password challenge; the
address's user:password is stripped first. `AppModel.checkLinks` keeps the old report when a run is stopped or when
nothing answered at all (`linkNote`), merges a one-directory run into it, and saves `linkcheck.json` (a failure is
reported; `settings.lastLinkCheckAt` keeps the schedule honest either way).

Backups: `Backup.make` seals the secrets with `secret.key` (or writes them in the clear when `backupSecretsPlain`),
adds the `PassphraseWrap` only while it still matches the key (`keyFingerprint`), and `BackupStore` lists / writes
(0600) / `setKept` / `prune(keep:)` (never a kept or unreadable file, never below 1). `AppModel.backUp` skips when
`Backup.digest` is unchanged (unless forced) and stands down on a launch that could not read its files
(`loadTrouble`). `restoreBackup` writes a kept "before restore" backup first (unless the library is fresh) and
refuses to go on without it; it goes through `importFile(.replace)` so the secrets are re-sealed with the current key.

## Where things are kept
`Home.folder()` = `~/Library/Application Support/Bookmark Manager/`, or `$BOOKMARKMANAGER_HOME`.
`library.json` (`{"app":"Bookmark Manager","library":{…}}`, secrets blank) · `secrets.enc` (AES-GCM,
`{bookmarkId: text}`) · `secret.key` (32 random bytes, 0600) · `settings.json` (appearance, accent, themes,
activeThemeId, browser bundle id, fetchIcons, `expanded` = the directory ids whose branch is open in the tree,
`secretHideMinutes` (0 = never), `touchIDForSecrets`, `linkCheckDays` 0/7/30) · `linkcheck.json` (the last link check: `checkedAt`, `checked`, `problems` with the address each had, `scope`, `automatic`, `bannerDismissed`, `seconds`) · `Backups/` (or the folder in
settings `backupFolder`): `Bookmark Manager <date>.bmbackup` = JSON `BackupFile` {app, kind:"backup", version 1, createdAt,
reason, kept, note, counts, library (secrets blank), secrets (AES-GCM of {id: text} with secret.key, base64),
passphrase {wrapped, salt, rounds} = secret.key sealed with PBKDF2-HMAC-SHA256(passphrase)}. Settings also keep
`backupsEnabled`, `backupWhen` (daily · dailyAndQuit · everyChange · manual), `backupKeep`, `backupPassphrase` (the wrap, safe to store), `backupSecretsPlain` (secrets in the clear in each backup; the file then has `secretsInClear: true` and no `secrets`), `lastBackupDigest`
(SHA-256 of the library with secrets: an unchanged library is not backed up again), `lastBackupAt`. · `icons/<host>.png` (`<host>_<port>.png` for a non-standard port).

The export file is `{"app":"Bookmark Manager","version":1,"exportedAt":…,"secretsIncluded":bool,"library":{…}}`
with the library exactly as in library.json (plus the secrets when included).

## Development hooks (harmless when unset)
- `BOOKMARKMANAGER_HOME=<folder>` — use a scratch folder instead of Application Support. **Always** for trying things.
- `BOOKMARKMANAGER_SAMPLE=1` — with an empty home, fill in example tabs and bookmarks (`Sample.swift`).
- `BOOKMARKMANAGER_AUTOSHEET=newBookmark | editBookmark | newFolder | editFolder | newTab | move | secret |
  search:<text> | settings[:general|colors|appearance|backups|transfer]` — open that sheet / window a second after launch
  (`newSecret` opens the bookmark editor with Secret only picked; `secret:<name prefix>` opens that bookmark's secret
  window, e.g. `secret:Backup` for the long sample secret; `keys:125,125,36` posts those key codes to the main
  window like real presses — 125 ↓, 126 ↑, 36 Return, 49 Space). Several steps run a second apart when separated
  by `;`: `search:admin;keys:125,125`. `linkreport` puts a made-up link report over the sample (marks + banner), `linkreport:sheet` also opens the sheet, `linkcheck` runs a real check (network!), `backupcheck` opens the Verify sheet for the newest backup in a window of its own.

Screenshots: run `.build/debug/BookmarkManager` with those variables, then `screencapture -x -l <window id>`
(after `caffeinate -u -t 1`; the window ids from `CGWindowListCopyWindowInfo`, owner `BookmarkManager`).
Prominent buttons draw grey while the window is not the active one.

## Adding a setting
App-level (the browser, the look): `AppSettings` in AppModel.swift — add the field, decode it with
`decodeIfPresent` and a default, show it in SettingsView. Library-level (something an export should carry, like
the color codes or the levels): `Library` in Models.swift, with a default in `init(from:)` and a check in
`Transfer.validate`.
