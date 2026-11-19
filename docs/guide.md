# Tuck guide

Everything Tuck does: where it lives, each gesture and depth, every setting, and how each feature
behaves. The [README](../README.md) is the short version; [development.md](development.md) covers
building it, and [architecture.md](architecture.md) how it works inside.

- [Where Tuck lives](#where-tuck-lives)
- [Setup and the tutorial](#setup-and-the-tutorial)
- [Using Tuck](#using-tuck)
- [What Tuck does](#what-tuck-does)
- [Permissions](#permissions)
- [Installing and uninstalling](#installing-and-uninstalling)
- [Newer macOS](#newer-macos)
- [Efficiency](#efficiency)

## Where Tuck lives

Tuck parks windows and holds files, links, music links and text you explicitly drop into it, in one
place at the top of the screen: a single list, newest first. It never collects anything on its own,
and it goes online only to preview a link or address you copy, while clipboard history (Settings →
Held, off by default) is on. A first launch starts empty.

Tuck runs as an agent app with no Dock icon. It appears around the notch on notched MacBooks and as a
small bubble in the menu-bar strip on other displays. It has three depths: closed, the shallow fold
(one row of the newest things, which scrolls sideways through the rest) and the full fold
(everything, with search). Its menu-bar item opens Tuck,
tucks the front window, restores the last tucked window, tucks Tuck away or brings it back, and has
Settings and Quit.
It can be hidden in Settings; Settings then opens from Settings… in the fold's context menu (a
secondary click on the fold's top line, level with the notch), or by opening Tuck again.

With Line Apps (the bundle's short line in the menu bar), a click on the line collapses Tuck's
menu-bar item into it, with Pulse's, Hum's and Glow's, and the line becomes the Line Apps curl; another
click brings them all back where they were. Only the menu-bar item goes: the notch and the bubble stay.
While it is collapsed, Tuck in the line's right-click menu, or opening Tuck again, opens Settings. It
holds only while Line Apps runs: quitting Line Apps brings the item back, and Tuck opened while Line
Apps is closed shows it.

## Setup and the tutorial

The first launch opens **Set Up Tuck**, a small window that teaches by doing, on the real Tuck. Every
step has Back and Continue (Return), and closing it at any point is safe: it opens again at the next
launch until it is finished.

| Step | What happens |
| --- | --- |
| Allow Accessibility | Tuck's mark and what Tuck is, in a line, then the one permission tucking needs: what Tuck reads about windows and what it never reads. Open System Settings… asks for it; the page notices when you turn Tuck on. Continue works without it |
| Try it on the notch | Four moves, each ticked off when Tuck does it, however you did it: open Tuck, tuck a window, bring it back from its tile, and drop a file, link or text onto the notch. On a display without a notch the step is "Try it in the menu bar" and points at the bubble, unless Settings › Notch draws a notch there. A line below names the two-finger swipes |
| You're set | Where Settings and the tutorial are, and Open Tuck at login (on by default the first time) |

Nothing in setup is a copy of Tuck: the moves are the real ones, so a window you tuck or a file you
drop is still in Tuck afterwards. Tuck never tucks its own windows, so click another app's window
before pressing Tuck, or click Finder in the Dock if no other window is open. Everything setup doesn't
mention, such as clipboard history, keyboard shortcuts and file access, is in Settings at its default.
Finishing opens the real fold once, so you see where Tuck lives. **Settings → General → Open
Tutorial…** opens the same window as "Tuck Tutorial", with only the practice.

## Using Tuck

**The notch or bubble**

| Action | Result |
| --- | --- |
| Click it | Open the shallow fold, or close the fold |
| Point at it while it holds something | Nothing opens. The mark's dip reaches down and springs back, the faint line lights up in Tuck blue, and the grey dot on the right wing gives way to the Tuck button's arrow. In a bubble, the mark itself gives way to the arrow, in the same place. Moving away puts them back |
| Click the arrow (pointed at) | Tuck the window in front, as the Tuck Front Window shortcut does, without opening the fold. A click on a bubble's ends, either side of the arrow, opens the fold |
| Point at it while it's empty | A notch says "Drop into Tuck" and opens nothing; a bubble offers the arrow. Opened on purpose (a click, the shortcut or the menu), an empty fold is one line high and says the same |
| Two-finger swipe down | One depth deeper: tucked away to closed, closed to the shallow fold, shallow to full |
| Two-finger swipe up | One depth back: full to shallow, shallow to closed, and closed to tucked away completely, where only the hardware notch remains. A swipe that starts over the full fold's list, while it is long enough to scroll, scrolls it instead |
| Two-finger swipe sideways | Over the shallow fold's row of cards, scroll it through everything; anywhere else, nothing. A swipe over the row goes the way it mostly moves: clearly up or down, it is a swipe like any other; otherwise it scrolls the row and never moves the fold |
| Escape | Back one step: a question, the window picker, an edit, the ring the arrow keys put on a tile, the search, the full fold, then the fold itself |
| Click elsewhere | Close the fold |
| Tuck Away / Bring Tuck Back (menu-bar item) | Hide every surface, or show them all again, without a swipe |

**The fold**

| Action | Result |
| --- | --- |
| Windows, Files or Copied (the lenses beside the notch, shallow fold) | Show only that kind; click the same lens again for everything. Files covers files, links, music links and text. Each lens shows its count where there is room, otherwise in its tooltip. Copied is there only while clipboard history is on |
| Scroll sideways along the shallow fold's row (two fingers, or a mouse's sideways wheel) | See the rest of the stream, newest at the left, as many cards at a time as Settings → Notch → Cards in a row says. An edge fades out while there is more beyond it. Unfolding, or something new arriving, takes the row back to its start |
| "N in all" (under the shallow fold's row, when there is more than a row) | Open the full fold, showing everything, as a swipe down does. With a lens on, it reads "Everything in Tuck" |
| ⌘F, or the magnifying glass on the full fold | Search everything (see "Searching") |
| A kind chip under the full fold's top line | Before any search, a line of quiet words names the kinds the stream holds, each with how many in a fainter grey, whenever there are two kinds or more. A click opens the search with that kind already filtered, and what you type adds to it. Only a chip that is on stands out, in Tuck blue on a blue ground |
| The chevron (full fold) | Fold back to the shallow fold, putting any search away |
| The arrow keys (while the fold has the keyboard: opened with the shortcut or the menu, unfolded, or searching) | Down, or Right before a search, puts a Tuck blue ring on the first tile. The arrows then move it from tile to tile, along the shallow fold's row or up and down the full fold's rows, and the list scrolls just enough to show that tile whole, the last row clear of the toolbar. Up from the top row takes the ring off, back to the search field during a search. The tile with the ring shows its second details, as under the pointer |
| Return, or Space outside a search | Open the tile with the ring, as a click on it does: a copy goes back on the clipboard, an item opens, a window comes back, and several windows or a stack open their list |
| Clear (right of the full fold's toolbar) | With no lens on, a menu of Clear Windows…, Clear Files… and Clear Copied… (while clipboard history is on), each greyed out while its section is empty; with a lens on, that section's one button. Each asks first (see "Clearing each section") |
| Secondary-click the fold's top line | Choose Windows to Tuck…, Clear Windows…, Clear Files…, Clear Copied… (while clipboard history is on), each greyed out while its section is empty, and Settings…, in either depth |

The fold opens on everything each time, with no lens and no search. Whatever arrives while it is open
shows at the top, letting go of a lens or search that was on.

**Windows**

| Action | Result |
| --- | --- |
| Tuck (left of the notch, shallow fold) | Put the window in front, named by its app's icon, into Tuck: a small card rises into Tuck and the window is gone the moment the card covers it, with no minimise animation. The button then goes blank until the fold next opens. Without Accessibility it reads Allow Tuck and opens System Settings |
| Right-click Tuck → Tuck All <App> Windows | Tuck every open window of the app in front, gathered into one tile for the app |
| Choose Windows to Tuck… (right-click Tuck or the fold's top line) | Choose open windows from a short list in the full fold and press "Tuck N" (see "Choosing windows to tuck") |
| Arrange windows (left of the full fold's toolbar) | The placement chooser for the window in front, without tucking it; Original undoes |
| Click a tucked window (a tile holding one window) | Restore it to its original size and position; the tile stays if the window can't be brought back |
| Click an app's tile holding several windows | Open or close its list of window titles, newest first, full width under its row of tiles, with Restore All and Hide. Nothing is restored |
| Click a title in an app's open list | Restore only that window |
| Clear Windows… (the Clear menu, the Windows lens's Clear button, or the fold's context menu) | Asks once, at the foot of the fold ("Put back the tucked window?", or "Put back all N windows?"), then puts every window back where it was, one after another. None is closed; any that can't come back stay |
| Right-click an app's tile holding several windows → Restore All <App> Windows | Restore that app's windows one after another, without asking |
| Command-click a tucked window | Inline chooser, laid out like a window's green-button menu: Move & Resize (halves, quarters), Fill & Arrange (full, thirds, two thirds, centre), then Original and Next display |
| A resting app | Its tile's icon is greyed and faded, and VoiceOver adds ", rested" to its name. Rest <App>… and Wake <App> are in the tile's context menu |
| Right-click a tucked window | Restore, Restore To… (the chooser, without ⌘-click), Rest or Wake (on its tile), and Forget Window, which removes a tile or title whose window can't be found and leaves the window untouched |
| Right-click a tucked window or an app's tile → Rest <App>… | With the experimental Rest setting on, pause an allow-listed app whose windows are all tucked; otherwise the item says why not |
| Modifier-drag (opt-in) | Hold ⌃⌥ (configurable) and drag a window to move it; right-drag or add ⇧ to resize |
| Scroll a mouse wheel (opt-in) | Smooth glide per notch (Snappy, Balanced or Gliding), and/or reversed wheel direction with the trackpad unchanged |

**What a tile shows**

Both depths show the same tiles, as many to a row as Settings → Notch → Cards in a row says (2 to 5,
three by default) and as big as Card size says (Small, 151 by 86 pt; Medium, 168 by 96, the default;
Large, 218 by 124). The shallow fold is one row of them, the newest at the left, that scrolls sideways
through everything; the full fold shows all of them in rows. On a display too small for the row the
cards shrink to fit, keeping their shape, down to 150 pt wide; past that a row holds one card fewer
(never fewer than two), so a narrow display shows two cards whose titles can be read rather than three
cramped ones. Nothing scrolls sideways in the full fold.

Every tile is the same light grey card, laid out the same way: what the thing is at the top, and one
line of details at its foot. What it is is an icon beside a title in bold, with a quieter line under
it, or the words or code themselves. A picture, a page's picture, a map or a colour takes the top of
the card instead, its full width, with the title and the line of details on the card under it, so a
title never sits over a picture. Pictures keep their shape, cropped to fill rather than stretched. A
title takes two lines where it needs them and the card has room; the quieter line goes before the
title is cut, and a file name keeps both its ends ("tuck-appi…-1024.png").

| What | Its tile |
| --- | --- |
| Text | Up to three lines of it from the card's top. Rich text keeps its bold, italics and links |
| Code | As an editor shows it: as many of its first lines as the card has room for (three on a small or medium card, five on a large one), quietly tinted, each beside its number. Blank lines between keep their place and their number, and a long line runs on to the card's padding and fades out there |
| A link or music link | The site's icon (a link symbol until its page is looked up, or when it has none) beside the page's title, two lines where the card has room; the site is on the line of details. A page with no title, or not yet looked up, is named by its site, with the rest of its address under it. A page that gives a picture for sharing shows it above its title |
| An email address | The person's initials on their colour, the name before the @, and "@" and the domain under it |
| A phone number | Its country's flag in a circle (a handset when the country isn't known), the number grouped as that country writes it, and the country under it |
| A colour | The colour above, over a checkerboard where it is see-through, and its hex under it |
| A contact | Their initials on their colour, their name, and their number, email or other detail |
| A date | A small calendar page, the weekday, and the day, month and year (the day, month and time when it was written with a time) |
| An address | A map, or a drawn one, with a pin, and the street under it; the town is on the line of details |
| An emoji, a path, a key | The emoji beside its name; the path's icon, name and folder; a lock and the key masked |
| An image, screenshot or video | The picture above, its file name under it (a copied picture is named by its kind); a video's first frame with a play mark. Until a picture is made, or when there is none, its kind's symbol stands quietly in its place |
| Audio | Its artwork, title and artist |
| A file, folder or stack | Its thumbnail or icon and name ("No longer there" once it is gone); a stack's icons fanned, with its first name and "and 2 more" |
| An app's windows | The app's icon and name and the newest window's title, with "Window" or "3 windows" on the line of details. With several windows a click opens their titles, full width under the row; each title restores its window. No tile, title or tooltip gives a window's size |
| The line of details | A small mark of the kind, in that kind's colour, then what it is and the one fact most worth a glance, in grey: "Markdown · 4 KB", "PNG · 1280 × 800", "Text · 11 words", "Swift · 6 lines", "Apple Music · Album", "Date · In 3 days", "Key · GitHub", "Folder · 8 items", "3 files · 419 KB". A link names its site there. What the title or the face says already isn't said again, and a text of one word or a one-line command shows no count |
| Under the pointer, with the ring or opened | The line adds what is worth knowing second, as far as it has room: a second fact (a song's or film's length, a colour's opacity, a stack's or file's size), the folder it is in ("in Downloads", "in ~", "in iCloud Drive"), and the icon of the app it came from |
| The app it came from | Under the pointer, with the ring or opened, the app's icon, at the end of the line and bare, drawn to the same size as every other app's: on text, links, code, colours, people, places and copied images, and on a file from any app but Finder (a mail attachment, say). Screenshots, files from Finder, Tuck's own copies and apps no longer on the Mac don't wear one. Its name is in the tooltip and VoiceOver ("from Safari") |
| The time (Settings → Held → Show when each was copied, off by default) | Every tile but a window's ends its line with when it was copied or dropped in, in a fainter grey: the time today ("3:41 PM", or "15:41" on a 24-hour clock), then "Yesterday" and the time, then the weekday within the week, then the date |
| A tile too narrow for its whole line | The time stays, then the kind and its first fact; "Yesterday 3:41 PM" becomes "Yesterday", and what still doesn't fit ends in an ellipsis |

The kinds' marks share twelve colours, one by kind: blue for links, violet for code, red for music and
audio, rose for emails and contacts, orchid for keys, orange for dates, gold for emoji, olive for
pictures and videos, leaf for addresses, green for files, folders, paths and stacks, teal for phone
numbers and sky for windows; text and colours take a grey one. People's initials sit on one of six
colours, picked from their address (or their name, without one), so the same person keeps the same
colour wherever they appear. A click's result shows for a moment as a small Tuck blue capsule over the
tile's corner, such as "Copied" or "Opened in Safari", and the line of details steps aside while it
shows. The line takes no clicks: a click, double-click or drag on it is on the tile. Everything the
line can say, the second details too, is also on the first line of the tile's tooltip ("PDF · 2.4 MB")
and in what VoiceOver says.

**Held items and copies**

| Action | Result |
| --- | --- |
| Drag files, URLs, text, images or promised files onto Tuck | Deposit into Tuck; three or more files become one stack. Over the open fold, the whole fold takes the drop |
| Start dragging something droppable toward the notch | The notch widens into one target that says "Drop file into Tuck", "Drop link into Tuck" or "Drop text into Tuck", its blue rim firming up as you get closer. The rim runs down its sides and round its bottom, fading out before the screen's top edge. Nothing opens |
| Click a file, link or music item | Open it in its default app; a link or music link waits a moment first, in case the click is a double-click |
| Click a stack | Show its files, full width under its row of tiles, scrolled into view; drag the stack to forward all of them |
| Right-click a file or stack | Open, Quick Look, Show Files (stacks), Show in Finder, Compress (zip), Unstack, Share, Remove from Tuck, or Delete Saved Copy for a copy Tuck saved itself |
| Right-click a text item, link or music item | Copy and Edit (text), Open and Copy Link (links), Share, Remove from Tuck. Text that is something more adds that kind's actions, as copies do |
| Click a text item | Copy it to the clipboard, once a moment has shown the click isn't a double-click |
| Double-click a text item, link or music link | Paste the text, or the link's address as text, into the app in front, as a double-click on a copy does |
| Right-click a text item → Edit | Edit it, full width under its row of tiles, scrolled into view |
| Drag a held item out | Forward the original file, the link, or the text |

**Copies** (while clipboard history is on)

| Action | Result |
| --- | --- |
| Copy anything on this Mac | It joins the top of the stream, shown as its kind: text, rich text, code, a link, music, an email, a phone number, a colour, a contact, a date, an address, an emoji, a path, a key (masked), an image, a screenshot, a video, audio, a file, a folder or several files. Copying it again moves it to the top. The Copied lens shows copies alone |
| Click a copy | Copy it back to the clipboard at once, as it was copied: the styling, the image or the files with it. It moves to the top of the stream only after the double-click time, so a second click still lands on it. Files that have all gone aren't copied, and the tile says "File no longer there" |
| Double-click a copy | Copy it and paste it into the app that was in front, as ⌘V there would: the fold closes, hands the keyboard back, and a moment later one ⌘V is typed if that app is still in front. The V is looked up on the keyboard layout in use, so it works on Dvorak or AZERTY too. With Tuck itself in front, it stays copied and the fold says "Copied · paste with ⌘V"; without Accessibility, it says "Copied · allow Tuck in Accessibility to paste here" (Device Control and Data Access on macOS 27). The tooltip names the app ("double-click to paste into TextEdit"), and VoiceOver has the same as a Paste into <App> action |
| Drag a copy out | Drop the original: the files, the image, the text, or a contact card |
| Right-click a copy | Copy, then the kind's own actions, then Keep in Tuck (holds it as an item of its own), Share (never for a key) and Remove from History. The kind's actions: Open (links, paths), New Message (emails), Call and Send Message (numbers), Copy Hex and Copy RGB (colours), Copy Name, Number or Email and Add to Contacts… (contacts), Open in Maps and Get Directions (addresses), Add to Calendar… (dates), Copy as Plain Text (rich text), Quick Look, Copy Text in Image and Save to Downloads (images) |
| Clear Copied… (the fold's context menu, or the full fold's Clear) | Ask first, then empty the history, with the images and styling Tuck kept for it. What is on the clipboard now stays, and so does anything kept in Tuck. Settings → Held → Clear Clipboard History empties it at once, without asking |

**Search** (full fold only)

| Action | Result |
| --- | --- |
| ⌘F, or the magnifying glass on the full fold | Open the field. The field shows only once asked for. From the shallow fold the fold opens fully and a lens that is on comes along, unless it holds nothing, when the search looks at everything. With nothing in Tuck, the fold says there is nothing to search yet |
| Type words | Show what has all of them, ignoring case and accents: app names, window titles, text, file names and folders, a stack's files, link titles, domains and addresses, the app it came from, the kind's name, and the words read in images |
| Type a kind: "images", "screenshots", "links", "code", "colors", "files", "windows", "keys"… | It becomes a chip, and only that kind shows; "photos", "urls", "snippets" and "colours" work too |
| Type a day: "today", "yesterday", "this morning", "last night", "this week", "last month", "friday"… | It becomes a chip, and only what was copied, held or tucked then shows. "This morning", "this afternoon" and "this evening" are today's; "last night" runs from 9 in the evening to 5 the next morning. Mix them: "images today", "links safari" |
| Type a file type: "pdf", "png", "jpeg", "zip", "archives", "disk images", "spreadsheets", "presentations", "md"… | It becomes a chip, and only files of that type show, with anything whose words say it ("pdf" also finds a Preview window titled "Invoice.pdf"). A stack shows when any of its files is one. Several types find any of them |
| Type a size: "2 mb", "500kb", "over 10 mb", "<1mb", "at least 1 gb", "large", "small"… | It becomes a chip, and only what is that big shows. "2 mb" is 2 MB up to 3 MB and "2.4 mb" 2.4 up to 2.5 MB, a megabyte being a million bytes as in Finder; "large" (or "big", "huge") is 10 MB or more, and "small" (or "tiny") under 100 KB. A stack counts its files together |
| Type a time of day: "3pm", "3:41", "15:00", "morning", "afternoon", "evening", "night" | It becomes a chip, and only what was copied, held or tucked then, on any day, shows. "3pm" or "15:00" finds the whole hour, "3:41 pm" that minute, and "3:41" that minute on either side of noon; a number alone is just a word. The morning runs from 5 to noon, the afternoon to 5, the evening to 9 and the night to 5 the next morning. Mix it with a day: "yesterday 3pm". Times are found whether or not tiles show them |
| Kind chips before a search | With more than one kind in the stream, the full fold shows a line of chips under its top line, each a kind with how many it holds, as many as fit. Click one to open the search with that kind already typed and the caret after it, so what you type next narrows it |
| Click a chip during a search | Turn that filter on, or take it out again (a chip that is on shows a ×). Each kind's chip counts what the words and day typed find of it |
| Return | Do what a click on the tile with the ring does, or with no ring, on the first match |
| Nothing matches in the lens | If something elsewhere matches, the lens steps aside and the search shows everything. Otherwise "No matches" says where else the words were found (as another kind, or on other days), with a click that leaves the kind or day out |

Keyboard shortcuts are off by default; see "Keyboard shortcuts" below.

## What Tuck does

- **The surface:** a notch surface on notched displays and a bubble on other displays, one per
  connected display. An empty Tuck on a notch is the bare notch, and so is one holding only copies.
  Holding a window or an item, Tuck's mark (the logo's round line) sits faint on the left wing with a
  small Tuck blue card in its dip, as the Dock's Trash shows it holds something, and a grey dot sits
  on the right wing. There is no count, no text and no control at rest. Without a notch, the bubble
  shows only the mark, centred, faint, with the card while Tuck holds something. Pointed at, nothing
  opens: the mark's dip reaches down and springs back, the line lights up in Tuck blue, and the dot
  gives way to the Tuck button's arrow; in a bubble the mark itself gives way to the arrow, in the same
  place. Pointed at with nothing in Tuck, a notch says "Drop into Tuck"; a bubble still offers the
  arrow. A click or a swipe down opens the fold. It is sized like a native notch app: the notch's
  own height, one notch-high wing either side. Swipes follow the fingers: the surface stretches, draws its wings in or
  slides them out, then commits or springs back.
- **The fold:** as wide as one row of its cards (540 pt for the three medium cards it starts with), so
  it grows wider before it grows taller, with its top line level with the notch. It is never narrower
  than the notch with room either side for the Tuck button and the lenses, where a short row sits in the
  middle, and on a display too small for the row the cards shrink to fit, then drop to one fewer a row
  (never under two) rather than shrink past reading. The shallow fold shows one row of cards, the newest
  at the left, that scrolls sideways through everything, with "N in all" under it when there is more
  than a row; the Tuck button sits left of the notch and the lenses right of it. The full fold shows
  everything in the same cards, in rows, scrolling past the smaller of 440 pt and the screen's height
  less the menu bar and 280 pt (never under 180). Text being edited, a stack's files and an app's window
  titles open full width under their row of tiles. Its top line reads "Everything in Tuck" ("Everything"
  on a narrow fold), with search and a fold chevron on the right, and the kind chips under it. Under the
  list, past a hairline, a quiet toolbar holds Arrange windows on the left (while a window is in front)
  and Clear on the right; the list scrolls until its last row sits whole above it. The fold is black, as
  the notch is, in Light and Dark alike. Unfolding gives Tuck the keyboard, so Escape and typing go to
  the full fold while it is open; a shallow fold opened by a click or a swipe leaves the keyboard with
  the app in front. A status line shows at the foot only while there is something to say.
- **One stream:** tucked windows, held items and, while clipboard history is on, copies, in one list by
  date, newest first. An app's windows share one tile. Copies alone don't bring the mark out on a
  notch.
- **Kinds:** what a copy is (a link, a colour, code, a date and so on) is recognised once, as it is
  copied, and a held item's kind is read from it the first time the fold shows it. Tiles of the same
  kind look alike whether the thing was copied or dropped.
- **Real windows:** tucking and restoring through Accessibility, with the frame checked after the move
  and size-constrained windows pinned to the chosen edges (see "Tucking goes into the notch, not the
  Dock"). Placement for the window in front: 15 layouts including thirds, quarters and next display,
  with Original returning it to where it was before Tuck moved it.
- **Drops:** file URLs, web and music URLs, plain text, raw images and promised files (Mail messages,
  Photos), with no destination dialog. Promised files and images are saved in Tuck's own folder and
  deleted when their tile is.
- **Drop invitation:** when a drag carrying something droppable enters a generous range around the
  notch or bubble, the surface widens into one target with an icon and "Drop file into Tuck", "Drop
  link into Tuck" or "Drop text into Tuck", read from what the drag says it carries as it starts
  (files win over a link, a link over text). As the pointer nears, a blue rim around the target
  strengthens, and firms up over it; under a notch it fades out before the screen's top edge. A drag never opens the fold. Over an open fold, the whole fold is
  the target and says the same. Releasing beside the target is refused rather than captured.
- **File tray:** saved to `~/Library/Application Support/Tuck/library.json`. Files are references
  (path plus bookmark): renamed or moved files are followed, deleted files leave the tray. Any held
  file or stack can be compressed into a zip next to the originals (Downloads if that folder is
  read-only), held in Tuck. Tuck holds at most 200 items; a full Tuck takes what fits and says so.
- **Deposits:** a drop on the closed surface draws into the mark, then the mark swells once; into an
  empty Tuck, the mark's card drops into its dip instead. Tucked windows send a small card up into the
  mark's dip, or with the fold open into their app's tile.
- **Optional, off by default:** modifier-drag move and resize; mouse-wheel smooth scrolling and
  wheel-only direction reversal (trackpad and Magic Mouse gestures, and scrolling with a modifier held,
  are never touched); global keyboard shortcuts; clipboard history of what is copied on this Mac (text,
  styled text, images, files, colours and contacts, each recognised as its kind once, as it is copied),
  with a retention setting and one-click clear; Rest. Clipboard capture is opt-in and skips content
  marked private by its source app. The words in copied images are read on this Mac (Settings → Held →
  Read text in copied images); a link's page title, icon and sharing picture and an address's map are
  fetched whenever clipboard history is on (with no switch of their own), and a link already in the
  history with no preview is looked up when its tile first comes into view.
- **Haptics** only for three moments: a drag crossing into the drop target, something landing in the
  mark, and a window placement snapping into place (Arrange windows or Command-click). Opening,
  closing and swipes add no tap, and taps are at least 0.35 s apart.
- **Setup:** a first-run window that asks for Accessibility, has you open Tuck, tuck a window, bring it
  back and drop something on the real notch, then offers open at login; reopened from Settings it is a
  tutorial of the practice alone (see "Setup and the tutorial").
- **Settings:** a sidebar of panes, as in System Settings. General: open at login, menu-bar item,
  haptics, Accessibility status, the tutorial, Quit. Notch: which displays show Tuck (all, built-in or
  external), a bubble or a drawn notch on displays without one, how many cards sit in a row (2 to 5)
  and how big they are (Small, Medium or Large), and whether Tuck shows beside full-screen apps and
  in screenshots and recordings. A change to the cards lays an open fold out again at once. Across
  apps: Windows (modifier-drag), Keyboard (shortcuts), Mouse (wheel). In the panel: Rest, Held (Widen
  when a drag comes near, Show when each was copied, file access, clipboard history, reading text in
  copied images). About: version and the library folder. Small choices are illustrated tiles that
  show what they do.
- **Design:** the fold is the notch's own black, drawn dark whatever the Light or Dark setting, with
  cool stone fills and hairline separators, rounded 20 pt (controls and tiles 10). Every tile is the
  same light grey card with dark ink on it, so the stream reads calmly and its pictures keep the only
  full colour; what a tile holds is told by a small mark at the start of its line of details, in one of
  twelve deep colours, all at one lightness so no kind shouts over another (see "What a tile shows").
  Apps have no colour of their own. On every card, under the pointer too, primary text keeps over
  12:1, secondary text over 4.6:1 and a kind's mark over 3.3:1; on a card the ring and the click capsule
  take a deep Tuck blue. One accent, Tuck blue (the logo's #7299C5, 7:1 on the black), marks the mark's
  light and card, the Tuck button's arrow, keyboard focus, a selected lens, the chip that is on, the
  drop target, deposits and restores, and the small capsule that says what a click did.
  People's initials sit on one of six colours of their own. It is built from the system's own pieces:
  system type (13 pt text over a 12 pt grey line, and nothing smaller but a tile's 11 pt line of details
  and code's line numbers), SF Symbols in menus (shown by macOS 27 only where needed) and Quick Look
  thumbnails for held files. There is at most one prominent button per prompt, filled blue; destructive
  actions are plain and never prominent. Prompts are laid out as AirDrop asks a question: two choices
  side by side with Cancel first, three stacked with Cancel last.
- **Increase Contrast** gives the cards a stronger grey, the kinds' marks a deeper colour and the
  text, fills, separators and Tuck blue each a stronger tone, draws an edge round each tile, and gives a
  white page's thumbnail an edge. Primary text keeps over 12:1 on every tile.
- **Reduce Motion** is honoured throughout: no card or drop flights, springs settle without bouncing,
  the fold, tiles and prompts fade instead of sliding, pressed controls don't shrink, the mark's card
  and the Tuck button's arrow fade in rather than drop or rise, and the mark's greeting, its swell on a
  deposit and refusals' shake don't play; pointed at, the line only lights. A fold opened from the
  keyboard opens without overshoot, and the shallow fold's row goes back to its start without sliding.
- **VoiceOver:** each tile is one element that says what it is, what its line of details says, the
  second details too ("README.md, Markdown, 4 KB, in Downloads, from Mail", and "copied at 10:57 AM"
  while tiles show times), when it arrived and what a click does, with a Paste into <App> action where a
  double-click pastes; the closed surface says what Tuck holds ("Tuck, 2 windows, 1 item"); status lines
  and what a click did are announced.

How each of the behaviours below was checked is recorded in [decision-log.md](decision-log.md).

### Tucking goes into the notch, not the Dock

When a window is tucked, a small card with the app's icon and the window's title rises from where the
window was, curving up into Tuck (on the window's own display). On the way it shrinks, lets go of its
icon and title, and becomes a blue dot, passing over Tuck's surface so it is seen arriving. With the
fold open, it comes down on the icon of its app's tile, which waits empty for it; it opens out
across the tile and clears to show it. With the fold closed, it lands in the dip of Tuck's mark and
merges into it, and the mark swells once, or, in a Tuck that held nothing, the mark's card drops into
the dip; a Tuck that was swiped away comes back first, so there is a mark to land in. The flight
takes about a quarter second (under half a second with the tile), staggers a few windows at a time,
uses no window pixels (so no Screen Recording permission), and lives in a short-lived click-through
panel that is closed on landing. With Reduce Motion on there is no flight: the tile simply appears,
or the mark's card fades in.

How the window itself goes away:

- **It is simply gone** the instant the card takes its place. Tuck waits until the card is on screen
  over the window, then moves the window just beyond a bottom corner of its display, as some window
  managers keep the windows of other workspaces. Nothing is minimised or hidden: no Dock animation,
  the app's other windows stay as they are, and no other app comes forward. macOS keeps one point of a
  window on screen, so a hairline as tall as its title bar (with a faint shadow) stays at the very
  edge of the corner.
- **The keyboard** goes where a minimise would send it: the app's next window in view, else the
  frontmost window in view. Switching to the app of a tucked window (its Dock icon, Command-Tab) brings
  that window back where it was.
- **Restoring** runs the flight backwards: the card leaves Tuck, lands where the window goes, and the
  window is just there under it, in front.
- **When it can't be moved there** (full screen, or an app that holds its window in view), Tuck
  minimises it instead, hiding its app for a moment so nothing is seen going down to the Dock; the app
  is shown again at once, its other windows gone for a couple of frames, and it stays in front if it
  was. Only an app that can't be hidden at all still minimises in view. A window that went to the Dock
  comes back with macOS's own restore animation.
- **Quitting Tuck** minimises windows waiting off screen the same way, so none is out of reach while
  Tuck isn't running; they restore from the Dock afterwards. If Tuck stops unexpectedly they stay
  where they are, and Tuck finds them again the next time it starts.

Once the window in front is tucked, the Tuck button goes blank rather than naming it, or the window
behind it, a moment after it went. Tucking another app's windows leaves the button as it was.

Without Accessibility permission Tuck says so and keeps every tile. Restoring a window whose app has
quit removes its tile or title with "That <App> window has closed".

### Windows from the same app

- One window of an app is a tile of its own: the app's icon and name, and the window's title. A click
  restores it, Command-click opens the placement chooser.
- Several windows of one app share a tile with the app's icon and name and the newest window's title;
  the tile doesn't say how many (its tooltip and VoiceOver do). Clicking it only opens or closes their
  list, full width under its row of tiles; it never restores anything. A resting app's icon is greyed
  and faded.
- The open list is headed "<App>'s windows", with Restore All and Hide. Its windows are listed by
  title only, and each is its own whole window: click restores just that one, Command-click opens its
  chooser, right-click → Restore, Restore To… or Forget Window.
- No tile, title, tooltip or VoiceOver label gives a window's size. A window's tooltip says when it was
  tucked, from which display when there are two or more, and "click to restore · ⌘-click to place".
- App tiles take their place in the stream by their most recently tucked window. Every tile starts
  closed, and one that drops back to one window forgets that it was open.
- Each window is a whole macOS window; browser tabs are not managed.

### Choosing windows to tuck

- **Choose Windows to Tuck…**, in the context menu of the fold's top line or of the Tuck button,
  opens the full fold with open windows to tick in place of the list: ordinary, visible, standard
  windows of ordinary apps on the current desktop, nearest the front first, grouped by app, at most
  12. An app with several windows opens on a click to list them by title, each ticked on its own,
  ending with Select All. Nothing is ticked to begin with, and nothing moves until you press "Tuck N".
  Escape, the fold chevron or a swipe up cancels.
- **Never listed:** Tuck itself, background and menu-bar apps, dialogs and floating panels,
  minimised, full-screen and tiny windows, windows tucked out of sight, windows on other desktops, and
  resting apps. Positions come from the window server's on-screen list (bounds only, no titles or
  pixels), so no Screen Recording permission is needed.
- **Tucking:** each ticked window is checked again just before it is put away and joins its app's tile
  in the stream. Windows that refuse are reported, not hidden.
- **Whole apps and Restore All:** "Tuck All <App> Windows" does the same for every window of the app in
  front. Windows always restore one per click, unless asked for together: "Clear Windows…" (see
  "Clearing each section") asks first, puts them back one after another, and keeps any that can't come
  back; an app's Restore All puts back that app's windows without asking.

### Searching

Search is in the full fold only, and its field shows only once asked for (⌘F, the magnifying glass,
or a kind chip). Before a search, with more than one kind in the stream, a line of chips under the
fold's top line names the kinds it holds, with how many, as many as fit and the commonest first; a
click on one opens the search with that kind already typed, so what you type next narrows it. The
search filters the stream as you type, on this Mac. Kind words ("images", "links", "code", "windows") and
day words ("today", "yesterday", "this week", "friday") become chips under the field, and every other
word must match somewhere: app names and window titles, held text, file names and their folders, the
files in a stack, link titles, domains and addresses, the app an item came from, copied text, the
kind's name and the words read in copied images, ignoring case and accents. So "images today" shows
today's images, and "links safari" the links copied from Safari. Searching an app's name keeps all its
windows; otherwise an app's tile keeps only the windows whose titles match. The chips under the field
count, kind by kind, what the other words find, and a click turns one on or takes it out.

The words a tile's line of details says can be searched too, and become chips like kinds and days: a
file type ("pdf", "png", "archives", "spreadsheets"), a size ("large", "small", "2 mb", "over 10 mb",
"<1mb") and a time of day ("3pm", "15:00", "3:41", "morning", "night"). So "pdf large" shows big PDFs,
and "screenshots yesterday 3pm" the screenshots taken in that hour yesterday. Each also finds what says
the word, so "pdf" still finds a Preview window titled "Invoice.pdf" and "3pm" a note that reads "meet
at 3pm". A stack is found by its files, and windows by when they were tucked. Several types or times
find any of them, while every size must hold, so "over 1 mb under 5 mb" finds what is in between.
Times are found whether or not tiles show them. A held file's size is read only when a search names
a size.

An app's name finds what came from it, and becomes a "From Safari" chip with the app's icon: its name
("safari", "visual studio code" for what Code copied), "from" and its name ("from music", "from notes"),
or a word only one app's name has ("chrome" for Google Chrome). So "terminal links" shows the links
copied in Terminal. Only apps something in Tuck came from count, gathered as the search begins. A chip's
own word ("code", "music", "screenshots") stays the kind unless "from" comes before it; another kind
word that is also an app's name ("notes", "mail") reads as the app once something came from it. Each
also finds what says the word, and several apps find any of them. Windows are found by their app's name
too.

A lens that came along from the shallow fold narrows the search. If nothing in it matches but
something elsewhere does, the lens steps aside; if nothing anywhere matches, "No matches" says where
the words were found once the kind or day typed is left out. Nothing is indexed: the search reads what
Tuck holds as you type. Escape, the magnifying glass again, or folding back puts it away.

### Clearing each section

Each section clears on its own, and each asks first, at the foot of the fold, in place of any other
section's question. The full fold's toolbar has Clear at its right: with no lens on it is a small Clear
menu of all three, and with a lens on it is that section's own button. The fold's context menu (a
secondary click on its top line) has the same three in either depth. Each is greyed out while its
section is empty, and Clear is out of the way during a search, while choosing windows, while a question
is open, and when there is nothing to clear.

- **Clear Windows…** asks "Put back all N windows?" ("Put back the tucked window?" for one), then puts
  each back where it was, one after another. None is closed, and any that can't come back stay listed.
- **Clear Files…** takes every held item out of Tuck:
  - Links, music links and text leave Tuck. Files are references, so clearing drops the reference and
    never moves or deletes your file.
  - Files Tuck wrote itself, for drops that arrived without a file of their own (a Mail message, an
    image), are deleted with them. The question says how many and the button reads "Clear and
    Delete".
  - Tucked windows and copies are never part of it.
- **Clear Copied…** (while clipboard history is on) asks "Clear all N copied items?", then empties the
  history, with the images and styling Tuck kept for it. What is on the clipboard now stays, and so
  does anything kept in Tuck. Cancel comes first and Clear is plain, as for files. Settings → Held →
  Clear Clipboard History empties it at once, without asking.

**Kept safe.** Removing a file inside a stack, clearing, or forgetting a window never touches your
own files; a copy Tuck saved is deleted only once nothing in Tuck refers to it. Files on a drive that isn't
connected stay in Tuck until it is. If Tuck's saved library can't be read (damaged, or from a newer
Tuck), it is moved aside as `library-unreadable-….json` rather than overwritten, apps it records as
resting are still woken, and no saved copies are cleaned up that it may refer to. A rested app is
woken when the last of its windows is forgotten.

### Sessions from earlier versions

Earlier versions of Tuck sorted things into sessions. The first time this version opens such a
library, it merges every session into the one stream, archived sessions and Loose included: every
tucked window and held item, newest first. Before saving, it copies the old file byte for byte to
`library-sessions-backup-<time>.json` beside it in `~/Library/Application Support/Tuck`; if that copy
can't be written, Tuck shows the merged stream but saves nothing until a later launch can make it. Session
names, colours and intentions are not carried over; the backup keeps them. Sample sessions from
earlier versions are taken out on the way. A library from a newer Tuck, or one that can't be read, is
set aside rather than merged. If the merged library holds more than 200 items, nothing is taken out,
but new drops wait for room. Clipboard history was never kept per session and is read as it was;
copies saved before Tuck recognised kinds are recognised as they load.

### Keyboard shortcuts (off by default)

Turn on Settings → Keyboard → Use keyboard shortcuts to use these from any app:

| Shortcut | Action |
| --- | --- |
| ⌃⌥⌘T | Tuck Front Window: the window in front goes into Tuck, with the same upward card |
| ⌃⌥⌘R | Restore Last Tucked Window: the most recently tucked window comes back where it was, one window, never more |
| ⌃⌥⌘O | Open or Close Tuck, on the display under the pointer |

- **Changing one:** click it in Settings and type the new combination; Escape cancels, Delete clears
  it. Each needs at least two of ⌃ ⌥ ⌘, so it can never take over an app's own shortcut such as ⌘C,
  and no two actions can share one. "Restore Defaults" puts the three back.
- **How they work:** through the system's hot-key service, which tells Tuck only about these exact
  combinations. Tuck never sees any other keystroke and needs no extra permission for the shortcuts
  themselves; tucking and restoring still need Accessibility. While shortcuts are off, none are
  registered. If macOS or another app already uses one, Settings says so.
- **Feedback with the fold closed:** a tuck shows its card flying into the mark; a restore shows the
  window coming back. A shortcut that does nothing (no window in front, nothing tucked, no permission)
  gives the mark and dot a small shake, and the reason is on the fold's status line for a few
  seconds.
- **The menu-bar menu** lists the same three actions and shows their shortcuts while they are on.
- **Keyboard layouts:** a shortcut is stored by key position and labelled from the layout in use when it
  was recorded. The defaults are labelled for US-style layouts; on another layout, record them again to
  get matching labels.

### Rest (experimental, off by default)

Rest pauses a tucked app's process to reduce active CPU work while it stays in memory, and resumes it
when you deliberately restore one of its windows. It does not free memory, does not reach an app's
helper processes (so the saving can be partial for multi-process apps), and never claims zero CPU or
universal safety. It is off until you turn on Settings → Rest, which also lists the apps on this Mac
that can rest.

- **Mechanism:** a same-user stop signal to pause and a continue signal to wake.
  - Before every signal, the process's pid, kernel start time and program path must match what was
    recorded, so a reused pid is never signalled.
  - Each pause and wake is checked in the kernel's process state; a pause that does not hold is undone.
  - Pausing needs the setting. Waking never does, so turning Rest off cannot strand a paused app.
- **Who may rest:** an allow-list of offline document apps (Preview, TextEdit, Pages, Numbers, Keynote,
  Calculator, Font Book). Calls, media, downloads, terminals, developer tools, VPNs, sync, remote
  desktop, system tools, browsers and messaging are refused by name, and any other app is refused as
  ambiguous.
- **Checked at the moment you ask:** the app must not be in front, must have no visible windows left
  (Rest pauses the whole app), and must not be using audio. A busy app needs a stronger confirmation.
  The first use shows the agreed explanation; with Rest switched off, one question turns it on and
  rests the app.
- **Shown as:** the app's icon greyed and faded on its tile, and ", rested" after its name for
  VoiceOver. Wake <App> is in the tile's context menu.
- **Waking:**
  - restoring one of its windows, a Wake menu item, or switching to the app yourself (Dock,
    Command-Tab, opening it); never on hover;
  - before Tuck quits, before the Mac sleeps or shuts down, and when the setting is turned off;
  - at Tuck's next launch, if Tuck crashed while an app was resting.
- **Unsafe by design, so not offered:** resting anything not on the allow-list, resting automatically,
  and any private API or privilege.

### Deliberately deferred

- Rest beyond the allow-list, and per-app testing of more apps.
- Frozen window previews (optional Screen Recording permission).
- A shortcut to hold the selected text: it would have to read other apps' selections through
  Accessibility, which many apps don't expose, or send a copy keystroke and overwrite the clipboard.
- Global layout shortcuts, edge snap zones and share links.
- Linear (fixed lines per notch) scrolling, per-app scrolling exceptions and scroll-to-zoom.
- Rich text dropped onto Tuck. Copied rich text is kept by clipboard history, with its styling.

## Permissions

Tucking, restoring and arranging real windows, and the optional modifier-drag and mouse-wheel
features, need **Accessibility** (System Settings → Privacy & Security → Accessibility, named Device
Control and Data Access from macOS 27; Tuck uses whichever name the running system shows). Setup's
first step offers it; otherwise Tuck asks the first time you use one of those features, never at
launch. It notices a newly granted permission without restarting, and a withdrawn one too: turned off
while windows are tucked, the mark and dot shake and the foot of the fold says that they can't come
back until Tuck is allowed again (minimised ones wait in the Dock meanwhile).

Tuck also needs macOS file access to read dropped files for their thumbnail, kind and size, and to
follow them if they move. Without anything set up, macOS asks about each folder the first time you
drop from it. In Settings → Held → File access, **Open System Settings…** beside Full Disk Access is
for access to files from any location without later file-access prompts. macOS requires you to enable
this yourself in System Settings → Privacy & Security → Full Disk Access; Tuck cannot request it.
Alternatively, **Ask Now** beside **Or just the usual folders** asks now for Desktop, Documents,
Downloads and iCloud Drive. It does not authorize other locations, such as external or network drives,
which macOS may ask about when first used. A local
build keeps its place in the Accessibility list across rebuilds once `scripts/signing-identity.sh` has
made its signing identity; signed ad hoc, each rebuild may need to be re-added.

Clipboard history reads what other apps copy. From macOS 15.4 the system can ask, or refuse, before an
app does that. Tuck reads only after a copy, and if Paste from Other Apps (Privacy & Security) is set to
ask or deny for Tuck, it pauses capture rather than raise an alert at every copy, and the fold (with
the Copied lens on, or opened fully) and Settings → Held say where to allow it. Capture resumes with
the next copy.

## Installing and uninstalling

- **Homebrew:** `brew install --cask millerroberts180/line-apps/tuck`, from the
  [Line Apps tap](https://github.com/millerroberts180/homebrew-line-apps). Give the full name, because
  Homebrew's own catalogue has an unrelated `tuck`. It downloads the same disk image as Tuck's page.
  `brew upgrade --cask millerroberts180/line-apps/tuck` updates it.
  `brew uninstall --cask millerroberts180/line-apps/tuck` quits Tuck and removes the app; add `--zap`
  to remove its settings and library too. Uninstall Tuck… below does more: it brings windows back first
  and resets the permissions.
- **The disk image:** download `Tuck-<version>.dmg` from
  [Tuck's page](https://lineapps.vercel.app/tuck/), open it and drag Tuck to Applications. The
  **Line Apps** installer, on the same site, puts Tuck in Applications with the other apps.
- **The first open:** until Tuck is notarized, macOS stops it the first time, however it was
  installed. Choose Done, then System Settings › Privacy & Security › Open Anyway. On macOS 14 you can
  also Control-click Tuck in Applications and choose Open.
- **Uninstall Tuck…** (Settings → About) brings back every tucked window and wakes every rested app
  first, and stops with nothing deleted if any won't come back. Its confirmation says how many files
  Tuck saved from drops, which may be the only copies, and can show them. Then it turns off Open at
  Login, deletes Tuck's own files (a backup of an earlier sessions library included) and settings,
  resets its permissions, moves the app to the Trash and quits, listing anything it couldn't do for
  you to finish.
- **Move to Applications:** opened from its disk image, or from a copy macOS runs from a temporary
  place, Tuck offers once to move itself to Applications and reopen. If a Tuck is there already, it
  names both versions first, and the old copy goes to the Trash only once the new one is in place.
  Declined, it doesn't ask again.

## Newer macOS

- **Liquid Glass (macOS 26):** Settings and Setup are standard SwiftUI and AppKit windows, so they take
  the system's glass, sidebar and control sizes from it; nothing is drawn to imitate glass. The closed
  surface stays black, continuing the hardware notch, and stays black as it opens into the fold;
  neither uses glass.
- **Menu-bar strip (macOS 27):** while the menu bar is hidden (auto-hide, or full screen), macOS lays an
  invisible window across a notched display's menu-bar strip at the status-bar level. Tuck's surface
  sits one level above it so the notch keeps its clicks, still well under menus, alerts and system HUDs.
- **Menu icons (macOS 27):** menus show symbol images only where they are needed. Tuck's menus read
  without their icons. Choosing windows to tuck happens in the fold itself, not in a menu, so it keeps
  its checkmarks.
- **Not yet run on the newer systems:** Tuck has been run on macOS 15.7 only. The decision log lists
  what to verify on macOS 26 and 27.

## Efficiency

Tuck's purpose includes staying out of the way of the Mac's resources. Measured on the release build
(Apple silicon, macOS 15.7, clipboard history on), over 60 s at rest:

| | |
| --- | --- |
| App bundle | ~3.6 MB |
| Idle CPU (collapsed) | 0.03% |
| Wakeups at rest | 2 a second, all from clipboard history's 0.5 s check |
| Memory footprint, collapsed (fresh launch) | ~12 MB |
| Memory footprint with the panel open | ~23 MB |

These were measured before the fold replaced the panel and have not been taken again since.

The collapsed surface is plain Core Animation layers. Its one repeating timer is clipboard history's
check, since macOS has no pasteboard change notification, and it runs only while history is on. The
SwiftUI fold is created on open and released on close. The modifier-drag and mouse-wheel event taps and
the global shortcuts exist only while those settings are on, the scroll glide's display link runs only
while a glide is moving, saves are coalesced off the main thread, and moved or deleted files are checked
when the fold opens rather than watched. A file's size for its line of details is read once while the
fold is open, off the main thread, and forgotten when it closes. See [architecture.md](architecture.md).
