# Tuck architecture

## Goals that shape the structure

1. **Lightweight.** A collapsed Tuck should cost nothing measurable: no polling, no idle animation, no
   heavyweight UI framework resident when it is not needed, no helper processes.
2. **Testable core.** The stream's logic, ordering, placement and policies are plain Swift value types
   with no UI dependency.
3. **Replaceable integrations.** Window parking, Rest, opening items, the pasteboard, the paste
   keystroke, haptics and persistence sit behind protocols: the app supplies the real implementations,
   and TuckCore has stand-ins for tests and previews (the paste keystroke's, `NoPaster`, is in the app).
4. **Online only to preview what you copy.** The one piece of network code is `ClipboardEnricher`'s
   previews (a copied link's title, icon and sharing picture, an address's map), which run whenever
   clipboard history, off by default, is on, with no switch of their own. There is no analytics or
   update check.

## Package layout

```
Package.swift
Sources/
  TuckCore/            Foundation only; unit-tested
    Models/            ParkedWindow (+ AppIdentity, ParkingMethod), HeldItem, RestState
                       (+ RestSafetyPolicy, RestController)
    Windows/           ParkingPolicy (+ ParkingPlan), WindowCandidates (CandidatePolicy,
                       WindowSelection, RestoreSummary), WindowDragGesture (+ WindowDragModifiers,
                       FrameThrottle)
    Library/           TuckLibrary (windows, held items, Rest states), TuckStream (+ StreamLens,
                       StreamEntry: the one list, its lenses and search), LegacySessions (merges a
                       sessions library), ClearPlan, SectionClearing (what clearing each
                       section asks), WindowOrdering (+ WindowGrouping,
                       WindowGroupExpansion), HeldItemClassifier, EarlierSamples (drops old sample
                       sessions as they merge)
    Placement/         Placement, PlacementChooserState, PlacementGeometry, PlacementHistory
    Scrolling/         ScrollSmoother, ScrollSmoothness, ScrollInput
    Files/             DropIntake (+ DropKind), FileReferences, ReceivedFileStore, ArchiveNaming,
                       FileLibraryPersistence
    Clipboard/         ClipboardHistory policy (+ ClipboardEntry, ClipPayload, ClipPreview,
                       ClipboardCapture), ClipboardAssetStore, FileClipboardPersistence
    Content/           ContentCategory (+ ContentRecognition, RGBAColor), ContentClassifier (+ VCard),
                       SearchQuery, SearchChips (the kind chips), SearchBadges (BadgeFilter,
                       SearchFacts: type, size and time words), SearchApps (SourceApp,
                       AppFilter: app names), BadgeText (the words on a tile's line of
                       details), ContactBadge (initials and their colour), PhoneNumberFormat
                       (+ PhoneNumber: code, grouping, flag)
    Gestures/          SwipeGestureTracker, ScrollGestureRouting, DropApproach (+ DragClassification)
    Motion/            SpringParameters, SurfaceMotion (the surface's springs), DepositFlight (a
                       tucked window's path)
    Layout/            FoldDepth, CardLayout (+ CardSize: the card setting), FoldLayout (the fold's
                       width and card size on a display), PanelListLayout, SurfaceDisplays,
                       NotchlessStyle
    Shortcuts/         KeyShortcut, ShortcutAction, ShortcutSet (validation, clashes, storage)
    Setup/             TourDesk (the pretend screen's state, shared by the tour and the gesture
                       step), TourLayout (its geometry, for the real drop and flight logic)
    Services/          Service protocols and their TuckCore stand-ins, HapticEvent, HapticPacing
  TuckApp/             AppKit + SwiftUI executable
    App/               Entry point, AppDelegate, TuckModel (shared UI state), TuckLogo (the logo
                       drawn in code: menu-bar template image, Settings' About mark), ReleaseInfo
                       (links and version from Info.plist), Uninstaller, MoveToApplications,
                       LineAppsFold (collapses the menu-bar item into Line Apps' line),
                       TrialLeftovers (deletes what builds with a trial left behind)
    Overlay/           ScreenAnchor, OverlayPanel, SurfaceView, OverlayController,
                       OverlayCoordinator, DragApproachWatcher, DepositAnimator
    Panel/             SwiftUI fold: band, lenses, FoldToolbar, StreamRows (StreamTiles,
                       StreamIcon), WindowRows (WindowGroupTile, WindowGroupContents,
                       ParkedWindowChildRow, the placement chooser, Tuck and
                       ArrangeWindowsButton), window picker (SuggestedWindowsView), prompts,
                       theme; ContentTiles (TileMetrics, TileGrid, TileStrip, TileChrome,
                       Headline, each kind's face and preview, WindowsFace), TileMeta (a
                       tile's line of details), TileActions (copy and held tiles, their menus,
                       drags and double-click paste), SectionClear (SectionClearButton and its
                       menu items, the Windows and Copied questions), SearchBar
                       (field, chips, No matches), ItemDetails (icons, thumbnails, FileSizes,
                       ThumbnailEdge, the inline editor), PanelSnapshots and TileSamples (debug
                       only)
    Settings/          SettingsStore, SettingsView (sidebar, pane header), SettingsPanes,
                       SettingsComponents (choice tiles, action buttons), SettingsWindowController,
                       ShortcutRecorder, SettingsSnapshots (debug only; setup steps too),
                       TuckWindow (closes on ⌘W, for Settings and setup)
    Setup/             SetupWindowController (+ SetupModel), SetupView (shell, welcome lockup,
                       permission, done, chips, LogoLine), SetupDesk (the tour, PretendScreen, MiniNotch), SetupChoices
                       (try-it pads), SetupGestures (the gesture step, SwipeArea)
    Windows/           AX (Accessibility wrappers, Displays), AccessibilityParkingService,
                       WindowCandidateSource, WindowDragController
    Rest/              ProcessRestService (+ POSIXProcessControl, AudioActivity, RestSwitch)
    Scrolling/         ScrollController (wheel event tap, glide display link)
    Shortcuts/         HotKeyCenter (system hot keys)
    Integrations/      SystemHaptics, SystemPasteboard, AppIcons, LoginItem, DropReader,
                       ReceivedIntake, ZipArchiver, WorkspaceItemOpener, ClipboardCaptureService,
                       ClipboardEnricher, Paster (SystemPaster: the ⌘V a double-click types)
Tests/TuckCoreTests/   Swift Testing suites
Support/Info.plist     Bundle metadata (agent app); the scripts stamp the bundle's copy, never this file
Support/release.env    Bundle ID, copyright holder and URLs: the one place both build scripts read
Support/AppIcon.icns   App icon, built from design/logo by design/logo/render.swift
VERSION                The version every build carries
design/logo/           Logo masters, generator and renderer, web icons and colour tokens
docs/legal/            Draft EULA (shipped in the DMG) and privacy policy
scripts/               build-app.sh, release.sh (signed, notarized DMG; docs/release.md), test.sh
```

## Runtime structure

```
AppDelegate
 ├─ SettingsStore ──onChange──▶ TuckModel
 ├─ TuckModel (ObservableObject, shared by every display)
 │    ├─ TuckLibrary (TuckCore)
 │    ├─ ClipboardHistory (TuckCore)
 │    └─ services: WindowParkingService, RestService, HeldItemOpening,
 │                 PasteboardWriting, KeystrokePasting, HapticFeedbackProviding,
 │                 LibraryPersistence
 ├─ OverlayCoordinator
 │    ├─ OverlayController per display ── OverlayPanel ── SurfaceView
 │    │                                                     └─ PanelHostingView (only while open)
 │    │                                                           └─ ExpandedPanelView (SwiftUI)
 │    ├─ DragApproachWatcher (global presses, and drag events only during a press → the drop
 │    │                       target; only while on)
 │    └─ outside-click monitor (installed only while the fold is open)
 ├─ WindowDragController (event tap, only while modifier-drag is on)
 ├─ ScrollController (scroll-wheel tap, only while a mouse-wheel option is on)
 ├─ HotKeyCenter (system hot keys, only while keyboard shortcuts are on)
 ├─ ClipboardCaptureService (pasteboard change count every 0.5 s, only while clipboard history is on)
 │    └─ ClipboardEnricher (once per new copy: words in images, media tags, link and map previews)
 ├─ Rest wake observers (workspace notifications, only while an app is resting)
 ├─ accessibility observer (distributed notification, no polling)
 ├─ SettingsWindowController (window created on demand, released on close)
└─ SetupWindowController (first launch, or Settings › General › Open Tutorial…; created on demand,
                          released on close)
```

### Overlay window

`OverlayPanel` is a borderless, non-activating `NSPanel` at status-bar level with `canJoinAllSpaces`,
`stationary`, `fullScreenAuxiliary` and `ignoresCycle`. It floats above the menu bar on every Space,
beside full-screen apps, and never activates Tuck or steals focus. The surface is black closed and
open, so what is drawn on it and the fold inside it resolve in the dark appearance
(`Theme.notchAppearance`, set on the hosting view) whatever the Light or Dark setting. It becomes key
only when asked to (`TuckModel.requestKeyFocus`): for the inline text editor, for search, for a fold
opened from the keyboard or the menu, so Escape and ⌘F reach it, and for the full fold, so its list
scrolls straight away and typing goes to the fold rather than the app behind. A shallow fold opened by
a click or a swipe leaves the keyboard where it was. While it is key, `OverlayPanel.sendEvent` offers
the bare arrow keys, Return and Space to the tiles first (`onTileKey`, see "Keyboard" under "The
fold"), before the search field sees them. Its frame is resized to the current state (collapsed or expanded) so it never blocks clicks on
the menu bar or desktop around it. Settings → Notch can drop `fullScreenAuxiliary` (not beside
full-screen apps) and set `sharingType` to none (left out of screenshots and recordings, deposit flights
included). `OverlayCoordinator.apply(_:)` takes these with the display choice and style, and rebuilds
surfaces only when the displays or style change.

### Anchors

`ScreenAnchor.resolve(for:)` detects a hardware notch from the screen's top safe-area inset and its
auxiliary top-left/top-right areas: the notch width is the gap between them. Notched displays get a
black surface that continues the hardware notch: the notch's height plus 2 pt (the physical notch can
end a fraction of a point below the reported inset, which would show as a thin line under the surface),
quarter-circle shoulders where it meets the top edge, and one wing either side (the notch height plus 4
pt): Tuck's mark on the left and a small dot on the right, shown only while Tuck holds a window or an
item. It is centred on the notch itself, which can sit half a point off the screen's centre, and the
mark and the dot are each centred in their wing, between the shape's side and the notch. Empty (copies
alone included), or tucked away, it shrinks to the notch itself and draws nothing. Other displays get a
soft bubble centred in the menu-bar strip, 72 pt wide, holding the mark alone, or, with Settings → Notch
→ Displays without a notch set to Notch, a drawn notch 180 pt wide and as tall as the menu bar
(`isSimulated`): the same black surface, but with nothing behind it, so an empty or tucked one leaves
only a near-invisible spot to point at or click. Only the displays chosen in Settings get a surface
(`SurfaceDisplays`); if none matches, the menu-bar display does. `SurfaceMetrics` holds the sizes both
the view and its controller use, the open fold's width among them (`fold`, from the card setting and the
display; see "The fold"); the window is always sized for the resting surface, so tucking and swipes
never resize it mid-animation.

### Collapsed surface (AppKit + Core Animation)

`SurfaceView` draws the collapsed state as quietly as the hardware allows. A `CAShapeLayer` is the
surface, always black, notch or bubble, so it continues the hardware notch; everything drawn on it
resolves in the dark appearance whatever the Light or Dark setting (`Theme.notchAppearance`). On a
notched display an empty Tuck is the bare notch, with no wings and nothing drawn; copies alone leave it
bare too, since the mark follows `TuckLibrary.totalItemCount` (windows and held items). While Tuck holds
something the left wing shows Tuck's mark (20 pt; centred in a bubble and 4 pt shorter than it), a
`markLayer` holding three layers: the logo's line, the screen's top edge dipping round the notch, faint
(`markBaseLayer`, the label colour at `TuckLogo.restingOpacity`, 0.32); the same line in Tuck blue
(`markLitLayer`), shown only while the pointer is over the closed surface; and a short card in the dip
stroked in Tuck blue (`markCardLayer`), there while Tuck holds something, as the Dock's Trash shows
empty or full. The right wing shows a 6 pt dot in the tertiary label colour (`restingDotLayer`). There
is no count. A bubble shows only the mark, centred, faint while Tuck is empty and with the card while it
holds something; it has no dot. Every piece is a `CAShapeLayer` or plain `CALayer` stroked from
`TuckLogo`'s paths, so nothing is drawn into images, and they change only when the library or the
pointer does.

