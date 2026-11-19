# Releasing Tuck

Tuck is offered directly from the Line Apps site, not the Mac App Store: the App Store's sandbox doesn't
allow the Accessibility window parking Tuck is built on. A release is a DMG holding Tuck.app, a link to
/Applications and the EULA. The app and the DMG are both signed with a Developer ID, notarized by Apple
and stapled, so Gatekeeper opens them without a warning, offline too. Tuck is built for Apple silicon
only (arm64), and has no update mechanism yet. It is free, with every feature for everyone, and never
connects to anything.

`scripts/release.sh` does all of it. Until the Apple Developer account exists, `scripts/release.sh
--unsigned` makes a test DMG, so the packaging can be checked now.

## Where things are set

| What | Where |
| --- | --- |
| Version people see (`CFBundleShortVersionString`) | `VERSION`, or the script's argument |
| Build number (`CFBundleVersion`) | Worked out by the script; see below |
| Bundle ID, copyright holder, website, support, privacy policy and EULA links | `Support/release.env`, the one place they are set |
| Everything else in the bundle's Info.plist | `Support/Info.plist` |
| The licence shipped in the DMG | `docs/legal/EULA.txt` |
| Signing certificate and notarization credentials | `DEVELOPER_ID` and `NOTARY_PROFILE` in the environment, never in the repository |
| Local signing identity, for local builds and the test DMG | "Tuck Local Signing", made once per Mac by `scripts/signing-identity.sh` in its own keychain, never in the repository (see "The local signing identity") |

Both scripts stamp the bundle ID, copyright and links from `Support/release.env` on the bundle's copy
of Info.plist, so local builds (`scripts/build-app.sh`) and releases carry the same identity. Both
stamp the version from `VERSION` as well, so a local build reports the version it was built at; a
release's argument, when given, takes its place. The source plist keeps the same values only so it is
complete on its own, and its build number, 1, is a placeholder that only a release replaces. The log
subsystem of Tuck's `os.Logger` is the bundle ID too.

**About's links** go to Tuck's page on the Line Apps site, to the privacy policy and the EULA in
`docs/legal/` on GitHub, and for support to Tuck's GitHub issues (`SUPPORT_URL`). No support email is
published. The Support link shows the email when `SUPPORT_EMAIL` is set, otherwise the support page's
host (`github.com`), and a placeholder address only when neither is set. A website, privacy policy or
EULA link left empty keeps the source plist's placeholder on `tuck.example`, so a test build still
points somewhere. About reads them all from the bundle, and Tuck opens one only when someone clicks it.
`scripts/release.sh` refuses a signed release while the website, privacy policy or EULA link is empty,
or while both `SUPPORT_EMAIL` and `SUPPORT_URL` are: either one will do for support.

**The build number** is the UTC date, the UTC time and the git commit count, such as
`20261106.30123.53` (2026-11-06 at 03:01:23 UTC, 53 commits). It starts with the date and time so it
rises with every build, whatever happens to the history (a squash or a rebase can lower a commit
count), and UTC never steps back for daylight saving. The count says roughly which commit a build came
from. Each part is a plain integer well under 2³¹, the form Apple asks for, so leading zeros of the
time are dropped (03:01:23 is 30123).

## One-time setup

Once these are done, nothing else is needed for a signed release.

1. **Join the Apple Developer Program** at <https://developer.apple.com/programs/enroll/> (paid yearly).
   - Enrolling as an individual puts your own legal name on the certificate, and macOS shows it as
     Tuck's developer.
   - Enrolling as an organisation shows the company's name instead. It needs a legal entity and a
     D-U-N-S number, and takes longer.
2. **Create a Developer ID Application certificate.** Only the account holder can create one.
   1. In Keychain Access, choose Keychain Access › Certificate Assistant › Request a Certificate From a
      Certificate Authority. Enter your email and name, choose "Saved to disk", and save the request.
      Its private key stays in your login keychain.
   2. At <https://developer.apple.com/account/resources/certificates>, add a certificate, choose
      **Developer ID Application**, keep the default (G2 Sub-CA) authority, and upload the request.
   3. Download the certificate and double-click it to add it to the login keychain.
   4. Check that it's there: `security find-identity -v -p codesigning` lists
      `"Developer ID Application: Your Name (TEAMID)"`.
   5. Back it up: in Keychain Access, export the certificate with its private key as a `.p12`, with a
      strong password, somewhere safe outside the repository (`.gitignore` excludes `*.p12`). Apple
      allows only a few Developer ID certificates per account, and a lost key can't be recovered.
