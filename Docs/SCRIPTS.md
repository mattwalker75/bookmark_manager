# Scripts

## INSTALL_APP.sh

```
./INSTALL_APP.sh [options…]

  (no options)    Check the tools, run the tests, build "Bookmark Manager.app" (BUILD_APP.sh) and
                  MOVE it to /Applications (asking first) — build/ is left without it.
  -t, --to DIR    Put the finished app in DIR instead of /Applications — for example
                  ./INSTALL_APP.sh --to ~/Desktop   (DIR must already exist).
  -u, --universal Build one app that runs on Apple-silicon and Intel Macs (for copying to another Mac).
  -s, --sign ID   Sign with a certificate from your Keychain, so the app keeps one identity across
                  rebuilds (below). Or set BOOKMARKMANAGER_SIGN_IDENTITY.
  -k, --skip-tests  Don't run the tests first (quicker when you just pulled new code).
  -p, --copy      Copy the app instead of moving it, so build/Bookmark Manager.app stays too.
  -n, --no-copy   Build only; leave the app in build/ and don't touch /Applications.
  -y, --yes       Don't ask before installing tools, installing on a failed test run, or replacing
                  an app that is already there.
  -c, --check     Only report what is installed or missing (and what the installed app was built
                  for and signed with); change nothing.
  -h, --help      This help.
```

Needs macOS 14 or newer and Xcode's command-line tools; when they are missing it offers to start Apple's
installer (`xcode-select --install`), then asks you to run it again. Test output goes to `build/test.log`; a red
suite asks "Build and install anyway?" (`--yes` goes ahead without asking). A failed build or copy stops with
the reason — the new app is copied beside the old one first and swapped in, so the old app is never replaced by
a broken one. If Bookmark Manager is open it offers to close it and opens the new version afterwards. Safe to run
again at any time: it rebuilds and replaces the app. Your bookmarks are not in the app — they stay in
`~/Library/Application Support/Bookmark Manager/`.

**Run it again after pulling new code.** (`BUILD_APP.sh` on its own only writes `build/`; the copy in
/Applications would stay old.)

## The signature

The default signature is **ad hoc**: its identity is a hash of the exact build, so every rebuild looks like a
different app to macOS. Nothing in Bookmark Manager depends on that — the secrets are in an encrypted file,
not the Keychain, so there is nothing macOS has to re-grant. If you still want one stable identity (for
example for a firewall rule), sign with a certificate of your own:

1. Keychain Access → menu Keychain Access → Certificate Assistant → **Create a Certificate…**
2. Name: `Bookmark Manager Local` (any name) · Identity Type: Self Signed Root · Certificate Type:
   **Code Signing** → Create.
3. Build with it: `./INSTALL_APP.sh --sign "Bookmark Manager Local"` (or `export
   BOOKMARKMANAGER_SIGN_IDENTITY="Bookmark Manager Local"` in your shell profile).

`./INSTALL_APP.sh --check` shows what the installed app is signed with.

## Using the app on another Mac

The finished `Bookmark Manager.app` is self-contained: copy the whole app to the other Mac (AirDrop, a USB
drive, a share) and open it. It needs macOS 14 or newer and nothing else installed. Move your bookmarks with
Settings → Export & import (tick *Include the secrets* if the other Mac should have them, and treat that file
with care).

- **Chips:** a normal build is for the kind of Mac that made it (Apple silicon or Intel). For a Mac with the
  other kind, build with `--universal`; that app runs on both.
- **"Apple could not verify…":** the app isn't from the App Store or notarized, so the first time macOS blocks
  it. On **macOS 15 or newer**: open it once, click *Done*, then System Settings → Privacy & Security → scroll
  down → **Open Anyway**, and confirm. On **macOS 14**: right-click the app → *Open* → *Open*. Once is enough.

## BUILD_APP.sh

Not meant to be run by a general user — `INSTALL_APP.sh` calls it for you. It is here for development (a
quick rebuild without the tests or the install step).

```
./BUILD_APP.sh [options…]

  (no options)        Release build for this Mac's kind of chip → build/Bookmark Manager.app
  -u, --universal     Build for Apple-silicon AND Intel Macs in one app
  -d, --debug         Debug build (faster to compile, slower to run)
  -o, --out DIR       Put the app somewhere else (default: build/; relative to where you run it)
  -s, --sign IDENTITY Sign with a Keychain certificate (see above); default: ad hoc
  -h, --help          This help.
```

Compiles with `swift build` (output in `build/build.log`; the last 40 lines are shown when it fails, and
nothing is packaged), then assembles the `.app`: the program as `Contents/MacOS/Bookmark Manager`,
`icon/BookmarkManager.icns`, an `Info.plist` (bundle id `com.mattwalker.bookmarkmanager`, version from
`Sources/BookmarkManagerCore/Version.swift`, macOS 14 minimum, and `NSAllowsArbitraryLoads` — on its own,
since macOS ignores it when `NSAllowsLocalNetworking` is there too — so site icons can be fetched from plain
`http://` addresses on your LAN or Tailscale) and the signature. A failed signature removes the half-made app.

## icon/make_icns.sh

Draws `icon/icon.svg` at 1024 px with the Mac's own image code (no browser needed), scales it with `sips` to
every size macOS wants and makes `icon/BookmarkManager.icns` with `iconutil`. The result is committed; run it
only after changing the SVG.
