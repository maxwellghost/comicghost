# Comic Ghost

A native macOS comic reader for local collections. Built with Swift and SwiftUI, themed in Catppuccin Mocha.

Point it at a folder and it handles the rest — series grouping, cover art, reading progress, and a reader designed for actually reading rather than clicking around.

---

## Features

### Library

- **Watched folder** — scans recursively through subfolders, picks up new files on rescan, drops entries whose files are gone
- **Series-first browsing** — one tile per series with stacked-cover art, issue counts, and read progress; drill in to see issues
- **Series sidebar** — collapsible list of every series with unread counts, for jumping straight to one
- **Smart Collections** — saved filters built from rules (series, title, status, rating, favorite, special, queued, page count, date added) with match-all/any and a live match count
- **Sections** — Library, New, In Progress, Reading List, Favorites, Completed
- **Continue reading shelf** — recent in-progress issues, one click from the top of the library
- **Search** by title or series
- **Sort** by title, date added, recently read, unread first, or rating
- **Grid or list view**, with three cover sizes
- **Stats** — totals, pages read, rating distribution, per-series completion

### Organization

- Statuses computed automatically: New, Unread, In Progress, Completed
- Mark read/unread per issue or across a whole series
- Favorites and 1–5 star ratings, with series-level rating averages
- Reading list queue with drag-to-reorder
- Specials, annuals, and one-shots detected and grouped separately from the numbered run

### Reader

- Resumes exactly where you left off
- Page turns via **← →**, **A / D**, or clicking the page edges
- **Manga mode** — right-to-left reading, saved per series, toggled with **M**
- **Two-page spreads** with automatic detection of covers and double-page splashes
- **Fit page / fit width** modes
- Pinch zoom to 6×, two-finger scroll panning, drag panning, ⌘-scroll zoom, double-click to toggle 2.5×
- **Page thumbnails** filmstrip (**T**) and jump-to-page (**G**)
- Next-page preloading, and automatic roll-forward into the next issue
- Auto-hiding chrome, edge progress bar, full screen (**⌃⌘F**)
- Slide-out navigation pane on the left edge

### Metadata

- Reads **ComicInfo.xml** when present
- Otherwise parses filenames: strips release-group tags, brackets, and years; handles `#12`, `034`, `170b`, `Annual 3`, `v01`, and decimals
- Falls back to the containing folder name for series
- Manual editing for title, series, issue number, and special flag — with a lock so hand-fixes survive re-parsing
- Rename and merge series across all their issues

### Appearance

- Catppuccin Mocha throughout
- Optional glass effect: frosted sidebar, blurred page art filling the reader letterbox
- Seven accent colors
- Ghost mascot empty states, loading skeletons, soft glow on interactive states

---

## Supported formats

| Format | Backend |
|---|---|
| `.cbz` `.zip` | ZIPFoundation |
| `.cbr` `.rar` | bundled `unrar` |
| `.cb7` `.7z` `.tar` | macOS `bsdtar` (libarchive) |
| `.pdf` | PDFKit (pages rendered and cached) |

Page images inside archives: JPEG, PNG, WebP, GIF, BMP, TIFF, HEIC, AVIF.

---

## Building

Requires Xcode 16+ and a recent macOS.

1. Clone the repo and open `ComicGhost.xcodeproj`
2. Add the **ZIPFoundation** package if it isn't resolved automatically:
   File → Add Package Dependencies → `https://github.com/weichsel/ZIPFoundation`
3. **Supply the `unrar` binary.** Download "RAR for macOS" from [rarlab.com](https://www.rarlab.com/download.htm), extract it, and add the `unrar` file to the project so it lands in **Build Phases → Copy Bundle Resources**.
   Before adding it:
   ```bash
   chmod +x ./unrar
   xattr -d com.apple.quarantine ./unrar
   ```
   Everything except RAR-based files works without it.
4. Build and run (⌘R)

### First run

Open Settings (**⌘,**), choose a folder to watch, then hit the rescan button in the toolbar. Large libraries import in parallel with a progress banner.

---

## Notes

- Reading progress and library metadata live in a local SwiftData store. The watched folder is never modified except when you explicitly remove an issue, which moves the file to the Trash.
- Folder access persists across launches via a security-scoped bookmark. If you move your comics folder, re-pick it in Settings.
- PDFs render their pages on first open and cache the result, so the first open of a long PDF takes noticeably longer than an equivalent CBZ.

## Not implemented

Multiple named libraries, keyboard navigation in the library grid, and guided panel-by-panel view.
