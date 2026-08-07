# Comic Ghost — Manual

## Getting started

Open Settings with **⌘,** and click **Add Library…**. Pick the folder your comics live in. Comic Ghost scans it and everything under it.

Scanning reads only the first image out of each file, which is why thousands of issues finish in seconds. Covers appear as it goes.

You can add as many libraries as you like. If you have more than one, a **Libraries** section appears at the top of the sidebar to switch between them.

**To add new comics later:** drop the files in your library folder, then use **Library actions** in the toolbar and pick **Rescan All Libraries**. Or drag files straight onto the window, or double-click a comic in Finder.

---

## Finding things

The **sidebar** is the main way around.

- **Library** — everything, grouped by series
- **New** — arrived since you last looked
- **In Progress** — started but not finished
- **Reading List** — your queue
- **Favorites**, **Completed**

Below that, the **series tree** breaks your collection into publisher, then franchise, then series. That structure comes from what you've set on each comic, not from your folders. If you haven't set a publisher on anything, everything just sits at the top level rather than getting shoved into an "Unknown" pile.

**Search** is in the toolbar. It matches titles and series names.

**⌘K** opens a jump-to box. Type a few letters of a series, an issue, a collection, or a setting and hit return.

The **View** menu in the toolbar controls grid or list, cover size, and sort order.

**Feeling indecisive?** The shuffle button in the toolbar opens a random unread issue.

---

## Reading

Click a cover to open it.

**Turning pages:** arrow keys, A and D, clicking the left or right edge of the page, or a two-finger swipe on the trackpad. Reaching the end of an issue takes you into the next one. Going back from page one takes you to the end of the previous one.

**Page layout:**

| Key | Does |
|---|---|
| **S** | Single page or two-page spread |
| **C** | Paged or continuous scroll |
| **M** | Manga mode, right to left |
| **F** | Fit the whole page or fit the width |
| **O** | Shift which pages pair up in spread mode |

Manga mode and continuous mode are remembered per series, so you set them once for a run and they stick.

**Spread mode is smart about splash pages.** A genuine double-page spread renders whole instead of being paired off with something else.

**Zoom:** pinch, ⌘-scroll, double-click for 2.5x, or the slider at the bottom of the page. **⌘+**, **⌘−** and **⌘0** work too. Drag or two-finger scroll to move around a zoomed page.

**Other keys:**

| Key | Does |
|---|---|
| **G** | Jump to a page number |
| **B** | Bookmark this page |
| **N** | Write a note on this page |
| **T** | Page thumbnails |
| **I** | Image adjustments |
| **L** | Floating magnifier |
| **H** | Hide all the controls |
| **?** | Show this list |
| **Esc** | Back to the library |

**Hover the left edge of the window** for a panel with the comic's title, previous and next issue, layout options, and your bookmarks.

**Image adjustments (I)** — brightness, contrast, gamma, grayscale, auto-contrast, margin cropping, rotation. There's a **Save for this series** checkbox: tick it and a 1970s scan can have its own settings without affecting anything else.

---

## Organising

Right-click any cover for its menu. Most of it is self-explanatory. The parts worth knowing:

**Status is worked out for you** — New, Unread, In Progress, Completed. You never set it, though you can mark things read or unread by hand.

**Series group and publisher** are what build the sidebar tree. Set them on a series and it slots into place. The dialog suggests values you've already used, so you won't end up with "Marvel" and "marvel."

**Specials** are annuals and one-shots kept separate from the numbered run. Comic Ghost guesses from the filename, and you can correct it.

**Labels** are your own categories — name them, colour them, stick them on anything. Favourite a label and it gets its own sidebar row.

### Doing several at once

**⌘-click** covers to pick them, **shift-click** to grab a range. Or turn on **Select** in the toolbar and just click.

A bar appears at the top with everything you can apply to the lot: series group, publisher, labels, ratings, read status, favourites, reading list, specials, removal.

**Esc** clears the selection.

### Removing things

Right-click → Remove gives you two options:

- **Remove from Library** — the file stays on disk, the app just stops showing it. Reversible from Library Tools.
- **Move File to Trash** — actually deletes it, recoverable from the Trash.

