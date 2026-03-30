#!/bin/bash
set -euo pipefail

API_KEY_PATH="AuthKey_${APPLE_KEY_ID}.p8"

echo "$APPLE_API_KEY_BASE64" | base64 --decode > "$API_KEY_PATH"
xcrun notarytool submit "$RELEASE_ZIP" \
  --key "$API_KEY_PATH" \
  --key-id "$APPLE_KEY_ID" \
  --issuer "$APPLE_ISSUER_ID" \
  --wait
xcrun stapler staple "$EXPORT_PATH/$APP_NAME.app"
ditto -c -k --keepParent "$EXPORT_PATH/$APP_NAME.app" "$RELEASE_ZIP"
