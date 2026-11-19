#!/usr/bin/env bash
# Runs the unit tests. With only the Command Line Tools installed, Swift Testing lives outside the
# default framework search path, so point the compiler and linker at it. Its Foundation cross-import
# overlay ships without module files, so overlays are disabled for the test build. Full Xcode needs no flags.
set -euo pipefail
cd "$(dirname "$0")/.."

extra=()
developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ "$developer_dir" == *CommandLineTools* ]]; then
  frameworks="$developer_dir/Library/Developer/Frameworks"
  if [[ -d "$frameworks/Testing.framework" ]]; then
    extra=(-Xswiftc -F -Xswiftc "$frameworks" -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xlinker -F -Xlinker "$frameworks" -Xlinker -rpath -Xlinker "$frameworks")
  fi
fi

swift test ${extra[@]+"${extra[@]}"} "$@"