The card follows the library (`followHolds`): it lifts out at once as Tuck empties (0.2 s), but drops in
only once what was deposited has landed (`landDeposit`), or shortly if nothing is on its way, so it never
drops under a window's card that is still flying. It drops from above on a spring (stiffness 385,
damping 28) with a 1.16× swell of the mark over 0.2 s; under Reduce Motion it fades in or out over
0.2 s.

Pointing never opens the fold; a click or a swipe down does. Hover gently grows the shape (8 pt wider, 2
pt taller on a notch) and lights the line. As the pointer arrives the mark greets it once (`greetMark`):
the line's dip reaches down, as the fold would drop from it, springs back a little past rest and settles
in 0.5 s, with the card riding it 0.035 s behind. It is a keyframed path on the line's layers, left to
finish rather than restarted, and skipped while the surface rests in the notch, while a closing fold is
still folding away and under Reduce Motion, where the line only lights. While pointed at, the dot gives
way to the Tuck button (`tuckArrowLayer`, an arrow up into the notch stroked in the logo's line and Tuck
blue): the dot shrinks to 0.4 and fades as the arrow grows from 0.6 and rises into its place; under
Reduce Motion they only fade. A bubble has one symbol, so there the mark gives way instead: it fades and
shrinks to 0.7 about its own centre as the arrow rises in its place, nothing moving sideways, and the
mark doesn't greet while it does. The button's target is the arrow and 6 pt round it; the bubble's 20 pt
ends (`bubbleEndWidth`) still open the fold. The button shows while the mark does and the pointer is
over the closed surface, with no prompt up. A press on the button presses it in (0.86, 0.12 s); letting
go over it calls `TuckModel.tuckFrontWindow()`, the Tuck Front Window shortcut's path, without opening
the fold; it tucks the focused window, not every window of its app. Pointing at a
notch whose stream is empty opens nothing either: the surface pops out as it does for a drag and says
"Drop into Tuck" (`isShowingCue`). A bubble offers the arrow even then. The glyph beside those words is
drawn into an image once per symbol, size, colour and appearance and kept (`SurfaceView.glyphs`), since
the closed content is recoloured at every model change; the cache is cleared when the appearance
changes.

What is deposited lands in the mark (`landDeposit`): an empty mark takes its card, otherwise the mark
swells once (1.12× over 0.24 s). A drop on the closed surface first draws the drop words and glyph into
the mark, shrinking, as the band folds back (`compressIntoMark`); under Reduce Motion they fade with the
band and nothing swells. When an action did nothing while the fold is closed (a keyboard shortcut, say)
the mark, the dot and the arrow give a small sideways shake (0.36 s; not while tucked away or under
Reduce Motion); with the fold open, its status line says why instead.

AppKit replaces the window's tracking area when the window resizes without sending an exit, so closing
the fold and each resize re-read where the pointer is (`pointerMayHaveMoved`): the closed surface goes
back to its resting form unless the pointer is still over it.

The view also:

- handles clicks (toggle) and two-finger swipes (`SwipeGestureTracker` from TuckCore). Vertical swipes
  step through four stages, tucked, collapsed, the shallow fold and the full fold, one step per gesture:
  down goes one deeper, up one back. An empty notch counts as collapsed, so a swipe down opens it as
  from the wings. Sideways does nothing, except over the shallow fold's strip, which it scrolls
  (see "The fold"). While a swipe is in progress on the closed surface the
  tracker's `pull` (−1…1) drives the shape directly, without animation: down stretches it towards the
  fold or slides the wings out of the notch, up draws the wings in and fades the content. Lifting short
  of the threshold springs it back; crossing it commits. Swipes play no haptic.
- is the drag destination for files, URLs and text (`DropReader`): over the drop target while closed,
  and anywhere over the open fold.

For VoiceOver the closed surface is one element: a button labelled "Tuck", whose value says what Tuck
holds (`TuckModel.spaceSummary`, such as "Tuck, 2 windows, 1 item" or "Tuck, empty"), and whose press
opens the fold as the keyboard would. A changed value is posted as the collapsed content refreshes
(`.valueChanged`, which VoiceOver speaks only with its focus on the notch).
While VoiceOver is on, the change is also announced a second after it settles (`.announcementRequested`
at low priority), so a burst of changes is one announcement and nothing else being read is cut into.
While the fold is open the surface is a group and the fold's own elements speak.

### The fold (SwiftUI, on demand)

Opening first builds `PanelHostingView` (hosting `ExpandedPanelView`) out of sight, so the fold's real
height is known one run-loop turn later. Then the window grows, with room below for the spring's
overshoot, and the outline makes a single spring to the right size. The shape, its shadow, the drop rim
and the mask of `PanelClipView` share that outline, so the fold stays clipped inside the shape and fades
in just behind it. The fill stays the notch's black (`Theme.paperNSColor` is black in dark, and the
fold is always drawn dark); opening only adds a soft shadow (0.26 s ease-out, 0.16 s under Reduce
Motion). Around
a notch the rim is the outline without its top, which is the screen's own top edge (stroked, it drew a
line along the wings and in under the notch). Its shoulders still set off along that edge, so a gradient
mask (`promptRimFade`) leaves the rim clear for 2 pt below the top and brings it in over the next 8, the
shoulder's height: it fades out as it climbs the shoulder and never touches the edge. It sits above the
fold, and while something is dragged over the open fold it shows there too, in Tuck blue. The fold's own
drop target (`DropTargetOverlay`) puts paper behind its tinted box, so the first row's cards, which
start a little higher, don't show their tops above it. Springs come from `SurfaceMotion` (TuckCore),
described as duration and bounce and converted to Core Animation's stiffness and damping, and always run
to completion:

- open: 0.45 s, bounce 0.4, about 10% overshoot;
- close: critically damped, 0.4 s response;
- release after a press: 0.6 s, bounce 0.35;
- hover, press, tuck and resize: critically damped, 0.3 s;
- drop invitation: 0.35 s, bounce 0.25.

A spring starts from the model path unless a morph is actually running. The presentation layer holds the
last committed frame, which right after a window resize is in the old window's coordinates; starting from
it made the shape open from about 62 pt to the left. A width change lands any morph in flight before
laying out, and the window shrinks after the drop invitation only once its morph has finished.

The fold has two depths (`FoldDepth`), both as wide as one row of its cards. The shallow fold
(`.peek`) shows one row, the strip, which holds the whole stream, the newest at the left, and scrolls
sideways through it; the full fold (`.full`) shows all of it in the same tiles, in a list that
scrolls.

