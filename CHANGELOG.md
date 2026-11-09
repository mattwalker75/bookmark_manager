# Changelog

All notable changes to Bookmark Manager (Keep a Changelog style; dates are when the change was made).

## [1.2.2] — 2026-11-08

Matt, Nov 8 2026: the results lists as windows of their own, then a deep review by five reviewers (core models,
parsers and network, the app model and windows, the views, data safety and the tests) — every verified finding
fixed, each with a test.

### Fixed
- 2026-11-08: **Link-check marks missed bookmarks typed without a scheme, with a space, or with a non-ASCII
  letter** — the checked address is "https://example.com/x" while the bookmark says "example.com/x", so the row
  wore no mark, the banner didn't count it, and *Use new address* refused it as "changed since". The mark now
  follows the address as typed.
- 2026-11-08: **An upper-case scheme (HTTP://, HTTPS://) was never checked and never got an icon**, and slipped
  past the "needs a host" rule. Schemes are compared without regard to case now.
- 2026-11-08: **A check of one directory of dead sites was thrown away as "no connection"** — that rule applies
  only to a check of everything now.
- 2026-11-08: **Firefox tags were not decoded** (`R&amp;D` came in literally). They are, like the addresses.
- 2026-11-08: **A front page bigger than the icon fetcher's cap was skipped altogether**, so a site with its icon
  on a CDN and no /favicon.ico got the fallback glyph for good. The front of the page is read now (up to the cap);
  an image bigger than its cap is still left alone.
- 2026-11-08: **A JSON import whose save was refused was reported as "Imported …"** — the pane says nothing was
  imported now, and the notice says why.
- 2026-11-08: **A settings file that couldn't be written was never mentioned** — the backup passphrase "was set"
  and was gone at the next launch. A notice says so now. **A settings file that isn't JSON at all was silently
  replaced** — it is moved aside with the date in its name and a notice says so.
- 2026-11-08: **A damaged secrets file retired a good secret key**, so every backup's secrets stopped opening
  "with this Mac's key". When the key reads fine it stays; only a damaged key retires both.
- 2026-11-08: **A new backup folder stayed empty until something changed** — choosing a folder (or Default) now
  forgets the last backup's digest, so the next automatic backup writes into it.
- 2026-11-08: **A save whose secrets prune failed left every later save refused as "changed by something else"**
  until relaunch. The library write is the save; the prune's failure is harmless and swallowed.
- 2026-11-08: **Validate let names made only of invisible characters through** (a word joiner, a soft hyphen…)
  that the editor refuses. Validate, the editors and the library share one rule now.
- 2026-11-08: **The notes window lost its clickable addresses after Edit → Cancel or Save** until reopened, and
  **didn't grow to fit after a Save** that added lines. Both fixed.
- 2026-11-08: **Delete notes… closed the window before the delete was tried**, so a refused save kept the notes
  but lost the window. The window closes only once the notes are gone.
- 2026-11-08: **A second Edit… from the Link check or Duplicates window replaced the editor already open**,
  throwing away what was typed. The open editor comes forward instead. **A refusal raised from those windows**
  (Use new address on a changed bookmark, say) appeared as an alert behind them; the main window comes forward.
- 2026-11-08: **A web bookmark switched to Secret only with nothing typed lost its address** and became an empty
  row; it is refused like a new empty secret. **Turning the secret off with text in the box** asks first now, like
  the notes.
- 2026-11-08: **Verify → Choose the key file… with the wrong key** left a dead end (the report and its controls
  gone). The report stays and the reason is shown under it.
- 2026-11-08: **Unkeep said "there are already N newer backups" when there weren't** — it counts only newer unkept
  backups now, the ones that decide whether this one would be pruned.
- 2026-11-08: **The empty page of a directory said "drag bookmarks here" but took no drop.** It does now.
- 2026-11-08: **The delete question in the Duplicates window got its plural wrong** ("the other bookmarks" for one).
- 2026-11-08: **A hide-after number outside 1…86400 typed into Settings was not applied on Return** (the field is
  not a SwiftUI field, so Return never reached it); it is applied when the field is left.
- 2026-11-08: **A tab name made only of invisible characters closed the sheet and failed behind it.** The sheet
  tries the name with the library's own rule and shows the refusal in place.
- 2026-11-08: Tests — two that could not fail (the icon fetch limit, the fetchIcons setting) now can; the clipboard
  test uses a pasteboard of its own instead of Matt's; a test restores the home variable it changed.
- 2026-11-08: **An editor left open overwrote changes made elsewhere** — the bookmark editor saved the whole
  bookmark as it opened it, so notes saved from the notes window, or a new address taken in the link check, while
  the sheet was open were put back on Save; the directory editor did the same to its notes. Both now save only
  what was changed in them, over the item as it is by then.
- 2026-11-08: The import-from-a-browser sheet built the new tab twice (once to check the name). It checks the
  name on its own now.

### Changed
- 2026-11-08: **The link-check results and the duplicates list are windows of their own** (Matt) — they were
  sheets, so *Show in place* and *Edit…* had to close them to reach the main window and the list had to be opened
  again for every bookmark. Now each is one window (*Link check*, *Duplicate bookmarks*) that stays open beside the
  main window while you work through it: Show in place and Edit… bring the main window forward and leave the list
  where it is; **Done** or the close button closes it; asking again brings the same window forward. Resizable, and
  it opens where it was left. Opened from Settings → General, the Bookmarks menu, right-click → Check links…, and
  the banner's *Show*, all the same way.

## [1.2.1] — 2026-11-08

Matt, Nov 8 2026: five of the findings from the code review of 1.2, fixed as one batch.

### Fixed
- 2026-11-08: **Deleting a directory closed its notes window first** — the window went away (with anything
  being typed in it) before the delete was even tried; a refused delete (the directory isn't empty) then left the
  directory but had lost the draft. The window — and a bookmark's secret and notes windows — now close only once
  the item is really gone.
- 2026-11-08: **A failed browser import reported success** — when the save failed after *Add the tab*, the
  Export & import pane still said "Imported …" while the real reason sat in a notice behind the sheet. The sheet
  now just closes and the pane says nothing; the notice says why.
- 2026-11-08: **A directory holding only notes was deleted as "empty"** — the *Delete the directory …?* dialog
  said "It is empty, so nothing else is lost." The delete still goes ahead (nothing inside it), but the dialog
  now says the notes are deleted with it.
- 2026-11-08: **A description after a skipped link landed on the wrong bookmark** — in a Firefox export, the
  `<DD>` under a bookmarklet (left out) was hung on the kept link before it. A description now only ever
  describes the link just before it, and one after a left-out link is dropped.
- 2026-11-08: **A folders-only export was rejected** — a bookmarks file with folders but not a single link was
  called "not a browser's bookmarks file". It reads now; the sheet shows no bookmarks and the empty folders left
  out, with *Add the tab* disabled.

## [1.2.0] — 2026-11-08

Matt, Nov 8 2026: three more things for the daily use — notes on directories, a way to bring a browser's
bookmarks in, and bigger or smaller text in the secret and notes windows.

### Added
- 2026-11-08: **Import from a browser** (Matt) — Settings → Export & import → *Import from a browser…* reads
  the HTML bookmarks file Safari, Chrome, Firefox, Edge or Brave export and brings it in as **one new tab**, its
  folders as directories (and sub-directories), its links as bookmarks, in the browser's order. A sheet shows
  what is coming (counts, where the file came from), lets you name the tab, and says what happens to the
  directory levels: raised to fit the file's folders (up to 6), anything deeper folded into the directory above.
  Bookmarklets and other non-addresses are left out and counted; so are empty folders. Firefox descriptions and
  tags come along. Nothing already here changes, and nothing in the browser.
- 2026-11-08: **Notes on directories** (Matt) — a directory or sub-directory can carry the same plain notes a
  bookmark can: tick *This directory has notes* in its editor. Its row (and its search result) gets the **Notes**
  button; right-click → Show notes; ⇧Space on the row. The same window — read-only until Edit, Save / Don't Save
  on close, Delete notes… turns them off — with a **Show directory** button in place of Open bookmark. Found by
  the search, in every export and backup. The sample library's *Self-hosted apps* shows one.
- 2026-11-08: **Text size in secret and notes windows** (Matt) — ⌘+ makes the text bigger, ⌘− smaller, ⌘0 puts
  it back, for that one window while it is open (the window grows or shrinks to fit, unless you resized it by
  hand). Settings → General has the size each kind of window opens with (*Text size in a secret window*, *Text
  size in a notes window*; 9 to 36 points, 14 to begin with). The View menu has the same three items.

## [1.0.0] — 2026-11-08

Matt, Nov 8 2026: in daily use with zero issues, so this is 1.0 — with the three tweaks below.

### Added
- 2026-11-08: **Notes on a bookmark** (Matt; mockups: row A, window A) — tick *This bookmark has notes* in the
  editor and type plain notes for yourself: where you left off on a project, how to find your way around a site
  that hides things. Not a secret: kept as they are, in every export and backup, found by the search. The row
  shows a **Notes** button beside Secret (only while notes are on; a secret-only item can have them too). The
  notes open in a window of their own — sized to the text, movable, never hidden by itself — **read-only** until
  you click **Edit** (no accidental typing); then **Save** (⌘S) or **Cancel**. Closing with changes asks *Save /
  Don't Save / Cancel*; so does quitting. **Delete notes…** asks first, then turns the notes off (the button goes
  until the editor turns them on again). Addresses in the notes are clickable; **Open bookmark** opens the site;
  the bottom line says when the notes were last changed. ⇧Space on a row shows its notes; the Bookmarks menu has
  **Show Notes**.
- 2026-11-08: **Find duplicate bookmarks** (Matt) — Settings → General → Links → *Find duplicate bookmarks…*
  (and the Bookmarks menu) lists every group of bookmarks at the same page, each bookmark with where it lives
  and Show in place / Edit… / Delete… (asked first). Two kinds: *same address* letter for letter, and *same
  page, written differently* (http/https, www, a trailing slash, tracking bits after "?", a #part). Nothing is
  deleted by itself. **Meant to be the same — keep all N** marks a group as intended (one bookmark per Gmail
  account, say) and leaves it out from then on; the mark is the bookmark's *Leave out of duplicate checks*
  switch in the editor (exported), and *Show the N left out* in the sheet brings such groups back with *Look at
  these again*. A new bookmark at a marked page shows the group again.

### Fixed
- 2026-11-08: The hide-after field in Settings → General came up **empty** (only a grey hint) even though the
  setting was there — the Settings window gives that field the cursor as it opens, and the text field refused a
  value while it had the cursor. It now shows the number straight away: 300 when nothing was ever set (Matt).

### Changed
- 2026-11-08: Settings → General: the **Duplicates** title is gone — *Find duplicate bookmarks…* is a card of its
  own under the **Links** heading, with *Check every address…* and *Fetch site icons* (Matt).
- 2026-11-08: **Hide a secret window after … seconds** (Matt: "5 seconds or 999 seconds") — Settings → General →
  Secrets is now a number of seconds typed or stepped (1 to 86,400), with "= 5 minutes" beside it and a "Never
  hide it by itself" switch, instead of the fixed list of minutes. A setting from before carries over (5 minutes →
  300 seconds). Open secret windows follow a change at once.

## [0.5.0] — 2026-10-30

### Added
- 2026-10-30: **Clear a link mark** — every row in the link sheet (and a marked row's right-click menu) can clear
  its mark once, or clear it and leave that bookmark out of link checks from then on; the bookmark's editor has
  the switch (*Leave out of link checks*) so it can be undone. Exports carry it.
- 2026-10-30: **The new address of a moved link is shown** in full under its row in the link sheet (selectable;
  right-click to copy), with *Open new…* to look at it in the browser before *Use new address* takes it.
- 2026-10-29: **Secret-only items** (Matt's pick from the tweaks canvas: row A, editor B) — a bookmark can now
  have no address at all when it has a secret (a passphrase, the Wi-Fi password). It lives in the same list as
  every other bookmark, so it can be ordered, colored, dragged and found by name or tag like any row. Its row
  shows a key instead of a site icon, the name opens nothing, and the button says **Secrets-Only** (web bookmarks
  keep **Secret**). The editor starts with a **Web page / Secret only** choice: Secret only hides the Address row
  and the secret switch; right-click a directory → **New secret here…**. Validate no longer stops on a missing
  address when the item has a secret.
- 2026-10-30: **Plain-text backups, by choice** — Settings → Backups → The secrets inside → Written as: sealed with
  this Mac's key (the default) or plain text, for the case where a backup must not hold anything encrypted. The
  pane warns in red while it is on; Verify says so; such a backup restores anywhere with no key or passphrase.
- 2026-10-29: **Backups** (Matt's pick, with his changes: "Enable backups", Verify, the key) — Settings → Backups:
  dated backup files of everything, secrets sealed with this Mac's key, written daily and on quit (or after
  changes, or by hand) into a folder you choose, only when something changed; keep the latest N, mark any as
  kept with a note so it never ages out; Verify reads one through and says whether its secrets open; Restore
  writes a kept backup of "now" first. Save a copy of the secret key, or set a passphrase that also opens the
  backups; on a new Mac, Restore from a file… asks for one or the other.
- 2026-10-29: **Check links** (Matt's pick: option B) — Settings → General → Check every address…, or right-click a
  directory → Check links in this directory…: each address is asked for once (HEAD, then GET when a server
  dislikes HEAD), five at a time, eight seconds each. One sheet lists the problems with their place: gone (404/410),
  moved (a permanent redirect — Use new address takes it), didn't answer (no such site, timed out, server error,
  login or robot block). Problem rows keep a red mark and a red line until the next check or an edit. Optional
  schedule, off by default: once a week or month, run quietly after launch with a banner above the list.
- 2026-10-29: **A browser per bookmark** (Matt's pick: editor only) — an "Opens in" row in the bookmark editor, "The
  browser from Settings" unless you choose one of the installed browsers for that bookmark. Nothing changes on
  the row. A browser removed later falls back to the Settings one with a sentence. Exports carry it.
- 2026-10-29: **The keyboard** — ↑ ↓ walk the rows of the open directory (or the search results, straight from
  the search box), Return opens the row under the keys, Space shows its secret, ⌘L copies its address, ⌘↑ goes up
  a directory; a Tabs menu with ⌘1 … ⌘9, ⌃Tab and ⌃⇧Tab.
- 2026-10-29: **Secret windows look after themselves** — a secret window hides itself after 5 minutes without
  being used (Settings → General: 1 to 30 minutes, or Never; clicking into it restarts the clock), and Settings
  can ask for Touch ID (or the Mac's password) before a secret is shown — one check covers the next minute.
- 2026-10-29: **Collapsible directories** (Matt's pick: option A, chevrons) — a directory with sub-directories
  gets a chevron in the folder tree; click it (or right-click → Show / Hide sub-directories) to open or close the
  branch. Everything starts closed; what you open is remembered in settings.json across launches. A closed
  directory's count reads "3 · 2 dirs". Selecting a directory, Show in place, Move to… and New directory inside…
  open the branch that leads there.
- 2026-10-29: **The secret window fits its text** — it opens just big enough to show the whole secret (measured
  in its own font), never smaller than 420 × 180 and never more than 60% of the screen's width or 70% of its
  height; a longer secret scrolls inside. Editing the secret refits the window unless you had resized it yourself.
- 2026-10-28: **The library** — tabs › directories › sub-directories › bookmarks, with the rules Matt set: at least one
  tab always; a tab or directory is deleted only when empty (the refusal names what is still inside); directory
  levels configurable (default 2, 1–6) and never lowered below what exists; bookmarks need a name and an address
  that can be opened; tags are tidied ("a, b,,A" → a, b); secrets are kept only when the box is ticked. Secrets live
  in an AES-GCM file beside the library (not the Keychain), never in library.json; damaged files are moved aside.
- 2026-10-28: **Moving things** — one function for drag and drop and Move to…: a bookmark or directory into another
  directory or a tab's top level, before another row, with "into itself" and "too deep" refused in plain words.
- 2026-10-28: **Search** across every tab — every word must match a name, address or tag (or a directory's name);
  each hit carries its path. Export / **validate** / import as one JSON: validate lists every problem with its place
  and changes nothing; import replaces everything (local secrets kept when the file left them out) or adds the
  file's tabs with fresh ids.
- 2026-10-28: **The window** (Matt's pick, mockup layout A): the search box in the title bar, the tabs across the top
  (drag to reorder, drop a row on one to move it there), the folder tree down the left with descriptions and counts,
  the open directory on the right — its sub-directories as rows, then its bookmarks with site icon, name (click opens
  in the chosen browser), description, Secret button, a pencil on hover, and a wash of its color code. Right-click
  menus everywhere; ⌘N new bookmark, ⇧⌘N new directory, ⌘T new tab, ⌘F search, ⌘E edit the open directory.
- 2026-10-28: **Editors** — bookmark (name, description, address with its icon, tags, color pills, where it lives,
  the secret box), directory (name, description, color), tab name, Move to…; a refusal shows in the sheet instead
  of closing it. **Secret window**: one per bookmark, select-to-copy, Edit bookmark…, Hide; follows edits and closes
  when the bookmark goes.
- 2026-10-28: **Settings** — General (the browser from those installed, directory levels, site icons, where things
  are kept), Color codes (4 to start, up to 10, any color and name, live preview, removal clears it everywhere),
  Appearance (App Starter's themes), Export & import (secrets off by default with a warning when on; Validate a
  file…; Import… with Add its tabs / Replace everything, confirmed).
- 2026-10-28: **Site icons** fetched once per host (the page's own link tags, then /favicon.ico), kept as 64 px PNG,
  the link glyph when none; can be turned off.
- 2026-10-29: **Dev hooks** — `newSecret`, `secret:<name>`, `keys:<codes>`, steps joined by `;`, `linkreport`,
  `linkreport:sheet`, `linkcheck`, `backupcheck`, `settings:backups`; the test suite grew to 126 (a test HTTP server
  on 127.0.0.1 for the link checker; no test can reach the real data folder).
- 2026-10-28: **Scripts, icon, docs** — BUILD_APP.sh / INSTALL_APP.sh as in App Starter; icon 2 "Tabbed folder"
  rendered by make_icns.sh without a browser; user guide, scripts and development docs; 48 tests.

### Fixed
- 2026-10-30: **Review 2** (four parallel reviewers over the Oct 29 work; verified findings only, each with a test):
  *secrets & backups* — Restore now refuses to go on when its safety backup can't be written and says "Nothing was
  restored" when the save was refused; a launch that couldn't read its secrets or bookmarks writes no automatic
  backup; a passphrase set for a key this Mac no longer has is noticed and left out; a crafted backup file can't
  crash the app; a failed quit-time backup holds the quit; settings.json is readable by you only.
  *link checker* — only headers are read, never a page (a 50 MB page used to cost 50 MB); redirects are followed
  only to web addresses and never from https down to http; a password typed into an address is never sent; a
  stopped run or one where nothing answered keeps the last results; Use new address refuses stale rows and
  non-web targets; plain words for redirect loops and odd answers.
  *window* — the arrow-key focus follows the rows; Show in place scrolls to the row; a secret window's hide clock
  runs on real use; a long one-line secret opens tall enough; the editor's refusal is visible; the whole tree
  row selects; buttons never truncate; the main window and Settings are tall enough for their sheets and panes;
  Unkeep and Remove passphrase ask first.
  *settings* — one wrongly typed value no longer resets every setting. *docs* — README, the user guide and the
  development notes brought up to date with everything added on Oct 29.
- 2026-10-30: **A test was writing the real settings file.** The browser-choice test built an AppModel without a
  scratch home, so every `swift test` (and every install) reset "Fetch site icons" and "Open bookmarks in" in the
  real settings.json. The test has its own scratch home now, and `Home.folder()` refuses the real folder whenever
  it runs under xctest, so no test can ever reach it again.
- 2026-10-28: **Deep review, core (13 verified findings, each with a regression test).** A damaged library.json
  now takes a copy of secrets.enc aside with it, so the next save can't prune the secrets the recovered file
  needs. Saving is two-phase (secrets old ∪ new → library.json → prune), so a save that fails on library.json
  loses no secret. The site-icon parser crashed on pages with letters like İ (it indexed the original text with a
  lowercased copy's indices); it now searches case-insensitively in place. The app's own export always validates
  (color codes need a name; a levels setting below what exists is repaired on load). Repeated ids are repaired on
  load and import. A drop onto the directory an item is already in keeps its place. Search ignores accents.
  Export files with an odd date or a text version still read, and a wrong shape names the place. Secrets messages
  no longer ask the user to move files the app already moved. Delete refusals count what the person sees.
- 2026-10-28: **Deep review, scripts and docs.** A failed build shows only the compiler's error lines (no
  9,000-character command lines) and leaves no stale app in build/; INSTALL_APP.sh says when the tests could not
  run, no longer warns about the app it moved out of build/, refuses --copy with --no-copy, says when it closes
  the open app. ⇧⌘N follows the New directory rule (inside, or beside when the levels don't allow deeper) instead
  of offering a directory that is always refused. Import… → Replace everything asks once more. Wording made
  consistent (color, directory list, level-3 directory, no bundle ids); docs corrected where they overstated.
- 2026-10-28: **Deep review, QA pass.** Two copies of the app on one bookmarks file silently overwrote each other:
  a second copy of the app now quits and brings the first forward, and a save is refused (with a plain sentence)
  when the file was changed by something else since it was read; a change that can't be saved is put back, so
  the window never shows what the disk doesn't hold. Addresses: javascript:, data: and the like are refused as
  not for a browser; a space inside a real address is written as %20; "two words" stays refused. Names made only of
  invisible characters are refused. An export's version must be at least 1. Duplicate tab names are noted once.
  A refused directory-levels change is shown under the picker in Settings instead of as an alert behind it.
- 2026-10-28: **Deep review, app layer (17 verified findings).** The icon fetch asked for a bookmark's full
  address — path and query included — so a bookmark like http://router/reboot would have been visited to find
  its icon; only the site's root is requested now. The editor's icon preview looked up every half-typed host;
  it now shows only what is already here. Fetches run four at a time instead of all at once, and an import
  fetches nothing (rows fetch as they appear). Open secret windows are brought up to date after an import and
  follow Appearance changes. The Dock icon brings the main window back when only a secret window is open.
  ⌘E, Rename Tab… and Sort are off while search results are showing. A directory dropped on its own row no
  longer alerts. The search match mark uses the accent (readable on tinted rows) instead of a fixed yellow.
  The browser list leaves out terminals that merely claim https:. A color's name is saved when typing pauses.
  Arriving icons redraw only the rows that show them; no per-bookmark window-frame leftovers in preferences.
