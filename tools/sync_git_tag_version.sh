#!/bin/sh

set -eu

if [ -z "${TARGET_BUILD_DIR:-}" ] || [ -z "${INFOPLIST_PATH:-}" ] || [ -z "${SRCROOT:-}" ]; then
  exit 0
fi

PLIST_PATH="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

if [ ! -f "$PLIST_PATH" ]; then
  exit 0
fi

RAW_TAG="${APP_GIT_TAG:-}"

if [ -z "$RAW_TAG" ]; then
  RAW_TAG="$(git -C "$SRCROOT" describe --tags --dirty --always 2>/dev/null || true)"
fi

if [ -z "$RAW_TAG" ]; then
  exit 0
fi

RAW_TAG="${RAW_TAG#refs/tags/}"
SEMANTIC_TAG="${RAW_TAG#v}"

NORMALIZED_VERSION="$(printf '%s' "$SEMANTIC_TAG" | sed -E 's/^([0-9]+(\.[0-9]+){0,2}).*/\1/')"

if ! printf '%s' "$NORMALIZED_VERSION" | grep -Eq '^[0-9]+(\.[0-9]+){0,2}$'; then
  NORMALIZED_VERSION="$(
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST_PATH" 2>/dev/null || printf '1.0'
  )"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NORMALIZED_VERSION" "$PLIST_PATH" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $NORMALIZED_VERSION" "$PLIST_PATH"

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NORMALIZED_VERSION" "$PLIST_PATH" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $NORMALIZED_VERSION" "$PLIST_PATH"

/usr/libexec/PlistBuddy -c "Set :AdaptiveGitTag $RAW_TAG" "$PLIST_PATH" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :AdaptiveGitTag string $RAW_TAG" "$PLIST_PATH"
