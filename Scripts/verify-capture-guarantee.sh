#!/bin/bash
#
# Checks the shapes that must not compile.
#
# `body(_:_:)` and `navigation(_:_:)` are type methods so that a description
# cannot capture the controller: the tree holds every closure a description
# carries for as long as the view lives, and the view belongs to the
# controller. That guarantee is a compile-time property, and a test suite has
# no way to assert "this does not build" — so it is asserted here.
#
# Each fixture declares the diagnostic it expects on its first line. Failing to
# build is not enough: a fixture that broke for an unrelated reason would pass
# while proving nothing.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${DERIVED_DATA_PATH:-$ROOT/.build/capture-guarantee}"
FIXTURES="$ROOT/Scripts/CaptureGuaranteeFixtures"

echo "Building FineUIKit for the fixtures to import…"
xcodebuild -scheme FineUIKit \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$DERIVED" \
    build >/dev/null

PRODUCTS="$DERIVED/Build/Products/Debug-iphonesimulator"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
# The deployment floor the package declares. A fixture is only ever
# type-checked, so the architecture just has to be one the SDK carries.
TARGET="arm64-apple-ios17.0-simulator"

status=0
for fixture in "$FIXTURES"/*.swift; do
    name="$(basename "$fixture")"
    expected="$(sed -n '1s|^// expect-error: ||p' "$fixture")"

    if [ -z "$expected" ]; then
        echo "FAIL: $name has no '// expect-error:' line."
        status=1
        continue
    fi

    if output=$(swiftc -typecheck -swift-version 6 \
        -sdk "$SDK" -target "$TARGET" -I "$PRODUCTS" \
        "$fixture" 2>&1); then
        echo "FAIL: $name compiled. The capture guarantee is gone."
        status=1
    elif ! grep -qF "$expected" <<<"$output"; then
        echo "FAIL: $name did not compile, but not for the stated reason."
        echo "  wanted: $expected"
        grep "error:" <<<"$output" | head -3 | sed 's/^/  got:    /'
        status=1
    else
        echo "ok: $name"
    fi
done

exit "$status"
