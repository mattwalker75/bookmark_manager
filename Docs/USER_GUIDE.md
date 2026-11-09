# Bookmark Manager — user guide

## The idea
Bookmarks are easier to find when they have a place. Bookmark Manager gives them three levels of places —
**tabs**, **directories** inside a tab, **sub-directories** inside a directory — plus a color code and tags, and
a search that looks everywhere at once. A bookmark can also carry a **secret** (a login, a token) that stays
hidden until you ask for it.

## Tabs
- The tabs run across the top of the window. There is always at least one; a new library starts with a tab called
  *Bookmarks* — rename it with **Rename tab…** (bottom of the folder tree, or right-click the tab → Rename…).
- **+** at the right of the tab bar (or ⌘T) makes a new tab. Drag a tab along the bar to reorder; right-click for
  Rename, New directory, Move left / right, Delete.
- A tab can only be deleted when it is **empty** — no bookmarks, no directories — and never the last one.

## Directories and sub-directories
- The directory list on the left shows the open tab's directories, each with its description (if it has one)
  and how many bookmarks sit directly in it. Click one to open it on the right.
- A directory with sub-directories has a **chevron** in front of it: click the chevron (or right-click → Show /
  Hide sub-directories) to open or close that branch. Closed, its count reads "3 · 2 dirs" so you can see there
  is more inside. The app remembers which branches you left open, in every tab, across launches. Opening a
  directory from the search (Show in place), Move to…, or making a new directory inside one, opens the branch
  that leads to it.
- **New directory** (bottom of the directory list, the button at the top of a directory's page, ⇧⌘N, or
  right-click → New directory inside…) makes one inside the open directory — or beside it, when the levels don't
  allow one deeper. Give it a name, an optional description, a color.
- Directories may go **two levels deep** by default (a directory with a sub-directory in it). Settings → General
  changes that (1 to 6). It can't be lowered while a deeper directory exists.
- **Edit…** (the button on its page, or right-click) changes the name, description and color — and can give the
  directory **notes** (see Notes): tick *This directory has notes*. Its row then shows a **Notes** button.
- A directory can only be deleted when it is **empty**. If it still holds something, the app says what, and nothing
  happens — move or delete what is inside first. That is on purpose, so a full directory never goes by accident.

