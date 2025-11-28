#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: publish-npm.sh <version>}"

# bun publish reads NPM_CONFIG_TOKEN env var directly

# Update versions
for f in npm/*/package.json; do
  jq --arg v "$VERSION" '.version = $v' "$f" > tmp && mv tmp "$f"
done
jq --arg v "$VERSION" '.optionalDependencies |= with_entries(.value = $v)' \
  npm/linear-cli/package.json > tmp && mv tmp npm/linear-cli/package.json

# Publish platform packages first, then main
for p in darwin-arm64 darwin-x64 linux-x64 linux-arm64; do
  echo "Publishing @0xbigboss/linear-cli-${p}..."
  (cd "npm/linear-cli-${p}" && bun publish --access public)
done

echo "Publishing @0xbigboss/linear-cli..."
(cd npm/linear-cli && bun publish --access public)

echo "Done"
