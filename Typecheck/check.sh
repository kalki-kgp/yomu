#!/bin/zsh
# Typechecks the app against the macOS SDK, for a Mac without Xcode. The two UIKit files are
# swapped for Shim.swift; CI is still what builds the real thing.
cd "$(dirname "$0")/.."
swiftc -typecheck -parse-as-library -swift-version 5 -target arm64-apple-macosx26.0 \
  $(find App -name '*.swift' ! -name Platform.swift ! -name Zoomable.swift) Typecheck/Shim.swift 2>&1 | grep -E 'error|warning: var|^$' -A3 | head -${1:-80}
echo "exit ${pipestatus[1]}"
