# Decision log

Newest first. Each entry records what was decided, why, what was checked, and what is deferred. Entries
are not rewritten: when a later decision changes one, a **Superseded** (or **Superseded in part**) note
at the top of the earlier entry says what changed and names the entry that changed it.

Live checks were made on a macOS 15.7 test Mac, a virtual machine with a 1280 × 800 display and no
notch, so Tuck shows its bubble there; it sends wheel events rather than trackpad swipes. Entries call
it the test Mac. An **Inspiration** note names an app whose behaviour gave Tuck an idea. It is
inspiration only: no code, assets or drawings were taken from any of these apps, and Tuck's version is
written for Tuck.

## 2026-11-19: Tuck's own bundle ID, real links in About, and a signature that stays the same

- **Decision:**
  - **The bundle ID is `com.millerroberts.Tuck`,** beside `com.millerroberts.Glow`,
    `com.millerroberts.Pulse`, `com.millerroberts.hum` and `com.millerroberts.lineapps`, in
    `Support/release.env` and `Support/Info.plist`. It was `app.tuck.prototype`.
  - **Settings carry over.** At the first launch under the new ID, before anything reads or writes a
    setting, `SettingsMigration` (in TuckCore, called first in `TuckMain`) copies every key saved under
    `app.tuck.prototype` into the new domain, when the new one has none yet and the old one has some. It
    never deletes the old domain, and does nothing under `swift run`, which has no bundle ID. Tuck has
    no sandbox and no entitlements file, so it can read the old domain.
  - **Accessibility and Open at login have to be set again** after the change, by everyone already
    running Tuck: macOS keys both to the app's identity, and copying settings can't bring them across.
    Full Disk Access and folder access are asked for again too. The library carries over, since its
    folder is named after the app.
  - **About's links lead somewhere real.** The privacy policy and the EULA are the files in
    `docs/legal/` on GitHub, and support is Tuck's GitHub issues. No support email is published. The
    Support link shows the email when one is set, otherwise the support page's host (`github.com`), as
    the Website row shows its host, and only then the placeholder address. The source plist no longer
    holds `support@tuck.example`, so a build has no `tuck.example` left once the other links are set.
  - **Uninstall** deletes the settings under the old ID too, so the copy the carry-over keeps doesn't
    outlive Tuck. The privacy policy draft names both preferences files for removing them by hand.
  - **`scripts/release.sh`** needs `WEBSITE_URL`, `PRIVACY_POLICY_URL`, `EULA_URL`, and `SUPPORT_EMAIL`
    or `SUPPORT_URL` for a signed release, where it needed the email before.
  - **One signature across updates, until there is a Developer ID.** `scripts/signing-identity.sh`
    creates "Tuck Local Signing", a self-signed identity in its own keychain
    (`~/Library/Keychains/tuck-signing.keychain-db`), as Glow's and Pulse's scripts do for theirs.
    `scripts/build-app.sh` signs with it when it exists, else ad hoc with a hint to make it.
    `scripts/release.sh --unsigned` signs the app with it under the hardened runtime, else ad hoc, and
    says which. The Developer ID path is unchanged. The identity's private key has to be backed up: a
    new certificate is a new signature, and everyone would grant Accessibility once more.
  - **The docs** (README, development, release, architecture and one line of the guide) say so, and the
    `log stream` predicates name the new subsystem.
- **Why:** I wanted Tuck's ID on my own domain, beside the other Line Apps'. Changing it used to drop
  everyone's settings; copying them keeps everything but what macOS ties to the app's identity. About's
  Support, privacy policy and EULA links still led to tuck.example. And every update of the ad-hoc DMG
  lost the Accessibility grant, which one stable certificate keeps, as it already does for Glow's and
  Pulse's builds.
- **Checked:**
  - `scripts/test.sh`: 408 tests in 48 suites pass, with the new suite "Settings carried over from the
    old bundle ID" (4 tests). It copies every key when the new domain is empty and leaves the old one as
    it was; it leaves a new domain that already has keys; it does nothing when the old domain is
    missing, or without a bundle ID, or under the old ID. The tests use throwaway domains and remove
    them, their files included.
  - `swift build` shows no warnings. `scripts/build-app.sh` builds `build/Tuck.app` with
    `Identifier=com.millerroberts.Tuck`, `Authority=Tuck Local Signing` and the three links stamped.
  - `scripts/signing-identity.sh`, run on this Mac, says the identity already exists, and leaves the
    keychain search list as it was.
  - `scripts/release.sh --unsigned` built the test DMG and said it signed with Tuck Local Signing. In
    the DMG, mounted read-only: `Identifier=com.millerroberts.Tuck`, `Authority=Tuck Local Signing` and
    `flags=0x10000(runtime)`. The designated requirement is `identifier "com.millerroberts.Tuck" and
    certificate leaf = H"d555d322…"`, the certificate's SHA-1, the same as the local build's.
    `codesign --verify --deep --strict` passes, and Info.plist has the three new links and no
    `tuck.example`.
  - `scripts/release.sh` in a scratch copy: with no credentials it lists only those. With `EULA_URL` and
    both support links emptied, it names `EULA_URL, SUPPORT_EMAIL or SUPPORT_URL (one will do)`, and
    refuses with dummy credentials. With only `SUPPORT_EMAIL` set, it goes on to the certificate check.
- **Not checked:** the built app wasn't launched, so the carry-over hasn't run in it; the tests drive
  the same code against real preferences domains. No one has yet updated from one DMG signed with this
  identity to the next, so the grant carrying over is the pattern Glow's and Pulse's builds rely on,
  not something seen with Tuck.
- **Deferred:**
  - **The legal drafts** still have their `[Support email]` and `[privacy policy URL]` placeholders.

## 2026-11-19: Local builds report 1.0.0, and the samples look made up

- **Decision:**
  - **The version:** `scripts/build-app.sh` stamps `CFBundleShortVersionString` from `VERSION` on the
    bundle's copy of Info.plist, so a local build says 1.0.0 in About and in Move to Applications' note,
    as a release does. `Support/Info.plist` says 1.0.0 too.
  - **Made-up keys look made up.** The snapshots' sample key and the classifier tests' keys say EXAMPLE
    and are put together in code, so no secret scanner takes them for real ones. They are still named
    and masked as before ("sk-ant-••••Ab3F").
  - **The snapshots' samples:** the note copied from Notes no longer has the held note's words, so the
    full fold doesn't show the same card twice. The mostly white page picture has a headline, a button
    and coloured blocks where a card's preview shows them, rather than pale panels that read as an
    empty picture. The copied path is `~/Developer/Tuck/Package.swift`.
  - **The README:** "One stream" is two sentences, and the guide keeps the detail. Install offers the
    Line Apps installer for all four apps, as Pulse's and Glow's READMEs do. `docs/images/hero.png` is
    the new `panel-fullKinds-dark`, laid over the same pretend desktop.
  - **Inspiration notes** say plainly that each is inspiration only, with no code taken.
- **Why:** a local build said 0.1.0 while Tuck is at 1.0.0; a key in a real format can trip secret
  scanning once the repository is public; and the README's first screen should say what Tuck does in a
  few lines.
- **Checked:** `scripts/test.sh`: 404 tests in 47 suites pass. `scripts/build-app.sh` builds, and the
  bundle's Info.plist reads 1.0.0. The new fold, rendered off screen, matches the old hero exactly in
  its unchanged rows and was laid in at the same place; `notch.png` still matches the surface snapshots
  inside each notch. Every relative link, anchor and image in the Markdown resolves, none points to the
  removed notes, and `git diff --check` is clean.

## 2026-11-19: The repository is ready to publish

**Superseded in part** by "2026-11-19: Tuck's own bundle ID, real links in About, and a signature that
stays the same": the privacy policy, EULA and support links are set, and support is by GitHub issues,
not email.

- **Decision:**
  - **The tagline** is "Clear the desk. Keep your place." in the README and on the logo board, which
    is rendered again. The board, `generate.py`, the logo README and `tokens.css` describe Tuck Blue as
    the app's colour and the other five as colours for illustrations, not spaces.
  - **The README's lockup** is 64 pt high, as in the other Line Apps' READMEs. The disk image comes
    from Tuck's page, and on macOS 14 Control-click › Open works as well as Open Anyway.
  - **About's website link** is Tuck's page, `https://lineapps.vercel.app/tuck/`, as Pulse's and Glow's
    are. The support email, privacy policy and EULA links stay empty until those are published.
  - **`scripts/release.sh --unsigned`** no longer says its DMG is not for release: the site and the tap
    ship it until a signed release exists.
- **Why:** the repository is to be made public.
- **Checked:** setup's steps, choices, shortcuts and permissions against the code; every setup step and
  the README's two pictures against the off-screen snapshots (`--snapshot-ui`, `--snapshot-panel`),
  which still match; every relative link, anchor and image in the Markdown; `scripts/test.sh`: 404 tests
  in 47 suites pass; `scripts/build-app.sh` builds and stamps the website link; `git diff --check` is
  clean.
- **Deferred:** the EULA and privacy policy are still drafts for legal review, with their placeholders;
  the memory and CPU figures in the README weren't measured again.

## 2026-11-19: Tuck installs with Homebrew, from the Line Apps tap

**Superseded in part** by "2026-11-19: Tuck's own bundle ID, real links in About, and a signature that
stays the same": the bundle ID is `com.millerroberts.Tuck`, About's links are set, and the test DMG is
signed with "Tuck Local Signing" rather than ad hoc. The cask's `uninstall quit:` and `zap` still name
`app.tuck.prototype` until the tap is updated.