**⌘Z undoes** most library changes.

---

## Smart Collections

Saved searches. Click **New collection** in the sidebar and stack up rules.

You can filter on series, title, status, rating, favourite, special, reading list, page count, date added, creator, character, publisher, story arc, or genre. Choose whether a comic has to match all your rules or just one. A live count updates as you build, so you can see whether you're onto something before you save.

Example: rating is 4 or more, and status is Completed, gives you a shelf of things you liked.

---

## Metadata

Right-click a comic → **Edit Metadata** opens the full editor. Every ComicInfo field is there, plus chapter markers for collected editions.

**This writes into your comic file.** Everything else in Comic Ghost stays in the app — this is the exception, and it only ever happens when you ask.

Every write is checked before it commits. The file is copied, changed, reopened, and verified, and only then does it replace the original. If anything fails, nothing is touched.

**CBR and 7z can't be written to.** The editor offers to convert to CBZ first. It'll say so before you start typing, not after.

**Collected editions with chapter markers** get treated properly — the reader shows which issue you're on alongside the page number, and the end-of-issue card appears at each chapter boundary rather than only at the very end.

**The Index** in the sidebar lists every creator, character, team, story arc, publisher and genre found across your collection, with counts. Click a name to see everything they're in.

---

## Notes and bookmarks

**Notes** come two ways. Press **N** while reading and the note remembers the page — clicking it later takes you straight back. Or write a general one from the Notes section. Both are searchable and pinnable.

**Bookmarks** get their own sidebar section, grouped by comic. Name them so you can find them again.

---

## Library Tools

In the sidebar. Sections fold away and remember how you left them.

- **Missing issues** — gaps in each numbered run, so you can see you're missing #14 and #22 of something
- **Duplicates** — the same issue present more than once
- **Removed from library** — everything you removed but kept on disk, restorable. Files that have since vanished get marked, and you can forget them
- **Storage** — where your disk space went, by series
- **File integrity** — opens every file to check it still works. Slow on a big library, worth running occasionally
- **Convert to CBZ** — CBR and 7z launch a helper program every time you open them; CBZ doesn't. Converting is slow but makes everything faster afterwards. Originals go to the Trash only after their replacement is verified
- **Export** — your whole catalogue as a spreadsheet or JSON

---

## Settings

**⌘,** opens Settings.

**Libraries** — add, rename, remove, or **hide**. Hiding leaves everything exactly as it is and just stops that library appearing anywhere in the app. Nothing is deleted, nothing moves, all your progress and ratings stay put. Useful for screenshots, or for a library you're not reading from right now.

**Theme** — 21 themes across 9 families. Click to expand. Light themes flip the whole app, not just half of it.

**Appearance** — accent colour, and a switch for the frosted glass effect.

**Reader** — auto-hide controls, hide them entirely, whether the page counter survives that, page-turn arrows, and the end-of-issue card.

**System** — remember where you were, Spotlight indexing, keep the display awake while reading.

**Backup** — see below.

---

## Backing up

Your reading progress, ratings, favourites, labels, notes, bookmarks and collections live in the app, not in your comic files. Copying your comics folder somewhere else does **not** copy any of that.

**Settings → Backup → Export** saves the lot as a single JSON file. Do this occasionally.

**Restore** matches on file path and merges — it won't invent entries for comics you don't have.

---

## Things worth knowing

**Your files are left alone.** The only two things that ever touch them are saving metadata and converting a format, both of which you ask for explicitly. Grouping, ratings, labels and reading progress never get written into your comics.

**Nothing is deleted outright.** Removed comics go to the Trash. So do originals after a conversion, once the new file has been checked.

**Loose image folders work.** A folder of JPEGs is treated as a comic and read in place with no unpacking, so it opens instantly.

**PDFs take a moment the first time.** Pages are rendered on first open and cached. After that they're as fast as anything else.

**If you move a library folder**, re-pick it in Settings. Comic Ghost remembers permission to a specific folder, and moving it breaks that.

**It works offline.** There's no account, no server, and nothing phones home.