## Bookmarks
- **New bookmark** (the + in the title bar, the button on a directory's page, or ⌘N) adds one to the open
  directory (or the tab's top level); right-click a directory → **New bookmark here…** adds one to that directory.
- The editor starts with a choice: **Web page** (an address, with a secret if you like) or **Secret only** (no
  address at all — a passphrase for your phone, the Wi-Fi password). Right-click a directory → **New secret here…**
  opens it with Secret only already picked. You can switch an item from one kind to the other later in Edit.
- A bookmark has:
  - **Name** — what the row shows. Click it to open the address in your browser.
  - **Description** — optional, a sentence or two, shown in smaller text under the name.
  - **Address** — `https://…` (or just `example.com`; https is assumed; a space inside is written as %20).
    `javascript:` and `data:` are not addresses a browser should open from a bookmark, so they are refused.
    The site's icon is fetched for the row — from the site's front page only, never from the bookmark's own
    address, and a few at a time.
  - **Tags** — optional words, separated by commas, for the search only. They never show on the row.
  - **Opens in** — the browser from Settings unless you pick one of the installed browsers here, for the odd site
    that only behaves in one of them. Set it and forget it: the row shows nothing about it. If that browser is
    removed later, the bookmark opens in the Settings browser and says so once per launch.
  - **Color** — one of the color codes from Settings; the row gets a light wash of that color.
  - **Secret** — tick *This bookmark has a secret* and type as many lines as you like (a user name, a password, a
    recovery address, a token, blank lines between for reading). It is kept encrypted on this Mac.
  - **Notes** — tick *This bookmark has notes* and type plain notes for yourself (see Notes). Not a secret.
- The row shows the icon, the name, the description, a **Secret** button and a **Notes** button when there are
  any, and a pencil while the pointer is over it. Right-click for Open, Copy address, Show secret, Show notes,
  Edit…, Move to…, Delete….
- A **secret-only** item sits in the same list as everything else (drag it, color it, move it like any row). Its
  row shows a key instead of a site icon, its name opens nothing, and its button says **Secrets-Only** — click
  that, exactly as you click Secret on a web bookmark. Without a description the row says "Secret only — no address".
  A secret-only item must have a secret: the editor won't add one with nothing typed, and it can't lose its secret
  without getting an address instead.
- Deleting a bookmark asks first. Its secret goes with it.

## Secrets
- Click **Secret** (or **Secrets-Only**) on a row, or in the search results, and the secret opens in a window of
  its own, sized to show the whole text: a one-line secret gets a small window, a long one grows until it would
  take more than about 60% of the screen's width or 70% of its height, and scrolls inside after that. You can
  still resize it by hand. Select
  the part you need — a word, a line — and copy it (⌘C, or double-click a word and right-click → Copy). There is
  no Copy button on purpose: a secret usually holds several things.
- **Hide** closes the window. Closing it any other way does the same. **Edit bookmark…** opens the editor.
- A secret window also **hides itself** after a while without being used — 300 seconds (5 minutes) unless you
  change it in Settings → General: any number of seconds from 1 to 86,400, 5 or 999 as you like, or the "Never
  hide it by itself" switch. Any click, key or scroll in the window counts as using it; a
  window you are working in never closes under you, one you left behind does.
- Settings → General can **ask for Touch ID** (or your Mac's password) before a secret is shown. One check covers
  the next minute, so opening several secrets in a row asks once. Turn it off there whenever you like.
- **Bigger or smaller text**: ⌘+ and ⌘− (or ⌘=) change the text size in the window in front of you, ⌘0 puts it
  back; the window grows or shrinks to fit (unless you resized it by hand). The size a secret window *opens*
  with is in Settings → General → Secrets → *Text size in a secret window* (9 to 36 points, 14 to begin with).
  The View menu has the same three items.
- Secrets never go into the bookmarks file, and go into an export only when you tick the box (see Export).

## Notes
- A bookmark can carry **notes**: plain text for yourself — where you left off on a project ("hero photo swapped,
  still need the phone crop"), or how to find your way around a site that hides things ("Billing is under
  Account › Billing › Invoices, not Payments"). Notes are **not secrets**: they are kept as they are in the
  bookmarks file, go into every export and backup, and the search finds them.
- **A directory can carry notes too** — a project's status, what lives where. Tick *This directory has notes* in
  its editor; its row (on the directory's page, and in search results) gets the same **Notes** button, and the
  window has **Show directory** in place of Open bookmark. Everything below applies to both.
- Tick **This bookmark has notes** in the editor and type as many lines as you like (or nothing yet). The row then
  shows a **Notes** button beside the Secret one; a secret-only item can have notes too.
- Click **Notes** (or press ⇧Space on the row, or right-click → Show notes) and the notes open in a window of
  their own, sized to the text like a secret window, that you can move around and leave open all day — it never
  hides by itself. It opens **read-only**, so nothing can be typed into it by accident; addresses in it are
  clickable. **Edit** turns the text box on; then **Save** (⌘S) keeps what you typed and **Cancel** puts the
  notes back. Close the window with changes in hand and it asks: *Save*, *Don't Save* or *Cancel* (quitting the
  app asks too). The bottom line says when the notes were last changed.
- **Delete notes…** asks first, then throws the notes away and turns them off: the bookmark stays, the Notes
  button goes. To have notes again, tick the switch in the editor and type them. Turning the switch off in the
  editor asks the same question.
- **Open bookmark** in the window opens the site, so instructions and the site sit side by side.
- **Bigger or smaller text**: ⌘+ and ⌘− (or ⌘=) in the window, ⌘0 puts it back. The size a notes window opens
  with is in Settings → General → Notes → *Text size in a notes window*.

## Arranging
- Bookmarks and directories stay in the order you put them. **Sort by name** on a directory's page sorts that
  directory's sub-directories and bookmarks once; after that the order is yours again.
- **Drag** a row (a bookmark or a sub-directory) onto a directory in the list on the left, onto a sub-directory row, or onto a
  tab to move it there. Drop a bookmark on another bookmark to put it just before that one; drop it in the space
  under the last row to put it at the end. A directory dropped on a bookmark goes into that bookmark's directory.
- **Move to…** (right-click, or *In* in the bookmark's editor) does the same from a list of every place.
- A move that can't work — a directory into itself, or deeper than the levels allow — is refused with the reason.

## Search
- The box in the title bar (⌘F) searches as you type: every word must be found in a bookmark's **name, address,
  tags or notes**, or in a **directory's name or notes**, in **every tab**. Descriptions are not searched.
- Results are grouped by tab. Each shows where it lives (*Work › Self-hosted apps › Admin pages*), what matched,
  and the Secret and Notes buttons. Click a name to open it; **Show in place** switches to its tab, opens its directory and
  marks the row for a moment. **Clear** (or Esc in the box) goes back.

## The keyboard
- **↑ ↓** walk the rows of the open directory (sub-directories first, then bookmarks); the row under the keys
  gets the accent outline. **Return** opens it: a bookmark in your browser, a secret-only item's secret, a
  sub-directory on the page. **Space** shows the row's secret, **⇧Space** its notes (a sub-directory's too). **⌘L** copies its address. **⌘↑** goes up to the
  enclosing directory, with the one you left under the keys.
- In a secret or notes window: **⌘+** bigger text, **⌘−** smaller, **⌘0** back to the size from Settings.
- While the cursor is in the search box, ↑ ↓ walk the results and Return opens the one under the keys; every
  other key keeps typing.
- **⌘1 … ⌘9** switch to that tab (the Tabs menu lists them); **⌃Tab** and **⌃⇧Tab** go to the next and previous tab.
- As before: ⌘N new bookmark, ⇧⌘N new directory, ⌘T new tab, ⌘F search, ⌘E edit the open directory.

## Checking links
- Settings → General → **Check every address…** asks each bookmark's address once, a few at a time, and lists
  the ones that didn't answer as expected, each with where it lives: **gone** (the page is not there any more),
  **moved** (the site says it has a new address — it is shown in full under the row, *Open new…* lets you look at
  it in the browser first, *Use new address* puts it into the bookmark), and **didn't answer** (no such site,
  timed out, a server error, or a login page or robot block — those can still work fine in your browser). Show in
  place and Edit… are right there, and the list is a window of its own: it stays open while you go through the
  bookmarks one by one, and closes with **Done** or its close button.
- Right-click a directory → **Check links in this directory…** (or a tab → **Check links in this tab…**) does the
  same for just that part; the Bookmarks menu has **Check Links in This Directory…** and **Check Every Address…**.
  The window has **Stop** while it runs and **Check again** after; Settings → General keeps **Last results…**.
- The check reads only each page's headers, never the page; it follows a site's "moved" only to another web
  address, never from https down to plain http (that is reported as "Sent to an unencrypted address"), and never
  sends a password typed into an address. If nothing answers at all (no connection), the last results are kept.
- After a check, a problem bookmark wears a small red mark on its icon and a red line under its name saying what
  happened and when. The mark goes when you edit the address or the next check finds it fine — or when you
  **Clear** it in the list (or right-click the row → Clear link mark). Clear offers two things: clear this mark
  once, or clear it and **leave this bookmark out of link checks** from now on, for a site that always turns the
  check away but works fine in the browser. That switch is in the bookmark's editor too, so it can be undone.
- **Check all addresses on their own** (Settings → General) is off unless you turn it on: once a week or once a
  month, the app checks quietly a few seconds after launch and puts a line above the list when something didn't
  answer. Nothing else in the app visits a bookmark's full address.

## Finding duplicates
- Settings → General → **Find duplicate bookmarks…** (or the Bookmarks menu) lists every group of bookmarks that
  point at the same page, each with where it lives. Two kinds: **same address** (letter for letter) and **same
  page, written differently** — http or https, with or without www, a trailing slash, tracking bits after "?"
  (utm_…, fbclid and the like), a #part. Each row has Show in place, Edit… and Delete… (asked first). Nothing is
  deleted by itself, and the list looks at the library as it is right now, so there is nothing to re-run. It is a
  window of its own that stays open while you work through the groups; **Done** closes it.
- Some duplicates are meant: one bookmark per Gmail account, all at the same address. Click **Meant to be the
  same — keep all N** on the group and every bookmark in it is marked; the group is left out from then on. The
  mark is the **Leave out of duplicate checks** switch in each bookmark's editor, so it can be undone one by one;
  the window's **Show the N left out** checkbox shows those groups dimmed, with **Look at these again** to unmark
  them all. If a new bookmark lands at a marked page later, the group shows again with the new one in it.
- Secret-only items have no address, so they are never duplicates.

## Color codes
- Settings → **Color codes**: each color has a name — *Important*, *Work*, *Personal*, *Reference* to start.
  Change a color (click the swatch) or its name, add more (up to 10), remove one. Removing a color asks first and
  says how many bookmarks and directories lose it, then clears it from them.
- On the rows only the tint shows; the name appears in the editor's color pills and in Settings.

## Settings
- **General** — *Open bookmarks in*: the Mac's default browser (whatever app that is), or any browser installed
  on this Mac. *Directory levels inside a tab*. **Secrets**: how long a secret window stays, the text size it opens
  with, and Touch ID before a secret. **Notes**: the text size a notes window opens with. **Links**: Check every
  address…, Last results…, the schedule, Find duplicate bookmarks…, and *Fetch site icons* (off = no network
  for icons; icons already fetched still show). Where the files are kept, with Show in Finder.
- **Color codes** — above.
- **Appearance** — Light / Dark / Follow the system, the accent color, and themes of your own.
- **Backups** — above.
- **Export & import** — below.

## Export, validate and import
- **Export…** writes everything — tabs, directories, sub-directories, bookmarks with their descriptions,
  addresses, tags, notes and colors, the color codes, the directory-levels setting — as one `.json` file. Easy to read,
  easy to keep as a backup.
  - **Include the secrets** is off unless you tick it. Ticked, the file holds every secret decrypted, in plain
    text — keep that file somewhere safe and delete it when you are done.
- **Validate a file…** reads a file and shows what it found: the counts, and every problem with where it is
  (*Work › Vendors › Webull: its address can't be opened*). Red marks stop an import; the others are notes.
  Nothing is changed. If the file is fine, you can import it from there.
- **Import…** validates first, then asks how the file should come in:
  - **Add its tabs beside mine** — the file's tabs are added as copies; yours stay as they are.
  - **Replace everything here** — what is here is thrown away first (it asks again). If the file was exported
    without secrets, bookmarks that are already here keep the secrets they have.
- **Import from a browser…** brings a browser's bookmarks in as **one new tab**, its folders as directories and
  sub-directories, its links as bookmarks, in the browser's order. Export them from the browser first, as an
  HTML file: Safari → File → Export → Bookmarks…; Chrome → Bookmarks → Bookmark Manager → ⋮ → Export bookmarks;
  Firefox → Bookmarks → Manage Bookmarks → Import and Backup → Export Bookmarks to HTML… (Edge and Brave much the
  same). A sheet shows what is coming — how many directories and bookmarks, which browser it looks like — and
  lets you name the tab. If the file's folders go deeper than your directory levels, the levels are raised to
  fit (up to 6); anything deeper still is folded into the directory above it, so no bookmark is lost.
  Bookmarklets and other things that aren't web addresses are left out and counted; so are empty folders.
  Nothing already here changes, and nothing in the browser. Run *Find duplicate bookmarks…* afterwards if you
  think some of them were here already.

## Backups
- Settings → **Backups**. **Enable backups** is on from the start: a backup is one file (`Bookmark Manager
  2026-10-29 14-02-33.bmbackup`) holding everything — tabs, directories, bookmarks, color codes, the directory
  levels and the secrets — written into the Backups folder beside your bookmarks (or any folder you choose:
  iCloud Drive, a Data Syncer folder) only when something changed since the last one.
- **When:** every day · every day and when the app quits (the usual) · after every change, at most once an hour ·
  only when you click **Back up now**. "Every day" is looked at when the app launches and then once an hour while
  it stays open. **Keep the latest** 5 to 90; older ones fall off the end — except the ones you mark **Keep…**
  (with a note, if you like: "before the big re-sort"), which stay for good. **Unkeep** asks first when the backup
  would be deleted at the next backup; the trash button deletes one file after asking. With backups switched off
  nothing is written on its own, but Back up now and the safety backup before a restore still work.
- **Verify…** on any backup reads it right through and says what it holds and whether its secrets open.
  **Restore…** (from the Verify sheet) replaces everything here with what the backup holds; a kept backup of the
  way things were is written first, so a restore can itself be undone — and if that safety backup can't be
  written, nothing is restored. (Only a library with nothing of yours in it yet skips the safety backup.)
- If the app couldn't read its secrets or its bookmarks when it launched, it writes no automatic backup that day,
  so a good backup is never pushed out by an empty one. A failed backup at quit time asks whether to quit anyway.
- **The secrets inside** are sealed with this Mac's secret key, the same as on disk. So: **Save a copy of the
  secret key…** once, somewhere safe (a password manager, a USB stick); **Show the key in Finder** finds it.
  Optionally **set a passphrase**; from then on each backup also opens with the words alone. If this Mac's key is
  ever replaced (that happens when the secrets file was unreadable), the pane says the passphrase no longer
  matches and asks you to set it again.
- **Written as** can instead be **Plain text** — then every secret is written in the clear in each backup from
  then on, readable by anyone who has the file (or a copy Time Machine or iCloud makes of it). Off unless you
  choose it; the pane says so in red while it is on. Such a backup restores on any Mac with no key or passphrase.
- **Starting over on a new Mac:** install Bookmark Manager, open Settings → Backups → **Restore from a file…**,
  pick the backup. The app finds its own new key doesn't open the secrets and asks for either the key file you
  saved or the passphrase. Verify, then Restore. The secrets are re-sealed with the new Mac's key from there on.
- Note: anyone with a backup *and* the key (or the passphrase) can read the secrets. Keep the key like a password.

## One copy at a time
Opening Bookmark Manager twice just brings the open one forward. If something else changes the bookmarks file
while the app is open (a second copy run by hand, an edit to the file), the next change is refused with a
sentence saying so, and nothing is lost: quit the other copy, then quit and reopen this one.

## Where things are kept
`~/Library/Application Support/Bookmark Manager/` — `library.json` (the bookmarks, no secrets), `secrets.enc`
and `secret.key` (the secrets, encrypted; the key is readable by you only), `settings.json`, `icons/`,
`linkcheck.json` (the last link check) and `Backups/` (unless you chose another folder). A damaged
bookmarks or secrets file is moved aside with the date in its name (the secrets are kept beside a damaged
bookmarks file), never overwritten; a damaged settings file is ignored and replaced.
