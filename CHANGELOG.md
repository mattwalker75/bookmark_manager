# Changelog

All notable changes to Bookmark Manager (Keep a Changelog style; dates are when the change was made).

## [0.1.0] — unreleased

### Added
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
