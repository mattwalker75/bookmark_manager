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
- The directory list on the left shows the open tab's directories and their sub-directories, each with its
  description (if it has one) and how many bookmarks sit directly in it. Click one to open it on the right.
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
- A bookmark has:
  - **Name** — what the row shows. Click it to open the address in your browser.
  - **Description** — optional, a sentence or two, shown in smaller text under the name.
  - **Address** — `https://…` (or just `example.com`; https is assumed). The site's icon is fetched for the row.
  - **Tags** — optional words, separated by commas, for the search only. They never show on the row.
  - **Color** — one of the color codes from Settings; the row gets a light wash of that color.
  - **Secret** — tick *This bookmark has a secret* and type as many lines as you like (a user name, a password, a
    recovery address, a token, blank lines between for reading). It is kept encrypted on this Mac.
- The row shows the icon, the name, the description, a **Secret** button when there is one, and a pencil while
  the pointer is over it. Right-click for Open, Copy address, Show secret, Edit…, Move to…, Delete….
- Deleting a bookmark asks first. Its secret goes with it.

## Secrets
- Click **Secret** on a row (or in the search results) and the secret opens in a small window of its own. Select
  the part you need — a word, a line — and copy it (⌘C, or double-click a word and right-click → Copy). There is
  no Copy button on purpose: a secret usually holds several things.
- **Hide** closes the window. Closing it any other way does the same. **Edit bookmark…** opens the editor.
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

## Color codes
- Settings → **Color codes**: each color has a name — *Important*, *Work*, *Personal*, *Reference* to start.
  Change a color (click the swatch) or its name, add more (up to 10), remove one. Removing a color asks first and
  says how many bookmarks and directories lose it, then clears it from them.
- On the rows only the tint shows; the name appears in the editor's color pills and in Settings.

## Settings
- **General** — *Open bookmarks in*: the Mac's default browser, or any browser installed on this Mac. *Directory
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

## Where things are kept
`~/Library/Application Support/Bookmark Manager/` — `library.json` (the bookmarks, no secrets), `secrets.enc`
and `secret.key` (the secrets, encrypted; the key is readable by you only), `settings.json`, `icons/`. A damaged
bookmarks or secrets file is moved aside with the date in its name (the secrets are kept beside a damaged
bookmarks file), never overwritten; a damaged settings file is ignored and replaced.
