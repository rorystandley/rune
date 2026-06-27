#!/usr/bin/env bash
set -euo pipefail

: "${APPLE_DEVELOPMENT_TEAM:?Set APPLE_DEVELOPMENT_TEAM to your Apple team ID.}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
config="$script_dir/../macos/Runner/Configs/LocalSigning.xcconfig"
identity="${APPLE_CODE_SIGN_IDENTITY:-Apple Development}"

printf 'DEVELOPMENT_TEAM = %s\nCODE_SIGN_IDENTITY = %s\n' \
  "$APPLE_DEVELOPMENT_TEAM" "$identity" > "$config"

echo "Wrote ignored local signing settings to $config"
