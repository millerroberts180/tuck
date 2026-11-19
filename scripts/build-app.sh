#!/usr/bin/env bash
# Builds a size-optimised, stripped Tuck.app for the host architecture into build/.
# Usage: scripts/build-app.sh [release|debug] [output .app path] [architecture] [dSYM path]
# With no arguments it builds build/Tuck.app for local runs. scripts/release.sh passes its own output
# path, arm64 and a dSYM path, so a release is assembled exactly as a local build is. Paths are relative
# to the repository root.
set -euo pipefail
cd "$(dirname "$0")/.."

config="${1:-release}"
app="${2:-build/Tuck.app}"
# The bundle is deleted and rebuilt, so anything but a .app path is refused.
if [[ "$app" != *.app ]]; then
  echo "error: the output must be a .app path, not '$app'" >&2
  exit 64
fi
# So is the dSYM, so anything but a .dSYM path is refused too.
dsym="${4:-}"
if [[ -n "$dsym" && "$dsym" != *?.dSYM ]]; then
  echo "error: the debug symbols must go to a .dSYM path, not '$dsym'" >&2
  exit 64
fi
# Naming an architecture makes the binary independent of the machine that builds it.
arch=()
if [[ -n "${3:-}" ]]; then arch=(--arch "$3"); fi
swift build -c "$config" ${arch[@]+"${arch[@]}"} --product Tuck
binary="$(swift build -c "$config" ${arch[@]+"${arch[@]}"} --show-bin-path)/Tuck"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Tuck"
cp Support/Info.plist "$app/Contents/Info.plist"
# The bundle ID and copyright are set in one place, Support/release.env, and stamped on the bundle's
# copy, never on the source plist. plutil takes each value as one argument, so quotes and apostrophes
# in a name stay as they are.
source Support/release.env
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$app/Contents/Info.plist"
plutil -replace NSHumanReadableCopyright -string "$COPYRIGHT" "$app/Contents/Info.plist"
# The version people see comes from VERSION, so a local build reports the version it was built at.
# scripts/release.sh stamps it again from its own argument, when it is given one.
plutil -replace CFBundleShortVersionString -string "$(tr -d '[:space:]' < VERSION)" "$app/Contents/Info.plist"
# Where About's links point, from the same file. One left empty keeps the source plist's placeholder.
for setting in TuckWebsiteURL=WEBSITE_URL TuckSupportEmail=SUPPORT_EMAIL TuckSupportURL=SUPPORT_URL \
               TuckPrivacyPolicyURL=PRIVACY_POLICY_URL TuckEULAURL=EULA_URL; do
  variable="${setting#*=}"
  if [[ -n "${!variable:-}" ]]; then
    plutil -replace "${setting%%=*}" -string "${!variable}" "$app/Contents/Info.plist"
  fi
done
# The app icon is built from the logo masters by design/logo/render.swift.
cp Support/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

# The debug symbols are kept apart first, when asked, so a crash report from a stripped build can still
# be read. dsymutil gathers them from the build's object files into a dSYM with the binary's UUID.
if [[ -n "$dsym" ]]; then
  rm -rf "$dsym"
  dsymutil "$app/Contents/MacOS/Tuck" -o "$dsym"
fi

if [[ "$config" == "release" ]]; then
  # Drop local, debug and Swift symbols; keeps the bundle small (about 8% of the binary over local
  # and debug alone). dyld binds through the binary's fixups, not its symbol table, so it loads the same.
  strip -rSTx "$app/Contents/MacOS/Tuck"
fi

# Ad-hoc signature so macOS will launch the locally built bundle. Not a distribution signature.
codesign --force --sign - "$app" >/dev/null

size="$(du -sh "$app" | cut -f1)"
echo "Built $app ($size)"
