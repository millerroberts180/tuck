# Tuck privacy policy

> **Draft for legal review. Not in force.** No lawyer has reviewed this draft. Text in [square brackets]
> is a placeholder to fill in before Tuck is released. It describes Tuck as the code stands on
> 2026-11-09, with the trial and licence keys removed on 2026-11-16. Check it again whenever Tuck starts
> to store, read or send something new.

Last updated: [date]

Tuck is a holding space for macOS, made by [owner's full legal name or business] ("we"). This policy
says what Tuck keeps, what it reads and what it sends.

**In short:** Tuck works on your Mac. It has no account, no analytics, no advertising and no tracking,
and it goes online only to preview a link or an address you copy, while clipboard history (off by
default) is on (see "What leaves your Mac"). What it holds stays on your Mac, and we never receive it.

## What Tuck keeps, only on your Mac

Tuck keeps its data in `~/Library/Application Support/Tuck/`. None of it is sent anywhere.

- **Your library** (`library.json`), one list of what you put in Tuck:
  - for each window you tuck: its title, its app's name and bundle ID (such as `com.apple.TextEdit`),
    its size and position, which display it was on, when you tucked it and how it was put away;
  - for each item you drop: the path to a file and a bookmark that lets Tuck follow it if it moves, or
    the link or text itself, its title, the name of the app it came from and when it arrived;
  - for an app you rest: its process ID, start time, program path and bundle ID, so Tuck wakes exactly
    that process later.
  - If the library file can't be read (damaged, or written by a newer Tuck), Tuck never writes over it:
    it renames it `library-unreadable-<number>.json`, in the same folder, and starts afresh.
  - If you used an earlier Tuck that sorted things into sessions, the first time this version opens it
    copies that library, unchanged, to `library-sessions-backup-<number>.json`, in the same folder,
    before merging the sessions into one list. The copy keeps the sessions' names, colours and
    intentions (such as Work or Personal), which the new list no longer has. Uninstall deletes it with
    Tuck's other files.
- **Clipboard history** (`clipboard-history.json`), only if you turn clipboard history on. It is off
  by default.
  - It holds what you copy on this Mac: text, and the styling copied with it; images; colours; contact
    cards; and, for files and folders you copy, their paths (the files themselves stay where they are).
    With each copy it keeps the name and bundle ID of the app you copied it from, when you first and
    last copied it, how many times, and what kind of thing it is (a link, a date, a key and so on).
  - Images and styled text are saved as separate files in `Clipboard/`, beside the history, and deleted
    once the history no longer holds their copy.
  - It also keeps what Tuck worked out on your Mac about a copy: the words in a copied image or
    screenshot (read by macOS's text recognition, unless you turn off Read text in copied images), and a
    copied song's or video's title, artist and length, from the file's own tags. It also keeps what it
    looked up online to preview a copy (see "What leaves your Mac"): a copied link's page title and
    icon, the picture the page gives for sharing it (such as the image a message app shows with the
    link), and a picture of a copied address's map.
  - Keys and tokens it recognises, such as API keys, are kept like other text but shown masked.
  - It skips anything an app marks as private, concealed or temporary, as password managers do, and
    anything copied from Keychain Access, Passwords, 1Password or Bitwarden.
  - It keeps at most the 200 most recent entries; the oldest goes when a new one arrives.
  - Entries are removed once they are older than the period you choose (1 hour, 1 day, 1 week, or until
    you clear them). Clear Clipboard History in Settings › Held removes them all at once.
  - If the history file can't be read (damaged, or written by a newer Tuck), Tuck never writes over it:
    it renames it `clipboard-history-unreadable-<number>.json`, in the same folder, and starts an empty
    history. Those files still hold old entries, so Clear Clipboard History deletes them too.
  - Turning clipboard history off stops Tuck reading what you copy. If entries are saved, Tuck first asks
    whether to keep or delete them. Delete History removes them, and those set-aside files, as Clear
    Clipboard History does. Keep History leaves them saved: they stay until they pass that period,
    checked each time Tuck starts, or until you turn it on again and clear them.
- **Copies of dropped content** (`Received/`). Some drops arrive without a file of their own, such as a
  Mail message or an image. Tuck saves those here, and deletes each copy when nothing in Tuck refers to
  it any more.
- **Your settings**, in macOS's preferences for Tuck (`~/Library/Preferences/`, under Tuck's bundle ID).

When you ask Tuck to compress files, it writes the zip next to the originals, or to your Downloads
folder if that folder is read-only.

Files you drop stay where they are. Tuck keeps a reference to them; it does not copy, move or delete
your own files.

## What Tuck reads but does not keep

- **Other apps' windows.** With the Accessibility permission, Tuck reads the titles, sizes and
  positions of other apps' windows, and which one is in front, to tuck, restore, arrange and list them.
  It keeps only what is listed above for windows you tuck. It also asks macOS where windows are on
  screen and which app owns each one, but never their contents: Tuck takes no screenshots and needs no
  Screen Recording permission.
- **Files you drop.** Tuck reads them to show their thumbnail, kind and size, and to follow them if they
  move. Thumbnails are made by macOS on your Mac.
- **Folders, for macOS's prompts.** If you choose Just the Usual Folders in setup, Tuck lists the
  contents of your Desktop, Documents, Downloads and iCloud Drive folders once, which is what makes
  macOS ask you about each. It does not keep the listing.
- **Whether it has Full Disk Access.** To see whether you have granted it, Tuck opens macOS's own
  privacy database file and closes it at once, without reading it.
- **What you drag.** Tuck notices when the left mouse button goes down, drags and comes up, in any app.
  During a drag it looks at what kind of content the drag carries, and where the pointer is, so the
  notch can offer to take it. It reads the content itself only once you drop it on Tuck.
- **Clicks and scrolling.** While Tuck's fold is open, it notices a click elsewhere, which closes the
  fold. With Modifier-drag or the mouse-wheel features turned on, it also handles mouse drags and
  scrolling, to move windows and smooth the wheel.
- **Keys.** Tuck's keyboard shortcuts use macOS's hot-key service, which tells Tuck only about those
  exact key combinations, never other keys. To tell your own switch between apps from one Tuck made, it
  asks macOS how long ago you last clicked or pressed a key, but never which key.
- **What you copy**, only while clipboard history is on, as described above. Tuck works out what kind of
  thing each copy is on your Mac, once, as you copy it. From macOS 15.4, macOS
  may ask you before Tuck reads what other apps copy, and Tuck follows your answer.
- **Other apps' activity, for Rest.** Rest is experimental and off by default. When you ask to rest an
  app, Tuck checks that app's process: its program path and start time, its recent CPU time, whether
  it is using audio (as macOS reports it, never what it plays or records) and whether it has windows
  open. Tuck pauses the app only if those checks pass, and wakes it when you ask.

Tuck writes diagnostic notes to macOS's own log about tucked windows (for example, that an app brought
one back), naming the app's bundle ID. They stay on your Mac, and macOS discards them unless someone is
recording the log at the time.

