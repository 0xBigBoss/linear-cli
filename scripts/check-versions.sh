#!/bin/bash
# Version consistency gate.
#
# The git tag is the single source of truth: build.zig derives the binary's
# --version string from `git describe --tags`, so nothing in-tree can restate
# it. What CAN drift are the four hand-maintained manifests, and a release
# whose parts describe different versions is worse than one that fails to
# build — it ships silently.
#
# Checked:
#   package.json                  pi package
#   .claude-plugin/plugin.json    Claude Code plugin
#   npm/*/package.json            npm dist packages
#   npm/linear-cli optionalDependencies pins
#   npm/*/package.json repository.url
#
# The repository check is here because trusted publishing generates sigstore
# provenance, and npm rejects the upload when package.json's repository.url
# does not match the repo the provenance came from. The four platform packages
# had no repository field at all, which failed the v0.3.1 publish with a 422
# AFTER the tag, the GitHub release, and every other gate had gone green.
#
# Usage: check-versions.sh [--expect <version>]
#   --expect pins every manifest to that version (CI passes the tag).
#   Without it, the manifests only have to agree with each other.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

expect=""
if [[ "${1:-}" == "--expect" ]]; then
    expect="${2:?--expect needs a version}"
elif [[ $# -gt 0 ]]; then
    echo "usage: check-versions.sh [--expect <version>]" >&2
    exit 2
fi

fail=0
report() { echo "  $1" >&2; fail=1; }

declare -a files=(package.json .claude-plugin/plugin.json)
while IFS= read -r f; do files+=("$f"); done < <(ls npm/*/package.json)

reference="$expect"
echo "Version check:"
for f in "${files[@]}"; do
    v="$(jq -r '.version // empty' "$f")"
    if [[ -z "$v" ]]; then
        report "$f: no .version field"
        continue
    fi
    echo "  $f: $v"
    if [[ -z "$reference" ]]; then
        reference="$v"
    elif [[ "$v" != "$reference" ]]; then
        report "$f: $v != $reference"
    fi
done

# The npm wrapper pins its platform packages exactly; a stale pin resolves to
# an older binary than the wrapper claims to be.
while IFS= read -r pin; do
    dep="${pin%%=*}"
    v="${pin##*=}"
    if [[ "$v" != "$reference" ]]; then
        report "npm/linear-cli optionalDependencies['$dep']: $v != $reference"
    fi
done < <(jq -r '.optionalDependencies // {} | to_entries[] | "\(.key)=\(.value)"' npm/linear-cli/package.json)

# Provenance: npm compares this against the OIDC claim and 422s on a mismatch.
expected_repo="git+https://github.com/alleneubank/linear-cli.git"
for f in npm/*/package.json; do
    url="$(jq -r '.repository.url // empty' "$f")"
    if [[ -z "$url" ]]; then
        report "$f: no .repository.url (npm rejects provenance without it)"
    elif [[ "$url" != "$expected_repo" ]]; then
        report "$f: repository.url is '$url', expected '$expected_repo'"
    fi
done

if [[ $fail -ne 0 ]]; then
    echo "FAIL: manifests disagree${expect:+ with tag $expect}" >&2
    exit 1
fi

echo "OK: all manifests at $reference"
