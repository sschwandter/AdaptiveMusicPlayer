#!/bin/bash
set -euo pipefail

APP_PATH="$1"
OUTPUT_ZIP="$2"

ditto -c -k --keepParent "$APP_PATH" "$OUTPUT_ZIP"
