# Changelog

All notable changes to Bookmark Manager (Keep a Changelog style; dates are when the change was made).

## [0.1.0] — unreleased

### Added
- 2026-10-29: **Secret-only items** (Matt's pick from the tweaks canvas: row A, editor B) — a bookmark can now
  have no address at all when it has a secret (a passphrase, the Wi-Fi password). It lives in the same list as
  every other bookmark, so it can be ordered, colored, dragged and found by name or tag like any row. Its row
  shows a key instead of a site icon, the name opens nothing, and the button says **Secrets-Only** (web bookmarks
  keep **Secret**). The editor starts with a **Web page / Secret only** choice: Secret only hides the Address row
  and the secret switch; right-click a directory → **New secret here…**. Validate no longer stops on a missing
  address when the item has a secret.
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
- 2026-10-28: **Scripts, icon, docs** — BUILD_APP.sh / INSTALL_APP.sh as in App Starter; icon 2 "Tabbed folder"
  rendered by make_icns.sh without a browser; user guide, scripts and development docs; 48 tests.

### Fixed
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
