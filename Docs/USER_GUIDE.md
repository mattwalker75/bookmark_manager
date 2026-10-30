# Bookmark Manager — user guide

## The idea
Bookmarks are easier to find when they have a place. Bookmark Manager gives them three levels of places —
**tabs**, **directories** inside a tab, **sub-directories** inside a directory — plus a color code and tags, and
a search that looks everywhere at once. A bookmark can also carry a **secret** (a login, a token) that stays
hidden until you ask for it.

## Tabs
- The tabs run across the top of the window. There is always at least one; a new library starts with a tab called
  *Bookmarks* — rename it with **Rename tab…** (bottom of the folder tree, or right-click the tab).
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
- **Edit…** (the button on its page, or right-click) changes the name, description and color.
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
    removed later, the bookmark opens in the Settings browser and says so once.
  - **Color** — one of the color codes from Settings; the row gets a light wash of that color.
  - **Secret** — tick *This bookmark has a secret* and type as many lines as you like (a user name, a password, a
    recovery address, a token, blank lines between for reading). It is kept encrypted on this Mac.
- The row shows the icon, the name, the description, a **Secret** button when there is one, and a pencil while
  the pointer is over it. Right-click for Open, Copy address, Show secret, Edit…, Move to…, Delete….
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
- A secret window also **hides itself** after a while without being used — 5 minutes unless you change it in
  Settings → General (1 to 30 minutes, or Never). Clicking into the window starts the clock again.
- Settings → General can **ask for Touch ID** (or your Mac's password) before a secret is shown. One check covers
  the next minute, so opening several secrets in a row asks once. Turn it off there whenever you like.
- Secrets never go into the bookmarks file, and go into an export only when you tick the box (see Export).

## Arranging
- Bookmarks and directories stay in the order you put them. **Sort by name** on a directory's page sorts that
  directory's sub-directories and bookmarks once; after that the order is yours again.
- **Drag** a row (a bookmark or a sub-directory) onto a directory in the list on the left, onto a sub-directory row, or onto a
  tab to move it there. Drop a bookmark on another bookmark to put it just before that one; drop it in the space
  under the last row to put it at the end. A directory dropped on a bookmark goes into that bookmark's directory.
- **Move to…** (right-click, or *In* in the bookmark's editor) does the same from a list of every place.
- A move that can't work — a directory into itself, or deeper than the levels allow — is refused with the reason.

## Search
- The box in the title bar (⌘F) searches as you type: every word must be found in a bookmark's **name, address or
  tags**, or in a **directory's name**, in **every tab**. Descriptions are not searched.
- Results are grouped by tab. Each shows where it lives (*Work › Self-hosted apps › Admin pages*), what matched,
  and the Secret button. Click a name to open it; **Show in place** switches to its tab, opens its directory and
  marks the row for a moment. **Clear** (or Esc in the box) goes back.

## The keyboard
- **↑ ↓** walk the rows of the open directory (sub-directories first, then bookmarks); the row under the keys
  gets the accent outline. **Return** opens it: a bookmark in your browser, a secret-only item's secret, a
  sub-directory on the page. **Space** shows the row's secret. **⌘L** copies its address. **⌘↑** goes up to the
  enclosing directory, with the one you left under the keys.
- While the cursor is in the search box, ↑ ↓ walk the results and Return opens the one under the keys; every
  other key keeps typing.
- **⌘1 … ⌘9** switch to that tab (the Tabs menu lists them); **⌃Tab** and **⌃⇧Tab** go to the next and previous tab.
- As before: ⌘N new bookmark, ⇧⌘N new directory, ⌘T new tab, ⌘F search, ⌘E edit the open directory.

## Color codes
- Settings → **Color codes**: each color has a name — *Important*, *Work*, *Personal*, *Reference* to start.
  Change a color (click the swatch) or its name, add more (up to 10), remove one. Removing a color asks first and
  says how many bookmarks and directories lose it, then clears it from them.
- On the rows only the tint shows; the name appears in the editor's color pills and in Settings.

## Settings
- **General** — *Open bookmarks in*: the Mac's default browser (whatever app that is), or any browser installed
  on this Mac. *Directory
  levels inside a tab*. *Fetch site icons* (off = no network at all; icons already fetched still show). Where
  the files are kept, with Show in Finder.
- **Color codes** — above.
- **Appearance** — Light / Dark / Follow the system, the accent color, and themes of your own.
- **Export & import** — below.

## Export, validate and import
- **Export…** writes everything — tabs, directories, sub-directories, bookmarks with their descriptions,
  addresses, tags and colors, the color codes, the directory-levels setting — as one `.json` file. Easy to read,
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

## One copy at a time
Opening Bookmark Manager twice just brings the open one forward. If something else changes the bookmarks file
while the app is open (a second copy run by hand, an edit to the file), the next change is refused with a
sentence saying so, and nothing is lost: quit the other copy, then quit and reopen this one.

## Where things are kept
`~/Library/Application Support/Bookmark Manager/` — `library.json` (the bookmarks, no secrets), `secrets.enc`
and `secret.key` (the secrets, encrypted; the key is readable by you only), `settings.json`, `icons/`. A damaged
bookmarks or secrets file is moved aside with the date in its name (the secrets are kept beside a damaged
bookmarks file), never overwritten; a damaged settings file is ignored and replaced.