- **Decision:** `brew install --cask millerroberts180/line-apps/tuck`, from a new public tap,
  [millerroberts180/homebrew-line-apps](https://github.com/millerroberts180/homebrew-line-apps), one
  tap for all the Line Apps.
  - **The download** comes from the Line Apps site, as for the other Line Apps:
    `https://lineapps.vercel.app/downloads/Tuck-1.0.0.dmg`, the file Tuck's page offers, with SHA-256
    `2bdc2e70bfab345679d2258181d3971a92d5869c8e206c2f06a1045256d6b6b5`. The cask first downloaded the
    tap's own release `tuck-1.0.0`, because Tuck's repository is private; it moved to the site the same
    day.
  - **No trust step:** installing by the full name trusts the cask itself, so there is no `brew trust`
    to run first.
  - **Until there is a Developer ID**, the cask ships the test DMG: signed ad hoc, not notarized. Its
    caveat, the README and the guide give the Open Anyway step. `docs/release.md` said the test DMG was
    never for release; it now says the site and the tap ship it until a signed release exists.
  - **The cask:** arm64 and macOS 14 or later, as the app requires; `livecheck` reads Tuck's page for
    the newest `Tuck-<version>.dmg`; `zap` removes the library, settings, caches and HTTP storage under
    the bundle ID.
  - **One caveat:** the cask's `uninstall quit: "app.tuck.prototype"` also quits any running Tuck with
    that bundle ID, not only the one Homebrew installed. Local builds take the same ID, so
    `brew uninstall` quits a running local build too.
  - **The full name** is in every instruction: Homebrew's own catalogue has an unrelated `tuck` cask
    (Irradiated Software's window manager), and `pulse` too.
  - **The README** gains Install, a fact line under the tagline, and a Line Apps section listing Tuck,
    Pulse, Hum and Glow, shared with their READMEs. `docs/release.md` has the steps for each version.
- **Why:** I wanted a Homebrew install, and the four apps' repositories to read as one family.
- **Checked:**
  - **The tap's release:** the DMG was cut from the commit before this one, build 20261119.93530.115,
    arm64. `brew style` and `brew audit --cask --strict --online` passed.
    `brew install --cask --appdir=<scratch>` downloaded it from the public release, matched the
    checksum and installed it. The installed app was quarantined, and `spctl` rejected it, as the
    caveat says. `brew uninstall` then removed it. `/Applications/Tuck.app` wasn't touched.
  - **The site's download:** the file at the URL has the SHA-256 above, Tuck's page links
    `downloads/Tuck-1.0.0.dmg`, and `brew audit --cask --strict --online` passes. The file is an older
    build, 20261117.71709.114, ad hoc, holding Tuck.app and the `/Applications` link but no `EULA.txt`.
    It wasn't installed through Homebrew.
- **Deferred:**
  - **About's links** still lead to the tuck.example placeholders, because `Support/release.env` has
    no website, privacy or EULA links yet.
  - **The bundle ID** still says `prototype`. Changing it later resets settings and Accessibility for
    everyone installed by then, and the cask's `zap` paths change with it.
  - **The first open after a real download** (Open Anyway) wasn't clicked through this time. The Line
    Apps installer's run on the test Mac showed the same step.

## 2026-11-16: No trial and no licence keys: every feature, for everyone

- **Decision:** Tuck has no trial and no licence keys. Every feature works for
  everyone, always, and nothing is ever locked.
  - **Gone from the app:** Settings › Licence; Enter Licence… and Buy Tuck… in the menu; the fold's
    "Your trial has ended" card; and every check that held a feature back once the trial was over
    (tucking, the window picker, Rest, keeping, drops, the notch's Tuck button, the drop invitation,
    clipboard capture and the input taps).
  - **Gone from the code:** `Trial`, `TrialRecord`, the key format, `LicenseValidator` and the embedded
    public key in TuckCore, `Licensing` in the app, and `LicenseTests` and `TrialTests` with them.
  - **Gone from the release:** `PURCHASE_URL` and `TuckPurchaseURL`, `scripts/make-license.swift`, and
    `release.sh`'s checks of the public key. The private key in `~/.tuck` is left where it is.
  - **What builds with a trial left behind** is deleted at each launch, quietly and off the main
    thread, by `TrialLeftovers`: `TrialRecord` and `LicenseKey` in Tuck's UserDefaults, and the login
    Keychain's generic password with service the bundle ID and account `trial`. An item another build
    made is refused the delete without anyone being asked, and is tried again at the next launch.
    Uninstall still removes Tuck's whole preferences, the first two with them.
  - **The docs** (README, guide, architecture, development, release) describe a free app. The EULA and
    privacy policy drafts lose their trial, purchase and key terms. For their legal review, these
    change in meaning: the EULA's grant (1.1) is free of charge, with no seat count and no "for use by
    you alone"; the trial (1.2), the restrictions on keys and licensing (2) and Refunds (9) are gone,
    and the sections after it renumbered; the limit of liability (8) was "the amount you paid", now a
    placeholder. The privacy policy no longer keeps a licence key or the trial's days, and loses
    "Licence check", "Purchases" and the log notes about the trial's keychain item and a damaged key.
- **Why:** I decided so on 2026-11-16.
- **Checked:**
  - `swift build` and `swift build -c release --product Tuck`, from scratch in a separate copy: no
    warnings, as at the commit before.
  - `scripts/test.sh`: 404 tests in 47 suites pass, down from 423 in 49 with the trial's and keys'
    tests.
  - `bash -n` on both scripts. `scripts/release.sh --unsigned` and `scripts/build-app.sh`, in that
    copy, build and check the DMG; the bundle's Info.plist has no purchase link.
  - Snapshots (`--snapshot-ui`, `--snapshot-panel`, 436 images, from 456): the Settings sidebar
    without Licence, About at full length, the fold's prompts, and the closed surface under the
    pointer, where the Tuck button shows.
- **Deferred:**
  - **The cleanup on a Mac with a trial record:** it hasn't been run against a real preferences
    domain or keychain item, only read against the code that wrote them.
  - **The menu** has no snapshot; from the code it is Open Tuck, Tuck Front Window, Restore Last
    Tucked Window, Tuck Away, Bring Tuck Back, Settings…, and Quit Tuck under a separator.
  - **Under another bundle ID** the leftovers stay: Tuck deletes them only under its own.

## 2026-11-14: One calm card, one line of details, a quiet toolbar, and the arrow keys

- **Decision:** the fold's cards of copied and held things, from my notes on them.
  - **One card for every kind.** Every tile sits on the light grey text had (OKLCH 0.89 on the black,
    #D9DBDD), so the stream reads calmly and pictures, maps, colours and page pictures keep the only
    full colour. The twelve hues stay, one by kind, as a small mark at the start of the line of
    details, deep enough to read on the card (0.53 at chroma up to 0.13; 0.43 with Increase Contrast).
  - **One layout.** What a thing is at the top (an icon, avatar, flag or calendar page beside a 13 pt
    semibold title and a quieter line, or the words or code themselves), the line of details at the
    foot, 14 pt tall on every card so a row's titles and lines align. Pictures, videos, page pictures,
    maps and colours take a full-width preview at the top, cropped to keep their shape, with a one-line
    title and the line on the card under it; nothing is written over a picture any more, so
    `PictureCaption` is gone. A missing picture leaves its kind's symbol, quiet, in its place.
  - **One line of details** in place of the badges: the kind's mark, then what it is and the one fact
    most worth a glance ("Markdown · 4 KB", "PNG · 1280 × 800"), in the card's quiet ink. Under the
    pointer, with the keyboard's ring or open, it adds the second fact, the folder and the app's icon;
    all of it is still in the tooltip and VoiceOver. Markdown files say "Markdown" rather than "MD".
  - **Cards with room for it:** medium 168 by 96 pt (was 170 by 70), small 0.9 of it (151 by 86),
    large 1.3 (218 by 124); 8 pt between cards and 10 pt to the fold's edge, so three medium cards make
    540 pt. A display too narrow for the row shrinks the cards only to 150 pt; past that the row drops
    a card, down to two, so a narrow display shows two readable cards rather than three cramped ones,
    and nothing scrolls sideways in the full fold.
  - **Header and filters:** "Everything in Tuck" in the headline weight and primary ink. The kind
    chips are quiet words with their counts in a fainter grey and no symbols (an app's filter keeps
    its icon); only a chip that is on stands out, in Tuck blue on a blue ground.
  - **A quiet toolbar:** Arrange windows and Clear move from rows at the list's foot to one toolbar
    under a hairline, Arrange at the left and Clear at the right, in a new quiet button role (no ground
    and grey ink until pointed at). The list ends 8 pt above the hairline, so its last row scrolls
    whole into view.
  - **The arrow keys** move a Tuck blue ring through the tiles while the fold has the keyboard, the
    list or strip scrolling just enough to show it; Return opens the tile with the ring, Space too
    outside a search, and Escape takes the ring off first.
- **Why:** the coloured grounds competed with each other and with the pictures; the cards were laid
  out differently kind by kind, with words over some pictures and chips of facts along their feet;
  three cards became cramped on a narrow display; the chips and the Clear and Arrange rows were as loud
  as the content; and the tiles could not be reached from the keyboard.
- **Checked:** the debug snapshots (`--snapshot-panel`, 456 images) before and after, at three medium
  cards (540 pt), two small and two medium (narrow) and five large and five medium (wide): long
  titles, files with no thumbnail, every kind mixed, times on and off, the strip, the toolbar with
  Arrange and Clear, the search chips, and the full fold scrolled to its last row at three widths. The
  last row sits whole above the hairline with the same 9 pt between, by a hand scroll to the end and by
  the arrow keys (measured in the renders); the ring along the strip lands clear of its faded edges.
  Contrast on the card and its hover in all four appearances: primary text 12.4:1, secondary 4.60:1,
  code's keywords and strings 4.60:1, a kind's mark 3.31:1 (5.17:1 with Increase Contrast).
  `TileNavigation` and the narrow-display column drop have tests; `scripts/test.sh`: 423 pass.
  `docs/images/hero.png` is rendered again from `panel-fullKinds-dark`.
- **Deferred:**
  - **The arrow keys in the running app:** the test Mac's build asked for Accessibility and its fold
    did not open, so the keys were checked in the snapshots and tests only, not live.
  - **Follow-up ideas, not built:** a list view beside the cards for long histories; layouts by
    filter (a photo grid under Images, a denser list under Text and Code); and stacking repeats of
    the same copy into one card with a count.

## 2026-11-13: Tuck's menu-bar item collapses into Line Apps' line

- **Decision:**
  - **Line Apps** is a new menu-bar app in the bundle (repository `line-apps`): a short line that, on
    a click, collapses Tuck's, Pulse's, Hum's and Glow's icons into itself and bends into the Line Apps
    curl, so the family needn't fill the menu bar. Another click brings them back.
  - **`LineAppsFold`**, one file shared by the four apps, listens for the line's distributed
    notifications and hides or shows the status item, each icon fading a moment after the line moves,
    the nearer the line the sooner.
  - **Each icon comes back where it was.** macOS forgets a hidden status item's place and puts it
    back at the far left, so the fold notes the place (`NSStatusItem Preferred Position`, in the menu
    bar's own terms) as the item goes and writes it back just before it shows.
  - **Only the menu-bar item goes.** The notch and the bubble stay: they are Tuck's place, not an
    icon among the others. While collapsed, Tuck in the line's menu, or opening Tuck again, opens
    Settings, as it already did with the item hidden.
  - **Collapsed holds only while Line Apps runs.** Tuck reads the state at launch only if Line Apps is
    running, and brings the item back if Line Apps quits, by Quit or not.
- **Why:** four icons from one family crowd the menu bar, most of all beside a notch; the line keeps
  one place for all of them without any app losing its icon for good.
- **Checked:** on the test Mac, from the release bundle: collapse and back keep the order
  (line 892, Glow 920, Hum 954, Pulse 992, Tuck 1030 pt); an app quit and reopened while collapsed
  stays in the line and comes back to its slot; quitting Line Apps while collapsed brings every icon
  back in place, and reopening it collapses them again; every app at 0.0% CPU while collapsed; the
  line's menu (Collapse/Show, each app, Open at Login, Quit). `scripts/test.sh`: 416 tests pass.
- **Deferred:** an app opened for the very first time while the others are collapsed has no place
  yet, so it comes back at the left end; from then on it keeps its place. Zero-length items, tried
  first, still take 16 pt each in macOS 15, so hiding is `isVisible`.

## 2026-11-09: The README's pictures show the current fold and notch

**Superseded in part** by "2026-11-14: One calm card, one line of details, a quiet toolbar, and the arrow
keys": `hero.png` now shows the grey cards with their line of details and the quiet toolbar.

- **Decision:**
  - **`docs/images/hero.png`** is now the full fold, dark, hanging from the notch on a pretend
    desktop: the coloured cards with their badges, links with their pages' pictures, text on grey, code
    with numbered lines, and the line of kind chips under the top line. It replaces the shallow fold
    with the Windows page.
  - **`docs/images/notch.png`** is the collapsed notch, light, in four captioned tiles: empty,
    holding something (the mark and a dot), pointed at (the mark lit and the arrow) and with a file
    dragged over it.
  - **Both are composed from the app's own off-screen snapshots** (`--snapshot-panel`:
    `panel-fullKinds-dark` and the `surface-*-light` shots), rendered once on a clear backdrop so they
    lay over the pretend desktop without a grey box. That backdrop was a local change for the render
    only; the snapshots in the repository still fill as before.
  - **The README's words follow:** a link is its site's icon and page title, code shows numbered
    lines, both pictures' descriptions say what they now show, and the app is 3.6 MB, as are the
    guide's and architecture's tables.
- **Why:** the pictures still showed the design from before the coloured cards, the grey text cards
  and the code face, so the repository page no longer looked like the app.
- **Checked:** both pictures at full size; `git status` clean of the clear-backdrop change before
  committing; the release build measures 3.6 MB (`du`, as before).

## 2026-11-09: A few words are no longer set large

- **Decision:** a text card no longer sets a few words (48 characters or fewer) large to fill it.
  Every plain and rich text card shows its words at the usual size, three lines from the card's top,
  as it did before the large sizes came in. The rounded face, and rich text's bold and italics kept as
  emphasis, stay. `TileText.largeSizes`, `TileText.isFewWords` and `Font.panelWords(size:)` are
  removed, as are the three short samples added to show them.
- **Why:** I wanted the larger text reverted.
- **Checked:** `swift build` builds clean and `scripts/test.sh` passes 416 tests in 48 suites. In the
  panel snapshots at every card size, light and dark, text cards show their words at the usual size
  from the top.

## 2026-11-09: Light grey text cards, and code shown as an editor shows it

**Superseded in part** by "2026-11-14: One calm card, one line of details, a quiet toolbar, and the arrow
keys": every card is now the light grey, the hues are small marks on the line of details, and code's
numbers sit in a 14 pt gutter with no rule.

- **Decision:** two changes.
  - **Text, rich text and colours sit on a light grey** (`TileTint.grey`, which replaces the cream):
    the lightest card and the only one with no hue, OKLCH 0.89 on the black fold (#D9DBDD) and 0.93 on
    paper (#E6E8EA), 0.90 and 0.91 with Increase Contrast, all at chroma 0.005 or less. It is a step
    darker than the cream was on black (0.93), so it reads as grey rather than white, and still the
    lightest of the cards (the rest are at 0.78). Under the pointer it lightens on black and darkens on
    paper as every other card does; the cream's own exception is gone.
  - **A code card looks like an editor** (`CodeFace`): each line has its number down a gutter on the
    left, 11 pt (`Font.panelCodeGutter`, a step under the code's 12 pt) in the card's secondary ink,
    with a hairline rule down the whole card between the numbers and the code. It shows as many of the
    first lines as fit with the badges under them: one or two on a small card, three on a medium one,
    four on a large one. A blank line between two lines keeps its place and its number, as in an
    editor, while blank lines before the first and after the last are left out, as the badge's line
    count leaves them, so the numbers match the count. A long line no longer ends in an ellipsis: it
    keeps its length and runs to the card's edge, fading out over the last 18 pt. Each line is its own
    small view (`CodeLine`), which also keeps the face quick to type-check.
  - The panel snapshots' samples gain a SwiftUI view with blank lines between its parts, longer than
    any card shows, and a one-line `git log` from Terminal.
- **Why:** I wanted text on a light grey, and code cards to look like they hold code. Line
  numbers, a ruled gutter, kept blank lines and lines that run off the edge are what an editor shows;
  tinted monospaced words alone read as styled text.
- **Rejected:** a darker gutter fill behind the numbers. On violet it took the numbers' secondary ink
  down to about 4.2:1, under the 4.60:1 every tile keeps; a rule and the numbers alone mark the gutter.
- **Checked:** `swift build` builds clean and `scripts/test.sh` passes 416 tests in 48 suites. On the
  grey, in the four appearances and under the pointer, primary text reads 13.40:1 at least (dark) and
  secondary text 4.77:1 at least (light, under the pointer; 6.94:1 on the black fold), and the open
  ring 3.91:1 at least. In the panel snapshots, at small, medium and large sizes, light and dark, with
  and without Increase Contrast, text cards are grey and code cards show numbered lines, the rule
  running under the badges, a blank line numbered, and long lines fading out at the card's edge. The
  fade first fell past the card, because a long line widened the face; the face is now held to the
  card's width. On the test Mac, the new build loads, and a five-line SwiftUI snippet copied in Terminal
  opens in the fold as a code card numbered 1 to 3, its blank second line kept, beside grey text cards.
- **Not checked:** the cards in the installed app with real copies; the snapshots and the test Mac
  draw the same views.

## 2026-11-09: The drop rim fades out before the screen's top edge

- **Decision:** the blue rim a drag brings up around the notch no longer runs along the top of the
  screen. The rim already left out the outline's top, but each shoulder (the 8 pt quarter circle where
  the surface flows out of the top edge) sets off along that edge, so a short blue line showed at the
  top on both sides as the surface grew to take the drop. A gradient mask on the rim (`promptRimFade`)
  keeps it clear for 2 pt below the top and brings it in over the next 8: it fades out as it climbs
  each shoulder, and is whole down the sides and round the bottom. The same mask applies while
  something is dragged over the open fold, and the setup tour's pretend notch fades its rim the same
  way. A bubble floats below the menu bar, so its rim still goes all the way round.
  - Over the open fold, the drop box now has paper behind it, so the first row's cards, which start a
    little higher than the box, no longer show a coloured edge above it.
  - `OpenTopRim`, a shape nothing drew, is removed; the panel snapshots now clip the fold to its own
    height, as the surface's outline does in the app, rather than to a 700 pt shape.
- **Why:** a blue outline showed along the top as a file neared the notch. The notch's top is the
  screen's edge, so nothing should be drawn there.
- **Checked:** `swift build` builds clean and `scripts/test.sh` passes 416 tests in 48 suites. In the
  surface snapshots the notch's drop target had blue in its top rows at both shoulders and now has
  none in the top 9 px; the rim is unchanged down the sides and round the bottom, and the bubble's ring
  is unchanged. In the open fold's drop snapshots, light and dark, no card shows above the box and the
  corners are round. A one-off render of the setup tour's notch with a drag over it shows its rim
  fading out the same way. On the test Mac, the new build loads and its fold opens.
- **Not checked:** the rim live on a notched Mac with a held drag. The test Mac shows Tuck's bubble, not
  a notch, and a drag sent to it lands at once: a held drag needs Accessibility for its Terminal, which
  was not granted.

## 2026-11-09: Text cards use a rounded face, and a few words are set large

**Superseded in part** by "2026-11-09: A few words are no longer set large": every text card shows
its words at the usual size, three lines from the top; the rounded face and the rich text's emphasis
stay.

- **Decision:** two changes to text cards, plain and rich.
  - **A rounded face.** Copied words use SF Pro Rounded (`Font.panelWords`) on the card and in the
    editor that opens on a double-click. The panel's own labels (titles, sites, names, badges) stay in
    SF Pro, so what you copied reads apart from what Tuck says about it.
  - **A few words are set large.** Text of 48 characters or fewer (about one to eight words) takes the
    largest of two sizes, semibold, at which it fits whole: 22 pt, then 17 pt, on a medium card, scaled
    with the card (18 and 14 on a small one, 29 and 22 on a large one). A size is used only if every
    word fits across the card at it, so no word is broken to fit. It sits down the card's middle, as a
    link's or a phone number's words do, rather than in its top corner. If neither size fits, it keeps
    the usual 13 pt, still down the middle. Longer text shows three lines from the top, as before.
  - Rich text now keeps its bold and italics as emphasis rather than fixed 13 pt fonts, so they follow
    the card's face and size.
- **Why:** I wanted the normal text friendlier, and a few words to fill their card rather than
  sit small in its corner. Facebook sets short posts larger the same way. Two steps rather than a size
  fitted to every card keep neighbouring cards in a common scale.
- **Checked:** `swift build` builds clean and `scripts/test.sh` passes 416 tests in 48 suites. In the
  panel snapshots at every card size, light and dark, with three new short samples: on a medium card
  "Thank you!" and "Blue Bottle Coffee" are at 22 pt on one line and "Meet at the north entrance" at
  17 pt on two; on a small card "Thank you!" is at 18 pt and "Blue Bottle Coffee" stays 13 pt, down
  the middle; the long note and the rich text keep three lines in the rounded face, their bold, italics
  and link intact. SF Pro Rounded has the same line heights as SF Pro, so no card loses a line.
- **Not checked:** text in right-to-left or East Asian scripts at the large sizes; a phrase with no
  spaces is measured as one word, so it may keep the usual size where it could have been larger.

## 2026-11-09: A link's site sits under its title again, and a link with no title is named by its site

- **Decision:** a link or music link without a page picture shows, beside its icon (or the link
  symbol), two lines:
  - **with a title:** the page's title (two lines where the card has room, one on a medium card) and
    its site under it, as before the last change. A long site is cut from its start, so its name
    stays: "…eloper.apple.com".
  - **without a title** (the page has none, couldn't be reached, or hasn't been looked up yet): its
    site as the title, "open.spotify.com", and its whole address under it, scheme and all, cut in the
    middle, over two lines where the card has room.

  A link whose address has no site keeps the address alone, as before.
- **Why:** I wanted the site back under the title, and a site's name in place of a missing
  title, with the full link under it.
- **Checked:** `swift build` builds clean and `scripts/test.sh` passes 416 tests in 48 suites. In the
  panel snapshots, small, medium and large: the HIG and Apple Music links show their titles over
  "…eloper.apple.com" and "music.apple.com", and the untitled Spotify link shows "open.spotify.com"
  over its address (two lines of it on a large card). On the test Mac, example.com showed "Example
  Domain" over example.com, and a link to a site that doesn't exist showed its site over its address.
- **Not checked:** nothing new; the earlier entry's notes still apply.

## 2026-11-09: Link previews are always on, a link without a picture shows its icon and title, and words over a picture always read

**Superseded in part** by "2026-11-09: A link's site sits under its title again, and a link with no title is named by its site": a link's site sits under its title again, and a link with no
title is named by its site, with its whole address under it.

- **Decision:** three changes.
  - **A link with no picture shows its site's icon beside the page's title**, up to three lines. A
    link symbol on a white rounded square stands in for the icon until the page is looked up, or when
    it gives none. Before the page is looked up, or when it has no title, the address stands beside it
    as before.
  - **Words over a picture always read** (`PictureCaption`, replacing `PictureScrim`): under a page's
    title and site, and an address's lines on its map, the picture is darkened to black at 70%, fading
    in over 20 pt above them (less on a small card). The old fade reached only about 45% under the
    title, about 3.4:1 for white text over a white picture; now the worst case, a white picture, gives
    8.4:1 for the title and 6.7:1 for the quieter second line. The band runs the card's width, so the
    badges beside the words sit on it too.
  - **Link previews are no longer a setting.** Settings › Held › Online previews is gone, and with it
    `SettingsStore.clipboardOnlinePreviews` and `ClipboardEnricher.fetchesOnlinePreviews`. Whenever
    clipboard history is on, a copied link's page is opened once for its title, icon and sharing
    picture, and a copied address's map is asked of Apple Maps, since one switch covered both. Clipboard
    history itself stays off by default, so a new Tuck still connects to nothing until it is turned on.
    The Clipboard history switch now says what it opens, About's footer and Always list say Tuck goes
    online only to preview what you copy, and the setup step, README, guide, architecture notes and
    privacy policy say the same. The old key is simply no longer read.
- **Why:** I wanted a title rather than a bare address for a link with no picture, text you can
  always read over a picture, and previews with no option to turn them off.
- **Checked:** `swift build` builds clean and `scripts/test.sh` passes 416 tests in 48 suites. In the
  panel snapshots a new sample with a white page picture (GitHub) reads clearly, as does the address
  on its map, and the held HIG link and the Apple Music album, with no icon, show the link symbol
  beside their titles. In Settings the switch is gone and the Always line fits on one line. On the
  test Mac, with the old setting written off, a newly copied swift.org link still got its picture,
  icon and title, example.com showed the link symbol beside "Example Domain", and the GitHub, Newsroom
  and macOS pages and the Cupertino map read over their pictures.
- **Not checked:** a page whose sharing picture has a dark band of its own at its foot (the caption
  darkens it further, which reads but hides more of it). Held links (dropped, not copied) are still
  not looked up.

## 2026-11-09: A fainter cream, and app icons drawn to one size

**Superseded in part** by "2026-11-09: Light grey text cards, and code shown as an editor shows it":
text, rich text and colours sit on a light grey, not cream, and it lightens under the pointer as every
card does.

- **Decision:** two changes.
  - **The cream is fainter:** OKLCH chroma 0.022 at lightness 0.93 on the black fold (#EEE7D8, from
    0.04 at 0.92), 0.018 at 0.96 on paper, and 0.024 to 0.027 with Increase Contrast, at the same hue.
  - **Every app icon is drawn to one size** (`AppIcons.normalized`): in badges, window tiles and rows,
    the search bar's app chip, Settings' app list and the tucked window's card. Apps place their art
    differently in the icon's canvas: Apple's leave a margin and a soft shadow, and some fill it to
    the edge, so a round one looked larger than Safari's. The art is found once per app, on a
    64-pixel drawing (pixels at least half opaque, so the shadow is left out), and drawn centred with
    its longer side at Apple's grid, 824 of 1024. Art that covers less of its box than a rounded
    square (0.93), a circle say, is drawn larger by the square root of the difference, up to 12%, so
    it looks as big. Layouts are unchanged, since Apple's own icons already sat at that grid.
- **Why:** I liked the cream but wanted it fainter, and the app icons to look one size.
- **Checked:** `swift build` builds clean and `scripts/test.sh` passes 416 tests in 48 suites. In the
  panel snapshots Spotify's round icon matches Safari's, the window tiles' TextEdit, Safari, Notes and
  Preview icons line up, and the cream is paler beside the old snapshots. On it primary text reads
  15.11:1 in dark (13.51:1 under the pointer), secondary 7.83:1 (7.00:1) and the accent 5.59:1
  (5.00:1); in light, secondary 5.59:1 (5.25:1) and the accent 4.59:1 (4.31:1).
- **Not checked:** icons whose art is mostly faint (under half opaque), which are measured by their
  solid parts only.

## 2026-11-09: Cream text cards, bare app icons, link icons, and American spelling on tags

**Superseded in part** by "2026-11-09: Link previews are always on, a link without a picture shows its icon and title, and words over a picture always read": a link with no picture shows a link symbol until its icon is
found, beside the page's title, and previews no longer wait for a setting.

**Superseded in part** by "2026-11-09: A fainter cream, and app icons drawn to one size": the cream is
fainter, and every app icon is drawn to one size.

- **Decision:** four changes.
  - **Text, rich text and colours sit on cream** (`TileTint.cream`), not stone: OKLCH lightness 0.92
    on the black fold at chroma 0.04, hue 88 (#F0E4C7), and 0.955 on paper. It is the lightest card,
    so under the pointer it darkens 5% on black as well as on paper, where lightening would barely
    show. The rows' and buttons' `Theme.stone` is unchanged.
  - **The app's icon stands bare** in a tile's badge row, with no chip round it, drawn a point past
    the row's height, since an icon's art sits inside its canvas. Every other badge keeps its chip,
    and the search bar's "From <App>" chip keeps its capsule, since it has words.
  - **A link shows its site's icon** once online previews have looked it up, which they already
    fetched and kept (`ClipPreview.iconFile`) but no face drew. Without a page picture the icon
    (28 pt) stands beside the page's title and its site, or beside the address when the page has no
    title; with one it sits at 14 pt before the picture's last line. A touch icon (opaque at its
    corners and sharp at that size) fills a rounded square; a favicon sits on a white one, so a dark
    mark reads on any card or picture. A link copied while online previews were off, with neither icon
    nor picture, is looked up when its tile first comes into view, at most once a launch
    (`TuckModel.lookUpPreviewIfNeeded`); the stream is lazy, so only links shown are looked up. The
    Settings text and the privacy policy say so.
  - **Tags are spelt in American English:** the colour kind's badge, caption and filter read "Color"
    and "Colors", and its search chip adds "colors"; "colour" and "colours" still find colours.
- **Why:** the stone ground for text looked dull beside the light cards; a chip round an app icon read
  as a frame round a frame; link previews fetched the icon but never showed it; and I wanted
  tags in American spelling.
- **Checked:** `swift build` builds clean and `scripts/test.sh` passes 416 tests in 48 suites. The
  panel snapshots, in all four appearances and at every card size, show cream text cards, the bare
  icons, the favicon on its plate over a page picture, and the touch icon filling its square. On
  cream in dark, primary text reads 14.73:1 (13.25:1 under the pointer), secondary 7.63:1 (6.87:1)
  and the accent 5.45:1 (4.90:1); in light, secondary 5.50:1 (5.17:1).
- **Not checked:** held links, which have no icon stored, so they keep their tile of words; and pages
  whose icon is neither a clear touch icon nor a favicon, which take the white plate.

## 2026-11-09: Light cards, badges on every kind with the app's icon, the bubble's lone mark, and page pictures

**Superseded in part** by "2026-11-14: One calm card, one line of details, a quiet toolbar, and the arrow
keys": the badges are one line of details, its second facts and the app's icon shown under the
pointer; every card is one light grey; a page's picture sits above its title rather than under words.

**Superseded in part** by "2026-11-09: Link previews are always on, a link without a picture shows its icon and title, and words over a picture always read": a page's picture is fetched whenever clipboard history is on, with
no Online previews setting, and its words sit on a dark band (`PictureCaption`) rather than a fade.

**Superseded in part** by "2026-11-09: Cream text cards, bare app icons, link icons, and American
spelling on tags": text, rich text and colours sit on cream, not stone, and the app's icon stands bare,
with no chip.

- **Decision:** four changes. Four branches built them (`tuck-colours`, `tuck-badges-all`,
  `tuck-bubble` and `tuck-link-previews`), merged into main.
  - **Tiles are soft printed card in the Line Apps' sphere** (`TileTint`), not dark coloured glass.
    - The twelve hues stay 30° apart round Tuck blue's own, which now land within 3° of Pulse's, Hum's
      and Glow's. They are lighter: OKLCH lightness 0.78 on the black fold at chroma 0.085 or less, and
      0.925 on paper at up to 0.05 (0.80 and 0.895 with Increase Contrast). Text, rich text and
      colours sit on warm stone (0.83 on black, a touch lighter so a grey beside colours doesn't look
      dull), in place of graphite.
    - Music and audio take red, Hum's hue (12°, Hum's is 13.7°), and keys the orchid music left.
    - Because a card is light on the black fold too, what is on it takes the card's inks: Theme's text,
      hairline, accent and on-accent tokens are card-aware (an `OnCard` shape style), and `TileChrome`
      marks the card once (`isOnTileCard`), so every face, badge, lock, calendar and capsule follows
      with no face edited, and a new face drawn with Theme's tokens does too. The open ring and the
      "Copied" capsule turn deep Tuck blue (#325C8D in dark), since the logo's blue stands only 1.4:1
      off a card. The fold itself stays black.
    - Worst ratios over every card and its hover: primary text 8.95:1, secondary 4.60:1, a badge's
      words 5.99:1, code's keywords and strings 4.60:1, the ring and the capsule 3.31:1 off the card
      (white on the capsule 5.13:1). With Increase Contrast secondary text is 7.01:1 or better.
  - **Every kind wears badges** (`TileBadges`), as files already did: its kind as a symbol and a
    word and one or two facts read cheaply from it.
    - Text and rich text their words; code its language and lines; a link the type of file it leads
      to; a music link its service and whether it is an album, track, playlist, artist or episode; a
      colour how it was written and its opacity; a date how far off it is; an emoji its name; a key its
      maker; a path its type and size or "Not found"; an app's windows "Window" or "N windows". A file
      adds the folder it is in, and a song or film its length. Emails, phone numbers and contacts keep
      the kind alone, since the face already shows the fact, and an address its map symbol, since its
      words share the foot line; its badges keep to half the card, as a page picture's do.
    - A text under 2 KB is counted on the main thread, so its row never reflows; a longer one in a
      detached utility task, remembered by the copy and its length until the fold closes.
  - **The app's icon is the last badge** (`ItemDetails.appIcon`), found by the copy's bundle
    identifier, or, for a held item, which records only a name, among the running apps; kept until the
    fold closes. It is left off Tuck's own copies, apps no longer on the Mac, screenshots (the camera
    badge says where they came from) and files, folders and stacks from Finder (their folder badge
    says where they are), and kept on files from any other app and on copied images, where the app is
    news.
  - **Typing an app's name searches by app** (`SearchApps.swift`): its name, "from" and its name, or a
    word only one known app's name has ("chrome") becomes a "From <App>" chip with the app's icon,
    which finds what came from it and anything that says the word. A chip's own word ("code",
    "music", "screenshots") stays a kind unless typed after "from"; another kind word ("notes",
    "mail") is the app when that app is in the history. The known apps are gathered once, when a
    search's first character is typed, with each one's bundle name when it differs ("Visual Studio
    Code" for "Code"), and dropped when the search ends.
  - **The bubble shows its mark alone again**, as in "2026-11-04: Keep collapsed controls anchored
    through surface transitions": no dot, the mark centred, faint while empty and with its card while
    Tuck holds something. Pointed at, the mark fades and shrinks to 0.7 as the Tuck arrow rises in
    its place, nothing sliding sideways (a plain fade under Reduce Motion); pointed at while Tuck is
    empty, it still offers the arrow rather than the drop prompt the notch shows. A click on the arrow
    (and 6 pt round it) tucks the front window, as the notch's button does; the bubble's 20 pt ends
    (`bubbleEndWidth`) open the fold. It stays 72 pt wide, so the fold's width doesn't move. While the
    arrow stands in the mark's place the mark doesn't greet, and a tucked window's card lands at the
    arrow's foot and the arrow takes the swell. Settings › Notch's bubble tile shows the mark cut out
    of its pill.
  - **A copied link shows its page's sharing picture**, filling its tile, with its title and site on a
    scrim, when Settings › Clipboard › Online previews is on (off by default). It is the picture the
    page declares for sharing (`og:image` or the like), which `LPMetadataProvider` already hands back
    with the title and icon (`imageProvider`), loaded beside the icon and kept as a JPEG 448 px wide
    (`ClipPreview.pageImageFile`, an asset of the copy, removed with it). So there is no dependency, no
    web view and nothing rendered or mirrored: a page with no such picture keeps its tile of words, with
    no fallback, as I wanted. A link copied before, without a picture, is looked up again when
    it is copied again.
- **Why:** the dark tiles looked too dark beside the Line Apps; I wanted badges on everything
  with the app it came from, and to find things by that app; the bubble back as it was, the logo alone
  that turns into the arrow; and website previews only if they needed no dependency and no mirroring.
- **Checked:** `swift build` builds clean, and `scripts/test.sh` passes 416 tests in 48 suites,
  `SearchAppsTests` and the new `SearchBadgesTests` cases among them. The panel and Settings snapshots in
  all four appearances were compared with main's: the notch's surface snapshots are byte-identical, and
  the card inks measure within 1 of the table once the snapshots are converted to sRGB. Live, in the
  release build on the test Mac (no notch, so the bubble):
  - The bubble shows the mark alone at rest; pointed at, the arrow takes its place without sliding,
    and the mark comes back as the pointer leaves. A click on the arrow reaches the Tuck Front Window
    path, which asked for Accessibility. A click on the bubble's end opens the fold on the first
    click, a moment after the button is let go.
  - The cards are light on the black fold with dark ink on them.
  - Badges: code wears "Code" and the Terminal icon, an image its size, and a tile's tooltip reads
    "From Terminal · copied at 11:14 AM".
  - Search: "terminal" makes a From Terminal chip with its icon; "terminal links" adds the Links chip
    and finds the one link.
  - With Online previews on, a copied https://www.apple.com/newsroom/ shows a Newsroom tile with the
    page's picture and "apple.com".
- **Not checked:** the tuck itself from the bubble's arrow, since Tuck has no Accessibility grant on
  the test Mac; swipes, which it can't send; a notched display; Increase Contrast live (snapshots
  fake it); and how the most colourful cards look on a real display.

## 2026-11-09: Twelve hues, a row of cards that scrolls sideways, and badges for type, size and time

**Superseded in part** by "2026-11-14: One calm card, one line of details, a quiet toolbar, and the arrow
keys": the hues mark a kind on the line of details rather than fill its card, medium cards are 168 by
96 pt, and a narrow display drops a card from the row rather than shrink it under 150 pt.

**Superseded in part** by "2026-11-09: Light cards, badges on every kind with the app's icon, the
bubble's lone mark, and page pictures". The cards are light (OKLCH 0.78 on black, 0.925 on paper) with
dark ink on them, text sits on warm stone rather than graphite, music takes red and keys orchid. Every
kind wears badges, text and links included, with the app it came from last.

- **Decision:** the tiles' colours, how many cards the fold shows and how big, and what a tile wears
  change. Three branches built it (the palette, the cards and the badges), merged into
  main.
  - **Tiles take one of twelve hues of equal lightness by kind** (`TileTint`), in place of graphite
    with a little of six hues.
    - The hues are 30° apart round Tuck blue's own (252° in OKLCH), all at one lightness: 0.30 on the
      black fold and 0.955 on paper (0.35 and 0.92 with Increase Contrast). Each is as vivid as chroma
      0.075 on black (0.035 on paper; 0.08 and 0.05 with Increase Contrast), or as its hue can be at
      that lightness when that is less: on black, teal, sky, olive, gold and green stop between 0.052
      and 0.067. The old dark tints had a chroma of 0.015 to 0.029, so the cards carry about three
      times the colour, and no kind is lighter than another.
    - By kind: links blue, code violet, music and audio orchid, emails and contacts rose, keys red,
      dates orange, emoji gold, images, screenshots and videos olive, addresses leaf, files, folders,
      paths and stacks green, phone numbers teal and windows sky. Text, rich text and colours stay on
      cool graphite at the same lightness (#2A2E34 in dark, was #252A31). Olive and leaf, the dullest
      on black, go to the kinds whose picture or map covers the ground. None is Pulse's, Hum's or
      Glow's colour.
    - The hover steps are smaller: 5% toward white on black (was 7%) and 3% toward black on paper
      (was 4.5%). With Increase Contrast they stay 9% and 6%.
    - The capsule that says what a click did is still Tuck blue, on every hue.
  - **Cards: how many in a row, and how big** (`CardLayout`, `CardSize`, `FoldLayout` in TuckCore).
    - Settings → Notch → Cards chooses 2, 3, 4 or 5 in a row (3 by default) and Small, Medium or
      Large (0.8, 1 and 1.3 times the 170 by 70 pt card, rounded down: 136 by 56, 170 by 70 and 221 by
      91).
      Its footer says how the fold scrolls and that cards shrink on a smaller display.
    - The fold is as wide as one row: the cards, 6 pt gaps and 8 pt either side, so three medium
      cards make 538 pt (the fold was 540). It is never narrower than the notch (or the bubble) and
      130 pt either side for the Tuck button and the lenses, and the row then sits in the middle; nor
      wider than the display less 48 pt each side, and the cards then shrink to fit, keeping their
      shape, rather than being cut. `SurfaceMetrics.fold` works it out for each display; the static
      `SurfaceMetrics.panelWidth` and `Theme.panelWidth` are gone.
    - Every tile reads its size from `TileMetrics`, in the SwiftUI environment, in place of
      `Theme.tileColumns`, `tileWidth` and `tileHeight`. Thumbnails are made at the card's width and
      made again when it changes.
    - A change in Settings lays an open fold out again at once: `TuckModel.cardLayout` tells the
      surfaces, and `OverlayController.refresh()` re-applies the window's frame when the open fold's
      width changes. On a fold kept narrow by small cards, the lenses fall back to their symbols and
      the full fold's title to "Everything" ("Choose windows" while choosing).
  - **The shallow fold scrolls sideways** (`TileStrip`).
    - It is one row of the whole stream, the newest at the left, as many at a time as Settings
      chooses, made only as each card comes into view (a `LazyHStack` in a horizontal `ScrollView`).
      Two fingers sideways or a mouse's sideways wheel scroll it. While there is more beyond an edge,
      that edge fades out over 28 pt; there are no arrows, dots or scroll bar. `FoldDepth.peekRows` is
      gone.
    - Over the strip a gesture's first events are held back until it has gone 8 pt, then go by the
      axis it mostly moves along (`ScrollGestureRouting`'s `.strip` region). Clearly more up or down
      than sideways (1.5×) is a swipe, which deepens, folds or closes as anywhere else, and the held
      events start it. Otherwise the strip is handed the held events and scrolls, and nothing moves the
      fold for the rest of the gesture. A gesture too short to show an axis is a swipe that went
      nowhere. The 8 pt and 1.5× are the lock and bias the open fold's swipes already used.
    - Deepening slides the strip back to its start, and it becomes the full fold's first row, cut
      halfway into the gap after it, so nothing jumps. Something new arriving at the left takes it
      back to the start too. Under Reduce Motion it goes back without sliding.
    - "N more" is "N in all" (`MoreRow`), since the strip already holds the rest; under a lens it
      still reads "Everything in Tuck".
  - **Tiles wear badges** (`TileBadges`, with their words from TuckCore's `BadgeText`).
    - Small chips along a tile's foot, a step stronger than the tile's ground with a hairline edge, in
      the ink of secondary text; over a picture or a colour, dark glass as the play button is. They
      are 16 pt tall (14 on cards under 60 pt tall), in 11 pt type (`Font.tileBadge`), the one place
      in the fold under 12 pt.
    - A file shows its type as a symbol and a short name (up to four letters in capitals, as "PDF";
      longer ones as a word, as "Swift"; "Keynote", "Pages" and "Numbers" by name) and its size as
      Finder writes it ("2.4 MB"). A folder shows how many items it holds, a stack or a copy of several
      files how many files and their size together, and a copied image "PNG" and the size it was
      copied at. A file that has gone shows no size rather than "Zero KB". Copied text and links wear
      no type or size, and window tiles no badges.
    - Settings → Held → Tiles → Show when each was copied (off by default) adds the time it was
      copied or dropped in: the clock time today, on the Mac's 12- or 24-hour clock, then "Yesterday"
      and the time, the weekday within the week, then the date, with its year when it isn't this
      year's.
    - A tile without room keeps the time first, then the type, then the size (`ViewThatFits`): the
      type shrinks to its symbol before anything goes, and a day-old time to "Yesterday".
    - Faces make room: each gives up the badges' row at its foot; code and stack faces show what fits
      above it; a video's play button rises clear of it; an address's words stop short of it.
    - Badges take no clicks, are hidden from VoiceOver and fade while the capsule shows. The tooltip's
      first line says the same ("PDF · 2.4 MB"), and VoiceOver says it after the tile's name
      ("README.md, MD, 4 KB, copied at 10:57 AM").
    - `FileSizes` (in `ItemDetails.swift`) reads each file's size once, off the main thread for a
      tile, and counts a folder once, off the main thread, keeping both until the fold closes.
  - **Search reads types, sizes and times** (`BadgeFilter` and `SearchFacts`, in `SearchBadges.swift`).
    - Type words ("pdf", "png", "jpeg", "zip", "archives", "disk images", "installers", "mp4",
      "spreadsheets", "presentations", "md" and more), size words ("large", "big" or "huge" for 10 MB
      or more; "small" or "tiny" for under 100 KB) and times of day ("morning" from 5 to noon,
      "afternoon" to 5, "evening" to 9, "night" to 5 the next morning) become chips, as kinds and days
      do; their chips wear a document, a weight or a clock.
    - Sizes and times can be written out. "2 mb" finds 2 up to 3 MB and "2.4 mb" 2.4 up to 2.5 MB, a
      megabyte being a million bytes as in Finder; "over", "under", "at least", "at most", ">", "<",
      "≥" and "≤" compare. "3pm" and "15:00" find the hour, "3:41 pm" the minute, and "3:41" that
      minute on either clock; a number alone stays a word.
    - The day phrases gain "this morning", "this afternoon", "this evening" and "last night" (9 in
      the evening to 5 the next morning).
    - Each finds what wears the badge and also what says the word, so "pdf" still finds a Preview
      window titled "Invoice.pdf". A stack is found by its files. Any one of several types or times
      may match, and every size must. Windows are found by time through when they were tucked.
    - Times are found whether or not tiles show them. A copy carries its files' extensions and its
      size from when it was copied; a held file's size is read only when a search names a size
      (`SearchQuery.asksForSize`), at once if no tile has read it yet, and kept with the tiles' sizes.
- **Why:** I wanted each of these. Twelve hues at one lightness let the stream read as families
  at a glance without any kind standing out, and on black they read as coloured cards rather than
  lights. A row of cards you choose suits the display and how much you keep in Tuck; a strip that
  scrolls sideways shows everything without unfolding, and going by the gesture's axis keeps a sideways
  flick from folding or closing the fold. Badges put back the facts that tell two files apart, small
  enough to leave the tile to the thing itself, and search reads the same words the badges say.
- **Lightweight:**
  - nothing new runs while Tuck is closed. The palette is constants, and the card setting two stored
    values;
  - the strip makes a card only as it comes into view, and its fades are a mask that animates only
    when an edge changes;
  - over the strip, the first events of a gesture are held in an array for at most 8 pt of travel;
  - sizes are read once per file, a tile's off the main thread, and kept only while the fold is open
    (`FileSizes`, emptied with `ItemDetails.purge`); search reads a held file's size only when it
    names a size;
  - badges and their words are worked out from what a tile already holds, with nothing fetched,
    indexed or watched.
- **Checked:**
  - `scripts/test.sh`: 397 tests in 47 suites pass (363 in 44 before), with new suites for the strip's
    gestures, badge words and badge text, and new tests for the card layout.
  - `--snapshot-panel` renders 94 states and `--snapshot-ui` 38, each in Light, Dark and both with
    Increase Contrast (376 and 152 PNGs). New among them: the shallow and full fold with 2 and 5
    medium, 3 small, 3 large, 2 small and 5 large cards beside the usual three; 5 large cards on a
    1024 pt display; the strip scrolled to its middle and to its end; the tile gallery with times at
    each card size; the kinds with times in both depths; a search for "md over 50 kb"; and Settings
    → Notch at full length with each choice.
  - The contrast of text on every hue and its hover, worked out from Theme's tones. In the shipped
    fold (dark) primary text is at least 10.13:1, secondary 4.57:1, code's keywords and strings 5.44:1
    on violet, and the Tuck blue capsule 3.86:1 off the ground. Across all four appearances the floors
    are 8.37:1 (dark with Increase Contrast), 4.57:1, 4.75:1 (light) and 3.86:1. Before, secondary text
    fell to 3.88:1 on the dark orange hover, though the old entry gave 4.81:1, measured on the fills
    alone. Code's numbers were drawn at 85% of the string colour, which fell to 3.88:1 on a light
    hover and 4.46:1 on a dark hover with Increase Contrast; they now take the strings' own tone, so
    they meet the strings' floor.
  - Each hue's OKLCH lightness and chroma, worked out from the same tones.
  - `git diff --check` is clean.
- **Checked live** on the test Mac, with no notch, so the bubble's fold; it shows
  always-on scroll bars, as a Mac with a mouse does, and its scrolls are wheel events, which are
  never swipes. The library held 43 real clips: a colour, a link, an email, a phone number, an
  address, a date, an emoji, text, code, a PNG image, a 12 MB video, a PDF, a text file and a folder.
  - The shallow fold opens from the bubble on a row of three and "43 in all". A sideways wheel scrolls
    the strip, and the fold neither deepens nor closes; "43 in all" deepens it.
  - The hues read apart on a real display: violet code, green files and folders, olive video and
    pictures, orange date, rose email, teal phone, blue link, gold emoji.
  - The badges on real files: "TXT · 12 bytes", "PDF · 307 KB", "MOV · 12.6 MB", "PNG · 7.9 MB",
    "Folder · 2 items", with the sizes there when the fold opened. A tile's tooltip begins
    "TXT · 12 bytes · copied at 11:12 AM".
  - Search: "png" becomes a PNG chip and finds the one image. "over 10 mb" becomes Over 10 MB and
    finds the video but not the 7.9 MB image. "pdf this morning" becomes PDF, This morning and the
    Files kind, and finds notes.pdf.
  - Show when each was copied, turned on with the fold open, puts the times on every tile at once.
    Where three badges don't fit, the type's narrows to its icon, and small cards keep two.
  - Cards in a row and Card size, changed with the fold open, resize it at once and keep it centred.
    Five medium cards make it about 878 pt wide, and five large about 1144 pt on the 1280 pt display;
    the fold grows taller once its outline has animated. Three small cards narrow it until the lenses
    drop their counts.
  - Found and fixed there:
    - The strip's `.scrollIndicators(.hidden)` still shows a scroll bar when a mouse is attached. That
      bar took about 15 pt of the strip's height and clipped every card top and bottom, badges
      included. The full fold's bar cut its right-hand column short too. The strip now never shows
      one, and the full fold's list shows only the bar that floats over its rows.
    - Show when each was copied was saved but not applied at launch, so the times came back only
      once another setting changed.
    - On a small card, the address pin sat across the street's name; it is smaller and higher there.
- **Not checked live** (from the branches' reports):
  - any trackpad swipe, since the test Mac sends only wheel events: a sideways swipe over the
    strip scrolling it with momentum and never deepening or closing the fold, even drifting down
    part-way; a swipe down over it deepening and up folding; a diagonal swipe following the axis it
    started along;
  - shift and the wheel, and a sideways wheel, scrolling the strip, and a plain wheel as before;
  - a click, a double-click paste, a drag out (a stack's several files too), the context menu, and a
    window group, stack or edit opening under the strip, with badges over part of the tile;
  - deepening from a scrolled strip without a jump in the first row, and the fades at the start, the
    middle and the end;
  - Cards in a row and Card size changed before opening the fold, and the drop target, search and
    prompts following a new width;
  - large cards' thumbnails sharp on a Retina display, 5 large cards on a 1440 pt display, the notch's
    fold, and 2 small cards' lenses and title;
  - Show when each was copied turned off with the fold open, and what VoiceOver says;
  - real files: a large stack summed, a deleted file without a size;
  - the capsule hiding the badges; addresses with real maps, colours, flags and initials on small
    cards; the strip with times at 2, 3 and 5 cards; a 24-hour clock;
  - the dark hover still noticeable at 5%, the deepest teal and green reading as cards rather than
    glowing on a real display, and the Tuck blue capsule on sky and blue tiles;
  - CPU and memory at rest.

## 2026-11-08: The notch greets without opening, the fold is black, and tiles show only what they hold

**Superseded in part** by "2026-11-09: Light cards, badges on every kind with the app's icon, the
bubble's lone mark, and page pictures". The bubble on a display without a notch shows the mark alone,
with no dot, and pointed at, the Tuck arrow takes the mark's place.

**Superseded in part** by "2026-11-09: Twelve hues, a row of cards that scrolls sideways, and badges for
type, size and time". Tiles wear badges again: a file's type and size and, when Settings asks, the time
it was copied. The shallow fold is one row of the whole stream that scrolls sideways, with "N in all"
under it rather than "N more", and Settings → Notch chooses how many cards sit in a row and how big,
the fold as wide as the row. Tiles take one of twelve hues of equal lightness by kind in place of
graphite with a little of six.

- **Decision:** the closed notch, the fold's look and what a tile does change. Three branches
  built it (the notch; pasting and clearing; the tiles), and the build they merge into
  becomes Tuck.
  - **Pointing never opens Tuck.** A click, a two-finger swipe down, the shortcut or the menu does.
    The hover dwell, its grace close and the bookkeeping that kept a fold opened by pointing open
    (`Trigger.hover`, `closesOnPointerExit`, `keepOpen()`, the panel's `onPointerDown`) are gone.
    Pointed at with nothing in Tuck, the surface says "Drop into Tuck" and opens nothing. A drag near
    the notch still widens it into the drop target, and nothing opens.
  - **The closed notch has no count.**
    - The left wing shows the mark, faint at rest, with a small Tuck blue card in its dip while Tuck
      holds a window or an item, as the Dock's Trash shows it holds something. The right wing shows
      a 6 pt grey dot. Copies alone still leave a notch bare; the bubble on a display without a notch
      always shows the mark and the dot.
    - Pointed at while Tuck holds something, the mark makes its greeting (the dip reaches down and
      springs back over 0.5 s, the card 0.035 s behind it) and its line lights in Tuck blue. The dot
      shrinks away as the Tuck button's 20 pt arrow rises in its place. Moving away puts them back.
    - A click on the arrow tucks the window in front, as Tuck Front Window does, without opening the
      fold (`tuckFrontWindow()`). The arrow shows only while the mark does, with no drop prompt
      showing, and while the licence allows features; once the trial has ended the dot stays, and a
      click there opens the fold.
    - A deposit swells the mark (to 1.12 over 0.24 s), or drops the card into a mark that had none. A
      refusal shakes the mark, the dot and the arrow together.
    - Under Reduce Motion the mark only lights; the card, the dot and the arrow fade.
    - The setup tour's pretend notch does the same, and pointing at it opens nothing. A click
      anywhere on it, the arrow included, opens the pretend fold, since the tour teaches tucking from
      the fold.
  - **The fold is black**, as the notch is, in Light and Dark alike. `SurfaceView` fills black closed
    and open, and the fold's SwiftUI host is always `darkAqua` (`Theme.notchAppearance`), so the fold
    is always drawn dark. The tour's pretend fold is black too.
  - **The full fold takes the keyboard.** However it is unfolded, `unfold()` asks for key focus
    (`requestKeyFocus`) without activating Tuck, so its list scrolls at once, with no click first.
    While it is open, typing goes to the fold rather than the app in front, and a search or edit field
    takes it; Escape folds, then closes, and closing hands the keyboard back. A shallow fold takes key
    focus only when opened from the keyboard or the menu.
  - **One accent, Tuck blue:** the logo's #7299C5 on the black, #9CBEE3 with Increase Contrast
    (`Theme.accentNSColor`, which keeps deeper tones for light ground), in place of the system blue.
    Settings and setup still use the system accent (`Color.accentColor`).
  - **Tiles sit on graphite, tinted by kind** (`TileTint`, read through `Theme.tileFill(for:)`):
    purple for code, blue for links, rose for emails and contacts, green for phone numbers, music and
    audio, orange for dates and emoji, teal for files, folders, paths and stacks, and plain graphite
    for everything else. Music is green because purple is code's. A colour, an image or a map still
    fills its own tile. A tile has an edge only with Increase Contrast.
  - **A tile shows only what it holds.** No face gives where a thing came from, when, how big or what
    kind it is; those are in its tooltip and what VoiceOver says. The footer is gone, and so is an
    app tile's window count. What a click did shows for a moment as a small Tuck blue capsule at the
    tile's bottom trailing corner (`FeedbackBadge`), ringed in the tile's own ground so it reads cut
    out of the words under it. A resting app's icon is desaturated and faded, VoiceOver adds
    ", rested", and Rest stays in the tile's context menu; the Rested tag and the hover control to rest
    or wake an app went with the rows.
  - **A link shows its whole address**, scheme and all, its site brighter than the rest, over up to
    three lines, shortened in the middle when it is longer.
  - **People show as initials** (`ContactBadge`): up to two letters, from an email address's name
    part split at dots, dashes and underscores (a "+tag" left out), or from a contact's first and last
    words. They sit on one of six colours (Tuck blue, then purple, green, orange, rose and teal at its
    lightness), picked by an FNV-1a hash of the lower-cased address, or the name without one, so the
    same person keeps the same colour between launches and Macs. The letters are in ink or white,
    whichever contrasts more.
  - **Phone numbers** (`PhoneNumberFormat`) are grouped as their country writes them ("(415)
    555-0132", "20 7946 0958"), with the calling code small above when it was written with one, and
    the country's flag in a circle (a handset when the country isn't known). A number without a code
    is read as ringing in the Mac's region; on +1, the area code tells Canada from the US, and on +7
    the first digit tells Kazakhstan from Russia. Only the showing changes: what is copied, dialled or
    texted is the digits as copied.
  - **The shallow fold is one row of three tiles,** the newest three, in the same `StreamTiles` grid
    as the full fold (`FoldDepth.peekRows` is 3), so unfolding only adds rows under it. Fewer than
    three sit from the left, where the newest is, so no tile moves when another arrives. "N more"
    stays under them. `StreamRow`, `HeldItemRows.swift` and `ItemKindPresentation` are gone.
  - **A double-click pastes.**
    - Double-clicking a copy, or held text, a link or a music link, copies it (a link's address as
      text), closes the fold and hands back the keyboard. 0.15 s later one ⌘V is posted at the session
      event tap (`SystemPaster`), if the app that was in front when the double-click landed is still
      in front, Accessibility allows it, and none of Tuck's own text fields holds the keyboard.
      Otherwise it stays a copy, and the fold says "Copied · paste with ⌘V", or "Copied · allow Tuck
      in Accessibility to paste here" without the grant. Held files and stacks don't paste.
    - The key posted is the one that types "v" with ⌘ held, looked up for each paste with
      `UCKeyTranslate` in the layout in use, then in the ASCII layout macOS falls back to for
      shortcuts, then `kVK_ANSI_V`, so a paste lands on Dvorak, AZERTY and layouts that switch to
      QWERTY under ⌘.
    - The keystroke is behind `KeystrokePasting`; snapshots, tests and any model made without the real
      keyboard get `NoPaster`, which never types.
    - A click on a copy still copies at once, but its move to the top waits one double-click
      interval, so the second click lands on the same tile; another copy in the meantime moves the
      waiting one first. A click on a held link or text item waits a moment, in case it is a
      double-click, before it opens or copies. Double-clicking held text used to edit it; Edit is in
      its context menu.
    - Tooltips name the app a double-click pastes into, and VoiceOver has a Paste into <App> action.
  - **Each section clears on its own.** The full fold's last row is Clear: with no lens on, a menu of
    Clear Windows…, Clear Files… and Clear Copied… (while clipboard history is on), each greyed out
    while its section is empty; with a lens on, that section's one button (`SectionClearRow`). The
    fold's context menu offers the same three in either depth (`SectionClearItems`); the shallow fold
    has no Clear row. Each asks first, at the foot of the fold (`SectionClearing` has the words).
    - Clear Windows… replaces Restore All Windows… and works for one window too. It asks "Put back all
      N windows?" ("Put back the tucked window?" for one), with Put Back All or Put Back, and never
      closes a window.
    - Clear Files… replaces Clear Held Items… and asks as before (`ClearPlan`).
    - Clear Copied… now asks "Clear all N copied items?", with Cancel first; Escape cancels it, as it
      does the other prompts. Settings → Held → Clear Clipboard History still empties the history at
      once.
  - **Kind chips before a search.** With more than one kind in the stream, the full fold shows the
    kind chips under its top line before any search, each with how many it holds, as many as fit. A
    click opens the search with that kind's word and a space already typed, so what you type next
    narrows it. The chips are worked out in one place, TuckCore's `SearchChips`, before a search and
    during one.
  - **Found along the way:** `NSAppearance(named: .accessibilityHighContrastAqua)` and its dark twin
    hand back the plain appearance, so every Increase Contrast snapshot, the panel's and Settings', had
    been drawn in the ordinary tones. A DEBUG-only `snapshotsIncreaseContrast` switch in `Theme`, set
    by `PanelSnapshots`, makes the panel's contrast shots use Theme's contrast tones. Settings'
    snapshots don't set it.
- **Why:** I wanted each of these. A fold that opens only when asked never covers what the
  pointer was on its way to, and the lit mark and arrow still answer the pointer. One black from the
  notch into the fold makes them one object. With nothing on a tile but the thing itself, tints and
  faces tell kinds apart, and the details are still a hover away. A double-click is the shortest way
  from a copy to where it is going.
- **Lightweight:**
  - nothing new runs while Tuck is closed, and pointing no longer arms a dwell or a grace close. The
    mark, card, dot and arrow are Core Animation layers with implicit animations; the card's wait is
    one work item, armed only by a deposit;
  - a paste is one work item and one ⌘V per double-click, with the key looked up then, not watched;
  - a copy's wait to move to the top is one work item, replaced by the next click;
  - initials, badge colours, flags and phone grouping are worked out in TuckCore from the text alone,
    with no Contacts lookup and nothing fetched or stored.
- **Checked:**
  - `scripts/test.sh`: 363 tests in 44 suites pass (343 in 40 before), with new suites for contact
    badges, phone numbers, search chips and section clearing.
  - `scripts/build-app.sh` builds a 3.2 MB app.
  - `--snapshot-panel` renders 71 states and `--snapshot-ui` 36, each in Light, Dark and both with
    Increase Contrast (284 and 144 PNGs; Settings' and setup's contrast shots still show the ordinary
    tones, as above). They include the closed surface at rest, pointed at and taking a deposit, the
    bubble, the black fold in both depths, every kind as a tile, the chips before a search and after a
    click on one, each lens's Clear button, the Clear Windows prompt for one and for three windows, the
    Clear Files and Clear Copied prompts, and the tour's pretend notch and fold.
  - The contrast of text on every tint, worked out from Theme's dark tones: primary text at least
    10.49:1 and secondary at least 4.81:1. Tuck blue is 7:1 on the black.
  - `git diff --check` is clean.
- **Not checked live** (none of this was tried on the test Mac):
  - pointing at the notch for a while without it opening, the greeting and light, and the dot giving
    way to the arrow and coming back;
  - a click on the arrow tucking the window in front;
  - the black fold in Light and in Dark, and the full fold scrolling straight after a swipe, "N
    more", ⌘F, the shortcut and the menu, with typing going back to the app in front once it closes;
  - a double-click pasting into TextEdit, on Dvorak and "Dvorak – QWERTY ⌘", with the search field
    focused, and without Accessibility;
  - a copy moving to the top only after the double-click time, and a held link's click waiting;
  - the caret after a chip's word, the Clear menu's items greyed out while their section is empty,
    and Escape on the Clear Copied prompt;
  - whether "Pasted into <App>" is seen: it is set after the fold has closed;
  - VoiceOver;
  - CPU and memory at rest. The README's figures are from before these branches.

## 2026-11-08: Main's every-kind clipboard joins the one stream: rows by kind, tiles three to a row

**Superseded in part** by "2026-11-09: Link previews are always on, a link without a picture shows its icon and title, and words over a picture always read": Online previews is no longer a setting; links and addresses are
looked up whenever clipboard history is on.

**Superseded in part** by "2026-11-08: The notch greets without opening, the fold is black, and tiles
show only what they hold". The shallow fold shows one row of the newest three tiles, the same tiles as
the full fold, rather than rows; `ItemKindPresentation` went with the rows. Tiles sit on graphite tinted
by kind, on a black fold, rather than on the paper, and show no footer: an app's tile no longer says how
many windows, and a resting app's icon is faded without a moon. A link shows its whole address. A
double-click on held text pastes it rather than editing it (Edit is in its context menu), and the kind
chips show before a search too.

- **Decision:** `main`'s clipboard work (every kind, tiles and search, and the white app-icon line) is
  merged into the redesign by hand, and the merged build becomes Tuck.
  - **Kept as the redesign built them:** the one stream in three depths, the lenses, the sessions
    migration and its backup rule, the single drop target, and the notch's open and close motion.
  - **Kept as `main` built them:** capture of every kind, recognition (`ContentClassifier`), what is
    learned later (`ClipboardEnricher`), `ClipboardAssetStore`, persistence, each kind's actions
    (`KindActions`) and drags (`ContentDrag`), and both switches in Settings › Held: Read text in
    copied images (on) and Online previews (off by default). `main`'s `clipboard-history.json` format
    is the one written; the redesign changes nothing in it.
  - **State 1, rows by kind.** The shallow fold keeps one-line rows. Each shows its kind as `main`
    recognises it, from one place, `ItemKindPresentation`, which reads a `TileContent` for a copy and a
    held item alike:
    - a colour shows its swatch, an emoji itself;
    - a link its favicon (once online previews fetched one, else the app that opens it), title and
      domain; music its service;
    - code its language, in a code face; a key masked;
    - a contact its name; a date, an address or a phone number its recognised form;
    - an image or a screenshot a 20 pt thumbnail, a file its icon, a stack its count.

    A copy's and a held item's menu (`ClipboardMenuItems`, `HeldItemMenuItems`) are shared by its row
    and its tile.
  - **State 2, tiles three to a row.** In the 540 pt full fold `main`'s tiles replace the rows: each
    (content width − 2 × 6) / 3 = 170 pt wide and 70 pt high, 6 pt apart, 10 pt corners, on the fold's
    paper (`TileChrome`).
    - **An app's windows are one tile** (`WindowGroupTile`): its icon and name, the newest window's
      title, and how many windows. Its footer drops the age before it would truncate, and a resting
      app's tile is greyed with a moon. One window restores on a click (⌘-click opens its placements
      under the row). Several open their titles full width under the row (`WindowGroupContents`, with
      Restore All and Hide), and each title restores its window. Several apps can be open at once. No
      tile gives a window's size. A tucked window's card lands on the tile's icon (`WindowLanding`).
    - **Text opens to edit and a stack opens its files**, full width under the row and scrolled into
      view. Arrange windows stays the last row.
  - **Search is in State 2 only**, on `main`'s `SearchQuery`:
    - kind and day words become chips that can be taken out, and the words left must all appear,
      ignoring case and accents;
    - each kind's chip counts what the query finds with its kinds left out;
    - with a lens on, if nothing in it matches but something elsewhere does, the lens steps aside.
      Otherwise "No matches" says where else the words were found ("Found as …", "Found on other
      days: …"), with a click that leaves the kind or day out;
    - ⌘F through a lens that holds nothing lets the lens go and searches everything. With nothing in
      Tuck, ⌘F says there is nothing to search yet rather than unfolding onto nothing.
  - **Privacy wording.** The README, guide, architecture, privacy policy, About and setup's clipboard
    choice say Tuck is offline unless you turn on online previews. About no longer mentions sessions,
    and the privacy policy describes the one stream and the sessions backup.
  - **Fixed along the way:**
    - a plain-text file's thumbnail has a hairline edge (`ThumbnailEdge`), so a white page doesn't
      vanish in light mode with Increase Contrast;
    - comments that still named the Clipboard page or the front-window bar now name the stream and the
      Tuck button;
    - `--snapshot-ui` renders Settings and setup with Increase Contrast too;
    - the app never handed the model its clipboard asset store, as `main` didn't either, so a copied
      image's tile and row showed only the checkerboard, Keep on a copied image failed, and styled text,
      page icons and maps didn't draw outside snapshots. `AppDelegate` now hands it over;
    - search opened from the magnifier took typing only once the field was clicked (⌘F was fine);
      the field asks for the caret again a moment after it appears;
    - a chip that is on could be squeezed to "Li…" when a row filled; chips are measured in their
      font, not estimated, and never shrink;
    - with no main menu, ⌘A, ⌘C, ⌘V, ⌘X, ⌘Z and ⇧⌘Z did nothing in the search field and the text
      editor; `OverlayPanel` now sends them to the field.
- **Why:** I wanted one Tuck with both branches' work. Main's tiles show what a copy is better
  than a row can, and the full fold is wide enough for three of them. The shallow fold is a glance, so
  it keeps one line each, now saying what each thing is.
- **Lightweight:**
  - thumbnails and pictures load in a `.task` only while the fold is open;
  - `ItemDetails.purge`, which also empties `ContentKinds`' cache, runs as the fold closes;
  - the SwiftUI host is built as the fold opens and released as it closes;
  - no new timers or polling: capture keeps `main`'s one 0.5 s change-count check, only while
    clipboard history is on.
- **Checked:**
  - `swift build` and `scripts/build-app.sh` build cleanly; the app is 3.4 MB, from `main`'s 3.5 MB.
  - `scripts/test.sh`: 343 tests in 40 suites pass.
  - `--snapshot-panel` renders 64 states and `--snapshot-ui` 36, each in Light, Dark and both with
    Increase Contrast (256 and 144 PNGs). They include every kind as a row and as a tile, an open
    editor, stack and app's windows, searches with chips, a lens stepping aside, "No matches" with its
    hint, and ⌘F through an empty lens.
  - On the test Mac, with the release build, these real copies:
    - Each of these shows its kind in the shallow fold and its tile in the full fold, three to a row:
      text from TextEdit; a link from Safari, with its compass icon and domain; a screenshot, with its
      picture once the asset store was handed over; a Finder file, with its icon; a hex colour, as a
      swatch with its rgb; and an emoji, as "Party popper".
    - The library and clipboard history from before the merge came through a relaunch.
    - "images today" gives the Today and Images chips and the one image.
    - "links", typed after ⌘F and after a click on the magnifier, gives the Links chip, on and whole
      ("Links 2 ×"), the two link tiles, and the other kinds' chips with their counts.
    - "images todalinks" gives "No matches" with its hint.
    - ⌘A, ⌘X and ⌘V work in the search field.
    - Online previews is off until turned on. Turned on, a link copied from Safari's address bar gets
      its page title ("MacBook Pro") and icon in its row and its tile.
    - The test Mac's Tuck settings and library were restored afterwards.
  - `git diff --check` is clean.
- **Not checked:**
  - tucking, restoring and arranging windows on the test Mac: the build there has no Accessibility
    grant ("Allow Tuck" shows), and none was given for this test;
  - opening a held note to edit, and a stack's files, on the test Mac, whose library held neither
    (both are in the snapshots);
  - an address's map with online previews on;
  - VoiceOver;
  - CPU and memory at rest for the merged build. The README's figures are from before it;
  - in off-screen snapshots the Images chip's symbol draws white. On the test Mac it draws
    correctly, so only the snapshot is affected.

## 2026-11-08: One place, one fold: the simplification redesign

**Superseded in part** by "2026-11-08: The notch greets without opening, the fold is black, and tiles
show only what they hold". Pointing at Tuck opens nothing, on the notch and on the setup tour's: the
mark greets and lights, and the dot gives way to the Tuck button's arrow. The closed notch shows the
faint mark, its card and a grey dot, with no count. The fold is black and drawn dark in Light and Dark,
the accent is Tuck blue rather than the system blue, and the shallow fold shows the newest three tiles
rather than four rows. Clear Windows…, Clear Files… and Clear Copied… replace Restore All Windows…,
Clear Held Items… and Clear Copied, and each asks first.

**Superseded in part** by "2026-11-08: Main's every-kind clipboard joins the one stream: rows by kind,
tiles three to a row". The full fold shows the stream as tiles, three to a row, with an app's windows
as one tile, rather than rows; the shallow fold keeps rows, each now showing its kind as main
recognises it. Search reads kind and day words with main's `SearchQuery`, not a plain word filter.

- **Decision:** Tuck becomes one temporary place, shown in three depths, following a
  plan to simplify it, in the Line Apps' shared design language. The notch's own open and close
  animation is unchanged.
  - **Three depths instead of a panel** (priority 1).
    - **State 0, at rest.** An empty Tuck on a notch is the bare notch. Holding something, the round
      U mark sits on the left wing and the count on the right, both in Tuck blue; past 99 the count
      reads "99+". Without a notch the bubble shows a faint mark when empty, and the mark and count
      otherwise. No text and no controls.
    - **State 1, the shallow fold.** Pointing at a Tuck that holds something opens it after 0.35 s
      (a click opens it at once). It is 540 pt wide and shows the first four rows of everything,
      newest first, with an "N more" row under them. Level with the notch, the Tuck button (the window
      in front, with its app's icon) sits on the left wing, and one cluster of lenses, Windows, Files
      and Copied, hugs the notch on the right. Copied appears only while clipboard history is on.
      A lens narrows the rows to its kind and a second click returns to Everything; there is no "All".
      Pointed at, the fold closes again as the pointer leaves, unless it was clicked in, unfolded, or is
      showing a prompt, chooser, picker, edit or search.
    - **State 1, empty.** An empty Tuck opens nothing when pointed at. The closed surface says "Drop
      into Tuck" instead. Opened on purpose (click, shortcut, menu), the fold is one line high, with the
      same faint cue.
    - **State 2, the full fold.** One more swipe down, a click on the "more" row, or ⌘F opens it. The
      lenses recede and the notch row becomes one quiet line: "Everything in Tuck" on the left, search
      and a fold chevron on the right. The search field takes a row only once invoked. The list scrolls,
      with hairlines between rows, up to the smaller of 440 pt and the screen's height less the menu bar
      and 280 pt (never under 180). **Arrange windows** is the last row: the front window's placements.
    - **Choose Windows to Tuck…** (from the band's or the Tuck button's context menu) replaces the list
      with the picker until it is done or cancelled.
  - **No sessions** (priority 2).
    - `TuckLibrary` replaces `SessionLibrary`: windows and held items, each newest first, and the Rest
      state of apps. Sessions, Loose, archiving, session colours and intentions, and the sideways swipes
      between them are gone, with the Sessions pane, the session style setting, the intention chooser
      and the Tuck hint.
    - **Nothing is lost on the way.** A format 1 library is merged as it loads (`LegacySessions`): every
      window and item from every session, archived ones and Loose included, newest first. The file is
      first copied byte for byte to `library-sessions-backup-<stamp>.json`, and only then is the stream
      saved over it as format 2. If the copy can't be written, Tuck shows the merged stream but saves
      nothing that run, and the next launch migrates again from the untouched file. Session names,
      colours and intentions are not carried over; the backup keeps them. Samples from earlier versions
      are taken out as the sessions merge, as before. A library from a newer Tuck, or one that can't be
      read, is set aside, not migrated. Uninstall's code is unchanged: `SupportFolder` counts the backup
      among Tuck's own files, so Uninstall removes it with them.
    - Clipboard history was never per session and stays where it was. While it is on, copies join the
      stream by date.
    - The held-item limit is 200 rows for the one stream. A migrated library may hold more; nothing is
      taken out, and new drops wait for room.
  - **Rows** (priority 3).
    - One line per row beside a 20 pt picture, two lines for text. Hairlines between top-level rows.
    - An app's windows share one row: its icon, name and count. One window restores on a click. Several
      open, on a click, to **titles only**. No row, tooltip or VoiceOver label gives a window's size;
      tooltips say when it was tucked, from which display, and "click to restore · ⌘-click to place".
    - Held items: text in two lines, a link's title with its domain, a file's name truncated in the
      middle, a stack opening to its files. Copies: two lines; a click copies again, a drag forwards.
    - What a row shows for a kind comes from one place, `ItemKindPresentation`, so a finer classification
      changes rows in one spot.
  - **One step deeper, one step back** (priority 4). On the surface and in the fold, a two-finger swipe
    down goes one depth deeper (tucked away, closed, shallow, full) and a swipe up one depth back.
    Sideways does nothing. A gesture that starts over the full fold's scrolling list scrolls it; the
    shallow fold doesn't scroll, its "more" row opens the rest.
  - **Search and Arrange only in the full fold** (priority 5). Search filters as you type, locally, by
    every word: app names, window titles, text, file names and folders, a stack's files, link titles,
    domains and addresses, the app an item came from, and copied text, ignoring case and accents.
  - **One drop target** (priority 6). A drag near the notch widens it into one target with an icon and
    "Drop file into Tuck", "Drop link into Tuck" or "Drop text into Tuck", read from the drag's
    pasteboard types as it starts. A drag no longer opens the panel; over an open fold, the whole fold
    is the target and says the same. On release the item compresses into the mark and the count rises.
  - **Look.** Warm paper, stone and hairlines in light, near-neutral charcoal in dark, each with an
    Increase Contrast tone. One accent, the system blue (#007AFF / #0A84FF), used for the mark and
    count, focus, a selected lens, the drop target and the deposit. No colour per session, kind or app.
    The fold is rounded 20 pt, controls 10. System type throughout.
  - **Motion and haptics.** Fold 0.26 s and settle 0.24 s, ease out. A deposit flies for 0.24 s, and
    the rows and count it lands in settle on a 0.48 s spring with almost no overshoot. Reduce Motion
    turns each into a short fade or a direct change. Haptics play only for a drag crossing into the drop
    target, a deposit (into the mark, or into its row with the fold open), and a window snapping to a
    placement; going back to its original frame is quiet, as a plain restore is. Opening, closing and
    paging no longer tick.
  - **Type-aware items are main's** (priority 7). `main` is building a content classifier, a search
    query parser, rich clipboard capture and per-kind rows. This branch builds none of them and keeps a
    plain word filter, so that work lands on `ItemKindPresentation` and `TuckStream`'s search at merge.
    `ClipboardHistory` and its file are untouched here, so `main`'s richer entries decode as they do
    there.
  - **Open questions, answered closest to the simplification plan:**
    - The Tuck button stays on the shallow fold's left wing. The simplification plan asks for no visible
      actions on the peek, but tucking the window in front is Tuck's first job and has no other
      one-click home.
    - The full fold's quiet line sits in the notch row rather than a new row under it, so the fold gets
      no taller than it needs.
    - The lens cluster shows counts when they fit beside the notch and drops them to the tooltip when
      they don't (`ViewThatFits`).
    - The bubble draws its mark in the band's middle, where a notch would be.
    - Clear Held Items…, Restore All Windows…, Clear Copied, Choose Windows to Tuck… and Settings… live
      in the band's context menu, not on the fold.
    - A status line shows under the list only while there is one.
    - Copies alone leave the notch bare and uncounted: they arrive by themselves, not because they were
      put down. Pointing at the notch still opens the fold to show them.
    - Clear Copied clears at once, as the Clipboard page's Clear did; Settings' Clear Clipboard History
      is the one that warns.
    - Setup's tour keeps the Haptic feedback switch, above the pretend screen, where a drop can be felt;
      the gestures step lost its haptics row, since swipes no longer tick. On the tour, pointing opens
      and leaving closes, as on the real notch; the gestures step leaves pointing alone so only swipes
      count there. A click on the pretend notch only opens it, and one on its desktop closes it. Its
      lenses follow Tuck's: Copied appears only while clipboard history is on.
    - VoiceOver reads the closed surface as "Tuck" and its contents ("2 windows, 3 items", or "Empty");
      announcements put "Tuck, " first.
- **Why:** the old panel was taller, segmented into pages and sessions, and asked people to organise
  what they were only putting down for a moment. The simplification plan asks for one stream, a fold that
  gets wider before it gets taller, and controls that appear only when they can be used.
- **Checked:**
  - `swift build` and `swift build -c release` show no warnings, and `scripts/build-app.sh release`
    builds the app.
  - `scripts/test.sh` passes 307 tests in 37 suites, down from 311 in 40.
    - The four session suites and the Tuck hint's went with what they tested.
    - `StreamTests` and `SessionsMigrationTests` are new.
  - `git diff --check` is clean.
  - The sessions migration:
    - unit tests cover the bytes `main`'s build writes, and a folder the backup can't be written to;
    - on the host, a library that a small program on `main`'s TuckCore wrote, read by this branch in
      a scratch folder, kept its 4 windows and 6 items, and its backup is byte-identical.
  - On the test Mac, `main`'s build saved 4 files across three sessions (Work, Personal, Study) and 2
    copies. This branch's release build then read them:
    - all 4 files and both copies showed in the one stream;
    - `library-sessions-backup-….json` is byte-identical to `main`'s file, and the library was
      rewritten as version 2;
    - `clipboard-history.json` was left untouched;
    - after a drop and a quit, the saved library held the dropped file as well.
  - On the test Mac, also checked:
    - the count on the bare notch, the shallow fold with its lenses, and the full fold with search;
    - the Files and Copied lenses, a drop from Finder, and the menu-bar menu;
    - all of it in light, dark, and Increase Contrast, and the fold opening with Reduce Motion on.
  - Off-screen snapshots (`--snapshot-panel`, `--snapshot-ui`) of every depth, drop label, row kind,
    and setup step, in light, dark and Increase Contrast, and with an empty Tuck, one item, several
    Safari windows, mixed items, and more than fifty rows.
  - One flaw seen, left for `main`'s per-kind rows: a plain-text file's thumbnail is a white page with
    no edge, so in light mode with Increase Contrast it disappears into the fold.
- **Not checked:**
  - Tucking, restoring and arranging windows on the test Mac. They need the Accessibility grant, and
    the test Mac asks for an administrator password to give it. The Tuck button, the window rows and
    Arrange are covered by tests and snapshots only.
  - The drop label during a real drag: the test Mac's drag lands at once, so only the result shows.
  - The timing of the motion with Reduce Motion on, haptics (no trackpad on the test Mac), and
    VoiceOver.
  - Idle CPU and memory, which were not measured again.
- **Merge risks:**
  - `main`'s content classifier, search query parser and per-kind rows replace this branch's plain word
    filter and `ItemKindPresentation`'s kinds; its header search field has to become the full fold's
    quiet line and search row, not a field on the shallow fold.
  - Both branches edit `HeldItemRows.swift`, `ExpandedPanelView.swift`, `TuckModel.swift`, the clipboard
    history and the Settings panes, so those merge by hand.
  - The white app-icon line on `main` touches the About tile in `SettingsView.swift` and
    `SettingsComponents.swift`, which this branch also edits nearby.
  - Both branches add entries at the top of this log.
  - A library this branch has saved is format 2. `main`'s build sets it aside as
    `library-unreadable-<stamp>.json` and starts empty, so going back means restoring the
    `library-sessions-backup-<stamp>.json` by hand.

## 2026-11-08: The clipboard keeps every kind, in tiles two to a row, and search reads kinds and days

**Superseded in part** by "2026-11-09: Link previews are always on, a link without a picture shows its icon and title, and words over a picture always read": Online previews is no longer a setting; links and addresses are
looked up whenever clipboard history is on.

**Superseded in part** by "2026-11-08: Main's every-kind clipboard joins the one stream: rows by kind,
tiles three to a row". Sessions and the Clipboard and Held pages are gone: copies join the one stream.
Two tiles to a row in the 360 pt panel becomes three to a row in the 540 pt full fold, and one-line rows
in the shallow fold. Search is in the full fold only, and a lens that finds nothing steps aside rather
than the panel moving to another page. Keep in Tuck holds a copy as an item in the stream, not in a
session.

- **Decision:**
  - **Capture of every kind.** `ClipboardCaptureService` reads a copy in this order:
    - **Files.** One file takes its kind from its extension: image, screenshot, audio, video, folder or
      file. Several files are a stack.
    - **An image.** PNG, TIFF, JPEG or HEIC up to 40 MB, taken as the image when the text that came
      with it is only a name or an address.
    - **Then** a colour, a vCard, and text. Text keeps its RTF (up to 512 kB) only when the styling says
      something: bold, italics, a link, an underline or a change of size.
    - **Where pictures and styling go.** Images and styled text are written beside the history as
      UUID-named files in `Application Support/Tuck/Clipboard` (`ClipboardAssetStore`, TuckCore). The
      history names the files it uses, and each save deletes the rest, sparing files under 2 minutes
      old.
    - **Copies again.** The same picture (by the SHA-256 of its PNG) or the same files copied again
      move to the top, like repeated text.
  - **Recognition, once, at capture** (`ContentClassifier`, TuckCore). The first match wins:
    - a contact, a colour, then a key;
    - a link (music links named by provider), an email, a path, an emoji;
    - a date or an address (`NSDataDetector`, only when it is the whole copy), then a phone number;
    - code, by a score (markers, indentation, a shell command on the first line). Copies from
      terminals and editors count as code, and so does one-line JSON;
    - rich text, then text.

    Keys are named ("Anthropic API key") and shown masked. History saved before Tuck recognised kinds
    is recognised as it loads.
  - **Learned later, once** (`ClipboardEnricher`):
    - the words in an image or screenshot, read with Vision on this Mac (Settings › Held › Read text in
      copied images, on by default, for images up to 25 MB);
    - a song's or video's title, artist and length, from the file's own tags;
    - only with Online previews (off by default), a link's page title and icon (LinkPresentation) and
      an address's map (a MapKit snapshot).

    What it learns is saved in the entry's `ClipPreview`, so tiles draw it and search finds it without
    doing the work twice.
  - **Tiles, two to a row,** on the Clipboard and Held pages: 169 × 70 pt in the 360 pt panel, each kind
    with a face of its own (`ContentTiles.swift`):
    - text, plus rich text in its own styling;
    - code: two highlighted lines and the language;
    - a link: its favicon or the app it opens in, the host, and the page title;
    - music: the service's icon;
    - an email: the name, with the domain under it;
    - a phone number: large digits;
    - a colour: the tile filled with it, hex and rgb;
    - a contact: a monogram;
    - a date: a page of a calendar, the weekday, and "In 9 days";
    - an address: a map, or a drawn map;
    - an emoji: large, with its name;
    - a path: a file icon, the name, and its folder;
    - a key: masked;
    - an image or a screenshot: edge to edge, with its size;
    - a video, with a play mark and its length;
    - audio: artwork, artist and length;
    - a file: its thumbnail, kind and size, or "No longer there";
    - a folder, with its item count;
    - a stack: its icons fanned.

    Pictures, colours and maps fill their tile; the rest sit on a card whose last line gives the
    kind's symbol, a detail or the app, and the age. Text being edited and a stack's files open full
    width under their row, and the page scrolls just enough to show them.
  - **Each kind's own actions** in its menu (`TileActions.swift`):
    - open a link;
    - write an email, call or message a number;
    - copy a colour as hex or rgb;
    - copy a contact's name, number or email, or add it to Contacts;
    - open an address in Maps, or get directions;
    - add a date to Calendar;
    - open a path, Quick Look it or show it in Finder;
    - copy rich text as plain text;
    - copy the text in an image, or save the image to Downloads.

    Dragging a tile out gives the original: files, the image, text, or a vCard. Share is never offered
    for a key.
  - **Search** opens from the magnifier in the strip, or with ⌘F, and Esc closes it.
    - **Kind and day words** (`SearchQuery`, TuckCore): "screenshots", "links", "code", "colours" and so
      on pick kinds. "today", "yesterday", "this week", "last month" or a weekday pick a span. The words
      left must all appear, ignoring case and accents. So "screenshots yesterday" or "links safari".
    - **What it searches.** It looks through the page showing: text, file names, the app, the kind's
      name, and what was recognised or learned.
    - **Chips** under the field name the kinds on the page, each counting what the typed words find,
      and a click turns that filter on or off. Return does what a click on the first match does.
    - **No matches on this page.** If nothing on the page matches but another page has matches, the
      panel moves there. Otherwise "No matches here" says where else something was found.
- **Why:** I wanted every kind of copy JustCopy shows to be built for Tuck:
  - a search;
  - a design of its own for each kind;
  - items that fit two to a row, rather than taking a whole row, and still show their preview.
- **Lightweight:**
  - **Capture.** Recognition runs once, at capture, on a background queue, and capture adds no polling
    beyond the existing 0.5 s change-count check.
  - **Learning later.** Each entry is enriched at most once. Online previews are off by default.
  - **The panel.** Thumbnails and pictures load only while the panel is open, and their caches are let
    go on close. The grid is lazy.
- **Inspiration:** JustCopy: its kinds of copy, and type and date words in search. Tuck's tiles, faces,
  chips and layout are its own.
- **Checked:**
  - `swift build`, `swift build -c release`, and `scripts/test.sh`: 342 tests. The new suites cover
    recognition of each kind and its thresholds, search parsing, matching and unpicking, and
    clipboard content: images and files, re-copies, previews, history from before kinds, asset
    cleanup, and uninstall.
  - `--snapshot-panel`:
    - every face, in `tiles-gallery`;
    - the Clipboard and Held pages;
    - an open stack and text being edited;
    - searches with their chips, and a search that moves to the page with a match;
    - in Dark, the Light setting and Increase Contrast.
  - `--snapshot-ui`: Settings › Held with its two new switches, and setup's Choose step.
  - `scripts/build-app.sh`: the app is 3.5 MB, up from 2.8 MB, with Vision, AVFoundation,
    LinkPresentation and MapKit linked. Collapsed after a fresh launch, it uses 12 MB and 0.01 s of CPU
    in 60 s.
- **Not checked:**
  - memory with the panel open on a long history of pictures;
  - capture from real apps on the real pasteboard;
  - Vision and online previews on real copies;
  - dragging each kind into other apps;
  - VoiceOver on the tiles.

## 2026-11-07: The app icon's line is white, as on Pulse's and Hum's

- **Decision:** the app icon draws the line in white (`#FFFFFF`) on its Tuck Blue tile, not in Ink. The
  touch and PWA icons, the About pane's tile (`TuckMark`) and the About pane's sidebar icon follow. Ink
  stays for the wordmark.
- **Why:** Pulse's and Hum's icons are a white line on a coloured tile. With the same treatment the three
  read as one family in the Dock, and the About sidebar icon now matches the other panes' white symbols.
- **Checked:** regenerated with `generate.py` and `render.swift` (`Support/AppIcon.icns`, the PNGs and
  web icons) and re-rendered `board.png`. The `--snapshot-ui` About pane shows the white line, and the
  icon sits beside Pulse's and Hum's on light and dark backgrounds.

## 2026-11-07: The README is a landing page; the guide moves to docs/guide.md

- **Superseded in part:** the panel picture is now the full fold with its coloured cards, not the
  Windows page. See "The README's pictures show the current fold and notch" above.
- **Decision:**
  - **`README.md` is now the repository's front page:** the logo, one line on what Tuck is, a picture
    of the panel, four things it does, a picture of the notch's states, privacy and footprint,
    requirements, three build commands, and a table of the docs.
  - **The guide moved, unchanged, to `docs/guide.md`:** where Tuck lives, setup, the action tables,
    what each feature does and how, permissions, licence and trial, newer macOS and efficiency.
  - **The build commands, debug flags, snapshots, tests and the release summary** moved to
    `docs/development.md`.
  - **The two pictures** in `docs/images/` are composed from the app's own off-screen snapshots
    (`--snapshot-panel`), so they show real UI: the Windows page hanging from the notch on a pretend
    desktop, and the collapsed notch empty, holding, pointed at and with a file dragged over it.
- **Why:** at 490 lines the README had become the whole manual. The repository page should say what
  Tuck is and show it in one screen, and point to the rest.

## 2026-11-06: The trial counts 7 days of use; turning clipboard history off asks first

**Superseded in part** by "2026-11-16: No trial and no licence keys: every feature, for everyone": there
is no trial. Turning clipboard history off still asks first.

- **Decision:**
  - **The trial is 7 days of use, not 7 days from the first launch.**
    - Each calendar day on which Tuck looks counts once: at launch, as the panel opens, as a feature is
      checked. There is still no timer.
    - `TrialRecord` holds those days (`TrialDay`, "2026-11-06", in the Gregorian calendar in the Mac's
      time zone).
    - Today is one of the days left, so the seventh day reads "Trial · Last day" and the eighth ends
      the trial. No days are added after that, so a record holds at most eight.
    - A clock set forward costs the one day it reads. One set back to a day already counted adds nothing.
    - The Keychain and UserDefaults copies merge as the union of their days.
    - The Keychain copy is still deleted and added, never updated. It is now written only when it lacks
      a day the record has.
  - **Records from before carry on.** One holding a first launch and a latest time seen becomes the
    latest day seen. When that day is also the first, it becomes no days.
  - **Turning clipboard history off asks first** when entries are saved, in Settings › Held and in
    setup's Choose step. Keep History turns it off and leaves them as before. Delete History clears them
    as Clear Clipboard History does, set-aside files too. Cancel leaves it on. With nothing saved, the
    switch just turns off.
- **Why:**
  - Under the old rule a clock that read a month ahead once, from a flat clock battery or a virtual
    machine, ended the trial for good. Counting days forgives a wrong clock either way and costs a day
    at most.
  - Days of use also suit someone who tries Tuck on a few days spread over weeks.
  - The old record never kept the days between its two times, so the latest day is the one it is sure
    of. The first day isn't counted because the old rule only ran from the hour the trial began.
    Counting that part day could end a trial begun late one evening a day sooner than before. However
    it is used, a carried-over trial ends no sooner than under the old rule, except one carried over on
    the day it began. That one ends at midnight after its seventh day, as every new trial does, rather
    than at the hour it began.
  - Counting continues while licensed, as the old trial's time did, so removing a licence carries on
    with what is left. The cap of eight keeps both the writes and the record small.
  - What was copied may be private. Someone turning history off may want it gone with the switch, and
    may not know it was kept.
- **Checked:**
  - `swift build` and `swift build -c release`, both from scratch in a separate build folder, show no
    warnings.
  - `scripts/test.sh` passes 311 tests in 40 suites, up from 309. The Trial suite was rewritten, 8
    tests to 10, replacing the test that pinned a forward jump using the trial up. It covers:
    - a forward jump costing one day, and the clock set back adding nothing;
    - the union across copies, the seventh day being the last, and the cap;
    - the old JSON carried over, with JSONEncoder's default dates.
  - `git diff --check` is clean.
  - Snapshots: the Licence pane in trial and ended, the panel's trial-ended scenes, and the clipboard
    prompt (`settings-held-turn-off-…`), drawn as an NSAlert with the same text, since a SwiftUI alert
    doesn't render off screen.
- **Not checked:**
  - The prompt on screen, as a sheet on the Settings and setup windows.
  - A migration on a real Mac's stored record. Only reading was done: both copies of my record
    hold a trial begun and last seen at 23:49 on 2026-11-05, which carries over as no days, so the next
    launch is day 1 of 7.
  - The keychain with a Developer ID build.

## 2026-11-06: The release gate checks the key itself; Move, Uninstall and the trial keychain made safe

**Superseded in part** by "2026-11-16: No trial and no licence keys: every feature, for everyone": there
is no public key to check and no trial keychain item to keep; Tuck deletes one left behind. The fixes to
Move and Uninstall stand.

**Superseded in part** by "2026-11-06: The trial counts 7 days of use; turning clipboard history off
asks first". The clock rule isn't pinned any more: the trial counts days of use, and the test of a
forward jump using the trial up is replaced.

- **Decision:** Fourteen fixes from a review of the sellable changes. The trial rule stays as it was.
  - **The key gate.** `scripts/release.sh` reads `LicensePublicKey.base64` from its one line. It
    refuses any build when that isn't 43 base64 characters and `=` (32 bytes). It refuses a signed build
    while the key equals the development public key, which the script holds. The `isDevelopment` flag
    is gone. `Licensing.system()` no longer force-unwraps the validator: with a damaged key it logs an
    error and reads every licence as not genuine (`Licensing.embeddedValidator()`).
  - **Move to Applications** copies to a hidden name in /Applications first. Only once the copy is
    complete does the old Tuck go to the Trash and the copy take its name. A failed copy is removed;
    a failed rename puts the old one back. Replacing needs the same non-nil bundle ID on both. The
    offer then says Replace and names both versions, with builds when the versions match, and says
    when the installed copy is newer.
  - **The clock rule is pinned, not changed.** A test shows a forward jump using the trial up to that
    time. `docs/release.md` ("Trials and the clock") documents it and the support reset: the
    "Tuck trial" keychain item (service = bundle ID, account `trial`) and the `TrialRecord` default.
    The unused `clockMovedBack` is deleted.
  - **The trial-ended card** asks for Accessibility only when it is off. Otherwise it says the windows
    are on their way, or that some couldn't be brought back, with Try Again.
  - **Uninstall** deletes only what `SupportFolder` (TuckCore) names. The folder goes only once it is
    empty; anything else stays and is listed. Its confirmation says how many files Tuck saved from
    drops and that they may be the only copies, and offers Show Files.
  - **Quit, with windows parked off screen and Accessibility off,** asks first: Open System Settings…,
    Quit Anyway, Cancel. Only the menu item asks, so logout and shutdown aren't held up. The
    Accessibility card says it too.
  - **The keychain never asks.** The trial item is never updated in place. It is deleted and added
    again. A build that didn't make it is refused the delete without a prompt, so UserDefaults carries
    the change. An item that exists but can't be decoded is replaced. Each refusal's OSStatus is
    logged at `.debug`.
  - **Smaller ones:**
    - Content changes are also announced to VoiceOver (`.announcementRequested`, low priority,
      a second after they settle, only while VoiceOver is on).
    - Licence keys keep only base64url characters after `TUCK-`, so a zero-width space can't spoil one.
    - Both scripts stamp Info.plist with `plutil -replace … -string`, not PlistBuddy.
    - `build-app.sh` refuses a dSYM path that doesn't end in `.dSYM` before anything is built.
    - The privacy policy says the licence is checked when Tuck starts and when a feature is used. It
      also covers the keychain's log notes.
    - The "prototype" check ignores case.
    - The build-number example in `ReleaseInfo` is corrected.
- **Why:**
  - A flag next to the key could say "not development" while the key still was. The gate now compares
    the key itself.
  - A force-unwrap of the embedded key would crash a shipped app at every launch. Failing closed keeps
    the trial working and tucked windows coming back.
  - The old Move trashed the installed copy before the new one existed.
  - Uninstall must not delete a folder that isn't wholly Tuck's.
  - An update from a different build (ad hoc test builds, then Developer ID) would show a "wants to use
    your confidential information" prompt. A refused delete shows nothing.
  - I haven't yet chosen between wall-clock days and days of use, so today's rule is pinned
    rather than changed.
- **Checked:**
  - `swift build` and `swift build -c release`, both from scratch in a separate build folder, show no
    warnings.
  - `scripts/test.sh` passes 309 tests in 40 suites, up from 306. New: invisible characters in a key,
    the clock set forward, and Uninstall deleting only Tuck's files.
  - `git diff --check` is clean.
  - `scripts/release.sh --unsigned 0.0.9` still builds and verifies the DMG, and its outputs were
    deleted. The bundle's Info.plist held the stamped ID, version, build and copyright.
  - The key gate's block from `release.sh` passes the development key (flagged as development) and a
    fresh random key (not flagged). It refuses a missing line, two lines and a one-character typo.
  - Keychain, with two ad hoc probe builds and interaction turned off:
    - the second build's read succeeded, its update needed a prompt (refused), its delete was refused
      with `errSecInvalidOwnerEdit`, and its add of a duplicate with `errSecDuplicateItem`;
    - the maker's own delete and update succeeded;
    - adding to the data protection keychain failed with `errSecMissingEntitlement`;
    - `security delete-generic-password` deleted a probe-made item without asking.
  - Snapshots: the trial-ended card with Accessibility off, with it on and windows kept, and the
    Accessibility card.
- **Not checked:**
  - Move to Applications from a real disk image, with and without a Tuck already installed.
  - The Uninstall confirmation and Quit warning on screen (alerts don't render in snapshots).
  - The Accessibility card's quit clause (the sample windows are all minimised).
  - VoiceOver speaking the announcement.
  - The keychain with a Developer ID build.
- **Open:** keep the wall-clock trial or count days of use; replace the development key pair.

## 2026-11-05: Sellable: a seven-day trial, offline licence keys, and Uninstall

**Superseded in part** by "2026-11-16: No trial and no licence keys: every feature, for everyone": the
trial and the licence keys are gone, and every feature works for everyone. Uninstall stands.

- **Superseded in part:** the `isDevelopment` flag is gone: `release.sh` compares the key itself. The
  Keychain item is deleted and added again rather than updated. Uninstall deletes only Tuck's own
  files, and Move to Applications copies before trashing. See "The release gate checks the key
  itself; Move, Uninstall and the trial keychain made safe" above.

- **Decision:** Tuck can be sold. It runs for seven days with everything working, then asks for a
  licence. Ten changes:
  - **Licence keys.** `LicenseValidator` (TuckCore) checks a key; its one adapter,
    `SignedLicenseValidator`, checks an Ed25519 signature with CryptoKit and the public key embedded
    in `LicensePublicKey.swift`. A key carries a licence ID, the licensee and the day it was issued.
    `scripts/make-license.swift` makes a key pair (`--new-keypair`), signs keys (`--to`) and checks
    them (`--check`). The embedded pair is a development pair, marked `isDevelopment = true`. Its
    private half lives at `~/.tuck/development-license.key`, outside the repository, and
    `release.sh` refuses a signed build while that pair is embedded.
  - **The trial.** The day it began and the latest time Tuck has seen are kept twice: in a login
    Keychain item whose dates sit in an attribute and whose secret is empty, and in UserDefaults. The
    copies are merged to the earliest start and the latest time. The rules (`Trial`, `TrialRecord`,
    `LicenseStatus`) are in TuckCore and never read the clock. The app passes the time in at launch,
    as the panel opens and as a tuck is tried, so there is no timer.
  - **When the trial ends.** Tuck wakes every rested app and brings every tucked window back, at launch
    or at the first check that finds the trial over. The panel then shows "Your trial has ended" with
    Buy Tuck and Enter Licence. Tucking, holding, the drop invitation and tuck hint, clipboard
    capture, window drag, smooth scrolling and the reversed wheel stop. Settings, About, Uninstall and
    Restore Last Tucked keep working. Settings has a Licence pane, and the menu-bar menu has Enter
    Licence… and Buy Tuck… until a licence is entered.
  - **About.** It shows the version, build, copyright and links, all from `Support/release.env`.
    `build-app.sh` stamps them into the bundle's Info.plist, with placeholders where they aren't set.
  - **Uninstall Tuck…** is in About, behind a confirmation. Every rested app is woken and every tucked
    window brought back; if anything stays, nothing is deleted and Tuck says why. Then Open at Login
    goes off, the support folder and settings are deleted, `tccutil reset All <bundle ID>` runs, the
    app goes to the Trash and Tuck quits. Whatever it couldn't do is listed for the person to finish.
    Both persistence stores gained `close()`, so no late save recreates the folder. The Keychain
    trial item stays, so reinstalling doesn't start a new trial.
  - **Accessibility withdrawn with windows tucked.** The existing `com.apple.accessibility.api`
    notification now reaches the model as a loss too. The notch refuses with a lock, and the panel
    keeps a card explaining it until the permission is back. If the trial has ended by then, the
    windows come back as soon as it is.
  - **Move to Applications.** Run from its disk image or from a translocated copy, Tuck offers once,
    at launch, to copy itself to /Applications and reopen from there. "Don't Move" is remembered.
  - **Debug-only flags.** `-TuckSupportDirectory`, `-TuckOpenSettingsOnLaunch`,
    `-TuckOpenSetupOnLaunch`, `-TuckOpenTutorialOnLaunch`, `-TuckTrialDaysUsed` and
    `OverlayCoordinator`'s `TuckOpenOnLaunch` block are inside `#if DEBUG`.
  - **VoiceOver.** The closed notch is one button named Tuck whose value is what the space holds.
    Pressing it opens the panel as the keyboard shortcut does, and a change of contents is announced.
  - **Crash symbols.** `build-app.sh` runs `dsymutil` before `strip`. `release.sh` checks that the
    dSYM's UUID matches the binary and zips it beside the DMG in `dist/`, never inside it.
    `docs/release.md` covers `atos` and `symbolicatecrash`.

  Also: "prototype" is gone from user-facing text and the README, and the Experimental badge on Rest
  stays. The privacy policy now covers the 200-entry clipboard cap, the unreadable files set aside
  (which Clear Clipboard History now deletes), the licence key, the Keychain item and Uninstall.
  `EarlierSamples.swift` stays: `FileLibraryPersistence.load` calls it
  (`FileLibraryPersistence.swift:55`) to strip the old sample sessions from libraries saved by
  earlier builds.
- **Why:** These are my decisions:
  - no network, ever, so keys are checked on the Mac;
  - the payment provider is still to be chosen, so it sits behind the validator protocol;
  - tucked windows must always come back.

  Ed25519 keys are short enough to paste, and CryptoKit is a system framework, so there is no
  dependency. Keeping the trial in two places means deleting either one doesn't restart it. Moving
  the latest time only forward means setting the clock back doesn't win days. Uninstall wakes rested
  apps before restoring windows, rather than after as my plan listed, because a paused app
  can't move its windows. It stops before deleting anything because the library is the only record of
  where tucked windows belong. Move to Applications is offered because a translocated path changes
  each launch, and neither it nor a disk image can open at login; asking once keeps it from nagging.
- **Checked:**
  - `swift build` and `swift build -c release` show no warnings.
  - `scripts/test.sh` passes 306 tests in 40 suites, up from 288 in 38. New: licence keys (8), trial
    rules (7), closed stores writing nothing (2), set-aside clipboard files removed (1).
  - `git diff --check` is clean.
  - Off-screen snapshots look right: the trial-ended panel (empty and with tucked windows), the
    revoke card, the notch hover after the trial, the Licence pane in trial, licensed and ended
    states, and About at full length, light and dark.
  - `tccutil reset All` from a shell, for a throwaway bundle ID: it exits 0 for a copy in
    `~/Applications`. For one in `/private/tmp`, which Launch Services hasn't registered, it fails
    with -10814 and exits 64.
  - A Keychain item was added, read, updated and deleted as `TrialKeychain` does it.
  - `scripts/release.sh --unsigned 0.0.9` wrote the DMG and `Tuck-0.0.9-unsigned.dSYM.zip` to
    `dist/`. The DMG holds no dSYM; the zipped dSYM's UUID matches the app in the DMG; and `atos`
    with it turns an address into `Uninstaller.removeEverything(supportFolder:)`
    (`Uninstaller.swift:32`). The three files were then deleted.
- **Not checked:**
  - None of the GUI flows has been run live: the end of the trial, entering a key in
    the pane, Uninstall, Move to Applications, and withdrawing Accessibility with windows tucked.
  - `tccutil` hasn't run from inside a signed, hardened Tuck, so the in-app reset is untried. A
    failure lists the System Settings steps instead.
  - `symbolicatecrash` needs Xcode, which isn't installed.
- **Open:**
  - Replace the development key pair before the first sale.
  - Choose the payment provider and decide whether it issues keys this way or needs its own adapter.
  - A clock set forward at first launch and then back freezes the trial until real time catches up.
    That follows from keeping the latest time seen, as my plan asks.
  - The Keychain item outlives Uninstall on purpose. The privacy policy says so; legal review should
    confirm it.

## 2026-11-05: Packaged for direct sale, as a signed and notarized DMG

- **Superseded in part:** licensing is no longer deferred, and `release.sh` also writes the zipped
  dSYM to `dist/`. See "Sellable: a seven-day trial, offline licence keys, and Uninstall" above.
- **Superseded in part:** the bundle ID is chosen, `com.millerroberts.Tuck`, and the test DMG is signed
  with "Tuck Local Signing" when the Mac building it has that identity. See "2026-11-19: Tuck's own
  bundle ID, real links in About, and a signature that stays the same" above.

- **Decision:** `scripts/release.sh` builds what is sold, and `docs/release.md` says how to use it.
  - **The steps:** an arm64 release build, assembled by `scripts/build-app.sh` in a temporary folder.
    Then the bundle's Info.plist is stamped, the app is signed with a Developer ID under the hardened
    runtime, notarized and stapled. It goes in a DMG with an `/Applications` link and the EULA, which is
    signed, notarized and stapled in turn. The script checks what ships from the mounted DMG and writes
    the DMG and its SHA-256 checksum to `dist/`.
  - **Without an account:** `--unsigned` makes a test DMG, signed ad hoc under the hardened runtime and
    not notarized. Without that flag, a missing `DEVELOPER_ID` or `NOTARY_PROFILE` fails at once with
    the setup steps. A signed build is refused while the bundle ID contains "prototype".
  - **One place for identity:** the bundle ID, copyright holder and the URLs still to come are set in
    `Support/release.env`. Both scripts stamp the ID and copyright on the bundle's copy of Info.plist.
    The `parking` log's subsystem is now `Bundle.main.bundleIdentifier`, or "Tuck" under `swift run`.
  - **Build numbers:** `CFBundleVersion` is the UTC date, the UTC time and the git commit count, so it
    rises with every build even if the history is rewritten.
  - **Info.plist:** it gains `NSHumanReadableCopyright`, the Productivity category,
    `LSArchitecturePriority` (arm64), and usage strings for the prompts setup brings up on purpose:
    Desktop, Documents, Downloads, iCloud Drive (`NSFileProviderDomainUsageDescription`), and removable
    and network volumes.
  - **Legal drafts:** a EULA and a privacy policy in `docs/legal/`, marked as drafts for legal review.
- **Why:** These are my decisions:
  - direct sale, since the App Store's sandbox blocks Accessibility window parking;
  - no Developer account yet, so everything is ready for the certificate and credentials alone;
  - the bundle ID chosen later;
  - Apple silicon only;
  - no updates for now, and licensing later.

  `build-app.sh` gained an output path and an architecture rather than being copied, so a release is
  assembled, stripped and stamped as a local build is. With no arguments it builds `build/Tuck.app` as
  before. The category is Productivity because Tuck organises windows and files around what you're
  doing; it isn't a system utility.
- **Hardened runtime:** no exception is needed, so there is no entitlements file:
  - no JIT and no unsigned memory;
  - only system libraries (`otool -L`);
  - no Apple Events;
  - Rest signals and reads the person's own processes with `kill` and `proc_*`, with no task port;
  - Core Audio is asked only whether a process is running audio;
  - the event taps are active taps for mouse and scroll events, covered by Accessibility, which is a
    TCC grant, not an entitlement.

  The code was also checked for other protected resources. Apple Events, Screen Recording and Input
  Monitoring aren't used: the window list is read for bounds, never names or pixels. iCloud Drive's
  prompt comes from the File Provider service, hence its usage string. A grep found no networking
  code: no `URLSession`, `Network` framework, sockets, `LinkPresentation` or WebKit.
- **Checked:**
  - `scripts/release.sh --unsigned` produced `dist/Tuck-1.0.0-unsigned.dmg` (about 0.9 MB). Mounted with
    `-nobrowse`, it holds Tuck.app (arm64 only), the `/Applications` link and `EULA.txt`.
  - The app's Info.plist has version 1.0.0, the stamped build number, the bundle ID and the copyright.
    `codesign --verify --deep --strict` passes, with flags `adhoc,runtime`, and the checksum verifies.
  - `scripts/release.sh` with no credentials fails in under a second with the setup message. With dummy
    credentials it refuses the prototype ID. In a scratch copy with a final-looking ID, it refuses a
    certificate that isn't in the keychain.
  - `build-app.sh` with no output path is unchanged apart from the new plist keys (checked by building
    to a scratch path; `build/Tuck.app` was left alone). A non-.app output path is refused.
  - `swift build` shows no warnings, `scripts/test.sh` passes 288 tests in 38 suites, and
    `git diff --check` is clean.
- **Not checked:**
  - No Developer ID signature, notarization, stapling or Gatekeeper assessment has run, since there is
    no account yet. The notarytool JSON handling follows its documented output and hasn't been run
    against Apple.
  - The test DMG wasn't opened in Finder or launched, so the app hasn't yet run under the hardened
    runtime, and no usage string has been seen in a real prompt.
- **Open:** the launch checklist in `docs/release.md`:
  - the final bundle ID;
  - the payment provider and licensing;
  - the support email and the privacy policy URL;
  - a trademark search;
  - testing on macOS 14, 15, 26 and the current release;
  - an Icon Composer icon;
  - legal review;
  - individual or organisation enrolment;
  - whether turning clipboard history off should clear it.

## 2026-11-05: Lighter at rest: one slow clipboard check, a panel that lets go, smaller binary

- **Decision:** Tuck does less while it sits closed. Six changes:
  - **Clipboard check.** It runs twice a second instead of twenty times, with 0.15 s of tolerance so
    the system can fold it into other wakeups. It is the one repeating timer Tuck keeps at rest, and it
    exists only while clipboard history is on. It can't go: macOS posts nothing when the pasteboard
    changes. Two copies inside half a second now keep only the later one.
  - **The panel lets go when it closes.** Releasing the panel now swaps the hosting view's root for an
    empty view before removing it. Once the closed outline is at rest and nothing is preparing to
    open, any hosting view still in the surface is released. So is a panel built for an open that was
    called off before it showed. The release still waits for the outline to settle, since tearing the
    tree down mid-close held a half-closed frame.
  - **Drag events only during a press.** `DragApproachWatcher` adds its global drag monitor at each
    press. It removes it at the release, or as soon as the drag is classified as not carrying content
    (0.8 s at most).
  - **Glyphs drawn once.** The collapsed surface's symbol images (the token's intention symbol, Loose's
    tray, the drop glyph) are cached by symbol, size, weight, colour and appearance. The cache is
    cleared when the appearance changes.
  - **Clipboard history file.** `FileClipboardPersistence` (TuckCore) writes it as the library is
    written: one coalesced, atomic write 0.6 s after a change, on a utility queue. It skips the write
    when the history matches the file, and holds off sudden termination while a write waits. An
    unreadable file is moved aside as `clipboard-history-unreadable-<time>.json` instead of being
    replaced by an empty history. The history keeps at most 200 entries
    (`ClipboardHistory.defaultMaxEntries`), dropping the least recently copied first. There is no size
    setting and no pinning. The limit is no longer saved, so files from before it, which recorded no
    limit, are held to it on load.
  - **Stronger strip.** `scripts/build-app.sh` strips with `-rSTx` (local, debug and Swift symbols)
    instead of `-x`.
- **Why:** Tuck is to be as light as possible before it is sold. At rest with clipboard history on,
  the panel closed, it measured:
  - 0.18% CPU and 20 timer wakeups a second, all from the 50 ms clipboard timer;
  - a 47.7 MB dirty footprint after the panel had been opened and closed, against 32 MB before it
    first opened.

  The heap of the running build showed why the footprint stayed up. One display's closed panel host
  had been removed from its view but was still alive, held only by its window's scroll latch
  (`_latchedViewForScrollEvents`), and its SwiftUI tree with it. The other display's host was still in
  the surface's clip view, at alpha 0, while the surface recorded no host and had no removal queued.
  - `attachPanel` added a new host to the view tree before recording it in `host`. Cancel, close and
    the ready check only ever removed the recorded host. So a host replaced in `host` before it was
    recorded, by an attach that adding it set off, would stay in the surface for good, observing the
    model. This is the only path in the code that matches that heap. It wasn't reproduced live, since
    the GUI is left alone.
  - The ready check had a second gap. A collapse seen while the panel was being built, before the
    preparing token was set, found nothing to cancel. The ready check then returned and left the built
    host in place.
  - Both are closed: the host is recorded before it is added, the token is set before the panel is
    built, and the idle release takes out every hosting view in the surface, not only the recorded one.

  The drag monitor received every mouse drag on the Mac, such as window moves and text selections,
  for as long as the drag lasted. The glyphs were drawn into new images at every model change. The
  clipboard file was encoded and written on the main thread at every copy and every settings change,
  and a damaged file was silently replaced by an empty one. Only the strip saves bytes on disk rather
  than at run time: 238 KB of the binary (8.2%).
- **Checked:** `swift build` (no warnings) and `scripts/test.sh`: 288 tests in 38 suites, up from 282.
  - "Clipboard history policy" has two new tests: the 200-entry default with the least recently copied
    going first, and a file from before the cap being held to it. Its round-trip test now expects the
    default cap.
  - The new suite "Clipboard history file" (4 tests) covers: no file not counting as damage; an
    unreadable file set aside and kept byte for byte while a fresh one is written beside it; saves
    batched into one write; and an unchanged or just-loaded history not being written.
  - The strip was tried on a scratch copy of the script writing to a scratch folder, so `build/Tuck.app`
    wasn't touched. Against `-x`, the binary went from 2,915,600 to 2,677,824 bytes (the bundle from
    2.9 to 2.6 MB). dyld's imports, exports and fixups and the load commands and linked libraries are
    identical. `codesign --verify --strict` passes. Tuck has no `--help`, so the stripped binary wasn't
    launched.
  - `git diff --check` is clean.
- **Not checked:** Tuck wasn't relaunched, so these weren't measured:
  - wakeups at rest;
  - the footprint after opening and closing the panel;
  - whether the scroll-latched host now frees its tree.

  Also unseen:
  - whether a drag that starts within a few milliseconds of its press loses its first event or two to
    the monitor being added (classification and the approach zone don't depend on them);
  - whether 0.5 s feels slow when something copied is looked for at once in the panel.

  Crash reports from a stripped release no longer name Swift functions, and no dSYM is kept yet.
  `docs/legal/privacy-policy.md` doesn't mention the 200-entry limit or the set-aside file, which
  Clear Clipboard History doesn't remove.

## 2026-11-05: Leaving Mission Control never untucks a window

- **Superseded in part:** the `parking` log's subsystem is now the bundle ID, set in
  `Support/release.env`: `com.millerroberts.Tuck` since "2026-11-19: Tuck's own bundle ID, real links
  in About, and a signature that stays the same". The `log stream` command below names
  `app.tuck.prototype`, so it finds only builds from before then; for a current build, use
  `subsystem == "com.millerroberts.Tuck"` (architecture.md, Diagnostics). See also "Packaged for direct
  sale, as a signed and notarized DMG" above.

- **Decision:** Leaving Mission Control (or App Exposé, or Show Desktop) brings a tucked window back
  only if you chose that window there. Leaving it any other way (clicking the window that was already
  in front, F3 again, Esc, or swiping down) leaves every tucked window tucked: any it left in view goes
  out of sight again, and the keyboard is handed on from any it left with the keyboard. Choosing a
  tucked window there brings it back where it was, as going to it from its app's Dock icon does.
- **Why:** an Obsidian window was tucked, and Mission Control opened with F3 or a four-finger swipe up
  and left with the window in front still in front. The tucked window came back on screen, and Tuck
  stopped treating it as tucked. Without a live reproduction, the code shows
  these causes, each of which could produce that:
  - **The focus path (confirmed in the code):** `frontWindowChanged` knew nothing of Mission Control.
    The Dock can come forward while it shows, so coming back to Obsidian counted as switching to it.
    If the keyboard was still in the tucked window (Mission Control's exit can make it the key window
    again, or Obsidian never let go of it), that window was restored as if you had gone to it, or,
    once back in view, its row was dropped (`broughtBack`).
  - **The drift path (confirmed in the code):** `OffScreenParking.drift` leaves a window the person
    "has in front". After Mission Control, a tucked window left in view with the keyboard in it was
    therefore left in view, and the focus path above then dropped its row.
  - **Judging too soon (likely; can't be confirmed without a run):** every parked window was checked
    the moment the Dock said Mission Control had ended, while its exit animation still ran, and while
    Obsidian, an Electron app, could still be moving or resizing its window or not answering. A move
    that failed then went straight to the fallback, and a busy app may not be hidden and minimised
    either; then the fallback put the window back where it was and dropped its row (refused). A window
    that didn't answer was skipped and left in view.
  - **The keyboard handoff (possible):** handing the keyboard to another window of the same app made
    that window main, but some apps keep their focused window where it was, in the window just
    parked. Mission Control would then return to the parked window.
  - **Ruled out:** restoring afterwards. Restoring sets the original frame wherever the window is, as
    the 2026-11-04 entry found.
- **How:**
  - `MissionControlVisit` (TuckCore) is the rule. As Mission Control begins, it notes what was in front:
    the app in front and its focused window, read past the Dock. A parked window was chosen only if it
    is now the focused window of the app in front and wasn't as Mission Control began. Moving between
    Mission Control's views keeps where it began. An exit with no start seen leaves the start unknown,
    and then nothing counts as chosen.
  - While Mission Control shows, nothing is judged. Its end is the Dock's `AXExposeExit`. In case the
    Dock doesn't post it (it may not, for a swipe), a parked window moving, or another app coming
    forward, while it shows is taken as its end, and the Dock's exit after that still belongs to the
    same visit. If the Dock posts neither start nor end, the moved and resized path re-parks windows as
    before.
  - For 1.5 s after the end, a move of a parked window or a focus change only puts off one look at
    everything Mission Control left: 0.4 s after the exit and at least 0.2 s after the latest move or
    focus change. It is one `DispatchWorkItem` at a time, with no repeating timer, and none while no
    window is parked. `missionControlSettled` then reads the front once, and
    `OffScreenParking.driftAfterMissionControl` decides each parked window. A chosen window comes back
    through `onParkedWindowFocused`. Any other back in view is parked again, even with the keyboard in
    it, and that isn't counted as a pull-back.
  - A window that can't be moved then, or doesn't answer, is tried once more 0.4 s later, and only falls
    back if it still can't be moved. A closed one is let go (logged). Last, if the app in front has a
    parked window focused, the keyboard is handed on from it.
  - `frontWindowChanged` no longer counts the Dock coming forward as a switch, and defers to the settled
    look around Mission Control. So do the drift check and every other check that can fall back
    (`keepOutOfSight`), so nothing is minimised or refused there before the retry.
  - `AX.focus` now also sets the app's focused window when the app's focused window is still another,
    so a same-app handoff can't leave the keyboard in the window just parked. If it still stays there,
    that is logged.
  - Each way a window stops being tucked without your restoring it from Tuck is logged through
    `os.Logger` (subsystem `app.tuck.prototype`, category `parking`), with the reason, the app's bundle
    ID and how lately Mission Control ended: brought back, refused, closed while tucked, and restored
    because you went to its app or chose it in Mission Control (`.info`). Mission Control's start and
    end, re-parks and minimising instead are `.debug`. To watch while reproducing:
    `log stream --level debug --predicate 'subsystem == "app.tuck.prototype" AND category == "parking"'`.
    (The subsystem has since changed: for a build since 2026-11-19, put `com.millerroberts.Tuck` in
    place of `app.tuck.prototype`. See the note at the top of this entry.)
- **Checked:** `swift build` (no warnings) and `scripts/test.sh`: 282 tests in 37 suites, up from 268.
  The new suite "Leaving Mission Control" (12 tests) covers:
  - leaving with the front where it was choosing nothing;
  - the keyboard left in the tucked window not counting as a choice;
  - choosing the tucked window, from another app or from the app's other window;
  - choosing another window, or the front not being read;
  - an exit with no start seen;
  - moving between views;
  - a second exit right after the first, and the Dock's exit long after an assumed end;
  - the 1.5 s span, the settle and beat waits, the single retry, and each visit starting afresh.

  Two more in "Parking windows off screen" cover `driftAfterMissionControl`: a window back in view is
  parked again even with the keyboard in it, one still parked stays, nothing is done without displays,
  and a chosen one comes back. `git diff --check` is clean.
- **Not checked:** Tuck wasn't run with Obsidian or Mission Control. Still unseen:
  - whether the Dock posts `AXExposeExit` for a swipe on this macOS (handled either way);
  - whether Obsidian moves its window as Mission Control ends, or only keeps focus in it;
  - whether 0.4 s is long enough for the exit to settle on a slow Mac (a window that still can't be
    moved is tried again once);
  - whether a re-park during App Exposé or Show Desktop looks right.

  Some limits remain:
  - If Tuck takes Mission Control to have ended while it still shows (an app moved a parked window
    during it), windows it left in view are parked again then, while it still shows.
  - A tucked window chosen in Mission Control more than 1.5 s after such an assumed end, with the Dock
    never posting its exit, is judged by the focus watcher as before.

## 2026-11-05: The front-window bar acts on the window it names

**Superseded in part** by "2026-11-08: One place, one fold: the simplification redesign". The bar is
gone: its Tuck is the Tuck button on the shallow fold's left wing, and its Arrange is Arrange windows,
the full fold's last row. Both still act only on the window they name and go blank once it is tucked.

- **Decision:** The bar's Tuck and Arrange now act on the window the bar names, and never on another.
  While the panel is open the bar follows the window in front. It updates when you switch app or
  window, when that window closes or is renamed, and when a window is tucked or restored by any path.
  If the window it names has closed, been put away or been replaced since, a click touches no window:
  the bar is read again and a status line says why. Once its window is tucked the bar still goes blank
  at once (the 2026-11-02 decision stands). It now fills again with the next window you bring forward,
  however soon after Tuck's own move, instead of staying blank until the panel opens again. The open
  picker drops windows that have closed, lost their app or been tucked since it listed them.
- **Why:** a window was tucked by another path while the expanded panel was showing the bar. The bar
  kept naming that app, and its Tuck then put away a different window. There were four causes:
  - The bar was read once, when the panel opened, and nothing changed it while the panel stayed open.
    After ⌘-Tab or ⌘`, a window closing, a restore by the shortcut, or Tuck handing the keyboard on,
    it named a window that was no longer in front, or one already tucked.
  - Its Tuck (`parkFrontWindow`) and Arrange (`placeFrontWindow`) asked Accessibility for the focused
    window again at the click. So they acted on whatever was in front by then, not on what the bar
    named. Arrange's status line named the bar's app even when it had placed another app's window.
  - A tuck from the picker or Tuck All read the front window again just before parking and judged that,
    not what the bar named.
  - The picker kept rows for windows that had closed, or been tucked by the shortcut, since it listed
    them. It never tucked another window, since it holds the exact elements, but it offered windows it
    couldn't tuck.
- **How:**
  - `FrontWindowInfo` now carries a `WindowToken` (TuckCore), made by the service from the window's
    `pid:CFHash` key. The service keeps the element itself (`frontTarget`), so the model holds only an
    opaque name. Reading the same window again gives an equal token. `frontWindow()` reads the app in
    front once and asks that app for its window (`AX.focusedWindow(of:)`), so a switch between two reads
    can't pair one app's name with another's window.
  - The bar's Tuck (`tuckShownWindow`) and Arrange (`placeShownWindow`) hand the token back. First
    `check` answers with a `ShownWindowCheck`: stale, closed, busy, put away, needs permission or ready.
    Only a ready window is parked (`park(_ window:)`) or placed (`place`), on that element, checked once
    more. Anything else touches no window. It shows "That Safari window has closed", "…is already put
    away", "Safari isn't answering · try again", "The window in front has changed" or the Accessibility
    line, with the closed notch's shake, and the bar is read again. A window that passes the check but is
    gone by the time `park` or `place` reaches it is checked once more for why
    (`ShownWindowCheck.missed`) and handled the same way, never as the shortcut's "No window to tuck".
  - `watchFrontWindow` runs the parking service's `FrontWindowWatcher` only while the panel is open. It
    may already be running for parked windows. Its new `watchesEdits` adds the focused window's close
    and title notifications. They wait on a beat of their own, so a title that keeps changing never
    holds back a switch. Once a close has settled, the focused window is read again and watched, in
    case the close was told before focus moved on. Each report carries the window now in front and
    whether the person brought it there. Nothing is read while the panel is closed, and nothing runs on
    a timer. The hint's watcher is unchanged.
  - `OwnFrontChanges` (TuckCore) tells Tuck's changes from the person's by where the front lands. Before
    a move that may bring something forward, the service records what: the window `giveKeyboard`
    focuses (or only its app, or Finder for the desktop), or the app `minimise` keeps in front. A change
    landing there within 0.5 s is Tuck's. One that leaves the front where it was, such as a rename,
    brings nothing forward. Any other is the person's, however soon it comes.
  - `frontWindow()` still offers no tucked window. That includes one parked off screen that is still
    its app's focused window, and now a resting app's.
  - `FrontWindowBarState` (TuckCore) holds what the bar names. A tuck of its window blanks the bar and
    holds it blank by any path: the bar, the shortcut, the menu, the notch, or the picker and Tuck All
    for its app (`ParkingPolicy.frontWindow`). It stays blank through Tuck's own changes and through any
    that leave no window to name. The hold lets go when the person brings a window forward or restores
    one. It also lets go when a window that couldn't be tucked, or was brought back, is in view again.
  - Naming a different window, but not a renamed one, closes Arrange's chooser.
  - The open picker prunes its rows, ticks and open groups (`stillListed`, which now asks first whether
    the app is still running). It does so when a listed window closes or its app quits, on each change
    the front-window watcher reports, and after a tuck by the shortcut or menu. `ListedWindowWatcher`
    watches the listed windows' close notification, one observer per listed app, and the workspace's
    terminate notification, only while the picker is open. A window put away some other way stays
    listed until the next of these, and choosing it then leaves it be.
- **Reviewed:** a review of the first version found four faults, fixed before commit:
  - the app and its window were read separately;
  - the picker kept quit apps' windows;
  - a switch within 0.5 s of Tuck's own move was taken as Tuck's;
  - a window lost between the check and the action showed the shortcut's message without reading the
    bar again.

  It also found that a close told before focus moved on left the next window unwatched.
- **Left as they were:** the shortcut, the menu item and the notch's Tuck arrow (and its peek) name no
  window. They tuck the window focused at the moment you use them, and blank the bar. Tuck All acts on
  the app whose name it shows. Setup's practice desk doesn't use this code and is untouched.
- **Checked:** `swift build` (no warnings) and `scripts/test.sh`: 268 tests in 36 suites, up from 252
  in 34. There are 16 new tests: 11 in "The front-window bar" and 5 in "Tuck's own changes to the
  window in front". They cover:
  - window identity across a rename;
  - the bar following changes;
  - the blank hold through Tuck's handoff, and through changes that leave nothing to name;
  - the person's switch filling the bar, even a fifth of a second after Tuck's handoff;
  - another window of the app Tuck focused counting as the person's;
  - a rename bringing nothing forward;
  - an expected landing lapsing after half a second;
  - a fresh read or a restore letting go of the hold;
  - picker and Tuck All tucks of its app and of others;
  - the check's order, so a quit or busy app is asked nothing more;
  - the reason given for a window lost after a ready check;
  - a token from an earlier read never reaching the window now in front.

  `git diff --check` is clean. `--snapshot-panel` renders the bar and its blank after a tuck as before.
- **Not checked:** Tuck wasn't run against real windows. Still unseen:
  - whether every app posts the title notification on its window (browsers do on a tab switch);
  - which comes first, the close notification or focus moving on (both orders are handled);
  - whether every app posts the close notification for a window behind others, which the picker relies
    on (a quit is caught either way);
  - how the bar feels when a title changes many times a second.

  Some limits remain:
  - Within half a second of Tuck's own move, a switch to the very window Tuck handed the keyboard to
    looks like Tuck's and keeps the blank. After a minimise, so does a switch to any window of the app
    Tuck kept in front.
  - Hiding an app for a moment can bring another app forward. If macOS drops both of Tuck's requests to
    put the app back, the bar names the other app's window, which then has the keyboard.

## 2026-11-04: A parked window is watched, so Mission Control can't bring it back

- **Superseded in part:** what Mission Control leaves is no longer judged the moment it ends by
  `OffScreenParking.drift`, which left a window with the keyboard in it to the focus watcher. It is
  judged once the exit has settled, by what was in front as it began, and a window left in view is
  parked again unless the person chose it there. See "Leaving Mission Control never untucks a window"
  above.

- **Decision:** A window parked off screen is now watched for as long as it is parked. If anything
  other than the person brings it back into view (its app, or Mission Control, App Exposé or Show
  Desktop ending), it goes out of sight again. If its app pulls it back a third time within 2 s, it is
  minimised the existing way instead. Windows that stay parked are left exactly as they were.
- **Why:** a virtual machine's window was tucked, then Mission Control opened with F3 and left again, and
  the window came back on screen while Tuck still listed it as tucked. After a window was moved off
  screen, Tuck read its frame back once and looked again 0.3 s later. After that, only two things made
  Tuck look at it: the keyboard landing on it (`FrontWindowWatcher`) or the displays changing (the
  screen-parameters observer). Leaving Mission Control does neither, since the keyboard stays where it
  was. So whatever moved the window back went unseen. The other way of reading the report, that the
  trouble came when the window was restored afterwards, doesn't fit the code: restoring sets the original
  frame wherever the window is. Without a live reproduction it isn't known what moved the window. It may
  be the virtual machine app resizing or re-placing its window as Mission Control shows and hides it, or
  macOS holding its edge on screen. Either way the app posts the window's moved or resized notification,
  or the Dock posts Mission Control's exit, and before this change Tuck listened for neither.
- **How:** `ParkedWindowWatcher` keeps one Accessibility observer per app with parked windows. It
  registers for moved and resized notifications on exactly those windows, and on the Dock for Mission
  Control's `AXExpose…` notifications (undocumented names, the ones yabai uses). It runs only while a
  window is parked off screen, and there is no timer. A move or resize, Tuck's own included, queues one
  check 0.2 s after the last. That way a resize and a move, or an animated frame, is judged once it has
  settled. While Mission Control is showing, moves are left alone. When it ends, every parked window is
  checked. `OffScreenParking.drift` (TuckCore) decides each one:
  - A window that is still parked stays.
  - So does one the person has in front: its app is frontmost and it is the focused window, which the
    app itself is asked. The focus watcher sees to those, by bringing the window back or letting its
    row go, as before.
  - Otherwise it is parked again.
  - After two re-parks within 2 s, it is minimised through the existing fallback.

  Checks queued during a display change are left to the display checks, as before.
- **Full-screen windows:** a full-screen virtual machine window has its own Space and was never parked
  off screen. It takes the minimise path as before, and Mission Control doesn't show minimised windows.
- **Checked:** `swift build` (no warnings), `scripts/test.sh` (251 tests; 6 new in "Parking windows off
  screen": a parked window that only changed size stays, one back in view is parked again, one in
  front of the person is left to them, repeated pull-backs minimise it, old pull-backs don't count, and
  nothing is done without displays), `git diff --check` and `scripts/build-app.sh`.
- **Not checked:** Tuck wasn't run against a real virtual machine or Mission Control. Still unseen:
  whether the Dock's `AXExpose…` notifications fire on this macOS (if they don't, the moved and resized
  notifications still catch the window, just without waiting for Mission Control to end); what virtual
  machine apps (UTM, Parallels, VMware Fusion) actually do with a parked window; and whether a re-park
  during App Exposé or Show Desktop looks right.

## 2026-11-04: The notch's line lights only while pointed at

**Superseded** by "2026-11-08: One place, one fold: the simplification redesign". An empty Tuck is now
the bare notch, and one that holds something shows the round mark and the count in Tuck blue at rest.
Pointing no longer lights the line, and there is no card in the dip.

- **Decision:** the closed notch's line is now faint (32 %) at rest, whatever the space holds, and
  lights at full colour while the pointer is over the notch, fading on in 0.16 s as its dip greets the
  pointer and back as the pointer leaves. A space that holds something still shows its card in the dip
  at rest, at full colour, so you can still see it's full without pointing at it. The card still drops
  in with the mark's swell when a space starts holding something, and lifts out when it empties. The
  setup's pretend notch does the same.
- **Why:** I wanted the light off until the notch is pointed at and on while it is, and chose
  to keep the card at rest over showing nothing.
- **How:** the lit line's opacity moved from the mark's holding state to `applyVisibility`, which
  already runs on every hover change, so the light needs no new observer. `setMarkLit` became
  `setMarkHolds` and now moves only the card. `TuckLogo.emptyOpacity` is now `restingOpacity`.
- **Checked:** `swift build`, `scripts/test.sh` (246 tests in 34 suites). `--snapshot-panel`: at rest
  empty (faint line), at rest holding (faint line and card) and pointed at (lit line and arrow).
  `--snapshot-ui`: a new `setup-tour-holding` shot shows the pretend notch closed and holding (faint line
  and card), and every other setup render is pixel-identical to before. Not tried by hand: the fade on
  the real notch as the pointer comes and goes.

## 2026-11-04: The gesture step teaches three swipes

- **Decision:** Swipe on the notch now teaches only Open (swipe down on the notch), Change page
  (sideways on the panel) and Close (up on the panel). Switch session, Tuck away and Bring back are
  gone from its chips, its instructions and its "what that did" line. On that step the closed notch
  only opens: swiping it sideways or up does nothing, and it doesn't start drawing in as a swipe goes
  up, so nothing happens there that the step doesn't teach. The haptics line says a tap comes when a
  swipe opens or closes the panel or changes page, and the line for people without a trackpad says to
  click the notch, since Tuck Away is no longer mentioned. When all three are done it says "That's all
  three."
- **Why:** I wanted the three removed from the gesture step.
- **Unchanged:** the real notch still switches session, tucks away and comes back by swipe; so does the
  tour's screen, as before, though those swipes tick nothing on either step now. If Tuck was tucked away
  on the tour, the gesture step says to swipe down on the notch, or click it, to bring it back, and a
  swipe down still does.
- **Checked:** `swift build`, `scripts/test.sh` (246 tests in 34 suites; a new test checks that session,
  tuck-away and bring-back swipes still change the desk but tick nothing). `--snapshot-ui`: the gesture
  step shows three chips and its new lines.

## 2026-11-04: Setup opens on Tuck's logo alone

- **Superseded in part:** the gesture step no longer teaches sessions; see "The gesture step teaches
  three swipes" above.

- **Decision:** Setup's first page is now only Tuck's stacked lockup, the line above the "tuck"
  wordmark, centred in the window with no title, text or list. As it appears the line draws itself out
  from the floor of its dip to its tails, dips once as the closed notch does when pointed at, and the
  wordmark rises in under it, all within about a second; pointing at the logo dips it again. Under
  Reduce Motion it is simply there. The footer (progress dots, Continue) and every later step are
  unchanged. The tutorial from Settings still starts at the tour, so it doesn't show this page.
- **Why:** I wanted the first page to be just a visual that stands for Tuck, with the rest of
  setup as it was. The four lines it held are each taught or asked later: the tour shows tucking and
  holding, the gesture step sessions, and the permission step says what Tuck reads and that it stays
  on the Mac.
- **How:** the wordmark is drawn in code like the line, as the centre lines of the strokes
  generate.py outlines, stroked 24 units wide with round caps (`TuckLogo.wordmarkPath`), with the
  lockup's grid and origins from `stacked` (`stackedSize`, `stackedLineOrigin`, `stackedWordOrigin`), so
  there is still no image to bundle. The line is a trimmed `LogoLine`, now shared with the pretend
  notch's mark, and the greeting is its keyframes (`TuckLogo.greetingLeg`). It runs once on appearing
  and on a pointer's arrival; nothing repeats or polls.
- **Checked:** `swift build`, `scripts/test.sh` (245 tests in 34 suites). The coded wordmark stroked
  over `tuck-logo-stacked.svg` at 3×: it covers the master's outlines exactly. `--snapshot-ui`: the
  welcome in light and dark (the snapshot now waits for its intro), the intro part-way at six moments,
  and every other setup render pixel-identical to before. Not tried by hand: the intro and the hover
  greeting in a real setup window, and VoiceOver on the page.

## 2026-11-04: The notch's Tuck button is an arrow in the logo's line; space symbols drawn heavy

**Superseded** by "2026-11-08: One place, one fold: the simplification redesign". The closed notch has
no Tuck button, and with sessions gone there are no space symbols. The Tuck button is on the shallow
fold's left wing.

- **Decision:** Pointed at, the closed notch's Tuck button is now a bare arrow drawn in the logo's own
  line, with no circle behind it: a shaft as tall as the mark's dip and a head, stroked as thick as the
  mark's line with round caps, in the space's colour (coral for Loose), so the two wings read as a pair.
  It rises a line's width into place and grows as the resting dot shrinks away; it presses in when held
  and is the same on a bubble, when peeking and when it blinks in after a minimise. The space symbols
  (Work's briefcase, Personal's house, Study's book, Health's heart) are now outlines drawn heavy, not
  filled silhouettes at semibold, wherever a token carries one: the panel's strip, the intention tiles,
  the notch's drop circle, a tucked window's card landing on a token, and Settings. The tokens keep
  their circles. Setup's pretend notch gets the same arrow; its tokens are numbered, so there is no
  symbol to change there. The open panel's own Tuck button is unchanged.
- **Why:** the round button looked too skinny beside the logo. I wanted just an arrow, thick
  enough to match it, and the space symbols to match the logo's style and the button's. A heavy
  outline's line is about an eighth of its size, as the logo's is, so the symbols read as the same
  rounded line; a heavier filled silhouette barely changes, since it is already solid.
- **How:** `TuckLogo.arrowPath(side:)` is drawn on the 256-unit grid from the small cut's top and floor
  and stroked `lineWidth(side:)` wide, on one `CAShapeLayer` sized like the mark; its path is set only
  when the size changes. The resting dot is its own layer. `SessionFace.symbolWeight` (heavy) and
  `symbolFont(forToken:)` set every token's symbol, AppKit and SwiftUI alike.
- **Checked:** `swift build`, `scripts/test.sh` (245 tests in 34 suites). A comparison of the four
  symbols, filled and outlined, at semibold, bold, heavy and black, beside the mark, at 16, 24 and
  28 pt in real pixels: heavy outlines match the line and stay open in the 16 pt circle; black narrows
  the briefcase's handle. `--snapshot-panel`: pointed at (numbered and intentions), the peek, the
  external bubble pointed at, the drop invitation with Work's briefcase, the strip and the intention
  tiles. Not tried by hand: the arrow rising in on a real notch, and Settings' token art.

## 2026-11-04: Pointed at, the notch keeps its logo; the Tuck button is tinted like the panel's

- **Superseded in part:** the Tuck button is no longer a tinted circle; it is a bare arrow in the
  logo's line. See "The notch's Tuck button is an arrow in the logo's line; space symbols drawn heavy"
  above. Since "2026-11-08: One place, one fold: the simplification redesign", the closed notch has no
  Tuck button and a drop shows the drop target, not a space's circle; the mark still greets the pointer,
  with no card.
- **Decision:** Pointing at the closed notch no longer swaps Tuck's mark for the current space's circle
  (Work's briefcase, or a number). The mark stays and greets the pointer once as it arrives: the line's
  dip reaches about 2 pt deeper, as the panel would drop from it, springs back a little past rest and
  settles in 0.5 s, with the card (when the space holds something) riding it a beat behind. Then it is
  just the logo. The round Tuck button on the right wing is now drawn as the open panel's round buttons
  are (the gear, +): the space's dark tint with ⤒ in the space's colour, instead of a filled circle in
  that colour with a black glyph. It is the same on a bubble and when it blinks in after a minimise.
  The drop invitation still turns the mark into the space's circle, so a drag shows where it will land.
  The open panel is unchanged, its own Tuck button included. Setup's pretend notch does the same.
- **Why:** I wanted the hovered notch to show the logo already on it, with a little animation,
  rather than the logo of the current space, and its Tuck button to match the rest of the app.
- **How:** `TuckLogo.linePath(side:reach:)` deepens the dip (every reach has the same path elements, so
  Core Animation morphs between them); `SurfaceView.greetMark` keyframes the two line layers' paths and
  adds the card's translation, once per arrival, left to finish rather than restarted, and skipped under
  Reduce Motion and on a bubble. Nothing runs at rest and nothing is cached.
- **Checked:** `swift build`, `scripts/test.sh` (245 tests in 34 suites). `--snapshot-panel`, before
  and after: pointed at (numbered and intentions), the peek, the external bubble pointed at, and the drop
  invitation, which is unchanged. The greeting's five keyframes rendered large from a copy of the path:
  the line stays inside its square and the dip stays open. Not tried by hand: the greeting in motion on
  a real notch, and setup's pretend notch.

## 2026-11-04: A long page stops at about four and a half rows

**Superseded** by "2026-11-08: One place, one fold: the simplification redesign". There are no pages.
The shallow fold shows four rows and an "N more" row; the full fold's list scrolls past the smaller of
440 pt and the screen's height less the menu bar and 280 pt (never under 180).

- **Decision:** The panel's list now scrolls past 230 pt, about four and a half two-line rows, down from
  352 pt (seven rows). The pages still share one height, so a swipe only slides, but that height can now
  grow only this far: a long Clipboard (or any long page) no longer stretches every page, and the
  panel, to most of the screen's height. The half row showing at the bottom of a full page says there
  is more. The window picker uses the same cap.
- **Why:** the whole panel grew when the Clipboard or another page got long. Since the pages
  share the tallest one's height, one long page made every page that tall, and seven rows plus the
  strip, header and footer came to 554 pt, over half of a 13-inch MacBook Air's screen.
- **Checked:** `swift build`, `scripts/test.sh`. `--snapshot-panel`: the crowded panel (15 windows, 25
  held, 128 copies) is 432 pt tall, down from 554; Held with five items shows four and half of the
  fifth; Windows with Restore All shows nearly four rows above it. Not tried by hand: scrolling a long
  page in the live panel.

## 2026-11-04: Page swipes only slide; every session in Intentions shows a symbol

- **Superseded in part:** the shared height now caps at 230 pt, not 352. See "A long page stops at
  about four and a half rows" above. Since "2026-11-08: One place, one fold: the simplification
  redesign", the rest has gone too: there are no pages, sessions or intentions.

- **Decision:** The panel's pages share the tallest one's height (capped as before), so a swipe or a
  tab click between Windows, Held and Clipboard only slides them sideways. A shorter page keeps its rows,
  and Restore All under them, at its top. The panel's height still follows what's in it: tucking,
  restoring and clearing change it as before. In the Intentions style, every session in the strip
  without an intention takes the next free one, in strip order (Work, Personal, Study, Health), with
  that intention's colour and everything in it. This happens at launch and on switching to Intentions.
  A window tucked with Loose current starts the next free intention rather than a colour-only session.
  Once all four are taken (an archived one counts, since it comes back with its things), any left over
  keep their numbers.
- **Why:** every swipe showed a little dip, as if the page reloaded. Each page had its own height (in the
  snapshots Windows, Held and Clipboard were 445, 459 and 295 pt). So every page change re-ran the
  outline's spring, resized the window when growing, and moved the list on SwiftUI's page spring; the two
  springs differ, so the footer and the outline drifted apart for a moment. With one height, nothing but
  the slide runs. Numbers also showed after the symbols build: the library saved before intentions had
  sessions with none, and the earlier entry kept them numbered on purpose. Strip order matches a fresh
  library (two sessions become Work and Personal), and nothing is guessed from what a session holds.
- **Checked:** `swift build`, `scripts/test.sh` (244 tests; 3 new: adoption in strip order with colours
  and contents kept, skipping taken and archived intentions and stopping at four, and the Loose tuck in
  each style). `--snapshot-panel`: Windows, Held and Clipboard now render at the same height (459 pt),
  rows at the top. Not tried by hand: the swipe on the live panel.

## 2026-11-04: Intentions and an app's windows are chosen in the panel, not in menus

**Superseded in part** by "2026-11-08: One place, one fold: the simplification redesign". The intention
chooser went with sessions. The window picker keeps its app rows; it opens from Choose Windows to Tuck…
and takes the place of the full fold's list until it is done or cancelled.

- **Decision:** The two system menus in the panel are gone. The strip's + (Intentions style) opens a
  chooser just under the strip: a tile for each intention not in it, in its own colour, carrying the
  filled token it adds, since adding one makes it current. An archived one says "Archived" under its
  name. The header names what the hovered tile does ("Starts empty", "Comes back with 10 tucked") in room
  that is always kept, as the placement chooser names its glyphs. + turns 45° into × and stays lit while
  open; Escape, choosing a tile, opening the window picker, closing the panel or switching to numbered
  sessions closes it. In the window picker, an app with several windows is now an app row that opens on a
  click, as its row on the Windows page does: a chevron that turns down, its windows by title, each
  ticked on its own in the space's tint, and a Select All N Windows row at the end (Deselect All once all
  are ticked). Closed, the row says "1 of 2 selected" and keeps the tint while any are ticked.
- **Why:** I wanted both in line with Tuck's design instead of the default Apple menu. A menu
  is a grey system surface outside the black panel, drops its symbols on macOS 27, and showed intentions
  without their colours. Opening in place keeps Tuck's own pattern for choices (the placement chooser,
  the app rows) and lets the panel grow under them, with no popover to clip at the panel's edge.
- **Kept as it was:** what each choice does. Intentions still come one of each, and archived ones still
  come back with everything in them. The picker still ticks exactly the windows chosen and nothing moves
  until "Tuck N". Every app row in the picker starts closed. Numbered sessions' + still makes a session
  at once. Context menus (right-click) stay system menus.
- **Checked:** `swift build`, `scripts/test.sh` (242 tests; one new, for an app's own ticked count), and
  `git diff --check`. `--snapshot-panel` has `addIntention` (Work archived, Health new) and
  `pickerGroupOpen` (Finder open, one of its two windows ticked) scenes, in the dark, Light-setting and
  Increase Contrast appearances. Not tried by hand: hovering a tile in a real panel, Escape with the
  panel holding key focus, and VoiceOver on the tiles and the opened app row.

## 2026-11-04: Sessions as intentions, with symbols

- **Superseded in part:** the symbols are outlines drawn heavy, no longer filled silhouettes at
  semibold. See "The notch's Tuck button is an arrow in the logo's line; space symbols drawn heavy"
  above.
- **Superseded in part:** sessions without an intention no longer keep their numbers in the
  Intentions style, and a window tucked with Loose current starts the next free intention. See "Page
  swipes only slide; every session in Intentions shows a symbol" above. The + menu became a row of
  tiles in the panel; see "Intentions and an app's windows are chosen in the panel, not in menus" above.
  Since "2026-11-08: One place, one fold: the simplification redesign", there are no sessions,
  intentions or symbols, no Sessions pane and no session style; a library from before is merged into the
  one stream, with a backup.
- **Decision:** Settings → Sessions chooses how sessions show: as intentions (the default) or numbered.
  An intention is something you do: Work, Personal, Study or Health. Each has its own colour and an
  SF Symbol, which its token carries wherever the number did: the panel's strip, the notch's 16 pt
  circle when pointed at or inviting a drop, and a tucked window's card landing on it. A fresh library starts with Work and Personal; + in the strip becomes a menu of the
  others, at most one of each, and an archived one comes back from it with everything in it.
  Intentions are kept: no hover ⓧ, emptying one doesn't close it, and × with things in it clears it and
  leaves it empty in the strip. Only an empty one can be removed, by × again or its token's menu, after
  "Remove Work?". Numbered keeps the earlier behaviour exactly.
- **Why:** I wanted intention sessions as the default, harder to delete, with symbols that work
  on the notch and match Tuck's look. Two confirmed steps (clear, then remove) mean a session with
  things in it never goes in one click, while an empty intention still goes when you want it to. The
  symbols are one family: filled single silhouettes, semibold like every glyph Tuck draws, the plainest
  picture of each thing (a briefcase, a house, a book), so each reads knocked out in black at 9 pt. Each
  is drawn at its own size, centred and kept 2.5 pt inside the circle (the widest, the briefcase, is 11
  × 9). Colours are fixed per intention, each its own palette, so Work is always the same blue. Four,
  not more: I cut an earlier eight (with Create, Travel, Errands and Play) to these. At rest the
  notch still shows only the drawer mark, as it did with numbers.
- **Kept as it was:** libraries saved before decode with no intention, so existing sessions keep their
  numbers under either style and nothing is guessed from their contents. The quiet session made when a
  window is tucked with Loose current is untitled and closes when empty. Switching style changes how
  sessions show and close, never what's in them.
- **Checked:** `swift build`, `scripts/test.sh` (241 tests; 14 new, for fresh libraries, no duplicates,
  bringing back an archived intention, kept on close, removal only when empty, clearing in place,
  clearing refused with windows parked, numbered ignoring intentions and older libraries decoding), and
  `git diff --check`. `--snapshot-panel` has `intentions` and `removePrompt` scenes and the notch pointed
  at and inviting a drop with Work's briefcase; `--snapshot-ui` renders the Sessions pane in both
  styles. Not tried by hand: the + menu and the remove prompt in a real panel, and VoiceOver on symbol
  tokens.
- **Deferred:** the setup tour's pretend notch still shows numbered sessions. Renaming an intention or
  choosing its symbol.

## 2026-11-04: A new logo, the notch line, lit with a card in the dip when a space holds something

- **Superseded in part:** the line is no longer lit while a space holds something; it is faint at rest
  and lit while pointed at, and the card alone shows that a space holds something. See "The notch's line
  lights only while pointed at" above.
- **Superseded in part:** pointed at, the mark now stays and greets the pointer instead of giving way
  to the circle, which shows only for a drop. See "Pointed at, the notch keeps its logo; the Tuck button
  is tinted like the panel's" above. Since "2026-11-08: One place, one fold: the simplification
  redesign", the notch's mark is Tuck blue rather than a space's colour, with the count on the right
  wing; there is no card in the dip, and an empty Tuck shows the bare notch.
- **Superseded in part:** the app icon's line is now white, not ink. See "The app icon's line is white,
  as on Pulse's and Hum's" above.

- **Decision:** Tuck's mark is now one rounded line, the top edge of the screen dipping down round the
  notch, in place of the card tucked into a drawer. It is a single colour, so it takes the current
  space's colour. At rest the notch shows it dim (32 %) while the space is empty; once it holds
  something the line is lit, with a short card, as wide as the line, resting in the dip. A window tucked
  at rest flies up as a dot just above the dip; the line pops on at full colour with the mark's swell,
  and the card drops into the dip from above on a spring (response 0.32 s, damping 0.72). Emptying lifts
  the card out as the line dims, both in 0.2 s. A deposit into a space already holding something lands
  on the card and swells the mark, and pointed at, the mark still gives way to the numbered circle. The
  card belongs to the notch; the logo itself is the line alone. The app icon is the line in ink on a
  Tuck Blue tile, and the touch and PWA icons match. The menu bar, favicon, notch mark and 16 and 32 px
  icons use a bolder small cut, with shorter tails and a deeper dip. Every master, PNG, web icon and the
  board are regenerated (`design/logo`), and the setup tour's notch does the same.
- **Why:** I wanted a logo as simple as Pulse's that matches what the app has become and can
  take each space's colour. The line is the app's own shape, the notch and the drop rim that wraps it,
  and Pulse's sibling: the same 256 grid, 24-unit line and round ends. Filling the dip in, the first way
  of showing that a space holds something, I turned down. Of eight others tried (a dot dropped
  in, a dip that sags, flat until used, a card bar, closing over, a heavier line, a catch, lighting up),
  I chose the card bar with lighting up, the light a pop rather than a sweep along the line. The
  card carries the old drawer-and-card idea into the line. The blue tile, which I chose over an
  ink one, stands out in a dark Dock or menu, where the ink tile nearly disappeared.
- **How it stays light:** the mark is three shape layers (the dim line, the lit line, the card), and each
  change is a handful of Core Animation animations run once. The library changes as a window is tucked,
  before its card has flown, so a space that has just started holding something waits for the card's
  landing ("+1") to light, or lights 0.54 s later if nothing lands. Reduce Motion cross-fades. The notch
  no longer draws or caches mark images.
- **Supersedes in part:** the drawer mark of "The drawer at rest, and the Tuck button peeking after a
  switch".
- **Checked:** `swift build`, `scripts/test.sh`; `--snapshot-panel` renders the empty, holding (with its
  card), Loose and bubble marks, and `--snapshot-ui` the About tile; `generate.py` and `render.swift`
  rebuild every SVG, PNG, `Support/AppIcon.icns` and web icon. Not seen live: the pop, the card's drop
  and lift, and a real tuck landing above the dip.
- **Deferred:** a trademark search, and print (CMYK, Pantone) values.

## 2026-11-04: The notch answers every switch; a page swipe back from Clipboard

**Superseded in part** by "2026-11-08: One place, one fold: the simplification redesign". The hop, the
Tuck button's blink and Settings → Notch → Answer window switches on the notch are gone, and so are
pages. A gesture's owner is still decided once as it starts: the surface or the full fold's list.

- **Decision:** At every switch to another window the notch's resting dot gives a small hop (a bubble,
  which shows no dot, hops its mark); a hop under way finishes rather than restarting, so ⌘-Tab through
  several apps is one hop. When the person puts a window away by the system's own means, minimising it
  or hiding its app, the Tuck button blinks in instead: in 0.14 s, held 0.6 s, out 0.24 s, clickable
  meanwhile. The bubble's mark and Tuck button are sized to the bubble (4 pt and 6 pt shorter than it)
  instead of the notch's 20 pt, which filled a 20 pt bubble edge to edge. Closing the panel, and every
  resize of the surface's window, re-read where the pointer is, so the closed surface returns to its
  resting form instead of staying in its pointed-at form. A two-finger gesture's owner, page swipe or
  list scroll, is decided once as it starts (`ScrollGestureRouting`, TuckCore).
- **Why:** I wanted a little jump at every switch, and a very brief Tuck button for "actions
  close to tucking", read here as minimising a window or hiding an app, which do a tuck's job through
  the Dock. The bubble's arrow was too big for its tab. The swipe back from Clipboard to Held failed
  because, over a list long enough to scroll, ownership was re-decided at every event and the swipe
  restarted each time; Held's list was too short to scroll, so it never showed there. The surface stayed
  expanded because AppKit replaces the window's tracking area on a resize without sending the exit.
- **Restraint:** the button blinks at most once every 8 s, a put-away inside that gets the hop; for 1.5 s
  after one of Tuck's own tucks or restores nothing answers, since they move windows and focus too; nothing while the
  panel is open, while tucked away, during a drag, or (the hop) under Reduce Motion. Settings → Notch →
  Answer window switches on the notch turns it all off, and with it the watching.
- **How it stays light:** still no timers or polling. Minimising comes from the same Accessibility
  observer on the app in front (kAXWindowMiniaturizedNotification, on the app and its focused window),
  hides from the workspace's notification; a burst of either is reported once, 0.2 s after it settles.
- **Checked:** `swift build`, `scripts/test.sh` (tests for the hint policy and for gesture routing over a
  long list, with wobble and on devices that omit the began phase), and `git diff --check`;
  `--snapshot-panel` renders the bubble at rest and pointed at with a 24 pt menu bar. Not tried by hand:
  the hop and blink on a real switch and minimise, the swipe on a real trackpad, and the close.
## 2026-11-04: Restore All moves to the foot of the Windows page

**Superseded in part** by "2026-11-08: One place, one fold: the simplification redesign". There is no
Windows page. Restore All Windows… is in the band's context menu, offered while two or more windows are
tucked, and still asks first, inline ("Restore all N windows?", with Restore N and Cancel).

- **Decision:** "Restore All N Windows…" is an action row at the foot of the Windows page, shown while
  the session has two or more windows: the restore glyph in the icon column, the name in the space's
  colour. It sits below the scrolling rows, so it stays in view however long the list is, and gets a
  hairline only while rows scroll above it. It asks first, in the inline prompt that opens just below
  it, and stays lit while asking; a second click puts the question away. The page header keeps only
  the tabs, the window picker and ×.
- **Why:** I wanted the untuck button in the right place, unsquashed, visible and working.
  Rendered with clipboard history on and large counts, the header's Restore All capsule shrank to "↶ …"
  and squeezed the tabs to "Win…" and "Clip…": three tabs, the picker and × fill the 324 pt header
  on their own. The foot has the page's full width and sits next to the windows it brings back.
- **One behaviour:** the header button restored at once while the × menu's "Restore All N Windows…"
  asked first. Both now ask, as the earlier window-set decision intended: a bulk restore moves every
  window at once, the row sits just above Tuck, and undoing it means picking the windows again.
  "Restore All <App> Windows" in an app row's menu still acts at once, since it is chosen by name
  from that app's row. A run in progress blocks a second one (which would restore windows twice
  and miscount them); meanwhile the row says "Restoring Windows…" and the menu items are disabled. The
  app row also offers its Restore All as a VoiceOver action.
- **Checked:** `swift build`, `scripts/test.sh` (208 tests), `git diff --check`. `--snapshot-panel`
  has a new `crowded` scene (15 windows, Held 25, Clipboard 128); in it the header and the foot render
  in full. A one-off check against the stand-in window service confirmed the prompt, the
  newest-first order, the emptied list and the "5 windows restored" status. Not tried by hand: a
  Restore All of real windows.
## 2026-11-04: Park tucked windows off screen

- **Superseded in part:** a parked window is no longer only read back and looked at once 0.3 s later.
  It is watched for as long as it is parked, and one brought back into view by its app or by Mission
  Control ending is parked again, or minimised if its app keeps pulling it back. See "A parked window
  is watched, so Mission Control can't bring it back" above.
- **Decision:** A tucked window is moved just beyond a bottom corner of its display, the way the
  AeroSpace window manager keeps other workspaces' windows, instead of being minimised. It stays open:
  nothing is minimised or hidden, so the app's other windows stay put and no other app comes forward.
  It goes only once its card is on screen over it (the deposit flight reports each card `covered` a
  frame after drawing it), so the window is gone the instant the card takes its place. Restoring flies
  the card back out of Tuck to where the window will be, and the window is set there, by its frame, as
  the card lands: no un-minimise animation. Rows record `ParkingMethod.offScreen`; older minimised and
  hidden rows restore as before.
- **Why:** I wanted tucking to show nothing but the card: no Dock genie, none of the app's other
  windows blinking out and back during the brief hide, no other app jumping forward with focus jumping
  back, and no un-minimise genie on the way back.
- **What differs from the earlier attempt:** "Tucking goes into the notch, not the Dock" recorded that
  moving a window off screen failed because macOS keeps a corner of it on screen. That still holds, but
  the corner can be made tiny. Probed with throwaway windows of the probe's own: AppKit keeps a
  window's title bar within the screen vertically (28 pt, 52 pt with a toolbar), holds a window pushed
  wholly beyond a side with 40 pt still showing, and pulls back a window left touching the edge with no
  overlap within 50–100 ms; a 1 pt overlap holds. So a window placed one point in from a bottom corner
  settles with a sliver one point wide and its title bar's height tall in view. Captured, that is about
  128 opaque device pixels and a faint shadow some 30 × 47 pt, darker where several windows wait at one
  corner.
- **Which corner:** bottom-right of the window's own display, else its bottom-left, else those of the
  other displays, the first with no display beyond it where the window would show
  (`OffScreenParking.origin`, tested). A display directly above another keeps windows off its bottom
  corners.
- **Read back, then fall back:** after the move the frame is read back. A window that didn't go out of
  sight (an app that won't let it move), or can't be moved at all (full screen, a fixed position, no
  free corner), is minimised the earlier way, its app hidden for the moment so the genie isn't seen, and
  its row says minimised. One that can't be minimised either is put back and its row goes, with "That
  window couldn't be tucked". Each is looked at once more 0.3 s later, in case its app pulled it back.
- **Focus:** when the window with the keyboard goes, the keyboard goes where a minimise would send it:
  the app's frontmost other window in view, else the frontmost window in view (from the window server's
  front-to-back list, skipping anything still listed where the parked window was), else Finder. Going to
  a parked window (its Dock icon, ⌘-Tab, an app opening a link in it) brings it back where it was, at
  once and without a flight. When the app passes the keyboard to it by itself (⌘`, its last window in
  view closing), the keyboard goes on to a window in view instead, so nothing is typed out of sight. A
  parked window brought back into view some other way loses its row. All of this rides on
  `FrontWindowWatcher`, running only while some window is parked off screen; a change within half a
  second of Tuck's own moves is taken as Tuck's.
- **Listing:** a window out of sight is never offered in Select…, never the front window, counts as
  already tucked, and doesn't count as visible for Rest.
- **Displays:** on a screen-parameters change (no polling), parked windows are checked at once and a
  second later, and moved again if they ended up in view or with nothing left on any display; if that
  fails they are minimised.
- **Quitting:** `applicationWillTerminate` minimises windows parked off screen (their apps hidden for
  the moment), so they wait in the Dock while Tuck isn't running and their rows restore as minimised
  rows. Sudden termination is held off while any row is off screen, so a normal quit reaches that.
- **Crash or force quit:** not handled. The windows stay off screen, each a sliver at its corner,
  until Tuck runs again; meanwhile Mission Control shows them, and dragging the sliver or the app's
  Window menu (Zoom, say) should bring one back, though neither was tried. At launch Tuck takes them up
  again (`adopt`): a window is matched by title among its app's windows that
  are out of sight, never a same-titled window in view; else a minimised window of that title; else
  the one out-of-sight window of its size, for a window whose title changed (a browser's).
- **Kept tucked:** a row asked to stay tucked (forgetting it, quitting) is minimised with its app
  hidden for the moment; forgetting says "it's in the Dock".
- **Checked:** `swift build`, `scripts/test.sh` (222 tests, 14 new in "Parking windows off screen":
  corners, what counts as out of sight, which window takes the keyboard, old rows decoding), and `git
  diff --check`. Throwaway probe scripts, against windows they made themselves, for the clamping, the
  sliver, the capture residue and the window server's list (it still lists a parked window as on screen,
  and lags the move by a moment, so neither is trusted for "out of sight").
- **Not checked:** Tuck itself was not run. Unseen so far: the tuck and restore end to end; whether 25 ms
  is always enough for the card to be on screen before its window goes; the keyboard handoff and
  restore-on-focus with real apps; apps not built on AppKit (Electron, Chrome, Java, Catalyst), which may
  clamp differently or snap back; several displays and displays changing, also while an app rests;
  Spaces (a parked window stays on its Space, so restoring one from another Space may switch to it, and
  Mission Control shows parked windows); Stage Manager; a click on the sliver itself.
## 2026-11-04: Ready for macOS 26 (Liquid Glass) and macOS 27

**Superseded in part** by "2026-11-08: One place, one fold: the simplification redesign". The held-back
clipboard guidance is a card in the fold, not on a Clipboard page, and the open fold follows Light or
Dark rather than staying black, still with no Liquid Glass.

- **Decision:** Five changes, each the smallest that covers a documented change in the newer systems:
  - The notch surface sits at the status-bar level + 1 (deposit flights stay one above or below it).
    While the menu bar is hidden, macOS 27 places an invisible status-bar-level window over a notched
    display's menu-bar strip, which can take the notch's clicks.
  - The window picker's multi-window menu uses toggles, so a chosen window shows the menu's own
    checkmark. macOS 27 hides symbol images in menus by default, and the choice was shown only by a
    checkmark or circle symbol.
  - Permission copy names the pane the running system shows: Accessibility, or Device Control and Data
    Access from macOS 27. The settings link (`Privacy_Accessibility`) and the permission are unchanged.
  - Clipboard capture checks `NSPasteboard.accessBehavior` (macOS 15.4+) after each copy. When it is
    ask or deny, capture pauses, and the Clipboard page and Settings → Held link to Paste from Other
    Apps. The default behaviour still reads, because the first read's alert is what lists Tuck there.
  - No Liquid Glass on the notch surface or panel. Settings and Setup take the system's glass
    automatically from the macOS 26 SDK.
- **Why:** Tuck's original plan keeps the surface black, continuing the hardware notch, and asks for the
  lightest technique. Each change uses public API only, adds no polling and no dependency, and leaves
  older systems unchanged except for the picker's checkmark style.
- **Restraint:** three things Tuck leaves out on purpose:
  - **A higher window level.** The shielding level, above system alerts and HUDs, is broader than
    needed; one level above the status bar is enough.
  - **Glass of its own.** Tuck draws no glass itself, so it needs no private API, which any macOS
    update could change or remove.
  - **Menu images forced back on.** On macOS 27, Tuck follows the system's menu default rather than
    opt menu items back into images, and makes sure no state depends on an image.
- **Not done:** an Icon Composer icon for macOS 26's icon styles. This needs Xcode's `actool`, and the
  Command Line Tools don't include it, so the `.icns` stays for now.
- **Checked:**
  - `swift build` against the macOS 26.2 SDK, with no warnings.
  - `scripts/test.sh`, all 208 tests passing.
  - `--snapshot-ui` and `--snapshot-panel` renders of the window picker and of the held-back clipboard
    guidance in the panel and in Settings, rendered with the flag forced on for the check.
- **To verify on macOS 26 and 27 hardware** (this Mac runs macOS 15.7):
  - Notch clicks and hover with the menu bar set to auto-hide, and beside full-screen apps.
  - Behaviour around lock and unlock, where the macOS 27 strip animates.
  - How the surface sits with the camera indicator, Live Activities and the macOS 27.2 HUD.
  - Taller Tahoe controls in Setup's fixed 840×600 window and in Settings' sidebar.
  - The Paste from Other Apps flow, including whether the system enforces it by default.

## 2026-11-04: Keep collapsed controls anchored through surface transitions

**Superseded in part** by "2026-11-08: One place, one fold: the simplification redesign". A bubble shows
no Tuck button when pointed at: a faint mark while Tuck is empty, the mark and count otherwise.

- **Decision:** Keep the notch's collapsed controls anchored to the closed wings while the larger panel
  outline opens. At external-display bubbles, show only the centered mark at rest and the Tuck button on
  hover; do not show a session number there. During tuck/reveal, keep the surface visible through the
  shape morph and fade it with the movement, so reveal feels like it rises from the notch.
- **Why:** The collapsed controls should not stretch toward the panel's far edges during expansion, and
  the bubble should stay visually simple. Reveal should be visible as it moves rather than appearing only
  after reaching its destination.
- **Checked:** `swift build`, `scripts/test.sh` (208 tests), and `git diff --check`. Runtime animation
  review on notch and external displays remains to be done.

## 2026-11-04: Tucking never leaves an app hidden

- **Superseded in part:** windows are now parked off screen rather than minimised, and restored by
  setting their frame. The brief hide and minimise below is kept only for windows that can't be parked
  off screen, and for minimising parked windows when Tuck quits. See "Park tucked windows off screen"
  above.
- **Decision:** When an app can be hidden, Tuck hides it briefly, minimises the selected windows while
  hidden (avoiding the Dock animation), then shows the app again. New tucked-window records are
  minimised, so restoring one brings it back without hiding its app. Older records marked hidden remain
  supported; restoring one still minimises its hidden siblings before showing the app.
- **Why:** Tucking the only or every visible window of an app previously left that app hidden, making it
  disappear while the stand-in card flew into Tuck.
- **Checked:** `swift build`, `scripts/test.sh`, and `git diff --check`.

## 2026-11-04: File access explained in setup

- **Decision:** Setup offers Full Disk Access for files from any location, and a lower-friction route
  that asks macOS for Desktop, Documents, Downloads and iCloud Drive. Full Disk Access cannot be
  requested by an app, so setup opens its System Settings pane and checks for the grant on return. The
  folder route probes each present directory to surface its system prompt before the first drop.
- **Why:** Tuck reads dropped files to show their thumbnail, kind and size, and to follow them if moved.
  Asking at the first use of each protected location interrupts the drag-and-drop flow.
- **Limit:** Only Full Disk Access can cover arbitrary locations and drives in advance. macOS requires
  the person to enable it manually; the folder route cannot promise no later prompts for other folders
  or external/network volumes. Setup now makes this distinction explicit rather than implying both
  routes cover every location.
- **Checked:** `swift build`, `scripts/test.sh` (208 tests), and the permission-step snapshot. A real
  Full Disk Access toggle and protected-folder prompt were not exercised interactively.

## 2026-11-04: The drawer at rest, and the Tuck button peeking after a switch

- **Superseded in part:** the drawer is now the notch line, dim while the session is empty and lit, with
  a card in its dip, once it holds something. See "A new logo, the notch line, lit with a card in the
  dip when a space holds something".
- **Superseded in part:** a switch now gets the resting dot's hop every time instead of the button's
  peek, and the button blinks in only when the person minimises a window or hides an app; the 30 s and
  once-per-window rules are gone. See "The notch answers every switch; a page swipe back from Clipboard".
  Since "2026-11-08: One place, one fold: the simplification redesign", the closed notch has no hop,
  blink or Tuck button, and shows the mark and count in Tuck blue only while Tuck holds something.
- **Decision:** At rest the closed notch shows Tuck's mark on the left wing, a drawer in the current
  session's colour: the drawer alone while the session is empty, with the card tucked into it once it
  holds anything, as the Dock's Trash shows empty or full. Pointed at, the mark cross-fades into the
  numbered circle and the round ⤒ button appears, as before. After the person switches to a window Tuck
  could tuck, the ⤒ button peeks in on the right for 1.5 s, a little smaller and quieter, and can be
  clicked meanwhile.
- **Why:** I found a lone dot said only that something lives in the notch, liked an empty/full
  mark, felt one side alone looked unbalanced, and suggested a small animation at a switch so people
  learn they can tuck. Loading and timer animations don't apply to Tuck; a switch is the moment a tuck
  is useful.
- **Restraint:** never twice in a row for one window and at most once every 30 s (`TuckHintPolicy`,
  tested), never for Tuck itself, an untitled or unreadable window, or while the panel is open; one fade
  in and out, no looping, no motion under Reduce Motion. A switch in Settings → Notch turns it off, and
  with it the watching.
- **How it stays light:** no timers or polling. App switches come from the workspace's activation
  notification and window switches within an app from an Accessibility observer on the app in front
  only, re-made at each app switch; both exist only while the setting is on. Browser tabs aren't
  windows, so switching tabs isn't seen.
- **Supersedes in part:** the resting dot of "A dot at rest, the notch's own pill when pointed at".
- **Checked:** `swift build`, `scripts/test.sh`; `--snapshot-panel` renders the empty and full drawer,
  the peek, the pointed-at pill, Loose and the bubble. Not tried by hand: a real switch on screen.

## 2026-11-04: Worktree changes consolidated on main

- **Superseded in part:** the page header's Restore All button, which restored at once, is now a row
  at the foot of the Windows page that asks first. See "Restore All moves to the foot of the Windows
  page" above.
- **Decision:** The uncommitted features from the clipboard-history, close-bug, hidden-apps,
  store-animation and untuck worktrees are incorporated into main alongside its setup, file-access and
  notch-hint work. This includes opt-in persisted plain-text clipboard capture; the close-morph
  completion fix; briefly hiding then restoring apps while minimising their tucked windows; Restore All
  actions; and the faster deposit flight. Existing panel landing, picker and setup behavior is retained.
- **Conflict resolution:** The close fix and store-animation changes touched the same overlay file. The
  merged version keeps the close-completion fix, uses the faster pulse timing, and pulses whichever
  closed-notch mark is currently visible. Clipboard and Restore All changes were merged into main's
  existing model, tabs and settings rather than replacing them. The main worktree and all source
  worktrees share the same base commit; their original worktree copies are left intact.
- **Why:** every worktree's feature was to be combined into one coherent build against main.
- **Checked:** `swift build`, `scripts/test.sh` (208 tests in 32 suites), and `git diff --check`.
  Interactive runtime checks of clipboard capture, permissions, window hiding and restore actions remain
  outstanding.

## 2026-11-04: A dot at rest, the notch's own pill when pointed at

- **Superseded in part:** at rest the notch now shows Tuck's drawer mark, empty or full, instead of a
  dot. See "The drawer at rest, and the Tuck button peeking after a switch" above. Pointed at, there is
  no circle and the Tuck button is tinted, not filled; see "Pointed at, the notch keeps its logo; the
  Tuck button is tinted like the panel's" above. Since "2026-11-08: One place, one fold: the
  simplification redesign", the notch shows the mark and the count in Tuck blue while Tuck holds
  something and nothing while it is empty; pointed at, it shows no circle, number or Tuck button.
- **Decision:** The closed notch shows only a small dot in the current session's colour (8 pt; neutral
  for Loose; centred in a bubble). Pointed at, it becomes the system's notch-pill form: the dot grows
  into a 16 pt circle on the left with the session's number knocked out in black, and a round Tuck
  button pops in on the right, a 20 pt circle in the session's colour with the same ⤒
  (`arrow.up.to.line`) as the panel's Tuck button, like the single filled button of the system's AirPods
  pill. Clicking the button tucks the window in front; anywhere else opens the panel. At
  rest there is no number on the closed notch, and there is never a count: the open panel's tabs carry counts, as Mail
  counts a mailbox ("Windows 3", "Held 2"; left out at zero). A deposit pulses the dot, with no "+n".
- **Why:** I felt the lone "1" was the only thing on the idle notch and looked odd, and wanted
  the notch quiet until it is used, then the pill form: no number on the blank notch, the number in the
  grown circle, and the same tuck symbol on the button as elsewhere.
- **Supersedes:** the numbered token and right-wing count of "Apple-built panel" and the count that
  crossfaded into ⤒ in "A smooth way back into the notch" below.
- **Kept:** the open panel's numbered tokens, colour as the notch's only space cue (the numbers say
  which space in the panel), every swipe, the drop invitation and deposit flight (which lands at the
  dot's or circle's size, without a number).

## 2026-11-04: A smooth way back into the notch, a Tuck button on the notch, a Clipboard page

- **Superseded in part:** the drop outlines are now the surface's outline without its top, for the
  open panel too, not a mask and a SwiftUI rim. See "The worktrees merged into one build" above. Since
  "2026-11-08: One place, one fold: the simplification redesign", there is no Tuck button on the closed
  notch and no Clipboard page: copies join the one stream, with a Copied lens and Clear Copied in the
  band's context menu. Going back into the notch stands.
- **Going back into the notch:** recorded at 60 fps, closing showed the outline fold about halfway in
  0.15 s, then hold a square-cornered black block for half a second (the recording has no frames from
  0.12 s to 0.65 s) before the shape jumped into the notch. Releasing the panel's SwiftUI tree mid-close
  took the main thread at the very moment the outline was moving. The panel still fades at once, but its
  tree is released only once the outline is at rest. Recorded again with the panel open, the longest gap
  between frames is 0.033 s and the outline folds into the notch frame by frame.
- **A Tuck button on the closed notch:** while the pointer is over the closed surface, the count on the
  right wing crossfades into ⤒ (`arrow.up.to.line`); pressing presses it in, and letting go there tucks
  the window in front without opening the panel. Anywhere else a click still opens the panel. Tuck moves
  whole windows, not browser tabs.
- **Clipboard is a page of its own,** after Held, while clipboard history is on: its own tab, the whole
  history (Held showed six), and Clear in the header where the session's × sits on the other pages.
  Turning clipboard history off while on that page moves to Held.
- **Pages no longer reset when swiped:** each page faded up from nothing as it slid in, so the page
  looked as if it had reloaded; pages now stay whole while they slide (Reduce Motion still cross-fades).
  The swipe tracker also judged direction afresh on every event, so a sideways swipe that began slightly
  upwards could cross the 14 pt close threshold before the 40 pt page threshold and close the panel,
  which reopens on its first page. Gestures now lock to an axis after 8 pt, and in the open panel only a
  clearly vertical one (1.5× more vertical than sideways) can close it. `.showHeld`/`.showWindows`
  became `.nextPage`/`.previousPage`.
- **Drop outlines never cross the top:** around the notch, the invitation's rim and the open panel's drop
  outline run down the sides and round the bottom only, so they come out of the notch rather than draw a
  line across it. The setup tour's pretend notch and panel do the same. A bubble's outline still goes all
  the way round, since it floats below the menu bar.
- **Checked:** `swift build`, `scripts/test.sh` (205 tests; new: a slanted page swipe turns the page and
  never closes, and pages step in order with Clipboard joining). `--snapshot-panel` renders the Clipboard
  page, a drag over the open panel and the strongest invitation. The close was recorded on screen.
- **Not checked:** the hover Tuck button and the swipes on a real trackpad (synthetic swipes reach
  whatever is under the pointer once the panel closes, so they were stopped).

## 2026-11-04: A tucked window lands in its row; the drop rim wraps the notch

- **Superseded in part:** with the panel closed, the card lands on the notch's dot, which pulses
  without "+n". See "A dot at rest, the notch's own pill when pointed at" and "The worktrees merged
  into one build" above. Since "2026-11-08: One place, one fold: the simplification redesign", the card
  becomes a Tuck blue dot and lands in its row when the row is showing, otherwise in the mark's dip as
  the count rises. The drop rim is Tuck blue, with no session colour, and the band says what the drag
  carries.

### Tucked into the open panel, the card opens out into the window's row
- **Decision:** With the panel open, a tucked window's card still rises from the window and becomes a dot
  of the session's colour, but it no longer goes to the session's token in the strip, and nothing
  shows "+n". It comes down on the icon of the window's row on the Windows page (the app's row, or the
  window's own row inside an open app row), as a 28 pt dot in the session's accent, the icon's size.
  From there it opens out to the row's shape (its frame and 10 pt corners), its colour settling from the
  accent to the session's tint, and clears to show the row. A row that holds only windows still on
  their way up keeps its place empty until its card covers it, so the row is first seen through the
  colour. The opening starts at 85% of the flight, added on top of the flight's last creeping stretch,
  so the dot doesn't stop on the icon. With the panel closed, the card still lands as the token, which
  swells with "+n". The model swells a token only when a card actually landed on one, so a window whose
  row can't be seen (scrolled out of view, or the panel open on another display) still confirms there.
- **Why:** I wanted the coloured dot to go up to where the app will be and expand, through the
  colour, into the app and its place on the Windows tab, instead of going to the space and showing
  "+1".
- **Broken on the way, fixed:** Rows measured in the panel's coordinates were taken mid-slide when a
  tuck moved the panel from Held to Windows, up to a page's width to the side (logged at −360 and
  −309 pt). Measured inside the list, a row came back half a row too high while the list was changing
  height, and the colour covered the page header. Rows now report across within the Windows page,
  which slides with it, and down within the panel, which already has their final places. The first
  version also opened only after the flight ended, so the dot sat still on the icon for about 0.2 s,
  and its accent turned to the tint within a frame or two, because the colour ran on the opening's
  eased curve; the colour now has its own clock.
- **Checked:** `swift build`, `scripts/test.sh` (190 tests). Recorded at 60 fps from a separate library,
  with the panel open and a stand-in window service (no real windows): a new app row, a window joining
  an existing app row that moves to the top, and a tuck from the Held page while the page slides back to
  Windows each land on the top slot's icon (to the pixel against the icon shown afterwards), open out
  below the header and clear to the row. With the panel closed, the card still lands on the notch's
  token, which reads "+1".
- **Not checked:** tucking real windows through Accessibility, since this build is ad-hoc signed and
  has no Accessibility permission; and Reduce Motion.

### The drop rim traces the notch, and the invitation rides its spring
- **Decision:** The drop rim around a notch is the outline without its top edge, which is the screen's
  own edge. It ran along the top of both wings and in under the camera housing, and stayed there while
  the rest of the band sprang out and bounced. The glyph and "Drop items here" now move on the
  outline's spring, so they come down with the band, bounce with it, and go back up into the notch
  with it; they used to appear at their final place. The open panel's drag rim, which was a rounded
  rectangle inset 4 pt inside the panel (its own 16 pt corners, straight across under the notch, and
  still while the panel sprang open), is now the same rim on the panel's outline, above the panel's
  content, in the colour of the session under the pointer, as before.
- **Why:** the coloured edge around the notch, with a file hovering, went in too much and didn't wrap
  around the notch, and the line just sat there while the bounce played. I wanted the download
  symbol to move with the notch's animation.
- **Checked:** `swift build`, `scripts/test.sh` (190 tests). `--snapshot-panel` now renders the
  invitation near the notch and over the target, around a notch drawn on top as the hardware hides what
  is under it, and as a bubble: there is no line along the top. Recorded at 60 fps with the invitation
  stepped through its levels and then a drag opening the panel: the words ride the band out and back,
  and the rim follows the panel's shoulders, sides and lower corners.
- **Not checked:** a real file dragged from Finder, since this harness sets the levels directly.

## 2026-11-04: Picker rows named by their app

- **Decision:** Each row in Choose windows is named by its app alone; the window's title is no longer
  shown on the row. VoiceOver still reads it after the app's name, leaving it out for an untitled
  window or one titled after its app (Music, Calendar). An app with several windows stays one row, its
  name over "2 windows", with the titles in its menu.
- **Tested:** app only against app + title (the title on a grey line under the name), rendered with
  `--snapshot-panel` on eight windows in seven apps, including a long Safari title, Music titled
  "Music" and an untitled TextEdit window. App + title said what each window held and kept every row
  two lines; app only was tidier and shorter. I chose app only.
- **Fixed:** the several-windows row used the borderless menu style, which flattens a custom label to a
  large bare icon and the app name, dropping "2 windows". It is now a plain-button menu with the
  shared row padding and hover. The snapshot fixture gave every window its own process, so this never
  showed; windows of one app now share one, as on a real Mac.
- **Checked:** `swift build`, `scripts/test.sh` (191 tests), `--snapshot-panel`.

## 2026-11-04: The tucked window goes up into the notch, not along it

**Superseded in part** by "2026-11-08: One place, one fold: the simplification redesign". The card now
goes up into the mark's dip on the left wing, or into its row in the open fold, not a token.

- **Decision:** The card's path is a cubic curve: it rises from the window, glides across below the
  menu bar, and goes straight up into the token from beneath it (control points straight above the
  window and straight below the token, half and three tenths of the climb).
- **Why:** the animation went outside on its way up. The old curve's control point sat level
  with the token, so the card arrived sideways at the token's height: drawn to scale on this Mac, it
  spent the second half of the flight sliding along the menu bar beside the notch, or across the
  hardware notch from the other side, where the camera housing hides it. It used to fade on the way, so
  that showed less; since it stays visible until it becomes the token, it was plain to see.
- **Checked:** `scripts/test.sh` (a new test: from either side of the screen, the last 15% of the
  flight climbs from below the token more than it moves sideways). The card's frames, drawn to scale
  over this Mac's notch and menu bar for windows on either side, enter the token's wing from below.
  Not recorded on screen.

## 2026-11-04: Black, like the notch it hangs from

**Superseded** by "2026-11-08: One place, one fold: the simplification redesign". The open fold follows
the Light or Dark setting again: warm paper or charcoal, each with an Increase Contrast tone, and one
accent, the system blue. The closed notch and the bubble stay black, and the deposit card follows the
setting too.

- **Decision:** The panel and the bubble are black whatever the Light or Dark setting, so Tuck looks
  attached to the notch rather than like a window under it. The overlay window, its menus and the
  deposit card are pinned to the dark appearance. The space palette keeps its six muted accents and
  their dark tints, now its only surfaces; on black the accent itself is the text colour, so each
  space is one accent and one tint. Row, pressed and tile greys are set for black (8, 13 and 11%
  white), because the system fills nearly vanish on it, and are stronger in the high-contrast
  appearance.
- **Why:** the light panel under a black notch broke the illusion of a surface coming
  out of the hardware.
- **Removed:** the palette's light pastels and light icon shades, which nothing drew any more.
- **Checked:** `swift build`, `scripts/test.sh` (189 tests). `--snapshot-panel` now renders under the
  Light setting to confirm the panel stays black, under Dark, and with Increase Contrast; the bubble
  is black on both a light and a dark menu bar.
- **Supersedes in part:** "Follow the system appearance" in "Muted space colors and compact panel
  refinements", "the Light/Dark panel" in "Apple-built panel", and the black-to-window-colour crossfade
  in "Going back into the notch, and landing as the token" below, which has nothing left to fade.

## 2026-11-04: Going back into the notch, and landing as the token

### The panel closing into the notch
- **Superseded in part:** the panel is now black like the notch, so there is no colour left to
  crossfade; the token and count still go back to the wings as closing starts. See "Black, like the
  notch it hangs from" above. Since "2026-11-08: One place, one fold: the simplification redesign", the
  open fold is paper or charcoal, so the fill crossfades again, from and to black, in 0.26 s; there is
  no token.
- **Decision:** The outline's fill crossfades between notch-black and the panel's window colour as the
  surface opens (0.2 s) and closes (0.24 s). Closing, the token and count go back to their places in
  the wings the moment it starts, while they are still hidden.
- **Why:** the animation of Tuck going back into the notch was broken. Since the panel took the
  system's window colour, the shape stayed panel-grey all the way in and turned black only once the
  spring had fully settled: recorded at 60 fps, it sat at its collapsed size in grey for about half a
  second, with the black hardware notch showing through it, then snapped to black. The collapsed
  content was still placed for the open panel, so it faded in about 23 pt out, at the shape's edge,
  and jumped into place at the same moment.
- **Checked:** recorded again, the shape is black by the time it reaches the notch and the token fades
  in where it stays. Opening leaves the notch black and takes the panel colour as it grows.

### The tucked window's card lands as the token
- **Superseded in part:** with the panel open, the card now lands in the window's row on the Windows
  page and the strip's token doesn't count it. See "A tucked window lands in its row; the drop rim
  wraps the notch" above. Since "2026-11-08: One place, one fold: the simplification redesign", there is
  no token: with its row not showing, the card lands in the mark's dip, which pulses as the count rises.
- **Decision:** The card arrives as a copy of the token it lands on, which `DepositLanding` now
  describes: around the notch the 18 pt token in the session's colour with its number in black; in the
  open panel the strip's 24 pt token, filled with a black number when current, otherwise tinted with
  its number in its colour and a faint edge. The card's bounds shrink, not a scale, so it ends a true
  circle with an unscaled edge; its corners round to a capsule halfway, so it closes in as a circle; the
  number fades in centred on its cap height, as the token draws it. It merges into the token on the
  clock over the last 15% of the flight, rather than on the flight's eased curve, and the token's swell
  and "+n" start as it does (85%, when the eased card is about 99% of the way; it was 70%, about 94%).
  The strip's token takes its size, edge and number font from `Theme`, which the card shares.
- **Why:** the dot coming up didn't look like the dot at the top. It ended as a fixed 10 pt
  pill, uniformly scaled from the card's proportions, in the bright accent colour, unlike either token.
  Its fade also ran on the eased curve, whose last stretch only creeps, so it vanished while still
  about four times the target's size, short of it. Swelling at 70% was set when the card vanished
  early; with the card now visible until it arrives, the swell and "+n" would have started under it.
- **Checked:** recorded frame by frame into the open panel and the collapsed notch: the card closes in
  as a circle and merges at the token's own size and position. The flight's panel is placed on whole
  points so the card's coordinates are the screen's.

## 2026-11-04: Setup: one working pretend screen

- **Why:** the first run in a real window found four problems. The pretend screen's notch sat on the
  frame's border and looked like it poked out of it; the practice notch on the gesture step was a
  picture (its pages, rows and items did nothing); the window's tuck swapped a dark card in for the
  window; and the dragged PDF jumped to centre under the pointer and left the desk.
- **One screen:** the tour and the gesture step now show the same `PretendScreen` on one `TourDesk`,
  which merges the old tour desk and practice notch: three sessions (each holds what went into it), the
  stage (tucked away, closed, open), both pages, the window, the PDF and the note. On either step you can
  click the notch, the page names and the session dots, press Tuck, drop the PDF in, bring things back
  and swipe. Moves (open, tuck, hold, bring back) tick off from anything; gestures only from swipes.
- **The frame:** the screen sits in an 8 pt bezel and the notch hangs from it, as on a MacBook; the
  gesture step marks where swipes count with a soft glow under the notch, inside the screen, instead
  of a dashed box that ran off its top. The wings are 42 pt, so the three dots sit clear of the edge.
- **Tuck and restore:** the window itself flies along `DepositFlight`'s path: a slight lift, then it
  shrinks quickly while still looking like itself, lets go of its contents and only near the dot warms
  into the session's colour and merges; the row and count appear as it lands, with "+1". Restoring
  reverses it, so the window grows back out of the dot to exactly where it was. The window was moved
  clear of the open panel so it never jumps above it.
- **Drag and drop as in Finder:** a see-through copy lifts from where the file was grabbed and follows
  the pointer; the original dims and stays on the desk, because Tuck keeps a reference. The cursor
  shows the copy badge over a target, and the copy draws in and lets go of its name there, so "Drop
  items here" stays readable. Let go over the notch or panel and the copy is pulled into the dot (the
  row appears as it lands); anywhere else it slides back. Bringing the file back means dragging it from
  Held into the Notes window, where it appears as an attachment and stays held.
- **Fixed on the way:** the notch and the desktop are now buttons, since a tap gesture missed the first
  click in a window that wasn't key; the pretend screen changes the setup model directly, since changes
  made from a delayed callback through a binding (a drop landing) redrew the screen but left the step's
  instruction and chips stale until the next change; the "+1" badge no longer truncates to "…"; the
  blank front-window bar says "No window in front"; and list and bar crossfades no longer overlap.
- **Checked:** `swift build` with no warnings and `scripts/test.sh` (203 tests in 31 suites; the setup
  suite now covers sessions, the note and clicks that don't tick gestures). In a real window (debug
  build, isolated library, input sent in the background so the person's pointer wasn't touched):
  opening by click and by swipe, Tuck with frames captured through the flight, a drop on the open panel
  and on the closed notch, a refused drop, page and session clicks, restore with frames of the return
  flight, dragging the PDF into the note, closing by clicking the window, and all six swipes, each with
  the step's text and chips read back through the Accessibility tree. `--snapshot-ui` renders 24 setup
  images; all were reviewed.
- **Cost:** the stripped, signed release binary is 2,291 KB, slightly smaller than with the separate
  practice notch (2,304 KB). Still nothing at idle.
- **Not checked:** the dwell-to-open during a held drag (the background drag can't pause near the
  top), the cursor badge (screenshots don't show the cursor), and a real trackpad's haptics.

## 2026-11-03: Apple-built panel: one status either side of the notch, Spotlight rows, AirDrop prompts

- **Superseded in part:** the panel is now always black; see "Black, like the notch it hangs from" above.
  Since "2026-11-08: One place, one fold: the simplification redesign", the closed notch shows the mark
  and count in Tuck blue, with no token or "+n"; the strip's tokens are gone; rows are one line beside a
  20 pt picture, with hairlines between them and no window size; and the fold follows Light or Dark
  again.
- **Superseded in part:** held items and clipboard copies are now tiles, two to a row, rather than
  Spotlight rows; windows keep their rows. See "The clipboard keeps every kind, in tiles two to a row,
  and search reads kinds and days" above.
- **Decision:** Finish the redesign from six reference designs for the notch, building on the muted
  palette, the Light/Dark panel and the Settings sidebar already in place, and using the system's own
  pieces wherever one exists.
  - **Collapsed notch:** one status either side, as the system's notch activities show one: the current
    session's token on the left wing (its colour, its number knocked out in black; a tray for Loose) and
    the count on the right, at the body size with tabular digits. A deposit pulses the token and
    stretches it into a capsule reading "+n". This replaces up to three 6 pt dots and a ring.
  - **Space tokens in the panel:** the current session's token is filled with its colour, the others
    tinted; "+n" is counted inside the token instead of floating above it (it was clipped against the
    notch band). Hovering an empty session shows Launchpad's ⓧ at its leading corner, and VoiceOver gets
    a Close Session action for it. The dashed "+" and the hairline under the strip are gone.
  - **Rows:** Spotlight's anatomy: 28 pt pictures, a semibold 15 pt title, a 12 pt grey line joined with
    " · ". Held files show their Quick Look thumbnail (`QLThumbnailGenerator`) and "kind · size"; links
    show the app that opens them, music the Music app. Times read "2 min ago" from the system's relative
    formatter. Windows inside an app row show their size (and display, with two or more) on their own
    line, so hover no longer has to. Rested is a plain crescent and word, not a pill. The moon that rests
    an app appears on hover, only for apps that can rest, and stays as a sun while the app rests.
  - **Placement chooser:** laid out like a window's green-button menu, "Move & Resize" and "Fill &
    Arrange" rows of glyphs, then Original and Next display by name; a highlighted glyph is named in its
    section's header.
  - **Prompts:** as AirDrop asks a question: glyph, bold title, grey line, large capsules. Two choices
    share the width with Cancel first; three stack, as an alert stacks its buttons, with Cancel last.
  - **Front-window bar and footer:** no grey card, a separator instead, so the blank bar after a tuck is
    simply empty; Tuck's glyph points up, as the card flies up. The footer is a status line only; how
    rows behave is in their tooltips and menus.
  - **Empty states** use `ContentUnavailableView`. **Menus** give every item an SF Symbol; held items
    gain Quick Look (the shared `QLPreviewPanel`) and Share (`ShareLink`). **Feedback** ("Copied") is a
    symbol that bounces once and a word, not a pill.
- **Fixed:** in Light mode the notch's count, ring and "Drop items here" resolved to Light label colours,
  dark on the black notch. Everything drawn on the closed notch now resolves in the dark appearance.
  Without a current session the drop rim was the label colour; it is now Tuck's accent.
- **Removed:** `DotRowLayout` and its two tests, the dot ring, the footer's hints and hover details.
- **Checked:** `swift build`, `scripts/test.sh` (189 tests in 30 suites). The debug-only
  `Tuck --snapshot-panel <folder>` renders 11 panel states and the collapsed surface (notch, deposit,
  Loose, bubble) in Light, Dark and both with Increase Contrast, from an in-memory library and a stand-in
  window service; all were reviewed. Reduce Motion paths: the token's stretch, the feedback bounce and
  every spring fall back as before.
- **Not checked here:** the collapsed surface and Quick Look in a running copy (another Tuck from a
  separate worktree was running and was left alone), VoiceOver by ear, and Reduce Transparency (the panel
  uses no material, so nothing changes under it).
- **Kept:** every feature, interaction and animation token. The muted palette, the Light/Dark panel, the
  plain page tabs and the one-tap ×, and the Settings sidebar are unchanged.
## 2026-11-03: Setup and tutorial

- **Superseded in part:** the Welcome step no longer has a title or lines; it is Tuck's logo alone. See
  "Setup opens on Tuck's logo alone" above.
- **Superseded in part:** Swipe on the notch teaches only open, change page and close, and no longer
  says where Tuck Away is. See "The gesture step teaches three swipes" above.
- **Superseded in part:** the separate practice notch, the card that stood in for the tucked window
  and the PDF leaving the desk are replaced by **Setup: one working pretend screen** above.

- **Decision:** the first launch opens **Set Up Tuck**, an 840 × 600 pt window that teaches by doing,
  in six steps: Welcome, How Tuck works (a pretend screen), Choose what you want (the optional extras),
  Swipe on the notch (a practice notch), One permission (Accessibility) and You're set (open at login).
  Each step opens with a title and a line saying what to do; the footer has progress dots ("Step n of
  m"), Back and Continue (Return). `setup.completed` is written on finish, not on close, so a setup
  closed part-way opens again at the next launch. Settings → General → Open Tutorial… opens the same
  window as "Tuck Tutorial", with only the tour, the choices and the swipes, ending on Done.
- **The process, on a pretend screen:** a notch, a Notes window and a PDF on a 776 × 300 pt desk. The
  person clicks the notch (or swipes down) to open the panel, presses Tuck in its front-window bar, drags
  the PDF to the notch and brings them back (clicks the window's row; drags the file out). Chips tick
  off Open the notch, Tuck a window, Hold a file and Bring it back as they happen, with a line saying
  what the latest one means; the step's own line changes to say what to do next.
- **Tuck's own logic on the desk's geometry,** so the tour needs no permission and touches no real
  window: `TourLayout` (TuckCore) holds the desk, and the drag runs `DropApproach.invitation`,
  `isArmed` and the dwell against it, with the approach zone now built by
  `DropApproach.approachZone(in:)` for both the desk and real displays (`ScreenAnchor` uses it; the
  numbers didn't change). The card follows `DepositFlight` with the real timing curve and keyframe
  times, the panel and notch move on `SurfaceMotion`'s springs, and the Tuck button and rows use the
  panel's own button and row styles. A drag released beside the notch is refused and springs back.
- **Gestures:** the practice notch has three sessions and both pages. Two-finger swipes go through the
  real `SwipeGestureTracker`, read exactly as `SurfaceView` reads them, and play the real haptic
  through `TuckModel.performHaptic` (so the setting and pacing apply). Only swipes tick anything off;
  a click opens and closes it, and the step says where Tuck Away is for people without a trackpad. The
  Haptic feedback switch sits above it. Swipes come from `SwipeArea`, an `NSView` that takes no clicks
  and has a local scroll-wheel monitor only while it is in the window.
- **Choices:** six pads in a row, named as Settings names them: Open when a drag comes near and Show in
  menu bar (on by default), Use keyboard shortcuts, Modifier-drag, Smooth scrolling and Clipboard
  history (off). Pointing at a pad plays a short drawing of what it does (once per entry, only then; with
  Reduce Motion it only lights); the switches are the real settings. Rest is mentioned, not offered:
  it's experimental and has its own first-use explanation.
- **One permission, asked late:** the step says what Accessibility reads (the window in front, each
  window's app, title, position and size), what it never reads, and that nothing is recorded or sent.
  The button shows the system prompt the first time in a launch, then opens the Accessibility list
  (`AX.hasPrompted`). The page reads `TuckModel.accessibilityTrusted`, which the existing distributed
  notification keeps current, and re-reads it when the step appears and when the window becomes key:
  no timer. Continue always works. While setup is open, switching on modifier-drag or the mouse wheel
  doesn't show the prompt (the permission step comes next); closing setup lets it ask.
- **Finish:** Open Tuck at login is on by default the first time and the system's state afterwards, and
  is applied only if it changed; it is disabled under `swift run`. Finishing the first run opens the
  real panel once, so the person sees where Tuck lives.
- **Also:** `SettingsWindow` is now `TuckWindow` (⌘W) and serves both windows; `LoginItem.isEnabled`;
  `-TuckOpenSetupOnLaunch` and `-TuckOpenTutorialOnLaunch` open them for checks.
- **Inspiration:** the interactive setup pattern (teach by doing, choose where you experience, one
  permission after the value), as other Mac apps' first runs use it. Tuck's steps, pretend screen, copy
  and drawings are its own.
- **Checked:** `swift build` with no warnings, `scripts/test.sh` (202 tests in 31 suites, 11 new: the
  tour's moves, the drop and flight geometry on the desk, and the practice notch fed by the real swipe
  tracker) and `scripts/build-app.sh` pass. `Tuck --snapshot-ui` now renders every setup step and three
  part-way states in light and dark; all were reviewed. A real window (debug build, isolated library)
  rendered as the snapshots do, and pressing Back and Continue through the Accessibility API moves one
  step each. In the Accessibility tree the progress is "Step n of 6" and the practice notch is a button
  whose value says its state ("Open on Windows, session 2").
- **Cost:** the stripped, signed release binary grew from 1,947 KB to 2,304 KB, all of it SwiftUI view
  code for the setup steps. Nothing changes at idle: the window and its views exist only while it is
  open, the swipe monitor only while a practice area is showing, and the pads animate only when tried.
- **Deferred:** pointer clicks, drags and trackpad swipes on the pretend screen were not driven end to
  end in a real window here (the logic and geometry are unit-tested and the views were rendered); try
  them by hand with `-TuckOpenSetupOnLaunch YES`. Not yet checked: granting Accessibility while the
  permission step is open, open at login from a bundled build, a display without a notch (the last step
  then says "bubble"), and a full VoiceOver pass through the tour's drag actions.

## 2026-11-03: Settings window redesign

**Superseded in part** by "2026-11-08: One place, one fold: the simplification redesign". Settings opens
from Settings… in the band's context menu, not a gear in the panel, and Held's drag setting is now
"Widen when a drag comes near", since a drag no longer opens the panel.

- **Decision:** Settings looks like System Settings: a 150 pt sidebar of eight tinted panes (General
  and Notch; Windows, Keyboard and Mouse under "Across apps"; Rest and Held under "In the panel"; About
  under "Tuck"), a grouped form for each pane, and the pane's tile and name in the title bar, level
  with the window buttons. An empty unified toolbar makes the title bar tall enough for that header. The
  content is fixed at 620 × 540 pt, with the sidebar running under the transparent title bar. Every
  existing setting and action is kept, and settings that depend on a switch dim instead of disappearing.
- **Choices you can see:** the modifier-drag keys, the scroll Feel, the clipboard retention, the
  displays and the notch style are illustrated tiles instead of segmented controls and menus. The keys
  are keycaps around SF Symbols (the ⌃ ⌥ ⌘ characters sit at different heights in the system font);
  each Feel draws its glide's distance-over-time curve, and picking one plays that glide once at its
  real speed (skipped with Reduce Motion); the retention tiles show how far back the history reaches;
  the style tiles draw a menu bar with a bubble or a notch. Action buttons share one soft-tile style.
- **New settings,** each of which keeps today's behaviour by default:
  - **Open at login,** through `SMAppService.mainApp`. Tuck stores nothing: it reads the system's
    login-item list back after every change and whenever General appears, and if approval is needed it
    points to System Settings › General › Login Items. When Tuck runs as a bare executable
    (`swift run`), the switch is disabled and says why.
  - **Show in menu bar.** While it's off, the status item doesn't exist. Settings opens from the panel's
    gear, or by opening Tuck again (`applicationShouldHandleReopen`).
  - **Notch → Show Tuck on:** all displays, the built-in one, or external ones. If none matches (the lid
    is closed, say), the menu-bar display keeps a surface (`SurfaceDisplays`, tested).
  - **Notch → Displays without a notch:** a bubble, or a drawn notch 180 pt wide and as tall as the menu
    bar. A tucked drawn notch draws nothing, since there's no hardware notch behind it.
  - **Notch → Show beside full-screen apps** (`fullScreenAuxiliary`) and **Show in screenshots and
    recordings** (`sharingType`, deposit flights included).
  - **Held → Open when a drag comes near:** the drop invitation. While it's off, the drag watcher's
    global monitors don't exist; dropping straight onto the surface still works.
  - **About:** a drawn Tuck mark (not an SF Symbol), the version, Show in Finder for the library
    folder, and what is always true (no account or network, nothing collected on its own).
- **Also:** the Rest pane lists the allow-listed apps on this Mac, their icons in one fixed column, and
  marks any that are resting. Held shows how many clipboard items are kept. ⌘W closes the window, since
  Tuck has no main menu to supply it. `-TuckOpenSettingsOnLaunch` now shows Settings without taking
  focus.
- **Not added:** settings from the reference notch apps that Tuck has no behaviour for, such as HUDs,
  idle activity and syncing settings between Macs (Tuck stays on this Mac). Mission Control and the app
  switcher are listed as always true, since Tuck never appears in them.
- **Kept:** existing UserDefaults keys are unchanged and each new one is read on its own with a
  fallback, so saved settings carry over with no migration. The window is still created on open and
  released on close, so the SwiftUI tree costs nothing while closed; the pane resets to General when
  the window is reopened. The window now also calls `orderFrontRegardless()`, because macOS can decline
  an agent app's request to activate while another app is in front.
- **Inspiration:** the sidebar-of-panes layout of System Settings, and the general settings notch
  utilities offer (menu-bar icon, full screen, screen capture, display choice, notch or
  island). Tuck's panes, copy, illustrations and mark are its own.
- **Checked:** `swift build` with no warnings, `scripts/test.sh` (191 tests in 30 suites),
  `scripts/build-app.sh` and `git diff --check` pass. The debug-only `Tuck --snapshot-ui <folder>`
  renders every pane in light and dark, with switches off and on (32 images), hosted as the real window
  hosts it; it uses a throwaway defaults suite and library, both removed afterwards. All were reviewed.
  A real window with an isolated support directory confirmed the header level with the window buttons
  and the dark pane header (off screen, the title-bar strip renders white). With the menu-bar item and
  screenshots turned off, the debug instance had no status-item window, and `screencapture -l` could
  not capture its surface.
- **Cost:** the release binary grew from 1,640 KB to 1,856 KB. Nothing changes at idle: the panes exist
  only while the window is open, the glide demo is one 0.55 s animation, the login-item status is read
  only when General appears, and the drop invitation, when off, removes three global monitors.
- **Deferred:** actually registering a login item, which changes the Mac's login items, so it wasn't
  tried here; it is not yet known whether an ad-hoc signed build keeps its login item after a rebuild.
  The drawn notch and the display choice weren't tried on a real external display (this Mac had only
  its built-in one), and hiding beside full-screen apps wasn't tried with a full-screen app. Also
  deferred: a VoiceOver pass, and moving through the tiles with Full Keyboard Access.

## 2026-11-03: Palette-driven panel controls

**Superseded** by "2026-11-08: One place, one fold: the simplification redesign". There is no session
palette; the fold has one accent, the system blue.

- **Decision:** Inject the current session's `SpacePalette` through the expanded panel. Regular buttons use its darker icon color on its pale surface, hover/pressed states use its accent, and prominent actions fill with that accent and use dark text. Destructive buttons remain rose. Placement choices, Rest controls, the Loose target, focus rings and the page selection now use the active session palette too. This means the controls follow blue, purple, green, orange, rose or teal instead of always showing system grey or static blue.
- **Checked:** `swift build`, `scripts/test.sh` (188 tests in 29 suites), and `git diff --check` pass.
- **Deferred:** Runtime visual check in the currently running app; the running process was left untouched and still has its previous UI loaded.

## 2026-11-03: Simpler page tabs and window picker

- **Superseded in part:** a single window's row is now named by its app, not by the window's title,
  and the several-windows menu row keeps its "2 windows" line. See "Picker rows named by their app"
  above.
- **Superseded in part:** The fixed-blue button decision below is replaced by the newer **Palette-driven panel controls** entry above.
  Since "2026-11-08: One place, one fold: the simplification redesign", there are no page tabs; the
  window picker stays.
- **Decision:** Remove the pill-and-underline treatment from Windows/Held; use plain labels with the palette's legible blue for the selected page. The open-window picker now shows one app-logo/title row for a single window and an app-logo menu of window titles for multiple windows. Selection checkmarks, selected counts and the single Tuck action remain; dimensions, display metadata and bulk-tick buttons are removed. Cancel is the small close control in the picker header.
- **Color:** Keep primary buttons on the muted blue, destructive actions on rose, and use the matching
  pale session surface for selected window rows and app menus. Labels use dark text on the pale blue
  primary fill for contrast.
- **Checked:** `swift build`, `scripts/test.sh` (188 tests in 29 suites), and `git diff --check` pass.
- **Deferred:** Runtime visual and interaction review of the tabs, menus and palette in Light and Dark Mode.

## 2026-11-03: Muted space colors and compact panel refinements

- **Superseded in part:** the panel no longer follows the system appearance and the light pastels are
  gone: the panel is black and the palette is set for it. See "Black, like the notch it hangs from"
  above.
- **Superseded in part:** The Windows/Held tab treatment, labeled Select button and one-row-per-window picker described here are replaced by the newer **Simpler page tabs and window picker** entry above.
  Since "2026-11-08: One place, one fold: the simplification redesign", there are no session colours,
  and the fold follows Light or Dark again, in warm paper or charcoal.
- **Decision:** Give sessions a six-color palette—blue `#7299C5`, purple `#A48BC7`, green `#7FAB94`,
  orange `#D9AA69`, rose `#CD8E91` and teal `#7DAAB2`—with pale coordinated surfaces in Light Mode and
  quiet tinted surfaces in Dark Mode. Persisted `SessionColor` raw values remain unchanged; TuckApp maps
  the first six in-use colors to distinct palette hues. Numbered space badges retain a non-color cue.
- **Panel:** Follow the system appearance instead of forcing dark mode; use semantic window,
  grouped-fill, text and separator colors, while keeping the closed notch black. Controls are shorter and
  quieter, Windows/Held are compact tabs without counts, Select is separate from a one-tap X clear
  action, and archive/restore remain in the secondary-click menu. Window-picker rows omit dimensions and
  display metadata visually while retaining it in VoiceOver labels. App icons in the Tuck preview are
  larger, and app rows expose a compact Rest/Wake control.
- **Scrolling:** Scroll ownership now compares the reported SwiftUI list frame with the hosting view's
  local pointer coordinates, rather than offsetting through the animated surface. Runtime trackpad/mouse
  verification is still needed.
- **Checked:** `swift build`, `scripts/test.sh` (188 tests in 29 suites), and `git diff --check` pass.
- **Deferred:** Light/Dark visual capture of populated pages, Reduce Transparency and Full Keyboard
  Access checks; hands-on confirmation that scrolling the candidate list no longer dismisses the panel.

## 2026-11-03: Apple-style visual redesign (in progress)

- **Superseded in part:** This entry's dark-only panel decision and system-blue space mapping are changed
  by the newer **Muted space colors and compact panel refinements** entry above. The black collapsed notch,
  semantic system colors, and Foundation-only core constraints remain. Its Settings tabs are replaced by
  the sidebar of panes in the newer **Settings window redesign** entry above. Since "2026-11-08: One
  place, one fold: the simplification redesign", session colours are gone, the system blue is the one
  accent, and the fold follows Light or Dark.
- **Decision:** Keep Tuck's panel dark and the notch surface hardware-black, while replacing hand-tuned
  white/grey values with AppKit's semantic text, fill, separator, control, destructive and accent
  colours. Primary actions and interactive emphasis use macOS system blue; neutral controls use subtle
  system fills so white labels remain legible. Panel fonts now use SwiftUI text styles. System
  appearance and contrast preferences determine semantic colour resolution; no custom luminance
  calculation remains.
- **Sessions:** `TuckCore.SessionColor` stays Foundation-only and keeps all persisted raw values. TuckApp
  owns the mapping to system colours; existing raw names remain and additional system-colour names
  make the palette more distinct. The former default red/coral dot now maps to system blue, clearly
  distinct from the notch's red screen-recording indicator. The selected ring uses a one-point outline
  centered on the same pixel-aligned dot frame. The expanded session strip shows a stable number on each colour dot,
  so a space is not identified by colour alone. Session numbers and colour names are included in
  VoiceOver labels. Session colours remain reserved for session identity and drop destinations, not
  ordinary action emphasis.
- **Panel:** Enlarged and clarified row icons and control targets, combined relative times with row
  subtitles, made Rested and overflow indicators neutral system chips, and used system blue for
  selection/action feedback. Aligned the current-session ring to the dot's frame. Existing page, row,
  deposit, and gesture behavior is unchanged.
- **Settings:** Reorganized the existing controls into General, Windows, Keyboard and Mouse tabs; all
  existing settings and actions remain present. The window is wider and shorter to fit those pages.
- **Checked:** the six notch references; `swift build`, `scripts/test.sh` (188 tests in 29
  suites), `scripts/build-app.sh`, and `git diff --check` pass. An isolated notch capture shows the
  default session in system blue rather than recording-light red. TuckCore remains Foundation-only.
- **Deferred:** runtime review of expanded button states, populated pages, Reduce Transparency and Full
  Keyboard Access. Settings tabs were inspected in an isolated test launch; no user library was used.

## 2026-11-03: Sample data removed

**Superseded in part** by "2026-11-08: One place, one fold: the simplification redesign". A first launch
starts with an empty stream rather than one empty session, and the pages' empty states are gone: an
empty Tuck says "Drop into Tuck". Samples are still taken out of an earlier library, now as its sessions
merge.

- **Decision:** Tuck no longer ships sample sessions. A first launch starts with one empty, current
  session, so the panel's empty states say what to do: "No windows tucked here" on Windows and "Nothing
  held yet" on Held. Reset Sample Data is gone from the menu-bar menu and Settings, along with the
  "Sample" tag, the sample file and the simulated restore of sample windows.
- **Why:** the demo rows could pass for real tucked windows and items. They needed a tag, special cases
  in Clear, Restore All, Restore Last Tucked Window and Rest, and a reset command that could replace a
  real library. Real use starts empty.
- **Earlier libraries:** a library saved with sample content is cleaned once on load, and the result is
  saved. Sample windows are found by the `isSample` flag they were saved with, sample held items by
  their exact contents, so a link the person saved under its own title stays. A session left empty by
  this goes; a library left with nothing starts again from one empty session. Rest records are kept, so
  a resting app is still woken.
- **Checked:** four new tests: a fresh library; samples removed while real windows, items, an empty
  session and rest records stay; a library of only samples; libraries without samples load unchanged.

## 2026-11-03: Native polish pass

- **Superseded in part:** the four-size scale is now the system text styles (nothing under 12 pt), hover
  details moved from the footer into each window's row inside an app, and the footer is a status line
  only. See "Apple-built panel: one status either side of the notch, Spotlight rows, AirDrop prompts" above.
- **Superseded in part:** the panel's drag rim is no longer a SwiftUI overlay with its own animation; the
  surface draws it on its outline. See "A tucked window lands in its row; the drop rim wraps the notch"
  above.
- **Superseded in part:** The note below that space colours update only when the panel reopens is
  addressed by the later dynamic Light/Dark palette and appearance callbacks in **Muted space colors and
  compact panel refinements**.
- **Audited** the panel and Settings against Apple's Human Interface Guidelines (buttons, segmented
  controls, gestures, lists, colour, typography, accessibility, motion, menu bar, context menus,
  materials, Live Activities), a SwiftUI code review, an animation and interaction review, and the
  six notch references, using screenshots of every page from a separate library.
- **Broken, fixed:**
  - The page switch showed four segments ("Windows | 3 | Held | 4"), because a segmented control turns
    each text in a label into its own segment. On Held the "3" segment was highlighted. Each segment is
    now one text.
  - The switch moved sideways between pages, because "Select…" exists only on Windows. It is now
    anchored to the leading edge.
  - File, link and music rows waited out the double-click interval before opening. Only text rows,
    which can be edited, still wait.
  - The drag rim's implicit animation covered the whole panel and re-timed a deposit's row animations.
    It now covers only the rim.
  - A page change while the panel was still opening (a quick drop onto the closed notch) could leave
    the switch and the page out of step. Tried five times at 0, 0.1 and 0.25 s after opening, with no
    mismatch after the fix.
- **Guidelines, fixed:**
  - Click targets under 20 pt: the new-session button was 15 pt, the gear about 12 pt, the session
    menu 20 × 14 pt, the dots 18 pt, the close mark 9 pt and Loose about 16 pt.
  - Text under 10 pt: "Sample" was 8.5 pt, and "Rested", the placement names and the picker header were
    9.5 pt. The panel used 11 font sizes; it now uses four.
  - Buttons with no pressed state.
  - The prominent action looked like any other button; it now uses the accent colour.
  - Destructive actions used a custom pink; they now use the system red.
  - Prompts put Cancel last; it now comes first.
  - Window rows were tap gestures, which Full Keyboard Access can't reach; they are now buttons.
  - Tucking Tuck away was swipe-only; the menu-bar menu now has Tuck Away.
  - Text items had no Copy in their context menu.
  - Increase Contrast and Differentiate without colour were ignored.
  - Under Reduce Motion, prompts still slid.
  - Settings explanations were separate rows; they are now native descriptions and footers. The window
    is shorter, so it fits smaller displays.
  - The orange shortcut warning was about 2.2:1 in light mode; it is now readable text with an orange
    symbol.
- **Motion (Emil Kowalski's review):** press feedback at 0.12 s ease-out. A panel opened from the
  keyboard settles without overshoot, since keyboard actions shouldn't make people wait.
- **Why a small system:** one set of greys, four type sizes and three button styles keep every new
  control consistent, rather than styling each screen on its own.
- **Deferred:**
  - Held and clipboard rows keep tap gestures (double-click to edit, drag out), so Full Keyboard Access
    can't reach them; VoiceOver can, through their actions.
  - The hover and edit state still re-renders the whole panel through the shared model; narrowing what
    each row observes is a larger change.
  - Measuring with `onGeometryChange` in place of preference keys.
  - Context menus still show an explanation line for an unavailable Rest, against the guideline to hide
    unavailable items, because it explains why (see "Fewer dead ends to Settings").

## 2026-11-03: Docs cleanup

- **Superseded in part:** the guide is now `docs/guide.md`, and the README is a short landing page. See
  "The README is a landing page; the guide moves to docs/guide.md" above.

- **Decision:** The README is the guide to using Tuck: what each action does and how each feature
  behaves. Reports of how a feature was checked live here, in the entry that introduced it, and the
  README points to this log. Entries here are not rewritten; a later change adds a Superseded note to the
  earlier entry. `docs/architecture.md` keeps the mechanism; this log keeps the reasons.
- **Why:** The README had grown into a mix of guide, test reports and implementation notes, with several
  lines describing behaviour that later changed (windows "otherwise minimising", text page labels, the
  Rest badge on the icon). Older entries here contradicted newer ones without saying so.
- **Measured** again for the efficiency tables, on the release build (macOS 15.7, Apple silicon, two
  displays): collapsed after a fresh launch, 11 and 12 MB; with the panel open, 23 MB; 0.0% CPU in both.
  One launch read 31 MB while collapsed, including app-icon image data that only the open panel loads,
  so the panel was probably opened during it; whether memory returns after the panel closes is still to
  be checked.

## 2026-11-02: Native segmented control for the panel pages

**Superseded** by "2026-11-08: One place, one fold: the simplification redesign". There are no pages;
the Windows, Files and Copied lenses beside the notch narrow the one stream instead.

- **Decision:** The Windows and Held pages are switched by a native, small segmented control in the
  page header, each segment showing its count (Held reads Loose when no session is current). It
  replaces two uppercase text labels, the current one brighter.
- **Why:** A system control reads at once as a page switch, carries the selected state for VoiceOver
  without custom traits, and matches the rest of macOS. Swipes still change page.

## 2026-11-02: Seamless selected-window tucking

- **Decision:** When only some windows from an app are tucked, Tuck briefly hides the app, waits until
  its ordinary windows have left the screen, minimises the chosen windows, then immediately shows the
  app again. Other windows remain in their original state and, if the app was frontmost, it returns to
  the front. If the brief handoff does not finish in time, Tuck falls back to a normal minimise.
- **Why:** A selected window should read as going up into Tuck, not down to the Dock. Hiding every app
  window already achieved that for full-app tucks; the same small handoff now gives selected-window
  tucks a visually continuous path without private APIs, off-screen window tricks, or changing the
  behavior of unselected windows.
- **Safety:** The fallback remains the public, reversible macOS minimise state. Tuck records every
  successfully minimised window and restores it normally; an app that declines the handoff is never
  left hidden.
- **Measured** with a throwaway two-window app, sampling the window server: the tucked window never
  came back on screen, and the window left open was gone for 33–47 ms. Minimising must wait until the
  app's windows have actually left the screen (an app reports itself hidden a few milliseconds
  earlier), and must be confirmed before the app is shown again, or the window comes back with it.
- **Focus:** hiding the app in front makes macOS bring another app forward as the windows leave the
  screen. Asking for the app to be frontmost again straight after showing it is accepted and then
  dropped; asked once its windows are back on screen, it holds. A second request a moment later covers
  a dropped one, unless the person has clicked or typed since.
- **Known limit:** restoring a window that went to the Dock still plays macOS's restore animation.
  Un-minimising it while the app is hidden doesn't help: macOS shows the app again and animates anyway.

## 2026-11-02: The front-window bar goes blank once its window is tucked

- **Superseded in part:** the bar now follows the window in front while the panel is open. After going
  blank it names the next window the person brings forward, rather than staying blank until the panel
  opens again. See "The front-window bar acts on the window it names" above. Since "2026-11-08: One
  place, one fold: the simplification redesign", the bar is the Tuck button on the shallow fold's left
  wing, which goes blank the same way.
- **Decision:** After a tuck, the bar under the panel shows nothing if the window in front was tucked or
  belongs to an app whose windows were. It also shows nothing when no window is in front (a hidden app,
  an app with no window open). It keeps its size, so the panel doesn't change height under the card.
- **Why:** It used to re-read the front window the instant the window went, and so named the window
  that had just been tucked (still focused while it went) or the window behind it, inviting a second
  tuck the person hadn't asked for.

## 2026-11-02: Tucking goes into the notch, not the Dock

- **Superseded in part:** a window whose app keeps other windows open is now minimised out of sight too;
  only apps that can't be hidden still animate to the Dock. See "Seamless selected-window tucking"
  above.
- **Decision:** When the windows being tucked are every window of their app still on screen (its only
  window, Tuck All, or all of them ticked in Select…), Tuck hides the app instead of minimising. The
  windows vanish in place and the card flying up into the notch is the only movement. When the app
  keeps other windows open, hiding would take those too, so Tuck minimises as before, and the Dock
  animation remains for that case only.
- **Why:** I wanted tucking to go into the notch, not down to the Dock. macOS animates every
  minimised window to the Dock and offers no public way to aim or skip it; moving the window off screen
  first was tried and failed (macOS keeps a corner of it on screen). Hiding the app is public, instant
  and undone by the person the usual way (Dock, Command-Tab).
- **Restoring one of several hidden windows:** showing the app would show all of them, which the
  window groups promise never to do by accident. So the others are minimised first, while the app is
  still hidden, and stay tucked as minimised rows.
- **Checked:** with Tuck's probe window (one window) and a TextEdit instance Tuck's tests opened with
  two documents: both were hidden with their app and never minimised; restoring one TextEdit window
  minimised the other first, so only the chosen one appeared; restoring the second brought it back. A
  recording of the bottom of the screen (the Dock is set to auto-hide there) showed no Dock movement
  when the TextEdit windows were tucked. `NSRunningApplication.hide()` reported failure while hiding
  the app, so success is judged by the app's hidden state, with Accessibility's hidden attribute as a
  fallback.
- **Known limits:** the case with other windows still open keeps the Dock animation; minimising a
  hidden sibling at restore time was confirmed to work but not filmed; an app shown again by the person
  (Dock, Command-Tab) shows its tucked windows too, while their rows stay listed until restored, as with
  a window un-minimised from the Dock.

## 2026-11-02: Stabilisation pass

**Superseded in part:** "Hovering a window row names its size and display in the footer" is replaced by
each window's size (and display) on its own line inside an app row. See "Apple-built panel: one status either side of the notch, Spotlight rows, AirDrop prompts" above.
"2026-11-08: One place, one fold: the simplification redesign" removes the size as well: no row, tooltip
or VoiceOver label gives a window's size, and an app row opens to titles only.

No new features; what was there is made dependable and calmer. Found by a read-through of every
module, each fix kept small. Regression tests are in `PolishRegressionTests`.

### Safety and data
- **Superseded in part:** Reset Sample Data no longer exists. See "Sample data removed" above.
- **Removing a file inside a stack** now removes it (a stack left with one file becomes that file).
  Before, the row stayed but a copy Tuck had saved was deleted anyway.
- **Saved copies** are deleted only once no row refers to them, by Remove and by Clear alike; Remove
  says "Delete Saved Copy" for them.
- **Unplugged drives:** files on a volume that isn't mounted are kept, no longer dropped for good.
- **Unreadable library:** moved aside rather than overwritten; its rest records are still woken; the
  launch clean-up of saved copies is skipped.
- **Rest:** a new rest record reaches disk at once; Reset Sample Data wakes rested apps first; an app
  whose last row is forgotten, archived or cleared is woken, since nothing would offer to wake it.
- **Prompts tied to a session** (Clear, Restore All, Rest) go when the session changes, so Restore All
  can't restore a session other than the one shown. Clear re-checks what it would do at confirm time
  and asks again if that changed (an item dropped in meanwhile, a saved copy that would go).
- **Dragging a stack out** offers copy or link only: Finder could otherwise move the originals.
- **Reset Sample Data in Settings** asks first, as the menu-bar item did.

### Flows
- Restore All and Restore, Then Clear say once that Accessibility is needed, instead of reporting each
  window as failed; Restore, Then Clear restores one window at a time.
- A second click or shortcut while a window is still minimising does nothing, rather than reporting
  "No window to tuck"; a window brought back from the Dock can be tucked again.
- Rest's two prompts are one when the setting is off ("Turn On and Rest").
- Opening the panel from the keyboard or the menu bar gives it key focus, so Escape closes it.

### Motion and geometry
- Closing no longer snaps when something changes mid-close; panel height changes animate; a
  drag-opened panel keeps its opening spring; surfaces rebuilt after a display change keep their state.
- The dots and count no longer shift by a point or two on hover, press or the drop invitation; the ring
  sits on whole pixels at 1×; the dot's swell stays inside its ring.
- The drop target counts the top row of pixels; a file held still before it is dragged is still seen
  as a droppable drag.
- The notch's hit layer stays clear of the notch's rounded corners; a swiped-away bubble can be
  hovered, clicked and swiped back too.
- Reduce Motion: no drop flights, no bounce in any spring, pages cross-fade.

### Clarity and restraint
- Hovering a window row names its size and display in the footer, so rows never change height under
  the pointer; the ⌘-click hint is in one place.
- One crescent per rested row (the tag), not two; an open app row doesn't repeat its count.
- Footer messages fit on one line; placeholder switches (launch at login, window previews) are gone
  from Settings; Clear Clipboard History and the menu's Restore Last Tucked Window are disabled when
  they can't act.

### Accessibility and cost
- Tertiary text is 0.46 white (about 4.5:1) instead of 0.34 (2.9:1); the faint shade is decoration
  only. Rows are single VoiceOver elements with spoken times; status lines are announced; the
  placement chooser is in each row's menu; the + and gear buttons and the shortcut fields are labelled.
- Accessibility requests time out after 0.25 s everywhere, not only for app elements. The Rest
  workspace observers exist only while an app rests. The shortcut recorder's key monitor ends with the
  Settings window.

### Not changed, on purpose
- The drag watcher's always-on global monitors are how a drag from any app is noticed; they do work
  only during droppable drags.
- Matching windows by title after a relaunch, and the remaining fine points of the outline springs
  (landing a spring on a width change), are left as they are; see the report for this pass.

## 2026-11-02: Haptics for page events only

**Superseded** by "2026-11-08: One place, one fold: the simplification redesign". Haptics now play only
for crossing the drop target, a deposit and a placement snapping, still at least 0.35 s apart. Swipes,
opening and closing no longer tick.

- **Decision:** A haptic tap now plays only when a swipe changes what Tuck shows: opening or closing the
  panel, moving between Windows and Held, or tucking Tuck away and bringing it back. Nothing else taps:
  not clicks (opening the panel by click, choosing a session, the + button, copying, opening an item),
  not switching session by swipe, the placement chooser, placing or restoring a window, tucking,
  dropping, zipping, or dragging over a session dot. Taps are also kept at least 0.35 s apart
  (`HapticPacing`), so quick swipes in a row can't become a buzz.
- **Why:** the taps were overwhelming. A click on a Force Touch trackpad already produces its own
  click, so a tap on top doubled it; small actions are frequent and already shown on screen (feedback
  text, the dot's swell, the card flying up).
- **Kept:** the Settings switch, still on by default, now describes exactly these moments.
- **Supersedes:** "Haptics: deliberate commits only" below.

## 2026-11-02: Global keyboard shortcuts

- **Superseded in part:** there are no sample rows to skip. See "Sample data removed" above. Since
  "2026-11-08: One place, one fold: the simplification redesign", Restore brings back the newest tucked
  window of all, as there are no sessions.
- **Decision:** Three optional global shortcuts, off by default: Tuck Front Window (⌃⌥⌘T), Restore Last
  Tucked Window (⌃⌥⌘R) and Open or Close Tuck (⌃⌥⌘O). Each can be changed or cleared in Settings, and
  the menu-bar menu shows them while they are on.
- **Why these:** tucking without opening the panel is the core action, and restoring the most recent
  window is its undo. Restore brings back one window only, the newest real one in the current session;
  sample rows are skipped because restoring one moves nothing. Opening the panel uses the display under
  the pointer, where the person is working.
- **Mechanism:** the system hot-key service (`RegisterEventHotKey`). It reports only the registered
  combinations, needs no permission and costs nothing between presses. A global key monitor or event
  tap was rejected: it would see every keystroke and need Accessibility or Input Monitoring for it.
- **Off by default:** like modifier-drag and the mouse wheel, anything global is opt-in. The defaults use
  ⌃⌥⌘ because apps and window managers rarely do; Rectangle and Magnet, for example, use ⌃⌥ alone.
- **Guard rails:** a shortcut needs at least two of ⌃ ⌥ ⌘, so ⌘C, ⌘⇧T and the like can't be taken over;
  two actions can't share one; a combination macOS or another app already holds is reported in Settings.
- **Feedback with the panel closed:** success is visible already (the card flying up, the window coming
  back); a refused shortcut shakes the dots, and the status line keeps the reason for a few seconds.
- **Checked:** in a separate test copy with shortcuts on, all three registered and each action ran from
  the hot-key event sent inside that copy. No key was pressed by hand, so the step from a
  physical press to the event is the system's and was not exercised here.
- **Deferred:** holding the selected text by shortcut. It would need to read other apps' selections
  through Accessibility (many apps don't expose them) or send a copy keystroke and overwrite the
  clipboard, which Tuck avoids.
- **Known limit:** shortcuts are stored by key position; labels come from the layout used when they
  were recorded, and the defaults are labelled for US-style layouts.

## 2026-11-02: Obvious Rest, tucking goes up into the notch, app rows for several windows

### Rested at a glance
- **Superseded in part:** the icon is only greyed, without a badge; the crescent is on the "Rested" tag,
  once per row. See "Stabilisation pass" above. Since "2026-11-08: One place, one fold: the
  simplification redesign", the tag is in secondary text, not a session's colour.
- **Decision:** A rested app's icon is greyed and carries a crescent badge, and its name is followed by
  a "Rested" tag (crescent and word) in the session's colour. Both appear on single-window rows and on
  multi-window app rows, open or closed. The tag's tooltip says the app is paused to reduce active CPU
  work and is still in memory.
- **Why:** The small crescent alone was easy to miss. The wording avoids suggesting that memory is
  freed or that any app can be rested; the allow-list and live checks are unchanged.

### Tucking goes up, not down
- **Superseded in part:** the card no longer ends as a small pill of the session's colour; it arrives
  as a copy of the token it lands on. See "The tucked window's card lands as the token" above.
- **Superseded in part:** the window no longer minimises in view. Tuck hides its app, or hides it for a
  moment while minimising it. See "Tucking goes into the notch, not the Dock" and "Seamless
  selected-window tucking" above. Since "2026-11-08: One place, one fold: the simplification redesign",
  it becomes a Tuck blue dot and lands in its row or in the mark's dip.
- **Decision:** Tucking a window (front window, Tuck All, or Select… → Tuck N) plays a Tuck-drawn
  deposit: a small dark card with the app's icon and the window's title rises from the window's spot,
  curving up into the destination session's dot on that window's display. It shrinks, drops its icon
  and title, and warms into the session's colour, arriving as a small dot that merges into the
  session's dot; the dot's "+n" swell starts as it arrives. 0.5 s, at most six cards 0.06 s apart, a
  short-lived click-through panel per card, nothing left running, no flight with Reduce Motion.
- **Checked frame by frame:** with the panel open (the usual case, since Tuck is pressed there) the
  first version slid under the panel's edge about 100 pt short of the dot, and a near-black card was
  invisible over Tuck's black surface anyway; the swell also came 0.2 s after the card seemed to
  vanish, while the eased flight crept the last few points. So the card now passes just above Tuck's
  surface when it lands on a dot (just below it for Loose, so it slips into the notch), takes on the
  session's colour, and the swell starts at 70% of the flight. Recorded again, the coloured dot lands
  on the target dot in both the open panel and the collapsed notch, and "+1" follows within about
  0.07 s.
- **Why:** I wanted tucking to read as going into the notch rather than into the Dock.
- **macOS limit:** Tuck still minimises the window with Accessibility, and macOS always animates a
  minimised window down to the Dock; there is no public way to aim or suppress that animation. Hiding
  the app, or moving the window off screen before minimising, would change what minimised means or
  fight the window server, and private APIs are ruled out. So the Dock animation still plays, under a
  card drawn above it and right over the window's spot. Choosing "Scale Effect" in Desktop & Dock makes
  the system's half shorter and quieter.
- **No window pixels:** the card uses the app's icon and the title Tuck already has, so no Screen
  Recording permission is involved.

### App rows for several windows
- **Superseded in part** by "2026-11-08: One place, one fold: the simplification redesign". The app row
  shows its icon, name and count and opens to its windows' titles only; it no longer shows the newest
  window's title or "N windows".
- **Decision:** Parked windows are listed by app. An app with one window is a direct row (click
  restores, Command-click opens the chooser). An app with several windows has one row with icon, name,
  count, chevron and the Rested tag; closed it shows the newest window's title, open it says "N
  windows" and lists the windows newest first. Clicking the app row only opens or closes it. Each
  window inside restores alone on a click, opens its chooser on Command-click, and can be forgotten
  from its context menu. App rows are ordered by their most recently tucked window.
- **Why:** Several windows of one app made the list long. The earlier grouping was dropped because a
  row of titles revealed on hover read like tabs; here each window is still its own whole-window row,
  only shown once the app row is deliberately opened, and nothing restores more than one window
  except the confirmed "Restore All N Windows…".
- **State:** every app row starts closed. Open rows are kept by group id in the model, and an id is
  dropped as soon as its group stops having several windows in the current session.
- **Supersedes:** "One row per window" below.

## 2026-11-02: Fewer dead ends to Settings

- **Decision:** Choosing Rest while the experimental setting is off now asks "Turn on Rest?" in the
  panel and continues to the first-use explanation, instead of a greyed-out item pointing to Settings.
  The safety policy is still checked first, and refusals still say why. The system Accessibility prompt
  is shown at most once per launch; after that the panel's hint and status line explain it.
- **Correction:** the real-window and Rest tests ran Tuck from the terminal, so macOS judged
  Accessibility by the terminal's permission. The code paths were the same, but the permission was
  not Tuck's own. A copy of Tuck opened from Finder needs Tuck itself in Privacy & Security →
  Accessibility. Because local builds are ad-hoc signed, every rebuild counts as a new app: remove and
  re-add Tuck after rebuilding. A stable signing identity would end that; it needs a signing
  certificate and is not set up here.

## 2026-11-02: Rest switched on behind an experimental setting

- **Decision:** Rest is available behind Settings → Rest (experimental), off by default. The service
  follows the setting. Pausing needs it, but waking never does: a continue signal can only undo a pause,
  and the process identity is still checked first. That way turning Rest off, which wakes every rested
  app, can never leave one stuck.
- **Tested with a real Preview window** (an instance launched for the test, in a test session removed
  afterwards):
  - Rest showed the first-use explanation, then paused it: kernel state stopped, 0.02 ms of CPU in
    3 seconds, memory steady at about 38 MB.
  - Opening Preview while it was paused (the same activation the Dock uses) produced an activation
    notification and woke it. This answers the spike's open question for that path; a literal Dock
    click wasn't performed.
  - Restoring its window, a wake-all, a normal quit, and relaunching after Tuck was force-killed each
    woke it.
  - Rest was refused while Preview was frontmost, and while a second window was on screen. Preview had
    reopened an earlier document, and the check caught it.
- **Found and fixed:** the normal-quit wake didn't run. Tuck's Info.plist allows sudden termination,
  so macOS could end Tuck without `applicationWillTerminate`. Tuck now holds off sudden termination
  while any app is resting. The same flaw could drop the library's last coalesced save on quit, so
  `FileLibraryPersistence` also holds it off until a scheduled write lands.
- **Still true:** helper processes keep running; a crash leaves the app paused until Tuck's next
  launch; the allow-list is deliberately short.

## 2026-11-02: Choosing windows, window sets, and the Rest spike

### Choosing windows
- **Superseded in part:** ticked windows are hidden with their app or minimised out of sight, not
  minimised in view. See "Seamless selected-window tucking" above. Since "2026-11-08: One place, one
  fold: the simplification redesign", the picker opens from Choose Windows to Tuck… in the band's or the
  Tuck button's context menu, in place of "Select…" and the ••• menu, and takes the place of the full
  fold's list until it is done or cancelled.
- **Decision:** A Suggested picker ("Select…" on the Windows page, or the ••• menu) lists open windows
  to tick, grouped by app. `CandidatePolicy` keeps it conservative:
  - only standard windows of ordinary apps, visible on the current desktop;
  - nearest the front first, at most 12;
  - never Tuck, background agents, dialogs or floating panels, minimised, full-screen or tiny windows,
    or resting apps.

  Nothing is ticked to begin with and nothing moves until "Tuck N". The ticked windows, and only
  those, are re-checked and minimised into the current session as separate rows.
- **Why:** the suggested flow in Tuck's original plan: visible, checkable candidates, an explicit "Tuck
  2", never automatic, nothing implying Tuck knows the whole context.
- **How:** Visibility and order come from the window server's on-screen list, read for bounds and
  owners only, so no Screen Recording permission is needed. Window facts come from Accessibility.
- **Tested on real windows:** two Preview windows and Calculator, in a Tuck session made for the test and
  removed afterwards. The steps were listing, "Tuck 2", restoring Calculator to its exact frame, "Tuck
  All Preview", and a confirmed "Restore All".

### Window sets
- **Decision:** "Tuck All <App> Windows" (right-click Tuck on the front-window bar) and "Tick all N"
  per app in the picker tuck a whole set; each window remains its own restorable row. Restoring is one
  window per click; "Restore All N Windows…" asks first and restores one after another, keeping any
  that fail. Whole windows only; browser tabs are not managed.

### Rest spike
- **Superseded:** Rest is switched on behind an off-by-default experimental setting (`RestSwitch`;
  `signalsApproved` is gone). Waking on activation was verified by opening the app as the Dock does; a
  literal Dock click still wasn't. See "Rest switched on behind an experimental setting" above.
- **Decision:** Rest is built and tested but switched off twice. `ProcessRestService.isEnabled` is
  false, and `POSIXProcessControl` refuses to send any signal while `signalsApproved` is false. No
  app was paused at any point.
- **Mechanism (proposed):** a same-user stop signal to pause and a continue signal to wake, to the
  app's own process.
  - Before every signal, the pid, kernel start time and program path must match what was recorded, so
    a reused pid is never signalled.
  - The kernel's process state is read back after each signal; a pause that does not hold is undone.
  - Failures leave the app running and say so.
- **Policy:** an allow-list of offline document apps. Named risky categories are refused (calls,
  media, downloads, terminals, developer tools, VPNs, sync, remote desktop, system, browsers,
  messaging), and every other app is refused as ambiguous. At the moment of asking, the app must not
  be in front, must have no visible windows, and must not be using audio (Core Audio per-process
  objects). If it is busy (CPU sampled over 0.4 s) or its audio state is unknown, a stronger
  confirmation is needed. The first use shows the agreed explanation.
- **Waking:** a deliberate restore of one of its windows, a Wake menu item, or switching to the app
  (activation notification). Everything wakes before quit and sleep, and at launch after a crash.
  Never on hover.
- **Known limits, unsafe by design:**
  - Helper and XPC processes keep running, so savings can be partial for multi-process apps.
  - A paused app cannot answer Accessibility, so Tuck never lists or queries resting apps.
  - Whether clicking a paused app in the Dock always produces an activation notification is
    unverified, and is the first thing to test once signals are approved.
  - A crash leaves the app paused until Tuck next launches.
- **To enable, after approval:** flip both switches, then test with a safe allow-listed app (Preview)
  for reduced CPU, kept memory and a clean wake, including the Dock-click path.

### Also
- Rest eligibility for menus uses only cheap facts. The checks that ask the app and Core Audio run
  when the person chooses Rest, so rows never query apps as they redraw.

## 2026-11-02: Real windows checked end to end; Archive and Clear

### Real windows
- **Superseded in part:** there are no sample rows, so no "Sample" tag. See "Sample data removed" above.
- **Decision:** Restores confirm asynchronously. After asking a window to un-minimise, Tuck checks
  its minimised state every 50 ms for up to about a second, without blocking, before calling the
  restore a failure. A window counts as gone as soon as its process no longer exists, checked with the
  kernel by pid, ahead of any other check. Sample rows carry a "Sample" tag.
- **Why:** Testing against a real app window (a throwaway probe app, so no real windows were
  touched) showed two bugs in the previous pass:
  - Restores worked but were reported as failures, so rows stayed. A window reports itself minimised
    until its un-minimise animation is under way, and the old check read it immediately.
  - A force-quit app's window answered "can't complete", which was treated as busy, not gone.
- **Verified:** tuck → real row; click → back to its exact saved frame, row removed; ⌘-click left
  half → the left half of the panel's display; quit the app → "That window has closed", row removed.
  Accessibility was granted. The missing-permission path is covered by the existing status message and
  never removes a row.
- **Housekeeping:** the first, buggy test run had left three probe rows in the library. They were
  removed after backing up the file; nothing else changed.

### Archive and Clear
- **Superseded in part:** windows tucked by hiding their app stay hidden rather than minimised. See
  "Tucking goes into the notch, not the Dock" above. Since "2026-11-08: One place, one fold: the
  simplification redesign", there are no sessions to archive. Clear Held Items… in the band's context
  menu clears every held item after an inline question (Clear, or Clear and Delete when files Tuck saved
  from drops would go) and never clears tucked windows; Restore All Windows… brings those back.
- **Decision:** A ••• menu in the page header offers Archive Session and Clear Session… for the
  current session (Clear Loose… when Loose is current), plus an Archived list to bring sessions back.
  - Archive keeps everything, and parked windows stay minimised with the session.
  - Clear removes the session and Tuck's records after an inline question (`ClearPlan`): a plain
    confirmation for links, text and file references; "Clear and Delete" when files Tuck saved from
    drops would be deleted; and, with real parked windows, "Restore, Then Clear" / "Archive, Keep
    Parked" / Cancel.
  - Restore-then-clear clears only if every window came back.
  - Empty sessions close at once.
  - The confirmation is inline in the panel rather than a modal alert, so nothing activates or
    steals focus.
- **Why:** the session lifecycle in Tuck's original plan: archive removes a session from the notch
  without deleting its items; never silently close, discard or lose parked windows; destructive removal
  must be clear. Archiving used to refuse sessions with windows; keeping them parked inside the archived
  session is the explicit "keep parked" choice.
- **Safety:** `ReceivedFileStore` deletes only inside Tuck's own folder, so a reference to your file
  cannot be deleted through Clear (tested with real files). New sessions skip archived sessions'
  colours, so a session brought back is still told apart by colour.
- **Deferred:** an undo for Clear. Archive is the reversible path, and Clear always asks first.

## 2026-11-02: Windows and Held pages; drag invitation that shows before the notch

### Two pages
- **Superseded in part:** the page names became a native segmented control with counts. See "Native
  segmented control for the panel pages" above. The panel's height no longer follows the page
  showing: the pages share the tallest one's height. See "Page swipes only slide; every session in
  Intentions shows a symbol" above. Since "2026-11-08: One place, one fold: the simplification
  redesign", there are no pages: one stream holds everything, newest first, with lenses beside the
  notch.
- **Decision:** The open panel has two compact pages side by side: Windows (parked windows only) and
  Held (files, links, music links, stacks and text, plus Loose items and opt-in clipboard history). It
  opens on Windows when the session has parked windows, otherwise on Held. A sideways swipe, or a click
  on the page names in a small header, slides between them. The panel's height follows the page
  showing. Each page shows a calm hint when empty. A swipe up closes from either page.
- **Why:** I wanted windows and held items to have their own interfaces rather than one long
  list. Sideways swipes in the open panel used to switch session. Sessions are still one click away on
  their dots, and sideways still switches session on the collapsed surface.
- **Supersedes:** "Windows first" below.
- **Detail:** Both pages stay laid out all the time. Inserting the incoming page during the transition
  made the list collapse for a few frames before it measured itself.

### Drag invitation before the notch
- **Superseded in part** by "2026-11-08: One place, one fold: the simplification redesign". The panel no
  longer opens after the dwell. The band says what the drag carries ("Drop file into Tuck" and the
  like), and over an open fold the whole fold is the target.
- **Decision:** A supported drag (files, URLs, text, images, file promises, judged by advertised types
  only) entering a top-centre range around the surface gets the invitation at once. The range reaches
  260 pt to each side and 220 pt down. The invitation strengthens as the pointer nears and firms up
  over the drop target. It disappears when the pointer passes 36 pt beyond the range or the drag ends.
  The panel still opens only after the existing dwell in the smaller approach zone. The surface accepts
  a drop only over the target, so releasing beside it is refused rather than captured.
- **Why:** The invitation usually appeared only once the pointer reached the notch. The watcher
  classified a drag once, on its first mouse-dragged event, before source apps write the drag
  pasteboard. Most real drags were judged not droppable, so the only feedback was the panel's own drop
  handling at the notch. The invitation also used to show anywhere on the display rather than in a
  defined range.
- **Limits:** A source that wrote the drag pasteboard before Tuck saw the mouse-down would still be
  missed. Common sources (Finder, browsers, AppKit apps) write it when the drag starts moving.

## 2026-11-02: Restores never drop a row on failure; deposits always confirm

### Restore safety
- **Superseded in part:** a window tucked by hiding its app stays hidden rather than minimised. See
  "Tucking goes into the notch, not the Dock" above.
- **Decision:** A parked-window row is removed only after a confirmed restore (moved, constrained or
  a sample) or a window confirmed gone. A failure, missing permission or no-op keeps the row and says so.
  The restore reads the window's minimised state back instead of trusting the request. It keeps its
  hold on the window until the window is back. It calls a window gone only when the app has quit or the
  system reports the element invalid; a timeout or an unmatched title counts as a failure.
- **Why:** Restores removed the row for every result except missing permission, so a refused or
  timed-out restore silently dropped the window from Tuck. Tuck's original plan: never silently close,
  discard or lose parked windows.
- **Also:** "Forget Window" in a row's context menu removes a row on purpose. The window itself is
  left alone and, if it still exists, stays minimised in the Dock.

### Hover details without previews
- **Superseded in part:** the size and display are now on the window's own line inside its app row,
  not shown on hover. See "Apple-built panel: one status either side of the notch, Spotlight rows, AirDrop prompts" above.
- **Decision:** Hovering a window row shows its original size and display. This is the original plan's
  fallback when there is no screen-recording permission, and it went missing with the app grouping.

### Deposits always confirm at the notch
- **Superseded in part:** with the panel open, a tucked window is confirmed by its row filling instead
  of "+1". See "A tucked window lands in its row; the drop rim wraps the notch". Since "2026-11-08: One
  place, one fold: the simplification redesign", the mark pulses and the count rises, with no "+1".
- **Decision:** Tucking the front window now swells the destination dot with "+1", like a drop does. A
  deposit while Tuck is swiped away brings the surface back first, so the confirmation is never drawn
  on a hidden dot.

### Reset Sample Data asks first
- **Superseded:** sample data and Reset Sample Data were removed. See "Sample data removed" above.
- **Decision:** The menu item explains what will be forgotten and deleted and needs an explicit
  Replace. It used to replace the whole library silently, including real parked-window records; the
  next launch's sweep then deleted copies Tuck had saved from drops.

## 2026-11-02: Stable dots, closing empty sessions, windows first

### Dots
- **Superseded:** the collapsed surface shows one token, the current session's, so there is no dot row
  or ring. See "Apple-built panel: one status either side of the notch, Spotlight rows, AirDrop prompts" above.
- **Decision:** Room for the current-session ring is reserved at both ends of the dot row, so dots sit
  in the same place whichever session is current (or none). Positions are snapped to the pixel grid.
  The count is placed by its font's cap height so the digits share the dots' centre line. In the bubble
  the padding absorbs the ring room, and the visible dots and count are centred together.
- **Measured:** around the notch, 5.5 pt and 6 pt either side of the dot row, the count centred
  31 px either side, the dots centred vertically to within 0.25 pt. In the bubble, 11 and 12 pt either side.

### Closing empty sessions
- **Superseded** by "2026-11-08: One place, one fold: the simplification redesign". There are no
  sessions to close.
- **Decision:** Hovering an empty session's dot shows a small × that closes it, and right-clicking any
  dot offers Close Session (disabled with a reason for sessions holding something). Only sessions with
  no parked windows and no held items can be closed, so nothing is lost. If the closed session was
  current, the neighbour that takes its place becomes current; with none left, items go to Loose.

### Opening without a sideways jump
- **Decision:** Shape springs start from the model path unless a morph is running, and a change of
  window width lands any morph in flight.
- **Why:** The open started from the presentation layer's path, which after the window widened was
  still in the old window's coordinates. The shape began about 62 pt left of the notch and drifted
  back while it grew. The drop invitation had the same flaw. A 60 fps recording now shows every frame
  centred to within 1 px.

### Windows first
- **Superseded:** by the Windows and Held pages above.
- **Decision:** With parked windows, the list opens sized to the Windows section plus a 30 pt peek of
  what follows; held items sit below a divider and are reached by scrolling. Without windows, held
  items show directly. The list still caps at its maximum height and scrolls beyond it.
- **Why:** I wanted windows and held items separated rather than mixed together, without adding
  a second page or controls.

## 2026-11-02: Opening and closing motion

- **Decision:** The surface opens with one spring for the whole outline (0.45 s duration, 0.4 bounce,
  so about 10% overshoot) and closes with a critically damped spring (0.4 s response). A press on the
  collapsed surface makes it give slightly; letting go elsewhere releases it on a 0.6 s, 0.35-bounce
  spring. The panel is clipped to the moving outline and fades in a beat behind it. The panel is built
  and measured before anything moves, and the window gets room below for the overshoot. Springs
  always run to completion.
- **Why:** Opening felt rough and jumpy. The old spring was cut off at 0.55 s, so it snapped at the end.
  Panel content appeared outside the still-small shape. The window had no room for overshoot. The
  panel's height arrived mid-animation and restarted the spring. The goal was motion that feels like
  Alcove's. Tuck describes its springs as SwiftUI does, by duration and bounce or by response and
  damping fraction, and converts them to Core Animation's stiffness and damping (checked by tests).
- **Departure from Tuck's original plan,** which avoided bouncing: I wanted some, so opening
  overshoots once by about 10% and settles, a released press settles with a slight
  bounce, and the drop invitation pops with a small one. Nothing loops or moves on its own; closing and
  all other changes settle without overshoot.
- **Measured:** In a 60 fps recording the outline grows in one continuous motion, overshoots its
  final height by about 10% and settles with no second correction. Closing eases in without bounce.
  Idle cost is unchanged.

## 2026-11-02: Notch polish, whole-window rows, "Drop items here"

### Covering the notch's lower edge and centring
- **Decision:** The collapsed notch surface reaches 2 pt below the reported notch height, and is
  centred on the notch itself rather than the screen (here the notch sits half a point right of
  centre). The dots are centred between the shape's straight side and the notch, counting the ring
  around the current dot, and snapped to the pixel grid.
- **Why:** a thin line of the hardware notch showed under the surface, and the dots sat off
  centre. At scaled resolutions the physical notch can end a fraction of a point lower than the
  safe-area inset says.

### One row per window
- **Superseded:** by "App rows for several windows" above.
- **Decision:** Parked windows are listed one row per window (app icon, app name, window title, time),
  newest first. The app grouping with a count and a reveal-on-hover list of titles is gone.
- **Why:** Tuck parks whole windows, but the grouped Safari row with three titles read like tabs. A row
  now means a whole window that comes back with everything in it. The sample data has one Safari window.

### "Drop items here"
- **Superseded in part:** the invitation shows only within 260 × 220 pt of the surface, as a "Drop items
  here" band. See "Drag invitation before the notch" above. Since "2026-11-08: One place, one fold: the
  simplification redesign", the band says "Drop file into Tuck", "Drop link into Tuck" or "Drop text
  into Tuck" in a Tuck blue rim, and nothing opens.
- **Decision:** As soon as a droppable drag starts on a display, the notch pops out by a 24 pt band
  under the hardware notch, or the bubble widens, showing a tray glyph and "Drop items here". It grows a
  little more and the session-coloured rim strengthens as the pointer nears; the panel still opens
  after a short rest near the top centre.
- **Why:** I wanted a modest pop-out that says plainly where to drop, rather than a shape that
  only grows.

## 2026-11-02: Notch fit and swipe to tuck away

### Collapsed notch fit
- **Superseded in part:** the wings now hold the current session's numbered token and the count, not up
  to three dots. See "Apple-built panel: one status either side of the notch, Spotlight rows, AirDrop prompts" above.
- **Superseded in part:** the surface reaches 2 pt below the notch's height. See "Covering the notch's
  lower edge and centring" above. Since "2026-11-08: One place, one fold: the simplification redesign",
  the wings hold the mark and the count in Tuck blue, only while Tuck holds something.
- **Decision:** On notched displays the collapsed surface is exactly the notch's height, with one wing
  either side that is the notch height plus 4 pt (259 × 33 pt on a 15-inch MacBook Air). Shoulders where
  it meets the top edge are quarter circles 8 pt across; the lower corners round at 13 pt. Session dots
  shrink to 6 pt with 4 pt gaps and at most three show, the current session always among them.
- **Why:** The earlier surface grew its wings to fit the dots and read as long and thin next to the
  notch. The goal was a fit like Alcove's. Tuck derives its sizes from the hardware notch: the width and
  height from the notch's auxiliary areas and safe-area inset. The outline was then laid over a
  screenshot of Alcove's notch on this Mac, and matches within half a point. No code, assets or drawing were
  taken from it.
- **Departure from the original plan's rule on numbers:** the earlier rule was to use Tuck's own
  sizes. I chose these dimensions, so this one place follows the measured fit.

### Swipe to tuck away
- **Superseded in part** by "2026-11-08: One place, one fold: the simplification redesign". A fourth
  stage, the full fold, follows the open panel: a swipe down on the shallow fold unfolds it and a swipe
  up folds it back. Only the full fold's list scrolls.
- **Decision:** Swiping up on the collapsed surface tucks it away completely: it shrinks into the
  hardware notch and draws nothing, so only the notch remains. Swiping down brings it back; swiping
  down on the resting surface opens the panel, and swiping up on the open panel closes it, anywhere
  except over a list long enough to scroll. One step per gesture, so a fast flick never skips a stage.
  The surface follows the fingers while a swipe is in progress and springs back if it falls short.
  Clicking a tucked notch still opens the panel, and closing returns it to the tucked notch. A
  menu-bar item brings every tucked surface back.
- **Why:** the goal was a vertical swipe that feels like Alcove's. Thresholds (24 pt to tuck, reveal or
  open, 14 pt to close), the stretch amounts and the three-stage model are Tuck's own.
- **How it stays light:** A local scroll-wheel monitor sees only scrolls aimed at Tuck's windows.
  Gesture-phase checks keep mouse wheels, Tuck's own smooth scrolling and momentum out. Shape updates
  run only while fingers are moving.
- **Deferred:** Remembering the tucked state across launches.

## 2026-11-02: Mouse-wheel smooth scrolling and wheel-only reversal

### Smooth scrolling
- **Decision:** Opt-in, off by default. Each notch of a classic mouse wheel becomes a short eased glide
  driven by the display's refresh. Three feels: Snappy, Balanced, Gliding. High-resolution wheels,
  trackpads, Magic Mouse and anything scrolled with a modifier held pass through untouched.
- **Why:** Notched wheels jump in line-sized steps, which is jarring in long documents; this is a common
  reason people install a separate utility, and Tuck can offer it at no idle cost.
- **How it stays light:** The tap sees scroll-wheel events only and exists only while a wheel option is
  on. The display link exists only while a glide is moving. Distances keep the system's own wheel
  acceleration; a fixed lift per notch keeps a single slow notch useful once events become pixel-based.
- **Inspiration:** how Vorssaint's smooth scrolling feels. Tuck builds it the usual way (wheel events
  held back in an event tap, the distance left eased by a display link, and the pixel events it posts
  tagged so the tap lets them through), with its own ease, presets, lift, frame cap and device rules.
- **Deferred:** Linear (fixed lines per notch) scrolling, per-app exceptions and scroll-to-zoom.

### Reverse mouse wheel direction
- **Decision:** Opt-in. Flips the wheel's direction only, so a trackpad can keep natural scrolling while
  the mouse scrolls the classic way (macOS ties both to one setting).
- **Inspiration:** Vorssaint's option to reverse the mouse wheel alone and leave the trackpad as it is.

## 2026-11-02: Real windows, shelf-grade file intake, drop invitation

### Real placement engine
- **Superseded in part:** tucking no longer minimises in view. Tuck hides the app, or hides it for a
  moment while minimising. See "Tucking goes into the notch, not the Dock" and "Seamless selected-window
  tucking" above.
- **Superseded in part:** the bar's Tuck and Arrange act on the window the bar names, not on whatever is
  focused at the click. See "The front-window bar acts on the window it names" above.
- **Decision:** `AccessibilityParkingService` replaces the mock in the app. Tucking minimises the
  focused window; restoring and arranging write size → position → size with `AXEnhancedUserInterface`
  off, then read the frame back. A window that keeps its own size is pinned to the placement's edges
  rather than left floating. The chooser gains thirds, two thirds, quarters, Centre and Next display in
  a compact glyph row under the four labelled placements. A front-window bar offers Tuck and Arrange for
  whatever is in front, with Original undoing Tuck's last move.
- **Why:** Placement was only useful once it moved real windows; verifying and re-anchoring is what keeps
  apps with minimum sizes (or fixed aspect) from ending up half off-screen.
- **Why minimise:** It is a state every app supports, survives a Tuck crash or quit, and the person can
  undo it from the Dock without Tuck.
- **Inspiration:** Vorssaint's window layouts, which still land well for a window with a minimum size.
  Tuck's read-back check, tolerance rule, anchor model, layouts and chooser are its own.
- **Deferred:** Global layout shortcuts and edge snap zones (not chosen for this round).

### Modifier-drag move and resize
- **Decision:** Opt-in, off by default. Hold ⌃⌥ (or ⌃⌘, or ⌃⌥⌘) and drag a window to move it;
  right-drag or add ⇧ to resize from the nearest corner. A session event tap for mouse buttons exists
  only while the setting is on; frames are capped at 60 per second, the final one always sent.
- **Why:** Moving windows without aiming at the title bar saves real time, but an always-on tap would
  conflict with Tuck's promise of near-zero idle work, hence opt-in and torn down when off.
- **Inspiration:** Vorssaint's modifier-drag move and resize. Tuck uses one update rate and its own
  corner rule.

### Shelf-grade drop intake
- **Superseded in part** by "2026-11-08: One place, one fold: the simplification redesign". The one
  stream holds at most 200 held items, not 120 per session; a full one still refuses new drops and says
  so.
- **Decision:** Drops accept promised files (Mail messages, Photos) and raw images in addition to files,
  links and text. Three or more files in one drop become a single stack row that drags out as all of
  them. Files are stored with a bookmark, reconciled on load and on every open; the library persists as
  coalesced, atomic JSON. Each session (and Loose) holds at most 120 rows; a full one refuses new drops
  and says so.
- **Why:** The tray has to survive a relaunch and cope with sources that only hand over a file on drop.
  Refusing rather than evicting keeps Tuck from silently losing things.
- **Received files:** Promised files and images have no original to point to, so they are written to
  Tuck's own folder and deleted with their row. Nothing outside that folder is ever deleted.
- **Inspiration:** Vorssaint's shelf, which takes promised files, keeps several files dropped together
  as one item, follows files that move and holds a limited number. Tuck's thresholds, cap, naming and
  ownership rules are its own.

### Zip archive
- **Decision:** Compress any held file or stack with the system's `ditto` (what the Finder uses), next to
  the originals, or in Downloads when that folder is read-only, with Finder naming ("Archive 2.zip").
  The archive is held in the same session.
- **Why:** No bundled compression code, metadata preserved, archives open everywhere.

### Drop invitation
- **Superseded in part:** the invitation shows only within 260 × 220 pt of the surface, as a "Drop items
  here" band. See "Drag invitation before the notch" above. Since "2026-11-08: One place, one fold: the
  simplification redesign", the rim is Tuck blue rather than a session's colour, the band says what the
  drag carries, and the panel no longer opens after the dwell.
- **Decision:** As soon as a droppable drag starts on a display, its collapsed surface opens up slightly
  with a rim in the current session's colour and a drop glyph in place of the count, growing in eight
  steps as the pointer nears. The panel opens after the drag rests in the approach zone for 0.18 s and
  closes only once it leaves a zone 36 pt larger.
- **Why:** People need to see that the notch accepts drops before they aim at it. The dwell stops drags
  heading for the menu bar from popping the panel; the larger exit zone stops flicker.
- **Inspiration:** Vorssaint's shelf appears as a drag nears it and rests, goes once the drag moves well
  away, and draws an animated droplet. Tuck keeps the idea and uses its own numbers and its own visual:
  no droplet, the existing surface simply opens towards the pointer.
- **Lightweight:** No timers; the surface redraws only when the discrete level changes.

### Real opening
- **Decision:** Files, links and music open in their default apps; a stack is revealed in the Finder.

## 2026-11-02: First interactive prototype

### Build system: Swift package, no Xcode project
- **Decision:** A SwiftPM package with a `TuckCore` library, a `TuckApp` executable and a test target.
  `scripts/build-app.sh` produces a size-optimised (`-Osize`), stripped `Tuck.app`.
- **Why:** No project file to maintain, no third-party dependencies, reproducible from the command line,
  and the package opens directly in Xcode when wanted. The resulting bundle is about 1 MB.
- **Deferred:** Developer ID signing, notarisation and an Xcode project for distribution.

### Always-on surface in AppKit and Core Animation; SwiftUI only while open
- **Decision:** The collapsed notch/bubble is a layer-backed `NSView` with shape, dot and text layers.
  The SwiftUI panel is hosted only while expanded and removed on collapse.
- **Why:** Tuck's purpose includes not slowing the Mac. A resident SwiftUI tree, timers or idle animation
  would cost memory and wake-ups for a surface that is almost always idle. Measured: 0.0% idle CPU and
  ~12 MB footprint collapsed.

### No background polling
- **Superseded in part:** a pending drag is re-checked at most every 30 ms, for up to 0.8 s, until its
  pasteboard is written. See "Drag invitation before the notch" above.
- **Decision:** All monitoring is event-driven. The outside-click monitor exists only while a panel is
  open. Swipes, clicks, hover and Escape are handled by Tuck's own view and panel. Drag detection reads
  the drag pasteboard once per drag rather than on a timer.
- **Why:** Polling the pasteboard or mouse location keeps the CPU waking even when nothing happens.
- **Update:** Swipes now arrive through a local scroll-wheel monitor (Tuck's own windows only), so a
  swipe on the open panel is seen before its list; see "Notch fit and swipe to tuck away".

### Overlay window behaviour
- **Decision:** Non-activating borderless panel at status-bar level, joining all Spaces as a full-screen
  auxiliary and ignoring the window cycle; resized to the current state.
- **Why:** Tuck must appear on every Space and beside full-screen apps without activating itself or
  stealing focus, and must not block clicks around it.
- **Inspiration:** Notch utilities such as Gojo also show on every Space and beside full-screen apps.
  Tuck uses the status-bar level and no private window-server APIs for now.
- **Deferred:** Showing on the lock screen; that would need private SkyLight space APIs and is out of
  scope.

### Notch geometry and the external-display bubble
- **Decision:** Detect a notch from the top safe-area inset plus the auxiliary top areas; the notch is
  the gap between them. Displays without a notch get a small, soft bubble centred in the menu-bar strip,
  with the same dots, count and interactions.
- **Why:** Tuck's original plan asks for a friendly, inviting presence on external displays rather than a
  flat utility bar.
- **Inspiration:** Alcove's quiet pill on non-notched displays. Tuck's bubble is its own shape and
  proportions, with a soft hover grow and no permanent text.

### Haptics: deliberate commits only
- **Superseded:** by "Haptics for page events only" above.
- **Decision:** One tactile tick, through the system feedback performer, when a deliberate action
  commits: opening the panel by click or swipe, a swipe crossing its threshold (open, close, switch
  session), selecting a session, opening the placement chooser, placing or restoring a window, copying
  text, dropping onto an explicit session dot, and the deposit itself.
- **Why:** I wanted the Alcove-like feeling of tactile responses to clicks and swipes on the
  island. Tuck's original plan rules out haptics for passive events and ordinary scrolling. The
  reconciliation: gestures fire at most one tick, at the moment they cross their threshold; list
  scrolling, hover and background changes never do. Every action also has a visual change, and haptics
  can be turned off.
- **Limits:** macOS plays haptics only on Force Touch trackpads, with a finger on the trackpad.

### Window placement
- **Superseded:** the real mover shipped; see "Real placement engine" above.
- **Decision:** Normal click restores the original frame (centred on the active display if the original
  display is gone). Command-click opens an inline chooser: Original, Left half, Right half, Full screen.
  Halves are computed from the display's usable area (menu bar and Dock excluded) and rounded down to
  whole points.
- **Why:** Direct and spatially obvious, with no settings screen or confirmation.
- **Inspiration:** Gojo's window actions, which put a window on one half of the screen. Tuck's chooser
  is its own inline strip attached to the row.

### File drop
- **Superseded in part** by "2026-11-08: One place, one fold: the simplification redesign". A drag no
  longer opens the panel. Over an open fold the whole fold is the target, and there are no session dots
  to aim at.
- **Update:** file promises and images shipped; see "Shelf-grade drop intake" above. Rich text is
  still deferred.
- **Decision:** The surface is a native drag destination for file URLs, web/music URLs and plain text.
  Dropping needs no dialog. A content drag approaching the top centre of a display opens the panel. While
  open, dropping onto a session dot (or Loose) targets it; anywhere else goes to the current session.
- **Why:** Tuck's original plan asks for immediate, low-friction drops that never interrupt the person.
- **Inspiration:** Gojo opens its notch when a drag nears the top of the screen. Tuck's version is
  event-driven and its own approach zone.

### File tray and clipboard history semantics
- **Superseded in part:** clipboard history now keeps images, files, colours, contacts and styled text
  as well as plain text, each in a tile of its own. See "The clipboard keeps every kind, in tiles two to
  a row, and search reads kinds and days" above.
- **Current clipboard implementation:** Clipboard history remains opt-in and short-term, but now watches
  the system pasteboard for plain text while enabled. It checks the pasteboard change count, ignores
  concealed, transient and auto-generated items and known password managers, and saves the history in
  the app's support folder so it survives relaunch. Rich content and images remain unsupported by the
  text-only Clipboard page.
- **Superseded in part:** the earlier decision below said clipboard history captured only copies made
  through Tuck. It now captures plain text copied on this Mac while enabled; it remains opt-in, private-
  marker aware, excluded-app aware, retention-limited and clearable in one action. Since "2026-11-08:
  One place, one fold: the simplification redesign", there is no Clipboard page: while history is on,
  copies join the one stream by date, with a Copied lens.
- **Decision:** Dropped files are stored as references to the original location, never moved or copied.
  Items are listed newest first and drag out as the original file, URL or text. Clipboard history is off
  by default. It skips content apps mark private (the nspasteboard.org concealed, transient and
  auto-generated markers) and known password managers, moves re-copies to the top, ages entries out by a
  chosen retention window and clears in one action.
- **Why:** Tuck's original plan asks for short-term, calm surfaces that are not an archive, and for no
  stealth capture.
- **Inspiration:** Droppy's tray and clipboard model (references rather than copies, private-content
  markers, retention, clear-all).
- **Deferred:** Rich clipboard content and images; the Clipboard page remains plain-text only.

### Rest is modelled, not implemented
- **Superseded:** Rest is implemented behind an experimental setting; see "Rest switched on behind an
  experimental setting" above. The greyed menu item became a prompt; see "Fewer dead ends to Settings"
  above.
- **Decision:** `RestState`, `RestEligibility`, `RestRiskCategory` and `RestPolicy` exist, plus a
  `DeferredRestService` that always reports Rest unavailable. App rows show a disabled Rest item that
  explains why.
- **Why deferred:** Pausing a third-party process is app-level and best effort. It keeps the process's
  memory, and it can break playback, calls, transfers, terminals, VPNs, sync clients and system tools. It
  needs per-category testing, conservative exclusions, an explicit first-use explanation and a reliable
  wake path before it ships.

### Optional window previews
- **Superseded:** the placeholder switch was removed (see "Stabilisation pass" above). Previews are
  still deferred.
- **Decision:** Setting present; Screen Recording is never requested. Window rows show app, title,
  original size and display on hover instead.
- **Why:** Previews are optional and must never block core use or nag for permission.

### Persistence and launch at login
- **Superseded:** the library persists as a JSON file with plain bookmarks, security-scoped only if Tuck
  is ever sandboxed (see "Shelf-grade drop intake" above). The launch-at-login switch was removed with
  nothing stored (see "Stabilisation pass" above), then returned as Open at login through
  `SMAppService`, still storing nothing (see "Settings window redesign" above). Sample data was removed;
  a first launch starts with one empty session (see "Sample data removed" above). Since "2026-11-08: One
  place, one fold: the simplification redesign", the library is one stream, saved as format 2, and a
  first launch starts with it empty.
- **Decision:** In-memory persistence and sample data for the prototype; launch at login is a stored
  preference only.

### Tests with Swift Testing on Command Line Tools
- **Decision:** Tests use Swift Testing. `scripts/test.sh` adds the framework search path and disables a
  cross-import overlay that the Command Line Tools ship without module files.
- **Why:** Lets the suite run without a full Xcode install; with Xcode, `swift test` works unchanged.
