# Comic Ghost

A native macOS comic reader for local collections. Swift and SwiftUI, no server, no account, no cloud.

Your library never leaves your machine. The one thing that can reach the internet is an optional update check, off until you turn it on — see [Privacy and the network](#privacy-and-the-network).

Point it at a folder and it handles the rest — series grouping, cover art, reading progress, and a reader built for actually reading rather than clicking around.

**[User manual](MANUAL.md)** · **[Download](https://github.com/maxwellghost/ComicGhost/releases/latest)**

---

## Features

### Library

- **Watched folders** — recursive scanning, picks up new files on rescan, drops entries whose files are gone
- **Multiple named libraries** — each with its own folder and access bookmark, switched from the sidebar
- **Per-folder scanning** — rescan or re-parse a single series instead of walking the whole collection
- **Series-first browsing** — one tile per series with stacked-cover art, issue counts, and read progress
- **Umbrella folders** — nested structures group automatically (Dragon Ball → Dragon Ball Z, Super)
- **Series sidebar** — collapsible list of every series with unread counts
- **Smart Collections** — saved filters built from rules (series, title, status, rating, favorite, special, queued, page count, date added) with match-all/any and a live match count
- **Custom labels** — colored, favoritable, attachable to any issue, each with its own sidebar row
- **Sections** — Library, New, In Progress, Reading List, Favorites, Completed
- **Continue reading** and **Recently added** shelves
- **Search**, **sort** (title, date added, recently read, unread first, rating)
- **Grid or list view**, three cover sizes, sticky section headers, collapsible series sections
- **Stats** — totals, pages read, rating distribution, per-series completion
- **Undo** — ⌘Z across library edits

### Library Tools

- **Missing issues** — finds gaps in each series' numbered run, collapsed into readable ranges
- **Duplicates** — same issue present more than once, with open and trash actions per file
- **Storage report** — total size and the biggest series by disk usage
- **File integrity** — opens every archive to find corrupt, empty, or missing files
- **Export** — the whole catalogue as CSV or JSON

### Organization

- Statuses computed automatically: New, Unread, In Progress, Completed
- Mark read/unread per issue or across a whole series
- Favorites, 1–5 star ratings with series-level averages
- Reading list queue with drag-to-reorder
- Specials, annuals, and one-shots detected and grouped apart from the numbered run
- Remove from library (option to move item to trash)

### Reader

- Resumes exactly where you left off; rolls forward into the next issue and back into the previous one
- **Three modes** — paged, two-page spread with splash detection, and continuous vertical scroll
- **Manga mode** — right-to-left, saved per series
- **Fit page / fit width**, with spread pairing offset for runs that pair wrong
- Pinch zoom to 6×, two-finger scroll panning, drag panning, ⌘-scroll zoom, double-click to toggle 2.5×
- **Trackpad swipe** to turn pages
- **Bookmarks**, **jump to page**, **page thumbnail filmstrip**
- **Image adjustments** — brightness, contrast, gamma, grayscale, auto-contrast, page rotation
- **Auto-crop margins** — optional trimming of uniform scan borders; off by default so the original scan is untouched
- **Floating magnifier**
- Next-page preloading, hidden or auto-hiding chrome, edge progress bar, full screen
- Keeps the display awake while reading
- Controls legend, recallable with `?`

### macOS integration

- **Open from Finder** — double-click a comic or use Open With
- **Drag and drop** files onto the window to import them into the active library
- **Spotlight** — search your library from system search and open results directly
- **Dock badge** showing unacknowledged new issues

### Metadata

- Reads **ComicInfo.xml** when present
- Otherwise parses filenames: strips release-group tags, brackets, and years; handles `#12`, `034`, `170b`, `Annual 3`, `v01`, decimals
- Falls back to the containing folder name for series
- Manual editing with a lock so hand-fixes survive re-parsing
- Rename and merge series across all their issues

### Appearance

- **21 themes across 9 families** — Catppuccin, Nord, Gruvbox, Dracula, Kanagawa, Tokyo Night, Rosé Pine, Everforest, One, and an SNES-inspired purple/grey pair. Light themes flip the whole app's color scheme.
- Accent color picker, optional frosted glass effect, ghost mascot empty states, loading skeletons

### Backup

Reading progress, ratings, favorites, labels, bookmarks, collections, and manual metadata edits live only in the app, not in your comic files. Settings › Backup exports all of it as JSON and restores it by matching on file path.

---

## Supported formats

| Format | Backend |
|---|---|
| `.cbz` `.zip` | ZIPFoundation |
| `.cbr` `.rar` | bundled `unrar` |
| `.cb7` `.7z` `.tar` | macOS `bsdtar` (libarchive) |
| `.pdf` | PDFKit (pages rendered and cached) |

Page images: JPEG, PNG, WebP, GIF, BMP, TIFF, HEIC, AVIF.

---

## Building

Requires Xcode 16+ and a recent macOS.

1. Clone the repo and open `ComicGhost.xcodeproj`
2. Add the **ZIPFoundation** package if it isn't resolved automatically:
   File → Add Package Dependencies → `https://github.com/weichsel/ZIPFoundation`
3. Build and run (⌘R)

`unrar` is bundled in the repo and copied into the app at build time — no download or setup needed. 7z, tar, PDF, and Spotlight all use frameworks that ship with macOS.

To make Comic Ghost the default handler for `.cbz` and `.cbr`, see
`FileAssociations-Info-plist.md` — those are Xcode target settings rather than code.

### First run

Open Settings (⌘, or the gear in the toolbar), add a library folder, then hit rescan. Large collections import in parallel with a progress banner.

---

## Privacy and the network

Comic Ghost is a local reader. It has no server, no account, no sync, and no
telemetry. Your comics, reading progress, notes, bookmarks, ratings and labels
live on your machine and are never uploaded anywhere. There is no analytics, no
crash reporting, and no phone-home.

There is exactly one thing in the app that can open a network connection, and it
is off until you switch it on:

**Update check.** Enable it in Settings and Comic Ghost asks GitHub, at most once
a day, whether a release newer than your build exists. If one does, a dot appears
on the Settings cog and Settings offers a button that opens the release page in
your browser.

What that request involves:

- It is an anonymous HTTPS GET to the public GitHub releases API for this repo.
- It sends nothing about you or your library — no identifiers, no file names, no
  counts, no usage data. The request body is empty and carries no cookies.
- GitHub, like any web server, sees an IP address and a timestamp. That is the
  entire privacy cost, and it is why the feature is opt-in rather than on by
  default.
- Failures are silent. Offline is a normal state for this app, not an error.

**Nothing downloads or installs by itself.** The button opens a page in your
browser; you download and install by hand, exactly as you did the first time.
Automatic updating is deliberately not offered: the app is ad-hoc signed rather
than notarized, so anything downloaded is quarantined by macOS, and making silent
updates work would mean the app stripping that protection off a binary it just
fetched from the internet. Doing it properly would require Developer ID signing
and notarization, which this project does not use.

If you never enable the setting, Comic Ghost makes no network connections at all.

---

## Notes

- Your comics folder is never modified except when you explicitly remove an issue, which moves the file to the Trash.
- Folder access persists across launches via security-scoped bookmarks. If you move a library folder, re-pick it in Settings.
- PDFs render their pages on first open and cache the result, so a long PDF takes longer to open the first time than an equivalent CBZ.

## Acknowledgements

Comic Ghost bundles the `unrar` command-line utility, copyright Alexander
Roshal, used under the UnRAR license — see `unrar/license.txt`. It is used
only to extract RAR archives. Per that license, the UnRAR code may not be
used to develop a RAR-compatible archiver or to re-create the RAR
compression algorithm, and Comic Ghost does neither.

CBZ support uses [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)
by Thomas Zoechling, MIT licensed — see `ZIPFoundation-0.9.20/LICENSE`.

### A note on licensing

Comic Ghost's own source is GPL-3.0. The bundled `unrar` binary is not
covered by it — it's a separate program under RARLAB's own license, which
is not GPL-compatible, invoked as an external process rather than linked
into the app. It's included for convenience; see `UNRAR-LICENSE.txt` for
its terms.