3. **Save notarization credentials** in the keychain, under a profile name the script uses:
   1. Create an app-specific password at <https://account.apple.com> › Sign-In and Security ›
      App-Specific Passwords.
   2. Find your Team ID under Membership details at <https://developer.apple.com/account>.
   3. Run this, and paste the app-specific password when it asks:

      ```sh
      xcrun notarytool store-credentials tuck-notary --apple-id you@example.com --team-id TEAMID
      ```

      An App Store Connect API key works too (`--key AuthKey_XXXX.p8 --key-id … --issuer …`). It suits a
      build server better. Keep the `.p8` out of the repository (`.gitignore` excludes `*.p8`).
4. **Tell the script about them**, in your shell profile or before each release:

   ```sh
   export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
   export NOTARY_PROFILE=tuck-notary
   ```

   `DEVELOPER_ID` may also be the certificate's SHA-1 hash, as `security find-identity` prints it.

The Command Line Tools include `notarytool` and `stapler`; Xcode isn't needed for any of this.

## Cutting a release

1. Before the first signed release, settle the launch checklist below. The script refuses a signed
   build while the bundle ID contains "prototype" (in any case), or while a link it needs in
   `Support/release.env` is still empty (see above).
2. Set the version in `VERSION` (three numbers, such as `1.0.1`), or pass it as the argument.
3. Commit everything. The script warns if the tree has uncommitted changes, since the release then
   matches no commit.
4. Run the tests: `scripts/test.sh`.
5. Build, sign and notarize:

   ```sh
   scripts/release.sh          # the version from VERSION
   scripts/release.sh 1.0.1    # or a version given here
   ```

   This checks the certificate and the notary profile before it builds, so a missing piece fails at
   once. Notarization runs twice, once for the app and once for the DMG, and usually takes a few minutes
   each. If Apple rejects either, the script prints Apple's log of what was wrong and stops.
