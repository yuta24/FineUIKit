#!/bin/bash
#
# Workaround for InjectionLite 1.2.x with Xcode 27 beta.
#
# 1. Xcode 27's SLF build-log tokens prefix the swift-frontend command line
#    with junk containing unbalanced quotes, which breaks the shell command
#    InjectionLite constructs ("unexpected EOF while looking for matching
#    quote"). This script extracts the frontend commands from the existing
#    build logs, strips the junk, and writes them into a clean
#    .xcactivitylog that sorts as the most recent log.
# 2. The injected dylib's rpaths don't cover /usr/lib/swift, so dlopen can
#    fail to find libswift_Concurrency.dylib. A symlink in
#    Build/Products/Debug-iphonesimulator/PackageFrameworks/ fixes that.
#
# Usage: Scripts/injectionlite-xcode27-fix.sh [project-name]
# Run it after every build (or add it as a scheme post-build action).

set -euo pipefail
export LC_ALL=C

PROJECT_NAME="${1:-ToDo}"

DERIVED=$(ls -td "$HOME/Library/Developer/Xcode/DerivedData/$PROJECT_NAME"-*/ 2>/dev/null | head -1 || true)
if [ -z "$DERIVED" ]; then
    echo "error: no DerivedData found for project '$PROJECT_NAME'" >&2
    exit 1
fi

LOGS="$DERIVED/Logs/Build"
if [ ! -d "$LOGS" ]; then
    echo "error: $LOGS not found — build the app in Xcode first" >&2
    exit 1
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# Newest logs first so the freshest command for each file wins the de-dupe.
for log in $(ls -t "$LOGS"/*.xcactivitylog); do
    case "$(basename "$log")" in injectionfix-*) continue ;; esac
    gunzip -c "$log" 2>/dev/null | tr '\r' '\n' | grep -a -- ' -primary-file ' |
        sed -E 's@^.*["#](/[^" ]*/(swift-frontend|swiftc) )@\1@' |
        sed -E 's@^[[:space:]]+@@' |
        grep -a '^/' || true
done | awk '!seen[$0]++' > "$TMP"

COUNT=$(wc -l < "$TMP" | tr -d ' ')
if [ "$COUNT" -eq 0 ]; then
    echo "error: no swift-frontend commands found in build logs." >&2
    echo "Touch a Swift file, build in Xcode, then run this script again." >&2
    exit 1
fi

# The explicit-module dependency map (…-dependencies-N.json) is renumbered
# every build, so commands from older logs point at deleted files. Repoint
# the flag at the newest map that actually exists.
FIXED=$(mktemp)
while IFS= read -r line; do
    mapfile=$(printf '%s\n' "$line" |
        grep -oE ' -explicit-swift-module-map-file [^ ]+' |
        awk '{print $2}' || true)
    if [ -n "$mapfile" ]; then
        mapdir=$(dirname "$mapfile")
        newest=$(ls -t "$mapdir"/*-dependencies*.json 2>/dev/null | head -1 || true)
        if [ -n "$newest" ]; then
            line=${line/ -explicit-swift-module-map-file $mapfile/ -explicit-swift-module-map-file $newest}
        fi
    fi
    printf '%s\n' "$line"
done < "$TMP" > "$FIXED"
mv "$FIXED" "$TMP"

rm -f "$LOGS"/injectionfix-*.xcactivitylog
OUT="$LOGS/injectionfix-$(date +%s).xcactivitylog"
gzip -c "$TMP" > "$OUT"
echo "Wrote $COUNT clean frontend command(s) to $(basename "$OUT")"

# rpath workaround: make libswift_Concurrency.dylib findable from the
# injected dylib. It must be the simulator runtime's copy — the toolchain's
# swift-5.5 back-deployment copy lacks newer runtime symbols.
PRODUCTS="$DERIVED/Build/Products/Debug-iphonesimulator"
RUNTIME_ROOT=$(xcrun simctl list runtimes -j 2>/dev/null | python3 -c "
import json, sys
runtimes = [r for r in json.load(sys.stdin)['runtimes']
            if r.get('platform') == 'iOS' and r.get('isAvailable')]
runtimes.sort(key=lambda r: [int(v) for v in r['version'].split('.')])
print(runtimes[-1]['runtimeRoot'] if runtimes else '')
")
RUNTIME_LIB="$RUNTIME_ROOT/usr/lib/swift/libswift_Concurrency.dylib"
if [ -d "$PRODUCTS" ] && [ -n "$RUNTIME_ROOT" ] && [ -f "$RUNTIME_LIB" ]; then
    mkdir -p "$PRODUCTS/PackageFrameworks"
    ln -sf "$RUNTIME_LIB" "$PRODUCTS/PackageFrameworks/libswift_Concurrency.dylib"
    echo "Linked runtime libswift_Concurrency.dylib into PackageFrameworks/"
fi
