#!/usr/bin/env bash
# Builds Tuck for direct download: an arm64 release build, signed with a Developer ID under the hardened
# runtime, notarized and stapled, inside a DMG that is signed, notarized and stapled too, with the EULA
# beside the app. The DMG, its SHA-256 checksum and the zipped debug symbols (dSYM, never inside the DMG)
# go to dist/. docs/release.md has the one-time setup.
# Usage: scripts/release.sh [--unsigned] [version]
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  cat <<'EOF'
Usage: scripts/release.sh [--unsigned] [version]
  version     The version people see, such as 1.0.1. Defaults to the VERSION file.
  --unsigned  A DMG signed ad hoc and not notarized, which needs no Apple account. The Line Apps site
              and the Homebrew tap ship it until a signed release exists.
A signed release needs DEVELOPER_ID and NOTARY_PROFILE set in the environment; see docs/release.md.
EOF
}

unsigned=false
version=""
for arg in "$@"; do
  case "$arg" in
    --unsigned) unsigned=true ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "error: unknown option '$arg'" >&2; usage >&2; exit 64 ;;
    *)
      if [[ -n "$version" ]]; then
        echo "error: give one version, not both '$version' and '$arg'" >&2
        exit 64
      fi
      version="$arg" ;;
  esac
done
version="${version:-$(tr -d '[:space:]' < VERSION)}"
# Apple's form for CFBundleShortVersionString: up to three period-separated integers.
if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "error: the version must look like 1.0.0, not '$version'" >&2
  exit 64
fi

# The bundle ID and copyright, from the one place they are set.
source Support/release.env
if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
  echo "error: BUNDLE_ID in Support/release.env must be reverse-DNS, like com.example.tuck, not '$BUNDLE_ID'" >&2
  exit 1
fi

# What would ship unfinished: a bundle ID that still says "prototype" in any case, and About's links
# leading to placeholders. A test DMG may have them; a signed release may not.
prototype_id=false
if [[ "$(tr '[:upper:]' '[:lower:]' <<<"$BUNDLE_ID")" == *prototype* ]]; then prototype_id=true; fi
unset_links=()
for variable in WEBSITE_URL SUPPORT_EMAIL PRIVACY_POLICY_URL EULA_URL; do
  [[ -n "${!variable:-}" ]] || unset_links+=("$variable")
done

