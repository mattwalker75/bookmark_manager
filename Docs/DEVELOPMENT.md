# Bookmark Manager — development

## Layout
```
Sources/BookmarkManagerCore/   Models · Arrange · Search · Store · SecretBox · Transfer · Favicons · Version
Sources/BookmarkManager/       BookmarkManagerApp (+ AppDelegate) · AppModel · MainWindow (SearchBar, TabBar, FolderTree,
                               FolderDetail, SubfolderRow, BookmarkRow, SiteIcon, DropGap, EndDrop) · SearchResults
                               Editors (BookmarkEditor, ColorPills, DestinationPicker, FolderEditor, TabNameSheet, MoveSheet)
                               SecretWindow · SettingsView (GeneralPane, ColorCodesPane, TransferPane, ValidationSheet)
                               Browsers · Icons (IconCache, IconFetcher) · Sample
                               Design · Themes · AppearancePane · PlainTextField · TextBox   ← App Starter's, keep in step
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

Site icons: `IconCache.image(for:)` answers from memory or `<home>/icons/<host>.png`, else starts one fetch
(`IconFetcher`: the page's HTML → `Favicons.candidates` → first picture that decodes, scaled to 64 px PNG).
A host that fails is skipped until the next launch.

## Where things are kept
`Home.folder()` = `~/Library/Application Support/Bookmark Manager/`, or `$BOOKMARKMANAGER_HOME`.
`library.json` (`{"app":"Bookmark Manager","library":{…}}`, secrets blank) · `secrets.enc` (AES-GCM,
`{bookmarkId: text}`) · `secret.key` (32 random bytes, 0600) · `settings.json` (appearance, accent, themes,
browser bundle id, fetchIcons) · `icons/<host>.png`.

The export file is `{"app":"Bookmark Manager","version":1,"exportedAt":…,"secretsIncluded":bool,"library":{…}}`
with the library exactly as in library.json (plus the secrets when included).

## Development hooks (harmless when unset)
- `BOOKMARKMANAGER_HOME=<folder>` — use a scratch folder instead of Application Support. **Always** for trying things.
- `BOOKMARKMANAGER_SAMPLE=1` — with an empty home, fill in example tabs and bookmarks (`Sample.swift`).
- `BOOKMARKMANAGER_AUTOSHEET=newBookmark | editBookmark | newFolder | editFolder | newTab | move | secret |
  search:<text> | settings[:general|colors|appearance|transfer]` — open that sheet / window a second after launch.

Screenshots: run `.build/debug/BookmarkManager` with those variables, then `screencapture -x -l <window id>`
(after `caffeinate -u -t 1`; the window ids from `CGWindowListCopyWindowInfo`, owner `BookmarkManager`).
Prominent buttons draw grey while the window is not the active one.

## Adding a setting
App-level (the browser, the look): `AppSettings` in AppModel.swift — add the field, decode it with
`decodeIfPresent` and a default, show it in SettingsView. Library-level (something an export should carry, like
the color codes or the levels): `Library` in Models.swift, with a default in `init(from:)` and a check in
`Transfer.validate`.