How wide, and how big the cards are, comes from the card setting. `CardLayout` (TuckCore) is Settings ›
Notch › Cards (`SettingsStore.cardColumns` and `cardSize`): 2 to 5 cards in a row (`columnChoices`,
clamped; 3 by default) and a `CardSize`, Small, Medium or Large, 0.9, 1 and 1.3 times the 168 by 96 pt
medium card (`FoldLayout.mediumCard`), rounded down to 151 by 86 and 218 by 124. `FoldLayout` makes a
fold of it for one display: the row's cards, 8 pt between them (`cardSpacing`, which is also
`Theme.tileSpacing`) and 10 pt either side (`edgeInset`), so three medium cards make 540 pt
(`FoldLayout.standard`). It is never narrower than its `minimumWidth`, and the row then sits in the
middle (`sideInset`); nor wider than its `maximumWidth`, and the cards then shrink to fit, keeping their
shape (but never shorter than a small card, so their lines stay whole). Before a card would shrink
under 150 pt (`narrowestCard`), where a title stops being readable, the row drops a card, down to two
(`CardLayout.columnChoices`' first), so a narrow display shows two wide cards rather than three
cramped ones; only past two does a card shrink further, never under 40 pt wide. `SurfaceMetrics.fold` gives it the bounds: the notch's width (the
bubble's resting width on other displays) and 130 pt either side (`bandWingWidth`) for the Tuck button
and the lenses, and the screen's width less 48 pt each side (`foldScreenMargin`) and the shoulders.
`panelWidth` is an instance property that reads it, and `expandedWidth` adds the shoulders.
`TuckModel.cardLayout`, seeded at launch and set by `apply(settings:)`, tells the surfaces when it
changes, and `OverlayController.refresh()` re-applies the window's frame when the open fold's width
changes, so a change in Settings lays an open fold out again at once. `ExpandedPanelView` hands the
fold's cards to everything inside it as `TileMetrics` (`\.tileMetrics`: columns, card width and height,
side inset and the row's width); anything drawn outside a fold has three medium cards.

From the top, `ExpandedPanelView` stacks:

- `FoldBand`, the top line, level with the notch, so the fold grows wider before it grows taller.
  Around a notch the notch itself is its middle; on a bubble the logo's line sits there, blue while
  Tuck holds anything and faint while it is empty. Shallow, the left holds `TuckFrontButton` (the
  window in front: its app's icon and "Tuck"; "Allow Tuck" without Accessibility) and the right
  `LensCluster`: Windows, Files and, while clipboard history is on, Copied, each with its count
  (`ViewThatFits` moves the counts to the tooltip where a notch leaves too little room, and on a fold
  kept narrow by small cards leaves each lens its symbol), with a hidden ⌘F button behind it. Full,
  the left reads "Everything in Tuck" in `panelHeadline` and the primary ink, so it reads as the fold's
  title ("Choose windows to tuck" while the picker is open; "Everything" and "Choose windows" where
  the fold is too narrow) and the right holds Search (⌘F) and the chevron
  that folds back. A secondary click on the band shows `FoldMenuItems` in either depth: Choose
  Windows to Tuck… (disabled without Accessibility), then `SectionClearItems` (Clear Windows…, Clear
  Files… and, while clipboard history is on, Clear Copied…, each disabled while its section is
  empty), then Settings….
- `SearchBar`, in the full fold only: the field while searching, and the kind chips
  (`SearchChips`) under the band before a search, when there are two or more, and under the field
  during one.
- The list: the window picker (`SuggestedWindowsView`) while it is open; `EmptyCue` when Tuck holds
  nothing ("Drop into Tuck") or a lens holds nothing; `NoMatches` when a search finds nothing;
  otherwise one `StreamTiles` grid of the whole stream for both depths. It begins with the strip
  (`TileGrid`'s `strip:`, `.scrolls` shallow and `.leads` full): in the shallow fold the strip scrolls
  and whatever any of it has open opens under it; in the full fold the same strip, back at its start,
  is the first row and the rest of the rows follow under it, so deepening keeps the first row where it
  is. Fewer tiles than a row keep their size and sit from the left. A tile of windows still on their
  way up is drawn empty, keeping its place, until they land in it.
- `MoreRow` ("N in all", or "Everything in Tuck" under a lens) in the shallow fold when the stream holds
  more than a row; it unfolds. The count stays true however far the strip is scrolled.
- `FoldToolbar`, in the full fold only, under the list and set off from it by a hairline the fold's
  width: `ArrangeWindowsButton` at the left while there's a window in front and Accessibility is
  allowed (it places that window through the placement chooser, which opens under the toolbar, without
  tucking it), and `SectionClearButton` at the right: with no lens on, a Clear menu of
  `SectionClearItems`; with a lens on, that section's one button. Both take `PanelButtonStyle`'s quiet
  role. Clear is hidden during a search, while the picker or any section's question is open, and when
  nothing can be cleared; with neither shown, nor is the toolbar. The list sits above it, never under
  it: `scrolling()` and `TileGrid` end the list with `Theme.listFoot` (8 pt), so a scroll to the end
  shows the last row whole with that room above the hairline.
- One prompt at a time, in this order: clearing held items (`ClearPlan`), clearing copies, putting
  back all windows, Rest, Accessibility withdrawn with windows tucked, the picker's
  action bar, then the note that copies from other apps are held back (only with the Copied lens or in
  the full fold).
- `PanelFooter`, the status line: what the last action did, or that Tuck is tucked away.

`TuckModel.expand(on:via:)` always opens the shallow fold with no lens and no search, and asks for key
focus only when the trigger is the keyboard or the menu; `unfold()` deepens it, drops the lens, so the
full fold shows everything, and always asks for key focus; `fold()` goes back, closing the
picker and the search. `beginSearch()` and opening the window picker unfold first; `beginSearch()`
keeps a lens that holds something and lets go of one that holds nothing.

**Keyboard.** While the fold is key, the arrow keys move a focus ring through its tiles.
`OverlayPanel.sendEvent` reads a bare arrow, Return or Space as a `TileKey` (Shift-arrows are left to
the search field's selection) and offers it to `OverlayController`'s `onTileKey`, which passes the
display's fold columns to `TuckModel.handleTileKey`. The ring's place is `tileCursor`, a
`StreamEntry` id, so it follows its tile as the stream changes; it is cleared when the fold opens,
deepens, folds back or closes, and when the search's words change. `TileNavigation.step` (TuckCore)
moves it in rows of `columns`, the shallow fold's strip being one long row: from no tile, Down (or
Right outside a search) goes to the first; Up from the first row goes to no tile, back to the search
field; Down into a short last row goes to its last tile; nowhere further keeps the place. On no tile,
Left, Right and Up stay the search field's. Return opens the tile with the ring (`TuckModel.open(_:)`,
what a click does), or the first match without one; Space does too outside a search. Nothing is taken
while an edit, the picker or a question is open, and Escape takes the ring off before it ends a search.
`TileGrid` gives the tile with the ring `isTileFocused`, so `TileChrome` draws a 2.5 pt ring (an open
tile's is 1.5 pt, so the two never read alike) and `TileMeta` shows its second details, and its
`ScrollViewReader` scrolls the least that shows the row: to the row's `RowAnchor`, or for the last row
with nothing open under it to `EndAnchor`, an anchor laid over the list's foot, so the keyboard leaves
the last row the same room above the toolbar that a hand scroll to the end does. `TileStrip` scrolls
the strip sideways to put the tile in the middle, clear of the faded ends. In the open fold a
vertical swipe moves one depth (`SwipeGestureTracker`): down from the shallow fold unfolds; up from the
full fold folds back, and from the shallow fold closes. Folding back or closing takes 14 pt of travel,
opening or deepening 24 pt. Each gesture locks to one axis after 8 pt; in the open fold it counts as
vertical only when clearly more vertical than sideways (1.5×), so a sideways brush never folds or
closes anything. `ScrollGestureRouting` decides who a gesture belongs to, by where it starts
(`Region`): a gesture that starts over the full fold's list while it has more than it shows scrolls
the list for the rest of the gesture (`.scrollableList`); one over the shallow fold's strip while it
holds more than a row (`.strip`) waits to show its axis; anywhere else it is a swipe. Over the strip
the router holds the gesture's events (`.hold`; `SurfaceView` keeps them in `heldScrollEvents`) until
it has gone 8 pt, by the same lock and bias as the swipes. Clearly more up or down than sideways, it
is a swipe begun by the first held event (`.swipeHeld`), which can deepen, fold or close as anywhere
else. Otherwise it belongs to the strip (`.passOnHeld`): the held events are sent back through the
window to the strip's `ScrollView`, with `isReplayingScroll` keeping the monitor from routing them a
second time, and the rest of the gesture and its momentum pass on to it. A gesture that ends before
showing an axis is a swipe that went nowhere. Ownership is decided once, as the gesture starts or,
over the strip, once its axis shows, and never re-decided mid-gesture. Mouse wheels have no gesture
phase and pass straight on, so a sideways wheel reaches the strip.

The strip (`TileStrip`) is a horizontal `ScrollView` of a `LazyHStack`, so a card is made only as it
comes into view, with no scroll indicators. Its viewport is the row's width and the 8 pt edge inset
either side, centred, so a fold the notch keeps wider than its row still shows only the chosen
number. While there is more beyond an edge, a 28 pt gradient in its mask fades that edge out
(`StripEdges`, animated with `Theme.quick`); that is all that says it scrolls. It reports its frame
(`StripFrameKey`, into `TuckModel.stripFrame`, which `SurfaceView.scrollRegion(for:)` reads) only
while it scrolls and holds more than a row. When the fold deepens, scrolling is turned off, the strip
slides back to its start with the fold (`Theme.fold`; at once under Reduce Motion) and its mask cuts
it halfway into the gap after its first row; something new arriving at the left takes it back to its
start too.

Closing fades the fold at once, folds it away inside the shrinking outline and, once the outline is at
rest, releases it (tearing the SwiftUI tree down mid-close held the screen on a half-closed frame): the
hosting view's root becomes an empty view, then it leaves the view tree. Removing it alone isn't
enough, because AppKit can keep a removed hosting view (the window holds on to the last view a scroll
went to), and the whole SwiftUI tree, still observing the model, stayed with it. Every refresh of the
closed surface, once the outline is at rest and no open is being prepared, also releases any hosting
view still in the surface; so does an open called off while its panel was being built. The panel is
recorded before it joins the view tree, so nothing that the insertion sets off can add a second one
that is never taken out. The shadow goes as it closes, and the mark and dot, put back in the wings
while hidden, return once it is nearly home. The fold reports its ideal height through a
preference so the window and shape fit the content exactly; the full list scrolls past its maximum
height (`min(440, max(180, screen height − menu bar − 280))` pt, through `PanelListLayout`), so it stays
a compact list rather than a drawer down the screen. Window tiles, and the title rows of an open app,
report where they are back to the model (`WindowRowFramesKey`, a `WindowLanding` per window: the frame
and the rect of its icon), so a tucked window's card lands on the tile's or row's icon, and the list its
frame, so the surface
knows when a swipe belongs to the list.

`TuckStream.entries` builds the one list on demand while the fold is open: windows grouped by app,
held items and copies together, newest first, narrowed by a lens and by a `SearchQuery`: its kinds
and day span, its badge words (types, sizes, times; see "Search" below), then every other word
somewhere in the entry (a window's app or title; an item's title, text, path, address, source app or
kind; a copy's text, source app, kind and what was recognised or learned about it). Nothing is
indexed or kept in the background. Windows are
`WindowGrouping.groups(for:)`: parked windows bucketed by app (bundle ID, or name when there is none),
each group's windows newest first, a group taking its place in the stream by its newest window. In
both depths every group is one `WindowGroupTile` (its face is `WindowsFace`: the app's icon and name and
the newest title, with no count): a single window's restores it (⌘-click opens its placements under the
row), and a larger group's only toggles `WindowGroupExpansion` in the model, opening
`WindowGroupContents` ("<App>'s windows", Restore All and Hide, then a `ParkedWindowChildRow` per title,
each restoring one window or opening its chooser) full width under the row. Several groups can be open
at once. The expansion set holds only ids of multi-window groups, starts empty and is pruned whenever
the library changes, so a tile that falls back to one window forgets that it was open.

### Panel design system

`Theme` holds the fold's tokens and styles; every view uses them, not literal values.

- **Colour:** the fold is the notch's black (`paper`, black in dark; the hosting view is always dark, so
  the warm paper tones for light never show in the fold), with `raised` for a field off it (the search
  field, the tucked window's card), `stone` for quiet fills (a hovered row, a resting button, the
  lenses), `hairline` for rules, and three text tones (`primaryText`, `secondaryText`, `faint`). Each is
  a `tone()`: a colour for light and dark, each with a stronger one for Increase Contrast, picked
  through `bestMatch`. Every tile sits on one card, `tileFill`, a step stronger under the pointer or with
the keyboard's ring (`tileHover`): a light grey with no hue (0.89 in OKLCH on black, #D9DBDD; 0.93 on
paper, #E6E8EA; chroma 0.005 or less), so the stream reads calmly and pictures, maps and colours keep
the only full colour. What a tile holds is told by a small mark at the start of its line of details,
its kind's symbol in `kindMark(for:)`, from `TileTint`: twelve deep hues 30° apart round Tuck blue's
own (252° in OKLCH), a wheel that lands within 3° of Pulse's indigo, Hum's crimson and Glow's peach,
though none is their colour, all at one lightness so no kind shouts over another (0.53 at chroma 0.13,
or less where a hue would leave sRGB, 0.09 for teal; 0.43 with Increase Contrast), the same in both
appearances since the card is. By kind: blue for links, violet for code, red (Hum's hue) for music and
audio, rose for emails and contacts, orchid for keys, orange for dates, gold for emoji, olive for
images, screenshots and videos, leaf for addresses, green for files, folders, paths and stacks, teal
for phone numbers and sky for windows; text, rich text and colours take a plain grey. A card is light
in every appearance, so what is drawn on it takes the card's inks: `TileChrome` sets `isOnTileCard`,
and the text, hairline and accent tokens are `OnCard` styles that resolve to ink (#111316), a warm dark
grey and a deep Tuck blue (#325C8D in dark) inside a card, so a face drawn with Theme's tokens follows
without knowing. On the card and its hover, in all four appearances, primary text is at least 12.4:1,
secondary text 4.60:1, code's keywords and strings 4.60:1, a kind's mark 3.31:1 (5.17:1 with Increase
Contrast), and the ring and the capsule 3.31:1 off the ground. There is one accent, Tuck blue (`accent`: the
  logo's #7299C5 in dark, 7:1 on black, and #9CBEE3 with Increase Contrast), with `accentTint` for the
  active drop target and a selection. It marks the mark's light and card, the Tuck button's arrow,
  keyboard focus (on a card, the tile with the keyboard's ring), the kind chip that is on, the active
  drop target, a selected or expanded control, the deposit and restore cue
  and the click feedback capsule; apps and clipboard formats have no colour of their own. People's
  initials take one of `ContactBadge.palette`'s six colours. Destructive choices are plain buttons,
  their label saying what they do. The closed notch and the open fold both draw in the dark appearance
  (`notchAppearance`). Settings and setup keep the system's own accent.
- **Shape and motion:** the fold's corners are 20 pt (`foldRadius`) and a control's 10 pt
  (`controlRadius`). `quick` (0.16 s) is for hover and focus, `press` (0.12 s) for a control pressed,
  `settle` (0.24 s) for a change inside the fold, `fold` (0.26 s) for a depth change or a lens, and
  `deposit` (a 0.48 s spring) for something arriving in the stream or leaving it. Under Reduce Motion
  the last three become `quick`, and `Theme.reveal(edge:)`, which slides prompts and opened lists in,
  becomes a fade.
- **Type:** system text styles, so the font's optical sizes and tracking apply: `Font.panelTitle`
  (body medium, 13) for row and prompt titles, `panelBody` (body, 13), `panelSubtitle` and `panelMeta`
  (callout, 12, tabular digits for counts and times), `panelControl` and `panelCaption` (callout
  medium), `panelHeadline` (body semibold, for large buttons). A card's title is `Font.tileTitle` (body
  semibold, 13), over `panelSubtitle`. No text is below 12 pt in the fold but a tile's line of details
  (`Font.tileMeta`, subheadline, 11 pt, tabular digits) and code's line numbers, whose words are all
  in the tooltip and VoiceOver too.
- **Rows** are left only where a list reads better than tiles: the titles in an open app's list
  (`ParkedWindowChildRow`), "N in all" (`MoreRow`) and the window picker. They take `RowButtonStyle`,
  whose `RowChrome` gives the rounded hover highlight in stone (10 pt corners) and the blue tint while
  pressed or opened out.
- **Tiles** (both depths): `TileGrid` lays the stream in rows of `TileMetrics.columns` in a
  `LazyVStack`, beginning with the strip, each card as wide and tall as `TileMetrics` says (from
  `FoldLayout`; 168 by 96 pt for medium), 8 pt apart (`Theme.tileSpacing`) with 10 pt corners. The rows
  are laid out by hand rather than with a grid, so a row can open a full-width section under it.
  `TileContent` reads a `ClipboardEntry` or a `HeldItem` into one shape, and `ContentTileView` lays
  out every kind the same way; an app's tucked windows are one `WindowGroupTile` with a `WindowsFace`
  (icon, name and newest title), laid out as the others are.
  - **One layout:** a card is what it is at the top and its line of details (`TileMeta`) at its foot,
    10 pt in from its edges (`Theme.tilePadding`; 9 pt at the foot, `tileFootPadding`, so a row's lines
    share a baseline). The line is 14 pt tall on every card (`TileMeta.height`), so titles and previews
    line up across a row. What it is at the top is one of three shapes:
    - **A headline** (`Headline`): a 30 pt picture at the left (`Theme.tileLead`: an icon, an avatar, a
      flag, a calendar page, an emoji, a lock) beside its title in `Font.tileTitle` and a quieter line
      under it in `panelSubtitle`. A `ViewThatFits` tries the title on two lines with the quieter line,
      then on one with it, then on one alone, so the quieter line goes before the title is cut. File
      names are cut in the middle, keeping their extension; names and titles at the end; a number or a
      key shrinks to 80% before it is cut.
    - **The words or code themselves:** text and rich text (`WordsFace`, `Font.panelWords`, which the
      text editor uses too) up to three lines from the card's top; rich text keeps bold, italics and
      links as emphasis, so they follow the face's size. Code as an editor shows it (`CodeFace`): as
      many of its first lines as the card has room for (`ViewThatFits`, up to `CodeExcerpt.mostLines`,
      6; three on a small or medium card and five on a large), quietly tinted (`codeKeyword` and
      `codeString`, nothing more), each a `CodeLine` with its number in a 14 pt gutter
      (`Font.panelCodeGutter`, in the faint ink). `CodeExcerpt.lines` leaves out blank lines before the
      first and after the last shown, as the line count does, and keeps those between, so the numbers
      are the lines' own. A long line keeps its length (`fixedSize`) and the face is held to the card's
      inner width, so it runs to the padding and fades out over its last 16 pt rather than ending in an
      ellipsis.
    - **A preview** across the card's full width, `TileMetrics.previewHeight` tall (the card less
      `Theme.tileLabelHeight`, the label under it), clipped, with a one-line title in `tileTitle` and
      the line of details under it on the card: a picture or screenshot (`ImagePreview`, its file name,
      or its kind for a copied one), a video's first frame with a play mark (`VideoPreview`), a colour
      over a `Checkerboard` where it is see-through (`ColorPreview`, its hex), an address's map, fetched
      or `DrawnMap` from the address itself, with a pin (`MapPreview`, its street), and a page's picture
      for sharing (`PagePreview`, its title, else its site). Pictures fill and crop (`TilePicture`,
      `.fill`), so they keep their shape. Until a picture is made, or when there is none,
      `PreviewPlaceholder` sets the kind's symbol quietly in its place, so the label stays where it is.
      Nothing is ever written over a picture.
  - **Each kind's top:** a link or music link's site icon (`SiteIcon`: a touch icon, opaque at its
    corners and sharp at that size, fills a rounded square, a favicon sits on a white one, and a link
    symbol stands in until the page is looked up or when it has none) beside the page's title; a page
    with no title, or not yet looked up, is named by its site, with the rest of its address under it cut
    in the middle. An email's initials (`Avatar`), the name before the @ and "@" and the domain; a phone
    number's flag (`PhoneBadge`, a handset when the region isn't known), the number grouped for its
    country (`PhoneNumberFormat`) and the country under it, with the calling code when it was written
    without one; a contact's initials, name and number, email or detail; a date's calendar page
    (`MiniCalendar`), weekday and date; an emoji, its name; a path's icon, name and folder; a key's lock
    and the key masked (`TileText.masked`); audio's artwork, title and artist; a file's or folder's
    thumbnail or icon and name ("No longer there" once it is gone); a stack's icons fanned
    (`FannedIcons`), its first name and the second, or "and N more".
  - **The line of details** (`TileMeta`): the kind's mark (`MetaLine`: its symbol at 10 pt semibold in
    `Theme.kindMark(for:)`), then what it is and the one fact most worth a glance, a quiet dot between
    them ("Markdown · 4 KB"), in secondary ink, and the time, when asked for, in the faint ink at the
    end. `revealsMore`, set while the tile is under the pointer, has the keyboard's ring or is open
    (`isHovering || isActive || isTileFocused`), adds the second fact, the folder and the app's icon.
    The line takes no hits (`allowsHitTesting(false)`), is hidden from VoiceOver, and goes to zero
    opacity while `FeedbackBadge` shows.
    - **What it says** (`TileMeta.Facts`): its kind as a symbol and a word, then a fact or two read
      from it, then, for a file, where it is, then the app's icon. A word already said (a link's site,
      say) isn't said twice (`Line` keeps each word once).
      - A file: a symbol from its `UTType` (PDF, image, movie, audio, archive, disk image, source
        code, spreadsheet, presentation, application, font, text, else a page) and `BadgeText.type`,
        a song's or a film's length (`BadgeText.duration`, from its preview) and its size; a folder
        "Folder" and `BadgeText.items`; a stack, or a copy of several files, `BadgeText.files` and
        their sizes summed. Each adds its folder (`BadgeText.folder`: "in" and its name, "~" for the
        home folder, "iCloud Drive" or "Trash"; none when the files are in different folders).
      - A copied image with no files: "PNG" with the photo symbol (the camera for a screenshot), its
        size in pixels and the byte count recorded when it was copied.
      - Text and rich text: "Text" or "Rich text" and `BadgeText.words`; code its language ("Code"
        without one) and `BadgeText.lines`. A count of one isn't shown. `TextCounts` (in
        `ItemDetails.swift`) counts a text under 2 KB at once, so its line never reflows, and a longer
        one in a detached utility task, keyed by the copy or held item and the text's length, so an
        edited text is counted again.
      - A link its site when the title says the page (else "Link") and the type of file it leads to
        (`BadgeText.linkedType`, nil for a page); a music link its service and what it opens
        (`musicKind`: album, track, playlist, artist, episode, podcast); a colour how it was written
        (`colourFormat`, "HEX" or "RGB") and its opacity when it isn't whole; a date how far off it is
        (`BadgeText.distance`: "Tomorrow", "In 3 days", "2 weeks ago"); an address its town; a key its
        maker (`keyMaker`: "Anthropic", "GitHub", "AWS", "JWT"); a path its file's type or "Folder" and
        its size or item count, read once per path while the fold is open
        (`ItemDetails.status(ofPath:)`), or "Not found". An email, a phone number, a contact and an
        emoji wear the kind alone, since the top already says the rest.
      - `WindowsFace` wears "Window" or "N windows", and "Rested" too under the pointer for a rested
        app.
    - **The app's icon** is the line's last fact, bare, drawn a point past the line, since an icon's
      art sits inside its canvas: `ItemDetails.appIcon(bundleID:name:)` finds the app by a copy's
      `sourceBundleID`, or, for a held item, which records only a name, among the running apps, and
      keeps it (32 pt, drawn to one size by `AppIcons.normalized`) until the fold closes. It is left
      off what Tuck copied, an app that isn't on this Mac, screenshots (the camera symbol says where
      they came from) and files, folders and stacks from Finder (the folder says where they are); a
      file from any other app, a mail attachment say, wears it, and so does a copied image, where the
      app tells one picture from another.
    - **Every app icon is drawn to one size** (`AppIcons.normalized`), on the line, in window tiles and
      rows, the search bar's app chip, Settings' app list and the tucked window's card, since apps place
      their art differently in the icon's canvas (Apple's with a margin and a soft shadow, some to the
      edge). The art is found once, on a 64-pixel drawing (pixels at least half opaque, so the shadow
      is left out), and drawn centred with its longer side at Apple's grid, 824 of 1024; art that
      covers less of its box than a rounded square (0.93), such as a circle, is drawn larger by the
      square root of the difference, up to 12%, so it looks as big.
    - With `TuckModel.showsCopyTimes` (Settings › Held › Show when each was copied, `SettingsStore`'s
      `showsCopyTimes`, off by default, seeded at launch and set by `apply(settings:)`) every
      `ContentTileView` adds `BadgeText.time`.
    - `BadgeText` (TuckCore) has the words: a type from the extension (up to four letters in
      capitals, longer ones as a word, a few by their own name, such as "Markdown", or their app's,
      "File" without one); a size as `ByteCountFormatter` writes a file's, nil for none or zero, so
      there is never "Zero KB"; "1 item", "N files", "N words", "N lines"; and a time as the clock today
      (in the locale's 12- or 24-hour form), "Yesterday" and the clock, the abbreviated weekday within
      the week, then the day and month, with the year when it isn't this year's. `shortTime` is
      "Yesterday" alone, and `spokenTime` the same for VoiceOver ("at 3:41 PM", "yesterday at 3:41
      PM", "on Monday", "on 2 November").
    - The line is a `ViewThatFits` of `Line`s, widest first. Revealed: the kind, both facts and the
      folder; without the folder; without the second fact; then with the short time; then the kind
      alone; each with the time and the app's icon at its end. At rest: the kind and its first fact
      with the time, then with the short time, then the kind and the short time. When none fits, the
      kind, its first fact and the short time end in an ellipsis rather than being cut.
    - A fact not yet known (a size, a count, a long text's words) is read in the line's `.task`
      through `FileSizes` or `TextCounts`. `TileMeta.spoken` gives every fact, the second ones too,
      for the tile's accessibility label (its title, then the facts, joined by commas: "in Downloads",
      "from Safari"), leaving out what the title says already (that it is a text, a colour), and,
      through `ContentHelp.badged`, a first line of the tooltip ("PDF · 2.4 MB").
  - **Initials:** `Avatar` draws `ContactBadge`'s initials (up to two, from a name or an address's name
    part) on the colour `ContactBadge.colorIndex(for:)` picks with an FNV-1a hash of the address, or of
    the name without one, so a person keeps one colour across launches and Macs. `PhoneBadge` draws the
    region's flag in a circle.
  - **Opening under a row:** text being edited, a stack's files, and an app's window titles (each
    restoring its window) or a window's placements open full width under their row of tiles, and the
    grid's `ScrollViewReader` scrolls just enough to show them.
  - **Loading:** pictures and thumbnails load in a `.task` only while a tile is on screen and the fold
    is open; a thumbnail is made at the card's width and made again when it changes. Held text is
    recognised once per text (`ContentKinds`).
  - **Actions:** `ClipboardTile` and `HeldTile` (`TileActions.swift`) and `WindowGroupTile`
    (`WindowRows.swift`) hold the clicks, drags and menus. A copy's and a held item's menu are
    `ClipboardMenuItems` and `HeldItemMenuItems`. `KindActions` adds each kind's own items, and
    `ContentDrag` hands out the original: files, the image, text, or a vCard. A copy's click copies at
    once and a simultaneous double-click gesture pastes (a multi-file copy's drag source reads the click
    count instead); held text, links and music take a double-click gesture first, so their single click
    waits for it, and files and stacks keep a single click. See "Pasting" below.
  - **Chrome:** `TileChrome` gives every tile its card (`tileFill`, `tileHover` under the pointer or
    with the keyboard's ring), corners, a ring in the card's deep Tuck blue, 1.5 pt while it is open
    and 2.5 pt where the keyboard is, a small press when a click lands, an edge (`tileEdge`) only with
    Increase Contrast, and `FeedbackBadge`: what a click did, a symbol and a word in a small Tuck blue
    capsule over the bottom trailing corner, ringed in the card's own ground, so the face never moves
    to make room for it.
  - **Checks:** debug builds render every face with `TileSamples`, drawn in code into a throwaway
    folder, as `gallery-tiles-<appearance>.png`, at each card size (`gallery-tiles-small-*`,
    `gallery-tiles-large-*`), and again with times on (`gallery-tiles-times-*`). `PanelSnapshots`
    also renders the fold in both depths with several card layouts (`panel-cards-*`), every kind on small
    cards two to a row and large ones five (`panel-kinds-*`), five large cards on a 1024 pt display, the
    strip scrolled to its middle and its end, the full fold scrolled to its last row at three widths
    (`panel-cards-*-full-end`), and the keyboard's ring on the fifth tile, on the last and along the
    strip (`panel-kinds-*-keyboard*`).
- **Lightweight:** `ItemDetails` keeps icons (apps' icons for tiles' lines and chips among them),
  thumbnails, summaries and whether a copied path is there only while the fold is open; it,
  `ContentKinds`' file cache, `TextCounts` and `FileSizes` are emptied as the fold closes
  (`ItemDetails.purge`), and the fold's SwiftUI host is built as it opens and released as it closes.
  No timers or polling. `FileSizes` (in `ItemDetails.swift`) remembers each file's size and each
  folder's item count, failures included: `loadByteCount` reads a size in a detached utility task for
  a tile, `itemCount(inFolder:)` counts a folder (hidden files aside) the same way, and
  `byteCount(of:)` reads at once for a search that names a size before any tile has. A folder has no
  size, and a stack's is its files' together.
- **Search** (the full fold only): `SearchBar` sits under the band. Its field shows only while
  `TuckModel.isSearching`; before a search it holds just the kind chips, when there are two or more.
  - **Opening and closing:** the magnifier, ⌘F and a chip open it, and it takes key focus; ⌘F from the
    shallow fold unfolds first, keeping a lens that holds something (one that holds nothing is let
    go). With nothing in Tuck, ⌘F says so in the footer instead. Esc, the fold folding back, or the
    fold closing ends it.
  - **The query:** each keystroke is parsed into a `SearchQuery`. Kind, day, badge and app words become
    chips that can be taken out; the words left must all appear, ignoring case and accents. A phrase
    that is read is replaced by as many spaces, so the chips keep the order they were typed in.
    `TuckStream.entries(…query:category:size:)` narrows the stream with it.
  - **Badge words** (`SearchBadges.swift`, TuckCore): a file type, a size or a time of day is a
    `BadgeFilter`, a kind (`.type` with a set of extensions, `.size` with a byte range, `.time` with
    ranges of minutes after midnight, two for the night), the phrase typed and the chip's label ("PDF",
    "Over 10 MB", "3 PM", "15:00"). `SearchQuery.badgeWords` holds the type words (such as "pdf",
    "jpeg", "archives", "disk images", "spreadsheets", "presentations", "md"), "large", "big" and
    "huge" (10 MB or more), "small" and "tiny" (under 100 KB) and "morning" (5 to 12), "afternoon"
    (12 to 17), "evening" (17 to 21) and "night" (21 to 5); none is a kind word. Two patterns read
    written sizes ("2 mb" is 2 up to 3 MB, "2.4 mb" 2.4 up to 2.5 MB; over, under, at least, at most and
    their symbols compare; a megabyte is a million bytes) and clock times ("3pm" and "15:00" are the
    hour, "3:41" that minute on either clock; a number alone is not a time). The day phrases gain "this
    morning", "this afternoon", "this evening" and "last night" (21:00 to 05:00). A filter holds when
    the text says its phrase, or for a type ".ext", or when the thing's `SearchFacts` (extensions and
    byte count) or its date fits. Any one of the types and any one of the times must hold, and every
    size. A copy's facts come from `ClipboardEntry.searchFacts` (its files' extensions, "png" for an
    image, and the size recorded when it was copied); a held item's from `HeldItem.fileExtensions` and,
    only while `SearchQuery.asksForSize`, the `TuckStream.ItemSize` closure the model passes in
    (`FileSizes.byteCount(of:)`). A stack is found by its files' facts too, and a window by
    `tuckedAt`, with no type or size.
  - **App words** (`SearchApps.swift`, TuckCore): an app something came from is a `SourceApp`, the
    name it gave and any other name it goes by (its bundle's name when that differs, so "Visual Studio
    Code" finds what Code copied). `ItemDetails.sourceApps` gathers them once, through
    `SourceApp.known`, as a search's first character is typed, from the history and the held items in
    the order first met, Tuck's own copies left out; `TuckModel.searchApps` keeps them until the
    search ends. `SearchQuery.parse(_:apps:)` reads, longest first, "from" and a name, then a whole
    name, before the kind words, so "notes" is the Notes app when Notes is known; then a word only one
    app's names have, three letters or more and not a common word in app names
    (`genericAppWords`), a type, badge or day word ("chrome" for Google Chrome). A chip's own word
    and its singular (`keptKindWords`: code, music, screenshots…) stay kinds unless "from" comes
    first. Each is an `AppFilter`, labelled "From Safari": it holds when the thing's
    `SearchFacts.sourceApp` is one of the app's names, or when its text says the phrase, and any one
    of the apps asked for will do. A copy's app is `sourceAppName`, a held item's its own (a stack's
    files take the stack's), and a window's its app's. `SearchQuery.removing(_:from:apps:)` takes an
    app chip's phrases out. The chip wears the app's icon (`SearchChip`'s `icon`, from
    `ItemDetails.appIcon`), the one picture among the chips, or none without one.
  - **A lens that finds nothing:** when something elsewhere matches, the lens steps aside
    (`TuckStream.lens(_:keptFor:)` over `TuckStream.counts`). Otherwise `NoMatches` says so and where
    the words are found with the kinds or the day left out, with a click that leaves them out.
  - **Chips** come from `SearchChips.chips`: the filters that are on and aren't kinds (a day, say),
    then the kinds the stream holds, those that are on first and then most first, as many as fit one
    line; beside other kinds, a kind that is everything shown says nothing and is left out unless it
    is on. Each counts what the query without its kinds
    finds. Before a search a click calls `beginSearch(filtering:)`, which opens the field with the
    kind's word and a space typed, so the caret sits after it; during one a click adds the kind's word,
    or takes out every word read as that kind (`SearchQuery.removing`). A `SearchChip` is a quiet label,
    not a pill: its name in secondary ink and its count in the faint ink, on no ground until the pointer
    gives it stone; only a chip that is on takes a ground, `accentTint`, with its name, count and the
    cross that takes it out in Tuck blue.
- **Styles:** `PanelButtonStyle` (normal, prominent, destructive and quiet roles, the quiet one, for
  the fold's toolbar, with no ground and secondary ink until pointed at, a selected state, regular
  24 pt or large 30 pt that share a prompt's width, hover, press and disabled; one prominent button at
  most per prompt), `PanelIconButtonStyle` (24 pt symbol buttons: search, fold), `PressableButtonStyle`
  (lenses and placement tiles that press in), `PromptCard` (a question laid out as AirDrop asks one:
  glyph, title, grey line, large buttons; two side by side with Cancel first, three stacked with Cancel
  last, as an alert stacks them), `FeedbackBadge` (the click feedback capsule over a tile's corner)
  and `EmptyCue` (one faint, centred line in place of the list).
- **Drop outlines** around a surface that hangs from the notch never reach the top, where it meets the
  screen's edge. The real surface's rim is `SurfaceView`'s outline without its top, faded out up the
  shoulders, for the invitation and the open fold alike (see "The fold" above); the setup tour's
  pretend notch masks its rim with the same fade. A bubble's floats below the menu bar, so it goes all
  the way round.
- **Menus** give every item an SF Symbol, as macOS draws them. Held items add Quick Look
  (`QuickLookPresenter`, the shared `QLPreviewPanel`) and Share (`ShareLink`).
- **Checks:** debug builds render every fold state (both depths, each lens, search, Arrange windows, the
  window picker and the prompts) and the collapsed surface, the drop target included (near and over
  it, around a notch drawn on top and as a bubble, with each drop label), in Light, Dark and both with
  Increase Contrast, with `Tuck --snapshot-panel <folder>`, from an in-memory library and a
  stand-in window service; the person's own library is never read. The fold draws dark in all of
  them, so the Light and Dark shots match. AppKit hands back the plain appearance for the
  high-contrast names and takes Increase Contrast only from the system's setting, so the Increase
  Contrast shots set `snapshotsIncreaseContrast` (debug only), which `Theme` reads in its place;
  Settings' snapshots don't set it.

### Outline motion

Every change to the surface's outline goes through one spring (`animateShape`), which starts from the
outline on screen. A morph replaced by a newer one hands its completion on: completions run only when
the outline is at rest (`whenSettled`), so the window is never resized mid-animation (resizing lands a
morph at once). The fold's height changes animate from the outline on screen; the window grows first and
shrinks only once the outline has. With Reduce Motion every spring is the critically damped one.

### Tucking animation

`TuckModel` asks the overlay, through `onWindowsTucked`, to play the upward deposit once windows are
parked. With the fold open it first marks them arriving (`arrivingWindowIDs`): a tile holding only
arriving windows is drawn empty, keeping its place, until `arrived` is called for its window. Once
every card is in, `landed` says whether any landed outside a tile or row, and only then does
the model confirm the deposit (`confirmDeposit`; straight away if nothing is set up to fly): a surface
that was swiped away comes back first, the deposit haptic plays, and `plusOne` tells the closed surface
to swell the mark once, or, if it was empty, to drop its card in. A card that lands in a tile or row is
its own confirmation.
`OverlayCoordinator` waits one run-loop turn, so the open fold has laid out the tiles the windows have
just taken, and picks the display the window was on (`depositTarget(for:frame:)`);
`SurfaceView.depositLanding(window:)` gives a `DepositLanding`. With the fold open, the picker closed
and the window's tile in view, that is the tile: tiles and the title rows of an open app report their
frames (`WindowRowFramesKey`; a window in a closed app tile has the tile's). The card lands on the
icon as a dot in Tuck blue as wide as the icon (`WindowsFace.iconSide`, 30 pt, on a tile;
`StreamIcon.size` on a title row), and the frame, its 10 pt corners (`RowChrome.cornerRadius`, as a
tile's) and the blue at a tenth come with it. Otherwise, on a closed surface that shows the mark, it lands in the mark's dip as a dot the
line's width; else in the middle of the surface with no dot.

`DepositAnimator` shows each flight in a borderless, click-through panel on whole points, one level
above Tuck's surface when it lands on a dot or a tile (so the landing is seen, even over the open fold)
and one level below otherwise. The panel holds a card in `Theme.raised` with a hairline edge (corners
up to 12 pt) and a soft shadow, with the app's icon and the window's title in a content sublayer, sized
and placed by `DepositFlight` (at most 240 × 150, centred on the window). One 0.24 s animation group
moves it along a cubic curve that rises from the window, glides across below the menu bar and goes
straight up into the target from beneath it, and shrinks its bounds about their centre to the dot's
diameter (10 pt with no dot), its corners rounding to a capsule a little past halfway. Landing on a
dot, it takes the dot's blue and loses its edge and shadow by 85% of the flight, so it arrives as the
dot; in the mark it then fades into it on the clock over the rest of the flight. Without a dot it fades
as it slips under the surface. The icon and title shrink with it and let go early. Landing in a tile
or row, it doesn't merge: from 85% of the flight, added on top of the flight's last creeping stretch so
it never stops on the icon, its position, size and corners open out to the tile's (0.12 s) while its
blue settles to the tint; it rests 0.02 s while the tile is drawn under it, then clears over 0.1 s. At most six
windows fly, 0.035 s apart. The panel is closed when the animation ends, so nothing runs between tucks,
and Reduce Motion skips the flight.

A window parked off screen waits in place until its card covers it: `fly` calls `covered` 25 ms after
each card's panel is put on screen (windows beyond the six shown flying go with the first card), and the
model then asks `moveOutOfSight` to move those windows, so no frame shows the spot empty. Without an
animator, under Reduce Motion, or with no card at all, they go at once; any still waiting when the
flights land go then. Restoring one runs the flight backwards (`flyOut`): the card leaves the same mark
or tile as a blue dot, grows to the card over the window's restored frame, and only as it lands does the
model call `restore`, which sets the window straight back under it; the card then fades over 0.1 s. A
minimised (older) row restores without a flight, as before. How the window itself goes away is under
"Windows".

### Event monitoring

| Monitor | Scope | When installed |
| --- | --- | --- |
| Drag approach | Global left mouse down and up; global left mouse dragged only from a press until the drag ends or is known not to carry content (0.8 s at most) | While Settings → Held → Widen when a drag comes near is on (the default); work happens only during droppable drags |
| Clipboard check | A repeating 0.5 s timer (0.15 s tolerance) reading the general pasteboard's change count | Only while clipboard history is on; the one repeating timer at rest |
| Outside click | Global left/right mouse down | Only while the fold is open |
| Modifier-drag | Session event tap, mouse buttons only | Only while the setting is on and Accessibility is allowed |
| Mouse wheel | Session event tap, scroll-wheel events only | Only while smooth scrolling or wheel reversal is on |
| Accessibility changes | `com.apple.accessibility.api` distributed notification | Always; fires only when permissions change |
| Window in front | Workspace activate and hide notifications; an AX observer on the front app (focus, minimise) and its focused window (minimise, close, title) | Only while the fold is open (and, without close and title, while a window is parked off screen) |
| Listed windows | Workspace terminate notification; an AX observer on each listed app, for its listed windows closing (a dozen windows at most) | Only while the window picker is open |
| Rest wake triggers | Workspace sleep, power-off and app-activation notifications | Only while an app is resting |
| Swipes | Local scroll-wheel monitor (Tuck's own windows only) | Always; sees events before the fold's list and the shallow fold's strip, and over the strip holds a gesture's first events until it shows its axis |
| Global shortcuts | System hot keys (`RegisterEventHotKey`), the chosen combinations only | Only while keyboard shortcuts are on |
| Recording a shortcut | Local key-down monitor (Tuck's Settings window only) | Only while a shortcut field is recording |
| Setup swipes | Local scroll-wheel monitor (the setup window only, inside its practice area) | Only while the tour or gesture step is showing |
| Click, hover, Escape | Delivered to Tuck's own panel | Built into the view/panel, no monitor |

The clipboard check is the one repeating timer Tuck keeps at rest (smooth scrolling's display link runs
only while a scroll is gliding), and it can't be replaced by an event: macOS
posts nothing when the pasteboard changes, and watching for ⌘C would miss copies made from menus or by
other means. Reading `changeCount` is cheap and never asks another app for its data; the contents are
read only when the count has changed. Twice a second, with leeway for the system to fold the check into
other wakeups, records a copy well before anyone can open the fold to look for it; two copies inside
half a second keep only the later one. Turning clipboard history off invalidates the timer.

`DragApproachWatcher` classifies each mouse drag from the drag pasteboard's change count and type list
only (`DragClassification`). Contents are never read before a drop. Sources write the drag pasteboard a
few events after the mouse starts moving, so a drag stays pending (re-checked at most every 30 ms)
until it does. A drag that hasn't written it within 0.8 s is a window move or selection and is ignored.
For each drag event of a supported drag it then measures the pointer against the display under it
(`DropApproach` in TuckCore):

- **Invitation.** A top-centre range around the collapsed surface (260 pt to each side, 220 pt down)
  invites the drop. Inside it the level runs from 0 at the edge to 7 near the surface, and 8 (accepted)
  over the drop target, which is the surface as it pops out. `SurfaceView` pops the shape out by a
  band under the notch (or widens the bubble) saying what the drag carries ("Drop file into Tuck",
  "Drop link into Tuck" or "Drop text into Tuck", from `DropKind`) beside its glyph, which move on the
  outline's own spring so they ride the band out, bounce with it and go back in with it; then grows it
  slightly and strengthens a rim in Tuck blue, which firms up over the target. Leaving the range needs
  the pointer 36 pt past it. Levels are discrete, so a whole drag costs at most a handful of short
  layer animations.
- **Scope.** Only presses and releases are watched all the time. The drag-event monitor is added at
  each press and removed at its release, or as soon as the drag is classified as not carrying content
  (0.8 s at most after it starts moving), so moving windows or selecting text sends Tuck no stream of
  drag events past that point.
- **Ending.** Mouse-up clears everything. While a supported drag is in flight a mouse-moved monitor
  also exists, since the first plain move means the drag ended even if its mouse-up went elsewhere.
- **Taking the drop.** The surface accepts the drag only over the drop target. Its transparent window
  margin refuses drags, so a release beside the notch is never captured.
- **Nothing opens.** Entering the approach zone arms a single dwell work item (0.18 s); if the pointer
  is still there when it fires, the model marks the drag active (`dragEntered`, which only records
  the drag's kind and that it is active), and the rim shows on an open fold. Disarming needs the pointer to
  leave a zone 36 pt larger, so jitter at the edge never flickers.

### Keyboard shortcuts

`ShortcutSet` (TuckCore) maps each `ShortcutAction` to at most one `KeyShortcut` (hardware key code,
modifiers and a display label) and refuses a shortcut with fewer than two of ⌃ ⌥ ⌘ or one another
action already has. It is stored as JSON in user defaults, listing only the shortcuts that are set, so a
cleared one stays cleared; anything unreadable falls back to the defaults (⌃⌥⌘T, ⌃⌥⌘R, ⌃⌥⌘O).
`HotKeyCenter` registers the set with `RegisterEventHotKey` and one `kEventHotKeyPressed` handler on the
application target, and reports any combination the system refuses. While shortcuts are off it holds
nothing. While a Settings field is recording, the hot keys are unregistered, so pressing one records it
instead of running it. `AppDelegate` maps actions to `TuckModel.tuckFrontWindow()`,
`TuckModel.restoreLastTuckedWindow()` (the most recently tucked window of all, one window) and
`OverlayCoordinator.togglePanelFromKeyboard()` (the display under the pointer). Refused actions bump
`TuckModel.refusals`; the collapsed `SurfaceView` answers with a 0.36 s additive shake of its mark and
its dot or arrow, skipped while tucked away and under Reduce Motion; with the fold open its status line says why.

### Pasting

A double-click on a copy, or on held text, a link or a music link, pastes it into the app in front.
`TuckModel.paste(entry:)` and `paste(item:)` note the frontmost app as the click lands, then copy: a
copy as it was copied (`copy(entry:)`, which refuses files that have all gone), held text as itself and
a link as its address. Then `paste(into:feedbackID:)`:

- With Tuck itself in front, or no app, it stays copied and the status line says "Copied · paste with
  ⌘V". Without Accessibility it says to allow Tuck in the Accessibility pane (`AX.paneName`).
- Otherwise the fold closes (`collapse(via: .click)`), handing the keyboard back, and 0.15 s later, if
  the same app is still in front, `KeystrokePasting.paste()` types one ⌘V. If it can't, the status line
  says to paste with ⌘V.

`SystemPaster` refuses while one of Tuck's own text fields has the keyboard, finds the key that types
"v" with ⌘ held by running `UCKeyTranslate` over the current layout, then the ASCII-capable layout
macOS falls back to for shortcuts, then `kVK_ANSI_V`, looked up on every paste since the layout can
change, and posts the key down and up at `.cgSessionEventTap`. Nothing listens for keys and nothing is
installed between pastes. A click on a copy moves it to the top of the history only after
`NSEvent.doubleClickInterval` (`moveToTop`), so its tile is still under the second click; another copy
in the meantime moves the waiting one first.

### Clearing each section

`TuckModel.requestClear(_:)` takes a `StreamLens`: Windows asks `restoreAllPrompt` (put back every
tucked window, in turn, none closed; any that can't come back stay), Files asks `ClearPlan`'s question,
and Copied asks `clearCopiedPrompt` (`clearClipboard()` on confirm). Each sets its own question and
clears the other two, so one shows at a time. `canClear(_:)` says whether a section has anything: a
window to put back (and no put-back running), a held item, or a copy while history is on. The wording
is `SectionClearing` (TuckCore), so tests can check it. Escape cancels each question, before anything
else it would close.

### Windows

`AccessibilityParkingService` implements `WindowParkingService` in-process:

- **Listing** (`WindowCandidateSource`): the window server's on-screen list (layer-0 windows, bounds
  and owner pid only) gives what is visible and the front-to-back order. Accessibility is then asked
  for the windows of just those apps (never Tuck itself, never a resting app). Each window becomes a
  `WindowCandidate` of plain facts, and `CandidatePolicy` in TuckCore decides what is offered.
  Elements from the latest listing are kept, so `park(_ candidates:)` puts away exactly the windows
  chosen, each re-checked first. While the picker is open it drops the rows of windows that have
  closed, lost their app or been tucked since it listed them (`stillListed`), with their ticks, so it
  offers only what it would tuck. It checks again when `ListedWindowWatcher` reports a listed window
  closing (`kAXUIElementDestroyedNotification` on each, through one observer per listed app) or a
  listed app quitting (the workspace's terminate notification), on each change the front-window
  watcher reports (below), and after a tuck by the shortcut or menu. The watcher runs only while the
  picker is open. A listed window put away some other way (minimised from its own menu, say) stays
  until the next of these; choosing it before then finds it already put away and leaves it be.

- **Tuck** captures each window's frame and display, then parks it off screen
  (`ParkingMethod.offScreen`): `park` only records it, and `moveOutOfSight`, called once its card covers
  it, moves it to the origin `OffScreenParking.origin` picks, one point in from the bottom-right corner
  of its display (else the bottom-left, else another display's, wherever no display lies beyond). AppKit
  keeps a window's title bar within the screen, so a sliver one point wide and a title bar tall stays in
  view; a window with no overlap at all is pulled back by macOS, and one pushed beyond a side is held
  with 40 pt showing. The move is a plain AX position change (with `AXEnhancedUserInterface` off), so
  nothing animates and the window stays open, unminimised, on its Space. The frame is read back: only a
  window `OffScreenParking.isOutOfSight` (showing no more than a strip 2 pt across and 120 pt long on
  any display) counts, and it is checked once more 0.3 s later in case its app pulled it back. From then
  on it is watched (below).
- **Kept out of sight:** a `ParkedWindowWatcher` holds one AX observer per app with parked windows,
  registered for `kAXWindowMovedNotification` and `kAXWindowResizedNotification` on exactly those
  windows, and one on the Dock for Mission Control, App Exposé and Show Desktop starting and ending
  (`AXExposeShowAllWindows`, `AXExposeShowFrontWindows`, `AXExposeShowDesktop`, `AXExposeExit`:
  undocumented names, the ones yabai listens for). Any move or resize, Tuck's own included, queues a
  check 0.2 s after the last one, so a resize and move, or an animated frame, is looked at once it has
  settled. `OffScreenParking.drift` decides: a window still parked is left, and so is one the person
  has in front (its app frontmost and it the focused window, asked of the app), which the focus watcher
  below brings back or lets go. Any other window is moved out of sight again, unless it was already parked
  again twice in the last 2 s; then its app is taken to be holding it on screen, and it is minimised
  (the fallback below). A check queued during a display change is left to the display checks. Around
  Mission Control none of this judges a window (below). Nothing is watched while no window is parked,
  and nothing runs on a timer.
- **Mission Control:** it shows every window on the Space, parked ones too. As it ends, it (or the app
  as it lets go: Obsidian and other Electron apps may move or resize their window then) can leave a
  parked window in view, or the keyboard in one. Neither is the person bringing that window back.
  `MissionControlVisit` (TuckCore) notes what was in front as it began: the app in front and its
  focused window, read past the Dock, which may come forward for it. While it shows, nothing is judged.
  Its end is the Dock's `AXExposeExit`, or, should the Dock not post it (it may not, for a swipe), a
  parked window moving or another app coming forward meanwhile; the Dock's exit after such an assumed
  end still belongs to the same visit. For 1.5 s after the end, moves of parked windows and focus
  changes only put off a single look at everything it left, 0.4 s after the exit and at least 0.2 s
  after the latest of them (one `DispatchWorkItem` at a time). Then `missionControlSettled` reads the
  front once and `OffScreenParking.driftAfterMissionControl` decides each parked window. The person
  chose a window there only if it is now the focused window of the app in front and wasn't as Mission
  Control began; that one comes back to its original frame (`onParkedWindowFocused`), as from its app's
  Dock icon. Any other back in view is parked again, wherever the keyboard is, and that isn't counted
  as a pull-back. A window that can't be moved, or doesn't answer, is tried once more 0.4 s later and
  only falls back if it still can't be moved. Last, a parked window left with the keyboard hands it on
  (below). So leaving with the front where it was (the window in front clicked, Esc, F3 or the swipe
  again) untucks nothing.
- **Fallback:** a window that can't wait off screen (full screen, position not settable, no free
  corner) or didn't stay there is minimised one app at a time (`ParkingPolicy`): the app is hidden for
  a moment, the windows are minimised while hidden (confirmed minimised), and it is shown again, and
  made frontmost again once its windows are back on screen if it was in front (a request made sooner is
  dropped). An app that can't be hidden (not a regular app, or already hidden) is minimised in view,
  with the Dock animation. The waits are bounded (0.3 s) and take a few milliseconds in practice; hiding
  is judged by the app's own hidden state, since the workspace request can report failure and still
  hide it. A window that can't be minimised either is put back and its row removed
  (`onParkingChanged`). The method is stored on the row (nil in older libraries means minimised;
  `hiddenWithApp` rows from earlier versions still restore).
- **The keyboard:** if the focused window has just gone, `handOffKeyboard` gives the keyboard to the
  window `OffScreenParking.successor` picks from the window server's front-to-back list: the app's next
  window in view, else the frontmost other window in view, ignoring any still listed at the parked
  window's old frame (the list lags the move); with nothing in view, Finder. While any window is off
  screen, a `FrontWindowWatcher`, the `ParkedWindowWatcher` above and a screen-parameters observer run
  (and stop once none is; the `FrontWindowWatcher` also runs while the fold is open, below). When the
  keyboard lands on a parked window: if the person switched to its app, `onParkedWindowFocused` restores
  it to its original frame, with no flight; if the app passed it on by itself, the keyboard goes to the
  app's next window in view, or the frontmost one; if it is back in view and Tuck didn't put it there,
  its row goes (`broughtBack`). Here, focus changes within 0.5 s of Tuck's own moves are taken as
  Tuck's; the Tuck button decides by where a change lands (below). The Dock coming forward (for Mission
  Control or Launchpad) isn't a switch: the app in front before it still counts. `AX.focus` raises the
  window it hands the keyboard to and makes it main, then, if its app's focused window is still another
  (the one just parked, in apps that won't move focus by themselves), sets it as focused before bringing
  the app forward.
- **Diagnostics:** each way a window stops being tucked without the person restoring it from Tuck is
  logged with `os.Logger` (category `parking`), with the reason, the app's bundle ID and how lately
  Mission Control ended: brought back, refused, closed while tucked, and restored because the person
  went to its app or chose it in Mission Control. The log subsystem follows Tuck's bundle ID
  (`Bundle.main.bundleIdentifier`, set in `Support/release.env`; `app.tuck.prototype` until the final
  one is chosen, and "Tuck" under `swift run`, which has no bundle). Those are `.info`; Mission Control
  starting and ending, re-parks and minimising instead are `.debug`. Neither level is kept on disk by
  default, so stream it while reproducing, with the bundle ID in use:
  `log stream --level debug --predicate 'subsystem == "app.tuck.prototype" AND category == "parking"'`.
- **Displays changing:** on a screen-parameters change, parked windows are checked at once and once
  more a second later, and any in view or with nothing left on any display is moved again, or minimised.
- **Quit and relaunch:** `applicationWillTerminate` minimises off-screen rows through `keepTucked` (the
  hide-and-minimise above) and records them as minimised; the model holds sudden termination off while
  any row is off screen. After a crash they are still off screen: at launch `adopt` takes them up again,
  found by `tuckedWindow(like:)`, which matches off-screen rows by title among the app's windows out of
  sight (never one in view), else among its minimised windows, else by size when exactly one window out
  of sight matches. Minimised rows are matched by title among minimised windows, hidden ones among
  windows not minimised. Elements found are kept for the run.
- **Front window:** `frontWindow()` reads the app in front once and asks that app for its focused window
  (`AX.focusedWindow(of:)`), so the app it names and the window it holds can't come from two apps when
  focus moves between the reads. It returns nothing when the app in front is hidden or resting, has no
  window, or its focused window is already tucked (minimised, hidden with its app, parked off screen or
  waiting there for its card, out of sight, or minimised a moment ago), so a window parked off screen
  that is still its app's focused window is never offered. Otherwise the service holds the window's
  element (`frontTarget`) and returns a `WindowToken` made from its `pid:CFHash` key; the element never
  leaves the service. The fold's Tuck button (`tuckShownWindow`) and Arrange windows row
  (`placeShownWindow`) hand the token back: `check` answers with a `ShownWindowCheck` (TuckCore): stale
  if it isn't the window last read, closed if its app quit or the window is gone, busy if the app didn't
  answer, put away if it is tucked or its app resting, else ready. Only a ready window is acted on, by
  `park(_ window:)` or `place`, on that element and checked again; otherwise no window is touched, the
  window in front is read again and a status line says why. A window that was ready but is gone, put
  away or unanswering by the time `park` or `place` reaches it is checked once more for why
  (`ShownWindowCheck.missed`) and handled the same way. Tuck All, in the Tuck button's context menu,
  acts on the app the button names (by bundle ID, by name without one). The shortcut and the menu item
  name no window, and park the window focused at that moment (`parkFrontWindow`). While the fold is open
  the model follows the window in front through `watchFrontWindow`: the service's `FrontWindowWatcher`
  runs (it may already, for parked windows) with `watchesEdits` on, so the focused window closing
  (`kAXUIElementDestroyedNotification`) or being renamed (`kAXTitleChangedNotification`, which includes
  a browser's tab switch) is reported too, 0.2 s after it goes quiet and on a beat of its own, so a
  title that keeps changing never holds back a switch. A close can be told before the app has moved
  focus on, so once it settles the watcher reads the focused window again and watches that one. Each
  report carries the window now in front, read as `frontWindow()` reads it, and whether the person
  brought it there. `OwnFrontChanges` (TuckCore) decides that by where the front lands, not only when:
  before each move that may bring something forward the service records what, the window `giveKeyboard`
  focuses (or only its app, or Finder for the desktop) or the app `minimise` keeps in front. A change
  landing there within 0.5 s is Tuck's; one that leaves the front where it was (a rename) brings nothing
  forward; any other is the person's, however soon after Tuck's move it comes. Closing the fold stops
  it; nothing is read while it is closed, and nothing runs on a timer. `FrontWindowBarState` (TuckCore)
  keeps what the Tuck button names. Once its window is tucked by any path, or another of its app's from
  the picker or Tuck All (`ParkingPolicy.frontWindow(_:afterTucking:)`), it goes blank. It stays blank
  through Tuck's own changes and any that leave no window to name, until the person brings a window
  forward, a tucked window is restored, or a window that couldn't be tucked or was brought back is in
  view again. Within that half second, the person switching to the very window Tuck gave the keyboard to
  (or, after a minimise, to any window of the app it kept in front) looks the same as Tuck's change and
  keeps the blank. Naming another window, not a renamed one, closes Arrange's chooser.
  `AX.focusedWindow`'s fallback, `WindowCandidateSource` and Rest's visible-window count all skip
  windows out of sight, which the window server's on-screen list would still include.
- **Restore** of an off-screen window: the app is shown if the person hid it, the window is focused
  while still out of sight (so it arrives in front, rather than behind and then jumping forward), and
  its frame is set and classified as below, with nothing to wait for. If it stays out of sight, the
  restore fails and it stays parked. Restore of a hidden window shows its app again. Showing an app shows every window it hid, so the
  model first asks `keepTucked` to minimise the other rows hidden with it (while the app is still
  hidden) and records them as minimised; only the chosen window comes back. A hidden app counts as
  having no visible windows for Rest.
- **Restore and place** compute the target with `PlacementGeometry`, write size → position → size with
  `AXEnhancedUserInterface` off, read the frame back and classify it (`exact`, `constrained`,
  `rejected`). Constrained windows are re-anchored to the placement's edges inside the usable area. A
  restore applies the frame while minimised, then settles it once more after the window is back.
  A restore counts only once the window reads back as no longer minimised and its app as not hidden.
  It is checked every 50 ms for about a second without blocking, since un-minimising animates, and the
  result is reported through a completion. A window is "gone" only when its app has quit or the
  system reports the element invalid (`WindowLookup`). A timeout or an unmatched title is a failure,
  and the row stays (`WindowActionResult.removesParkedRow`).
- **Original** for the front window returns to the frame recorded before Tuck first moved it
  (`PlacementHistory`, bounded).
- Every AX call carries a 0.25 s messaging timeout, set globally at launch (on the system-wide
  element), so a hung app cannot stall Tuck, the notch or the mouse.
- A window parked off screen (or waiting for its card), out of sight, tucked in the last 1.5 s, still
  minimised, or whose app is hidden, is never parked again (a
  second click or shortcut returns `.alreadyTucked`, which says nothing); after that only its state
  counts, so a window brought back from the Dock can be tucked again. Restoring a window clears it from
  that 1.5 s guard, so it can be tucked again at once. The front-window fallback never picks a
  minimised window.

`WindowDragController` installs a session event tap for mouse buttons only while modifier-drag is on.
A modifier-click on a standard window is consumed; frames come from `WindowDragGesture` and are sent at
most 60 times a second (`FrameThrottle`), with the final frame always delivered on release.

### Mouse wheel

`ScrollController` installs a session event tap for scroll-wheel events only while smooth scrolling or
wheel reversal is on. For each event:

1. Events Tuck posted itself (marked in the source user-data field) and events with a modifier held
   pass through.
2. `ScrollInput` classifies the device from the event's own fields: gesture phases mean a trackpad or
   Magic Mouse (always passed through untouched); otherwise the continuous flag tells a high-resolution
   wheel from a notched one.
3. Reversal flips every delta representation (lines, fixed-point, pixels) of wheel events.
4. With smoothing on, a notched tick is consumed and its pixel delta (plus a small lift so a single slow
   notch moves a useful distance; the system's acceleration is kept) is added to `ScrollSmoother`.

A `CADisplayLink` from the screen under the pointer runs only while a glide is moving. Each frame moves
an exponential fraction of the remaining distance (time constant from Snappy/Balanced/Gliding, frame
time capped at 1/30 s), carries fractional pixels so the total is exact, and posts one pixel-unit event
at the point where the glide started. Reversing direction drops what was left on that axis. When the
glide settles the link is invalidated.

### Files

- `DropReader` prefers file references, then promised files (unless the drag carries a real web link),
  then links and text, then raw images. Three or more files become one `.stack` row (`DropIntake`).
- Files are stored with a bookmark (`FileReferences`). The library is reconciled on load and each time
  the fold opens: moved files are followed, deleted ones removed, stacks that lose members collapse.
- Promised files and images land in `ReceivedFileStore` (one folder per drop). Only files there are ever
  deleted, when their row is removed; unreferenced folders are swept at launch.
- `ZipArchiver` runs `/usr/bin/ditto` on a background queue; several files are cloned into a temporary
  folder first (APFS clones cost no space). `ArchiveNaming` follows the Finder's naming.

### Setup

`SetupWindowController` hosts `SetupView` in an 840 × 600 pt `TuckWindow`, created when shown and
released on close. `AppDelegate` shows it at launch until `setup.completed` is set (written on finish,
not on close), and as a tutorial from Settings › General (`SetupModel.steps` is then only the tour,
choose and gesture steps). Choices bind straight to `SettingsStore`. The step and the pretend screen's
`TourDesk` live in `SetupModel`, so Back and Continue keep them, and the tour and the gesture step show
the same screen.

- **Welcome:** the first step is Tuck's stacked lockup alone, centred a touch above the middle, with no
  text. The line is `LogoLine` (the shape the pretend notch's mark uses too), trimmed out from the
  middle of its path, the floor of the dip, to its tails in 0.9 s; 0.42 s in it gives the notch's
  greeting, the same keyframes as `greetMark`, and the wordmark (`TuckLogo.wordmarkPath`, Ink, or
  Paper in Dark) fades and rises 10 pt in after 0.3 s. Pointing at it greets again, once per arrival.
  Under Reduce Motion it is drawn whole and never greets. VoiceOver reads it as "Welcome to Tuck".
- **The pretend screen** (`PretendScreen`) is SwiftUI on a fixed 760 × 280 pt screen inside an 8 pt
  bezel the notch hangs from; its geometry is `TourLayout` (TuckCore, y up). It changes `setup.desk`
  through the model rather than a `Binding`: changes made from a delayed callback through a binding
  redrew the screen but not the step's text and chips. The notch and the desktop are buttons, so a first
  click counts even before the window is key.
- **Tuck and restore:** the Notes window itself follows `DepositFlight`'s path
  (`TourLayout.flight(open:row:)`), shrinking fast at first and letting go of its contents, to where it
  lands: the top row's icon in the open fold, or the mark's line on the closed notch, arriving that size.
  It comes back out along the same path on restore. The row and the mark's card wait for it to land.
- **Drops:** dragging the PDF lifts a see-through copy from where it was grabbed; the original dims and
  stays, since Tuck keeps a reference. The drag calls `DropApproach.invitation` and `isArmed` with
  `TourLayout.zone`, built by the same `DropApproach.approachZone(in:)` the real displays use; the dwell is
  `DropApproach.dwell`. Over a target the cursor shows the copy badge and the copy draws itself in; let
  go there, it is drawn into the mark, which swells once or, empty, takes its card; otherwise it slides
  back. A held PDF
  drags out into the note.
- Springs are `SurfaceMotion`'s stiffness and damping through `Animation.surface(_:)`. The Tuck button
  and rows use small copies of the panel's styles (`MiniButtonStyle`, `MiniIconButtonStyle`,
  `MiniRowButtonStyle`, `MiniRowChrome`). The pretend fold is black and drawn dark, as the real one is,
  and still lists the stream as rows.
- **Swipes** in the tour and the gesture step come from `SwipeArea`: an `NSView` that takes no clicks
  and keeps a local scroll-wheel monitor while it is in a window. It reads deltas exactly as
  `SurfaceView` does (precise deltas only, physical direction, began/ended phases, the glide after its
  own swipe swallowed) and feeds `SwipeGestureTracker`. An event that arrives without a window (posted
  to the app) is placed by its screen location. As on the real notch, a swipe plays no haptic; a drag
  crossing into the drop target does, through `TuckModel.performHaptic`, so the setting and the pacing
  apply. The gesture step teaches open, unfold and close (`TourDesk.Gesture`), so there
  `PretendScreen.closedNotchOnlyOpens` drops an upward swipe on the closed notch, and its upward pull,
  before it reaches the desk; on the tour it tucks Tuck away as on the real notch, ticking nothing.
- **Pointing and clicks:** pointing at the pretend notch opens nothing, as on the real one
  (`MiniNotch`). One that holds something shows the faint mark with its card and a grey dot; pointed
  at, the mark greets the pointer (the same keyframes as `greetMark`) and lights in Tuck blue, and the
  dot gives way to the Tuck button's arrow. An empty one shows "Drop into Tuck". A click anywhere on the
  closed notch, the arrow included, opens it, and one on the desktop closes it. The lenses
  (`TourDesk.toggleLens`) narrow the rows as the real ones do; Copied appears only while clipboard
  history is on, as in Tuck.
- **Permission:** the step reads `TuckModel.accessibilityTrusted`, which the existing distributed
  notification updates, and re-reads `AX.isTrusted` when the step appears and when the window becomes
  key again. Nothing polls. The button shows the system prompt once per launch (`AX.hasPrompted`), then
  opens the Accessibility list directly.
- **File permissions:** `FileAccess` offers two routes. Full Disk Access must be enabled manually in
  System Settings (macOS does not let apps request it); returning to setup rechecks it by opening the
  protected TCC database read-only and closing it immediately. Or `FileAccess.request` reads each
  present Desktop, Documents, Downloads and iCloud Drive directory in sequence to trigger macOS's
  folder prompts. Those permissions do not cover arbitrary folders or external/network volumes, so
  macOS can still ask when those are first used. The folder probes run off the main thread because the
  system prompt waits for an answer.
- **Prompts held back:** while setup is open, `updateInputTaps` doesn't show the Accessibility prompt
  for modifier-drag or the mouse wheel, since the permission step comes next; closing setup runs it
  again.

### Rest (experimental)

`RestSafetyPolicy` (allow-list, named risky categories, live checks) and `RestController` (pause and
wake, each checked for process identity and effect) are in TuckCore. `ProcessRestService` and
`POSIXProcessControl` in the app supply live facts (frontmost app, visible windows via Accessibility,
Core Audio's per-process objects, CPU time via `proc_pid_rusage`) and the two signals. Rest is available
only while the experimental setting (`RestSwitch`, off by default) is on. Pausing needs the setting;
waking never does. Rested apps are woken before quit, sleep and power-off, at launch, when the setting
is turned off, and when the person switches to one.

Tuck's Info.plist allows sudden termination, which skips `applicationWillTerminate`. So Tuck holds it
off while any app is resting (the quit must wake it), while a library save is pending (the change
must reach disk), and while any window is parked off screen (the quit must minimise it).

### What builds with a trial left behind

Tuck once had a trial and licence keys; it has neither now, and nothing is ever locked. Builds from
then kept the days the trial had counted in UserDefaults (`TrialRecord`) and in the login Keychain (a
generic password item, service the bundle ID, account `trial`), and a licence key in UserDefaults
(`LicenseKey`). `TrialLeftovers.remove()` deletes exactly those three, once per launch, off the main
thread and without a word; once they are gone it finds nothing to do. A Keychain item made by a
different build is refused the delete without anyone being asked (`errSecInvalidOwnerEdit`), so it
stays and is tried again at the next launch. Uninstall's removing the settings removes the first two
as well.

### Accessibility withdrawn

The accessibility observer (a distributed notification, no polling) calls
`TuckModel.accessibilityChanged`. Turned off while windows are tucked, the mark and dot shake and the
status line asks for it again; the fold then shows "N tucked windows can't come back" with Open
Settings… at its foot, until it is allowed. Windows tucked by minimising wait in the Dock
meanwhile; ones parked off screen stay there, since only Accessibility can move another app's windows.
The card says that quitting leaves those out of sight, and Quit from the menu-bar menu asks first
while any are (Open System Settings…, Quit Anyway, Cancel). Logout and shutdown aren't held up: only the
menu item asks.

### Uninstall

Settings › About › Uninstall Tuck… asks first, saying how many files Tuck saved from drops
(`ReceivedFileStore.fileCount`), since they may be the only copies, with Show Files to open `Received/`.
Then `AppDelegate.uninstall` wakes every rested app and
brings back every tucked window, in turn. Rested apps are woken first, since a paused app can't move
its windows. If any window stays tucked or any app stays paused, it stops with nothing deleted and
says why. Otherwise it stops everything Tuck runs (capture, taps, hot keys, the menu-bar item) and
closes both persistence stores (`close()`, after which no save is written), so nothing recreates what
is removed. `Uninstaller` then turns off Open at Login, deletes what Tuck keeps in its support folder
and the preferences domain, runs `tccutil reset All <bundle ID>` (checking its exit status), and moves the app to the
Trash, unless it runs from a disk image or a translocated copy. Anything it couldn't do is listed as a
step to finish by hand, and Tuck quits. `tccutil` finds an app through Launch Services, so it resets an
app in Applications but not one in a temporary folder.

`SupportFolder` (TuckCore) names what Tuck keeps there: `library.json`, `clipboard-history.json`, the
unreadable copies the stores set aside, the sessions library kept when it moved to the one stream
(`library-sessions-backup-<stamp>.json`), and `Received/`, whose drop folders (named by UUID) are
deleted one by one. Anything else in the folder stays, and the folder with it, listed as a step to check
by hand. So a debug build pointed at some other folder with `-TuckSupportDirectory` can't delete it.

### Move to Applications

At launch, before anything else, `MoveToApplications` looks at where the bundle is. On a read-only
volume under `/Volumes` (its disk image) or under App Translocation, it offers once to move. A Tuck
already in Applications counts only with the same, non-nil bundle ID; then the offer becomes Replace,
naming both versions (and both builds when the versions match) and saying when the one there is newer.
Another app of the same name is never replaced. The copy is made in /Applications under a hidden name
without `.app` (so Launch Services never sees a half-made app), loses its quarantine attribute so it
isn't translocated again, and only then does the old copy go to the Trash and the new one take its
name. A failed copy is removed and leaves Applications as it was; a failed rename puts the old copy
back. Tuck reopens from there once this copy has quit. A declined offer is remembered in UserDefaults
and not repeated.

### Line Apps

Line Apps (its own repository, `line-apps`) is a menu-bar app in the bundle that shows a short line;
a click collapses the family's menu-bar icons into it and the line bends into the curl. It says so
with a distributed notification, `com.millerroberts.lineapps.fold` or `.unfold`, carrying the line's
mid x. `LineAppsFold` is the same file in Tuck, Pulse, Hum and Glow; the copy in line-apps
(`Shared/LineAppsFold.swift`) is the one to change first.

- **Hiding:** the status item's `isVisible`. Each icon waits `min(|its mid x − the line's| / 900, 0.24)`
  seconds, the nearer the sooner, then fades its button over 0.16 s before it goes; coming back, it
  fades in. Reduce Motion skips both.
- **Places:** a hidden status item loses its place, and macOS puts it back at the far left. So the
  fold notes the place as the item goes, in the menu bar's own terms (`NSStatusItem Preferred
  Position <autosave name>`: points from the screen's right edge to the item's left edge), and writes it
  back just before `isVisible` turns true, which puts it where it was. An item collapsed as Tuck opens
  isn't laid out yet, so it keeps the place macOS opened it at. Quitting while collapsed writes the place
  back too, so Tuck reopens there.
- **Only while Line Apps runs:** Tuck reads the collapsed state (`folded` in Line Apps' defaults) at
  launch only if Line Apps is running, and while collapsed it watches for Line Apps terminating, so
  no item is left out of reach. A `NSStatusItem Visible` of false left by a quit that never said so is
  cleared at launch.
- **Tuck only:** the menu-bar item goes; the notch surface and the bubble stay, being Tuck's place
  rather than one icon among the others. With "Show in menu bar" off there is nothing to collapse.
- **Cost:** three notification observers, and a fourth (workspace terminations) only while collapsed.
  Nothing runs between changes.

## Data model

- `TuckLibrary` is one stream: tucked windows and held items, each newest first, and the Rest state
  of apps. There are no sessions. `totalItemCount` counts windows and held rows, a stack as one. Tuck
  keeps at most 200 held rows (`heldItemLimit`); a drop onto a full Tuck takes what fits
  (`remainingCapacity`) and the status line says Tuck is full. Windows have no limit.
- `FileLibraryPersistence` saves it as format 2. A format 1 library, saved with sessions, is merged as
  it loads (`LegacySessions`): every window and every item from every session, archived ones and Loose
  included, newest first, with session names, colours and intentions dropped. The file is first copied
  byte for byte to `library-sessions-backup-<stamp>.json` (`backUpSessions`; a name already taken gets
  -2, -3 and so on), the samples earlier versions started with are taken out (`EarlierSamples`), and
  the stream is saved over it, so the migration runs once. If the copy can't be written, the store
  takes the merged library but writes nothing that run (as after `close()`), so the next launch
  migrates again from the untouched file. A file from a newer Tuck, or one that can't
  be read, is never overwritten: it is set aside as `library-unreadable-<stamp>.json`, and any apps it
  records as resting can still be woken.
- `HeldItem` keeps files as references to their original location and music as openable links.
- `ParkedWindow` stores app identity, title, original frame, display, tuck time and how it was put
  away (`method`: off screen, minimised, or hidden with its app; nil, in older libraries, means
  minimised).

## Services

| Protocol | App | Stand-in in TuckCore |
| --- | --- | --- |
| `WindowParkingService` | `AccessibilityParkingService` | `MockWindowParkingService` (used in tests) |
| `RestService` | `ProcessRestService` (experimental, off by default) | `DisabledRestService`: never signals |
| `HeldItemOpening` | `WorkspaceItemOpener` | `SimulatedItemOpener` |
| `PasteboardWriting` | `SystemPasteboard` | none |
| `KeystrokePasting` (TuckApp) | `SystemPaster`: one ⌘V through a session event tap | `NoPaster` (TuckApp): never pastes |
| `HapticFeedbackProviding` | `SystemHaptics` | `RecordingHaptics` |
| `LibraryPersistence` | `FileLibraryPersistence`: coalesced, atomic JSON in Application Support | `InMemoryLibraryPersistence` |

Clipboard history holds every kind of copy.

- **Capture.** `ClipboardCaptureService` reads the pasteboard on its 0.5 s change-count check, then
  hands the reading to a utility queue. There it becomes a `ClipboardCapture`:
  - its text;
  - a `ClipPayload`, holding file URLs, or an image or RTF written to `ClipboardAssetStore`
    (`Application Support/Tuck/Clipboard`, UUID-named files), plus a `key` that tells re-copies apart;
  - a `ContentRecognition` from `ContentClassifier`.
- **Learning later.** Once it is recorded, `ClipboardEnricher` may learn more, once:
  - Vision text recognition for images;
  - AVFoundation tags for audio and video;
  - `LPMetadataProvider` for a link's title, icon and sharing picture (its `imageProvider`, kept as a
    448 px JPEG that fills the link's tile), and `CLGeocoder` with `MKMapSnapshotter` for an
    address's map. This is Tuck's only network code. It has no switch of its own: it runs whenever
    clipboard history is on, and clipboard history is off by default.

  Whatever it learns lands in the entry's `ClipPreview`. A link with neither icon nor picture (copied
  with an earlier Tuck, or while its page couldn't be reached) is looked up when its tile first appears
  (`TuckModel.lookUpPreviewIfNeeded`, from `ClipboardTile`'s `.task`): the stream is lazy, so only the
  links shown are looked up, each at most once a launch. A link copied again without a picture is looked
  up again then too.
- **What search reads.** `ClipboardEntry.searchText` joins everything search looks through.
- **Old history.** History from before kinds decodes with no recognition, and
  `recognizeUnrecognized` fills it in at load.

`FileClipboardPersistence` (TuckCore) saves clipboard history the same way: one coalesced, atomic
write a moment after a change, on a utility queue, and no write when the history matches what the file
holds. An unreadable file is moved aside as `clipboard-history-unreadable-<time>.json`, never written
over. The history keeps at most 200 entries (`ClipboardHistory.defaultMaxEntries`), dropping the least
recently copied first; the limit isn't saved, so a file from before it is held to it on load. After
each write it deletes the assets the history no longer names (`removeUnreferenced`, sparing files under
two minutes old, which may belong to a copy being recorded), and uninstall empties `Clipboard/` one
asset at a time. Clear
Clipboard History also deletes the set-aside files (`removeSetAsideFiles`), since they hold old entries.
Turning history off with entries saved asks first (`ClipboardHistorySwitch`, in Settings › Held and
setup's Choose step): Keep History leaves them, Delete History clears them as Clear does, and Cancel
leaves history on.

## Efficiency budget

| Measure | Target | Current (release build) |
| --- | --- | --- |
| Idle CPU, collapsed | ≈ 0% | 0.0% |
| Memory footprint, collapsed (fresh launch) | < 20 MB | ~12 MB |
| Memory footprint, panel open | < 40 MB | ~23 MB |
| App bundle | < 5 MB | ~3.6 MB |

The current figures were measured before the fold replaced the panel and have not been taken again
since.

Release builds use `-Osize`; `scripts/build-app.sh` strips local, debug and Swift symbols
(`strip -rSTx`) before ad-hoc signing for local runs. Given a dSYM path (as `scripts/release.sh` gives
it), it runs `dsymutil` first, so the symbols survive outside the bundle.