# Everything a signed release needs from outside the repository is checked before anything is built,
# so a missing piece fails at once rather than minutes in.
if ! $unsigned; then
  if [[ -z "${DEVELOPER_ID:-}" || -z "${NOTARY_PROFILE:-}" ]]; then
    # Everything still to do goes in one message, the bundle ID included.
    problems=()
    [[ -n "${DEVELOPER_ID:-}" ]] || problems+=("DEVELOPER_ID is not set.")
    [[ -n "${NOTARY_PROFILE:-}" ]] || problems+=("NOTARY_PROFILE is not set.")
    if $prototype_id; then
      problems+=("BUNDLE_ID in Support/release.env is still $BUNDLE_ID; set the final one too.")
    fi
    if (( ${#unset_links[@]} )); then
      problems+=("${unset_links[*]} in Support/release.env are still empty; set them too.")
    fi
    {
      echo "error: a signed release needs a Developer ID certificate and notarization credentials."
      printf '  %s\n' "${problems[@]}"
      cat <<'EOF'

One-time setup (docs/release.md has each step):
  1. Join the Apple Developer Program: https://developer.apple.com/programs/enroll/
  2. As the account holder, create a "Developer ID Application" certificate at
     https://developer.apple.com/account/resources/certificates and install it in this Mac's login
     keychain. `security find-identity -v -p codesigning` then lists its name; set it:
       export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
  3. Save notarization credentials in the keychain under a profile name, with an app-specific
     password from https://account.apple.com, and set the profile:
       xcrun notarytool store-credentials tuck-notary --apple-id you@example.com --team-id TEAMID
       export NOTARY_PROFILE=tuck-notary

To check the packaging without an account: scripts/release.sh --unsigned
EOF
    } >&2
    exit 1
  fi
  if $prototype_id; then
    echo "error: the bundle ID is still $BUNDLE_ID. Set the final one in Support/release.env before a" \
      "signed release; docs/release.md says what changing it means for anyone already using Tuck." >&2
    exit 1
  fi
  if (( ${#unset_links[@]} )); then
    echo "error: ${unset_links[*]} in Support/release.env are still empty, so About's links would lead" \
      "to placeholders. Set them before a signed release." >&2
    exit 1
  fi
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  identity="$(grep -F -- "$DEVELOPER_ID" <<<"$identities" || true)"
  if [[ -z "$identity" ]]; then
    echo "error: no valid signing certificate matching '$DEVELOPER_ID' is in the keychain." \
      "\`security find-identity -v -p codesigning\` lists the ones there." >&2
    exit 1
  fi
  if [[ "$identity" != *"Developer ID Application:"* ]]; then
    echo "error: '$DEVELOPER_ID' is not a Developer ID Application certificate, which notarization needs." >&2
    exit 1
  fi
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "error: notarytool can't use the keychain profile '$NOTARY_PROFILE'. Save it with" \
      "\`xcrun notarytool store-credentials $NOTARY_PROFILE\` (docs/release.md), and check this Mac is online." >&2
    exit 1
  fi
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo "warning: the working tree has uncommitted changes, so this release won't match a commit." >&2
  fi
fi

# The build number (CFBundleVersion) rises with every build because it starts with the UTC date and
# time, whatever happens to the git history, and UTC never steps back for daylight saving. The commit
# count after them says roughly which commit it came from. Three integers, each well under 2^31.
now="$(date -u +%Y%m%d.%H%M%S)"
build_number="${now%.*}.$((10#${now#*.})).$(git rev-list --count HEAD 2>/dev/null || echo 0)"

# Everything is assembled in a temporary folder; only the DMG and its checksum land in dist/.
work="$(mktemp -d -t tuck-release)"
mount=""
cleanup() {
  if [[ -n "$mount" ]]; then hdiutil detach "$mount" -quiet || true; fi
  rm -rf "$work"
}
trap cleanup EXIT

app="$work/Tuck.app"
dsym="$work/Tuck.app.dSYM"
scripts/build-app.sh release "$app" arm64 "$dsym"

archs="$(lipo -archs "$app/Contents/MacOS/Tuck")"
if [[ "$archs" != arm64 ]]; then
  echo "error: expected an arm64-only binary, found: $archs" >&2
  exit 1
fi
# A crash report names the binary by its UUID; the dSYM only reads it if the two match. Stripping and
# signing leave the UUID as it was.
binary_uuid="$(dwarfdump --uuid "$app/Contents/MacOS/Tuck" | awk '{print $2}')"
dsym_uuid="$(dwarfdump --uuid "$dsym" | awk '{print $2}')"
if [[ -z "$binary_uuid" || "$binary_uuid" != "$dsym_uuid" ]]; then
  echo "error: the dSYM ($dsym_uuid) doesn't match the binary ($binary_uuid)" >&2
  exit 1
fi

# Only the bundle's copy of Info.plist is stamped, with this release's version and build number.
plist="$app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$plist"
plutil -replace CFBundleVersion -string "$build_number" "$plist"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$plist"
plutil -replace NSHumanReadableCopyright -string "$COPYRIGHT" "$plist"

# No entitlements file: Tuck has no sandbox, JIT, plug-ins or Apple Events, and Accessibility, event taps
# and file access are permissions people grant (TCC), not entitlements. So the hardened runtime needs no
# exception (docs/release.md). Stamping changed Info.plist, so the bundle is signed again either way.
if $unsigned; then
  # Ad hoc, but under the hardened runtime as well, so a test build runs as a signed one will.
  codesign --force --options runtime --sign - "$app"
else
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$app"
fi
# The output is read in full first: piped straight into grep -q, codesign can be cut off once grep has
# matched, and pipefail then counts the check as failed.
signature="$(codesign --display --verbose=1 "$app" 2>&1)"
if [[ "$signature" != *flags=*runtime* ]]; then
  echo "error: the app was signed without the hardened runtime" >&2
  exit 1
fi

notarize() {
  local file="$1" name result status id
  name="$(basename "$file")"
  result="$work/notary-$name.json"
  echo "Notarizing $name; Apple usually answers within a few minutes…"
  # Whatever notarytool's exit status, the status it reports is what counts.
  xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json \
    >"$result" || true
  status="$(plutil -extract status raw -o - "$result" 2>/dev/null || echo "no answer")"
  if [[ "$status" != Accepted ]]; then
    echo "error: notarization of $name ended as: $status" >&2
    id="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
    if [[ -n "$id" ]]; then
      xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    else
      cat "$result" >&2
    fi
    exit 1
  fi
}

if ! $unsigned; then
  # The notary service takes a zip of the app; the ticket it issues is stapled to the app itself, so
  # Gatekeeper can check it offline.
  ditto -c -k --keepParent "$app" "$work/Tuck.zip"
  notarize "$work/Tuck.zip"
  xcrun stapler staple "$app"
fi

mkdir -p dist
if $unsigned; then dmg="dist/Tuck-$version-unsigned.dmg"; else dmg="dist/Tuck-$version.dmg"; fi
symbols="${dmg%.dmg}.dSYM.zip"
stage="$work/dmg"
mkdir -p "$stage"
ditto "$app" "$stage/Tuck.app"
ln -s /Applications "$stage/Applications"
cp docs/legal/EULA.txt "$stage/EULA.txt"
rm -f "$dmg" "$dmg.sha256"
# LZMA (ULMO) makes the smallest download, and every macOS Tuck runs on opens it.
hdiutil create -volname Tuck -srcfolder "$stage" -fs HFS+ -format ULMO -ov -quiet "$dmg"

if ! $unsigned; then
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$dmg"
  notarize "$dmg"
  xcrun stapler staple "$dmg"
fi

# Checks run on what ships: the app as it is inside the DMG, mounted out of sight of Finder.
mount="$work/mount"
mkdir -p "$mount"
hdiutil attach "$dmg" -nobrowse -readonly -noautoopen -mountpoint "$mount" -quiet
shipped="$mount/Tuck.app"
codesign --verify --deep --strict --verbose=2 "$shipped"
if [[ "$(lipo -archs "$shipped/Contents/MacOS/Tuck")" != arm64 ]]; then
  echo "error: the app in the DMG isn't arm64 only" >&2
  exit 1
fi
if [[ "$(readlink "$mount/Applications")" != /Applications || ! -f "$mount/EULA.txt" ]]; then
  echo "error: the DMG is missing its Applications link or the EULA" >&2
  exit 1
fi
if ! $unsigned; then
  spctl --assess --type execute -vv "$shipped"
fi
hdiutil detach "$mount" -quiet
mount=""
if ! $unsigned; then
  spctl --assess --type open --context context:primary-signature -vv "$dmg"
fi

(cd dist && shasum -a 256 "$(basename "$dmg")" >"$(basename "$dmg").sha256")
# The debug symbols go beside the DMG, never in it: nobody running Tuck needs them, and they are what
# turns someone's crash report back into function names (docs/release.md, "Reading crash reports").
rm -f "$symbols"
ditto -c -k --keepParent "$dsym" "$symbols"

echo
echo "Tuck $version (build $build_number), $BUNDLE_ID"
if $unsigned; then
  echo "Signed ad hoc and not notarized: Gatekeeper stops it until it is allowed with Open Anyway."
  if (( ${#unset_links[@]} )); then
    echo "It has placeholder links, as a signed release may not."
  fi
else
  echo "Signed with $DEVELOPER_ID, notarized and stapled."
fi
echo "  $dmg ($(du -h "$dmg" | cut -f1 | tr -d ' '))"
echo "  $dmg.sha256"
echo "  $symbols (debug symbols, UUID $binary_uuid; keep it for as long as this version is in use)"