6. It leaves `dist/Tuck-<version>.dmg`, `dist/Tuck-<version>.dmg.sha256` and
   `dist/Tuck-<version>.dSYM.zip`, the debug symbols (`dist/` isn't committed). Keep the symbols for as
   long as anyone uses that version: they are the only way to read its crash reports (see "Reading crash
   reports"). They never go in the DMG or on the site.
7. Try the DMG as someone downloading it would. Download it from the site to a Mac that has never run
   Tuck, so it arrives quarantined. Open it, drag Tuck to Applications and open Tuck: macOS should show
   only its ordinary "downloaded from the internet" question, naming the developer.
8. Upload the DMG and its checksum to the site, then tag the commit: `git tag v1.0.1`.

What the script does, in order:

1. `swift build -c release --arch arm64`, through `scripts/build-app.sh release <path> arm64 <dSYM>`,
   so the bundle is assembled (and stripped) exactly as a local build is, but in a temporary folder.
   `build/Tuck.app` is never touched. With the fourth argument, `dsymutil` gathers the debug symbols
   into a dSYM before `strip` removes them from the binary. It checks that the binary is arm64 only, and
   that the binary and the dSYM have the same UUID (`dwarfdump --uuid`).
2. Stamps the bundle's copy of Info.plist with the version, the build number, the bundle ID and the
   copyright, using `plutil -replace <key> -string <value>`, which takes each value as one argument, so
   a quote or apostrophe in a name stays as it is. `scripts/build-app.sh` stamps the links the same way.
3. Signs the app: `codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID"`, with no
   entitlements file (see below), and checks that the hardened runtime is on.
4. Zips the app with `ditto -c -k --keepParent`, notarizes it with
   `xcrun notarytool submit --keychain-profile "$NOTARY_PROFILE" --wait`, and staples the ticket to the
   app with `xcrun stapler staple`.
5. Makes the DMG with `hdiutil` (LZMA-compressed, volume name "Tuck"): the app, an `/Applications` link
   and `EULA.txt`. It then signs, notarizes and staples the DMG too.
6. Mounts the DMG out of sight of Finder and checks what ships: `codesign --verify --deep --strict`,
   arm64 only, the link and the EULA, and `spctl --assess --type execute -vv` for the app. After
   detaching it, `spctl --assess --type open --context context:primary-signature -vv` checks the DMG.
7. Writes the SHA-256 checksum beside the DMG in `dist/`, and zips the dSYM there too
   (`ditto -c -k --keepParent`), named after the DMG.

### A test DMG, before the account exists

```sh
scripts/release.sh --unsigned
```

This makes `dist/Tuck-<version>-unsigned.dmg` without any Apple account. The app is signed with "Tuck
Local Signing" when this Mac has it (below), else ad hoc, and the script says which. Either way it is
signed under the hardened runtime, so it runs as a signed build will. Nothing is notarized, so the
Gatekeeper checks are skipped, and Gatekeeper refuses the DMG once it has been downloaded. To try it on
a test Mac, open it from System Settings › Privacy & Security › Open Anyway, or copy it over without a
download. Until the account exists, this is also what the Line Apps site and the Homebrew tap ship
(below), with that step spelled out; once a signed release exists, they ship that instead.

### The local signing identity

macOS ties the Accessibility grant to the app's signature. An ad-hoc signature changes with every
build, so anyone who updates to a new ad-hoc DMG has to allow Tuck in Accessibility again, and so does
every local rebuild. "Tuck Local Signing" is a self-signed certificate that stays the same between
builds. Its designated requirement names the certificate (`certificate leaf = H"…"`), so each build
it signs is the same app to macOS, and the grant carries over. Make it once per Mac:

```sh
scripts/signing-identity.sh
```

It creates the identity in its own keychain, `~/Library/Keychains/tuck-signing.keychain-db`, with
the password `tuck-local-signing`, and adds that keychain to the search list so `codesign` finds the
key. The password is not a secret: the certificate is trusted by nothing and signs nothing anyone else
would accept, and the password only lets the scripts use the key without a prompt. Run again, the
script only says the identity already exists. `scripts/build-app.sh` signs with it whenever it exists,
and `scripts/release.sh --unsigned` does too, under the hardened runtime. Without it, both sign ad hoc,
and `scripts/build-app.sh` says how to make it.

**Back up its private key.** Until there is a Developer ID, this identity signs the DMG people
download. A new certificate is a new signature, so if the key is lost, everyone has to allow Tuck in
Accessibility once more at their next update. In Keychain Access, open the `tuck-signing` keychain
(unlocked with the password above), export "Tuck Local Signing" with its private key as a `.p12`, with
a strong password, and keep it somewhere safe outside the repository (`.gitignore` excludes `*.p12`). On
another Mac, importing that `.p12` into the same keychain, as the script's own `security import` and
`set-key-partition-list` lines do, keeps the same identity; running the script there instead makes a
new one. A signed release doesn't use it: the Developer ID signature replaces it, and that change asks
for Accessibility once more too.

## Publishing to Homebrew

Tuck installs with `brew install --cask millerroberts180/line-apps/tuck`. The tap is its own public
repository, [millerroberts180/homebrew-line-apps](https://github.com/millerroberts180/homebrew-line-apps),
with one cask per Line Apps app in `Casks/`. The cask downloads the same file as Tuck's page,
`https://lineapps.vercel.app/downloads/Tuck-<version>.dmg`, and checks it against its `sha256`. The full
name is needed because Homebrew's own catalogue has an unrelated cask called `tuck`.

For each version:

1. Cut the DMG as above (`scripts/release.sh`, or `--unsigned` until the account exists).
2. Put it on the Line Apps site at `/downloads/Tuck-<version>.dmg`. In the site's repository it goes in
   `downloads/` (a test DMG loses its `-unsigned`), and the download links on the home page and in
   `tuck/index.html` point at it. The cask's `livecheck` reads Tuck's page for that name.
3. In the tap's `Casks/tuck.rb`, set `version` and `sha256` (from the `.sha256` file). For a signed
   release, drop the Open Anyway caveat.
4. Check it: `brew audit --cask --strict --online millerroberts180/line-apps/tuck`.
5. Commit and push the tap. `brew upgrade` picks the new version up from there.

The cask's `zap` removes Tuck's library, settings, caches and HTTP storage under the bundle ID, and its
`uninstall quit:` quits any running app with that ID. Change both with the bundle ID (see "Changing
the bundle ID").

## Reading crash reports

The release binary is stripped, so a crash report someone sends shows addresses, not function names.
The dSYM zipped beside the DMG turns them back into names, but only for the exact build it came from.

1. Unzip `Tuck-<version>.dSYM.zip`. Check that it matches the report: `dwarfdump --uuid Tuck.app.dSYM`
   prints a UUID that must equal the one on the `Tuck` line of the report's Binary Images (in a `.ips`
   file, the `uuid` of the image named Tuck).
2. For one address, use `atos` with the load address from that Binary Images line:

   ```sh
   atos -arch arm64 -o Tuck.app.dSYM/Contents/Resources/DWARF/Tuck -l 0x100c34000 0x100c5a1f4 0x100c4b880
   ```

3. For a whole report, `symbolicatecrash` finds the dSYM by its UUID through Spotlight, once it is
   unzipped somewhere Spotlight indexes, such as a folder in your home:

   ```sh
   export DEVELOPER_DIR=$(xcode-select -p)
   "$(xcode-select -p)/../SharedFrameworks/DVTFoundation.framework/Versions/A/Resources/symbolicatecrash" report.crash > symbolicated.crash
   ```

   `symbolicatecrash` ships with Xcode, not the Command Line Tools, and reads the older `.crash` text
   form. For a `.ips` report, open it in Console (which shows the text form) and save that, or use
   `atos` per frame. This step hasn't been tried yet: the Mac Tuck is built on has only the Command
   Line Tools. `atos` and `dwarfdump` come with those.

## The hardened runtime needs no exceptions

Notarization requires the hardened runtime. Each exception it allows was checked against the code and
the release binary; none is needed, so there is no entitlements file.

- **JIT and unsigned executable memory:** none. Tuck is compiled Swift, with no JavaScriptCore, WebKit
  or code generation.
- **Library validation:** `otool -L` shows the binary links only system frameworks and `/usr/lib/swift`.
  Tuck has no embedded frameworks, plug-ins or dependencies, so nothing loaded needs another team's
  signature.
- **DYLD environment variables:** not used.
- **Debugging other processes:** Rest pauses and wakes apps with `kill(SIGSTOP)` and `kill(SIGCONT)` on
  the person's own processes, and reads them with `proc_pidinfo`, `proc_pid_rusage` and `proc_pidpath`.
  None of these needs a task port or a debugger entitlement.
- **Apple Events:** none are sent (no `NSAppleScript`, no Apple Event descriptors), so neither the
  `com.apple.security.automation.apple-events` entitlement nor `NSAppleEventsUsageDescription` is needed.
- **Audio input:** Rest asks Core Audio which processes are running audio
  (`kAudioHardwarePropertyProcessObjectList`, `kAudioProcessPropertyIsRunning`). It captures nothing, so
  no audio-input entitlement and no microphone or audio-capture usage string.
- **Camera, location, contacts, calendars, photos:** not used.
- **Event taps:** modifier-drag and the mouse wheel use active (`.defaultTap`) session taps for mouse and
  scroll events, and the wheel posts scroll events. Both are covered by the Accessibility permission,
  which is a TCC grant the person gives, not an entitlement. Neither is a listen-only keyboard tap, so
  there is no Input Monitoring prompt.
- **Screen Recording:** not needed. The window list is read for bounds, owner and layer only
  (`CGWindowListCopyWindowInfo`), never window names or pixels.
- **Other system services:** global mouse monitors (`NSEvent.addGlobalMonitorForEvents`), hot keys
  (`RegisterEventHotKey`), the login item (`SMAppService.mainApp`) and `/usr/bin/ditto` for zips need
  no entitlement. Nor do Uninstall's `/usr/bin/tccutil reset All <bundle ID>` and Move to
  Applications' `/bin/sh` relaunch, which are ordinary child processes.
- **The keychain:** at launch Tuck deletes the generic password item that builds with a trial left in
  the login keychain (`TrialLeftovers`), which needs no keychain-access-groups entitlement. An item
  another build made is refused the delete without the person being asked.

SwiftPM also leaves an `LC_RPATH` to the Command Line Tools' Swift libraries in the binary. Nothing
loads through `@rpath`, so it does nothing on a Mac that runs Tuck.

This was checked by reading the code and the binary. Tuck hasn't yet been run with a Developer ID
signature; the first signed build should be tried through every permission before it's released.

## Info.plist choices

- **Usage strings.** Setup's Just the Usual Folders route reads the Desktop, Documents, Downloads and
  iCloud Drive folders on purpose, to bring up macOS's prompts before the first drop. Dropped files on
  external and network drives bring up their own. Each prompt shows a usage string that says why Tuck
  asks: `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`,
  `NSDownloadsFolderUsageDescription`, `NSRemovableVolumesUsageDescription`,
  `NSNetworkVolumesUsageDescription`, and `NSFileProviderDomainUsageDescription`. That last one is the
  key macOS shows for iCloud Drive and other cloud folders ("wants to access files managed by iCloud
  Drive").
- **Not needed:** Accessibility and Full Disk Access have no usage string (macOS words those prompts
  itself, and Full Disk Access can't be requested). Tuck uses no Apple Events, no Screen Recording and
  no Input Monitoring, and reading the clipboard has no usage string.
- **Category:** `public.app-category.productivity`. Tuck organises your windows and files around what
  you're doing (sessions as Work, Personal, Study). That makes it a workflow tool, not a system utility
  like a disk or network tool. Finder's Group By Application Category uses it.
- **`LSArchitecturePriority`:** `arm64`, matching the build.
- **`NSHumanReadableCopyright`:** "© 2026 Miller Roberts", stamped from `Support/release.env`.

## Changing the bundle ID

The bundle ID is `com.millerroberts.Tuck`, set once in `Support/release.env`, in the same family as
the other Line Apps (`com.millerroberts.Glow`, `com.millerroberts.Pulse`). Until 2026-11-19 it was
`app.tuck.prototype`, the ID of Tuck 1.0.0 as the site and the tap first shipped it. macOS knows an app
by its bundle ID, so anyone updating from a build with the old one finds:

- **Accessibility has to be allowed again, and Open at login turned on again** (Settings › General).
  macOS keys both to the app's identity, so neither carries over, and nothing Tuck does can bring them
  across. Full Disk Access and any folder or drive access belong to the old ID too, and are asked for
  again.
- **Settings carry over.** They are kept in macOS's preferences under the bundle ID. At its first launch
  under the new ID, before anything reads a setting, Tuck copies every key saved under
  `app.tuck.prototype` into the new domain, while the new one has none (`SettingsMigration`, called
  first in `TuckMain`). Setup is marked done with the rest, so it doesn't run again. The old domain is
  never deleted, so Uninstall, which removes the current ID's settings, leaves it behind.
- **The library carries over:** tucked windows, held items, clipboard history and saved copies live in
  `~/Library/Application Support/Tuck`, which is named after the app, not the ID.
- **What builds with a trial left behind stays under the old ID.** Tuck deletes it at launch, but only
  under its own bundle ID (`TrialLeftovers`).
- **Logs** move to the new subsystem: `log stream` predicates name `com.millerroberts.Tuck` (see
  architecture.md's Diagnostics).
- **The Homebrew cask's** `zap` paths and `uninstall quit:` name the bundle ID, so they change with it.

Changing it again would need the same carry-over from the ID before. Local builds take the same
bundle ID as releases. On a Mac that runs both, they share settings, and the Accessibility grant goes
to whichever signature last asked, so run one at a time.

## Launch checklist

Still open before Tuck is released:

- [ ] **Try Uninstall on a signed build in Applications.** `tccutil reset All` worked from a shell for a
  throwaway bundle that Launch Services knew (one in `~/Applications`), and failed for one in a
  temporary folder, which it couldn't find. It hasn't been run from inside a signed Tuck; when it fails,
  Tuck lists the System Settings steps instead.
- [ ] **Support and the privacy policy URL in the EULA and the privacy policy.** `Support/release.env`
  links About to Tuck's GitHub issues and to the drafts in `docs/legal/` on GitHub, with no support
  email. The drafts still have `[Support email]` and `[privacy policy URL]` placeholders, to be filled
  once they are reviewed.
- [ ] **A trademark search for "Tuck" in software** (Nice class 9), at least in the US, the EU and the UK,
  before the name is printed anywhere that's hard to change.
- [ ] **Testing on macOS 14, 15, 26 and the current release, with real apps,** using the signed,
  notarized DMG downloaded from the site: Gatekeeper's first open, every permission prompt and its usage
  string, tucking and restoring across apps, Rest, and quitting with windows tucked. Tuck has so far run
  only on macOS 15.7, and only as a local build.
- [ ] **An Icon Composer icon for macOS 26 and later.** It needs Xcode's `actool`, which the Command Line
  Tools don't include, so `Support/AppIcon.icns` stays until then.
- [ ] **Legal review** of `docs/legal/EULA.txt` and `docs/legal/privacy-policy.md`, filling in their
  placeholders: the legal name or business, address, jurisdiction, and the EULA's limit of liability
  (section 8).
- [ ] **Enrolment as an individual or an organisation,** since it decides whose name macOS shows as
  Tuck's developer (see "One-time setup").
- [ ] **Clipboard history when switched off.** Turning it off stops capture but keeps saved entries until
  they age out, and Clear Clipboard History is unavailable while it's off. The privacy policy says so
  as it stands. Clearing on switch-off may be what people expect.