## What leaves your Mac

Nothing reaches us. Tuck has no analytics, crash reporting or update check of its own, and sends no
data to us or anyone else.

The one exception is **previews of what you copy**, part of clipboard history, which is off by default
(Settings › Held › Clipboard history). While clipboard history is on:

- when you copy a link, Tuck loads that page once, as a browser would, to read its title and icon, and
  loads the picture the page names for sharing, if it names one. A link already in your history that has
  no preview yet, such as one copied with an earlier Tuck, is loaded the same way, once, when it first
  shows in Tuck. The site, and the site that serves that picture if it is another, sees a request from
  your Mac, as it would if you opened the link;
- when you copy an address, Tuck asks Apple's maps service (MapKit) to find it and draw a small map.
  Apple's privacy policy covers that.

Previews can't be turned off on their own: turn clipboard history off and nothing you copy is looked up
online. Nothing else you copy is sent anywhere.

Some things you do with Tuck involve other software, under that software's own privacy terms:

- opening a held link opens it in your browser, which loads the page;
- sharing an item hands it to the service you choose in macOS's Share menu, such as AirDrop or Mail;
- dragging an item out of Tuck hands it to the app you drop it on.

macOS itself may contact Apple about Tuck, for example to check its notarization the first time you
open it, or to send a crash report if you have chosen to share analytics with Apple. Apple's privacy
policy covers that.

## Your choices

- Remove any item, clear held items, or clear clipboard history from within Tuck.
- Turn off clipboard history (and with it the previews of links and addresses), reading text in copied
  images, or Rest, in Settings at any time.
- Withdraw Accessibility, Full Disk Access or folder access in System Settings › Privacy & Security.
- To remove everything Tuck has kept, choose Uninstall Tuck… in Settings › About. Tuck first brings back
  every tucked window and wakes every rested app, then turns off Open at Login, deletes the files it
  keeps in `~/Library/Application Support/Tuck/` (the folder too, unless something else is in it) and its
  preferences, resets its permissions in Privacy & Security, moves itself to the Trash and quits. Before
  you confirm, it says how many files it saved from drops, such as Mail messages, which may be the only
  copies, and can show them to you. To do the same by hand, quit Tuck, then delete that folder and
  Tuck's files in `~/Library/Preferences/`: `com.millerroberts.Tuck.plist`, and
  `app.tuck.prototype.plist` if an earlier version left one.

Because we never receive your Tuck data, we cannot see, export or delete it for you; it is all on your
Mac, under your control.

## Children

Tuck is not directed at children, and we do not knowingly collect information from anyone.

## Changes

If a new version of Tuck changes what it keeps, reads or sends, we will update this policy before that
version is released, and change the date above.

## Contact

[Support email]
[owner's full legal name or business, and postal address]
