#!/bin/bash
# Publish the five npm packages for a release.
#
# Auth is npm TRUSTED PUBLISHING (OIDC), not a token: the workflow grants
# `id-token: write`, npm exchanges that short-lived GitHub identity for publish
# rights, and each package on npmjs.com names this repo + workflow filename as
# its trusted publisher. There is no NPM_TOKEN to leak, rotate, or let expire —
# which is what broke v0.2.11 and v0.3.0.
#
# `npm publish`, not `bun publish`: bun cannot present an OIDC identity
# (oven-sh/bun#22423, open since 2025-09) and fails with "missing
# authentication". Do not switch this back for speed.
#
# Requires npm >= 11.5.1 and Node >= 22.14.0. Publishing from a public repo
# also gets provenance attestations for free.
set -euo pipefail

VERSION="${1:?Usage: publish-npm.sh <version>}"

# Update versions. .github/workflows/release.yml has already run
# scripts/check-versions.sh --expect "$VERSION" against the committed
# manifests, so this only restates what the gate proved.
for f in npm/*/package.json; do
  jq --arg v "$VERSION" '.version = $v' "$f" > tmp && mv tmp "$f"
done
jq --arg v "$VERSION" '.optionalDependencies |= with_entries(.value = $v)' \
  npm/linear-cli/package.json > tmp && mv tmp npm/linear-cli/package.json

# Platform packages first: the wrapper pins them as optionalDependencies, so
# publishing it first would leave a window where `npm install` resolves a
# wrapper whose binaries do not exist yet.
for p in darwin-arm64 darwin-x64 linux-x64 linux-arm64; do
  echo "Publishing @0xbigboss/linear-cli-${p}..."
  (cd "npm/linear-cli-${p}" && npm publish --access public)
done

echo "Publishing @0xbigboss/linear-cli..."
(cd npm/linear-cli && npm publish --access public)

echo "Done"
