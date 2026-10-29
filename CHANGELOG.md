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
