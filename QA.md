# Linear CLI Manual QA Guide (Zig 0.15.2)

Use this checklist for live verification against Linear with a real `LINEAR_API_KEY`. Prefer a fresh temp config file to avoid polluting defaults.

## Quick start (copy/paste)
```
export LINEAR_API_KEY=<paste key here>
export LINEAR_ONLINE_TESTS=1
export LINEAR_TEST_TEAM_ID=<your-team-id>
# Optional data to unlock more cases:
# export LINEAR_TEST_ISSUE_ID=<identifier like ENG-123>
# export LINEAR_TEST_PROJECT_ID=<project id>
# export LINEAR_TEST_MILESTONE_ID=<milestone id>
# export LINEAR_TEST_ALLOW_MUTATIONS=1   # enables create/delete tests
rm -f /tmp/linear-cli-qa.json
echo "$LINEAR_API_KEY" | ./zig-out/bin/linear --config /tmp/linear-cli-qa.json auth set
./zig-out/bin/linear --config /tmp/linear-cli-qa.json auth test
zig build test
zig build online
```

## Finding test IDs (no guessing)
- Team: use the default above or `./zig-out/bin/linear --config /tmp/linear-cli-qa.json teams list --json` to pick `id`.
- Issue identifier: `./zig-out/bin/linear --config /tmp/linear-cli-qa.json issues list --limit 1 --quiet` (copy the identifier). If nothing suitable exists and mutations are allowed, create one with `LINEAR_TEST_ALLOW_MUTATIONS=1 ./zig-out/bin/linear --config /tmp/linear-cli-qa.json issue create --team <TEAM_KEY_OR_ID> --title "CLI QA seed" --quiet` and reuse its identifier for view/delete tests.
- Project/milestone: `./zig-out/bin/linear --config /tmp/linear-cli-qa.json issues list --include-projects --fields project,milestone --limit 1 --json` and copy ids, or use GraphQL passthrough (`gql`) to query.

## Automation
- Run the live regression suite: `LINEAR_ONLINE_TESTS=1 LINEAR_TEST_TEAM_ID=<TEAM_ID> zig build online` (requires `LINEAR_API_KEY`; optional `LINEAR_TEST_ISSUE_ID`, `LINEAR_TEST_PROJECT_ID`, `LINEAR_TEST_MILESTONE_ID`; opt-in mutations with `LINEAR_TEST_ALLOW_MUTATIONS=1`). This covers `auth test`, `me`, `teams list`, `issues list` (with/without sub-issues), `issue view` (when identifier provided), schema introspection, and optional create/delete.

## Core commands
- `me`: `./zig-out/bin/linear --config /tmp/linear-cli-qa.json me` (table) and `--json` via global flag anywhere (e.g., `... me --json` or `--json me`).
- `teams list`: plain table; also `--json`.

## Issues list (pagination, formats, filters)
- Basic paged fetch: `./zig-out/bin/linear --config /tmp/linear-cli-qa.json issues list --limit 5` (stderr should show cursor when more remain).
- Pagination walk: `./zig-out/bin/linear --config /tmp/linear-cli-qa.json issues list --limit 6 --pages 2` (should fetch 2 pages) and `--all` (walks until end). Resume with `--cursor <endCursor>`.
- Format variants:
  - `--plain --human-time` (aligned, relative timestamps).
  - `--fields identifier,title,state --no-truncate`.
  - `--quiet` (identifiers only) and `--data-only` (TSV), with `--json --data-only` (JSON object containing `nodes`, `pageInfo`, `limit`, `maxItems?`, `sort?`).
- Filters: `--assignee <user_id>`, `--state-type canceled`, `--label ...`, `--project <id>`, `--milestone <id>` (ensure non-empty result).
- Parent/sub and projects:
  - `--include-projects --fields parent,sub_issues --limit 3` (columns appear; JSON nodes contain project/milestone).
  - Disable sub-issues: `--sub-limit 0 --fields sub_issues` (sub columns omitted).
  - Truncation warning: `--sub-limit 1 --quiet` should print stderr notice about sub-issues limited.
- Max items: `--limit 5 --max-items 3 --quiet` stops early and warns on stderr.

## Issue view/create
- View: `./zig-out/bin/linear --config /tmp/linear-cli-qa.json issue view <IDENTIFIER>`:
  - default table, `--human-time`, `--quiet`, `--data-only --json`.
  - Fields: `--fields project,milestone` and `--fields parent,sub_issues --sub-limit 1` (sub-issue truncation warning printed to stderr).
- Create (target a safe team): `./zig-out/bin/linear --config /tmp/linear-cli-qa.json issue create --team <TEAM_KEY_OR_ID> --title "CLI QA test <timestamp>" --description "Temporary QA issue" --quiet` (expect identifier only). Optionally follow with `issue view` of the new issue. Clean up in Linear if needed.

## GraphQL passthrough
- Basic: `echo 'query { viewer { id name email } }' | ./zig-out/bin/linear --config /tmp/linear-cli-qa.json --json gql --data-only`.
- Fields filter (works without `--data-only`): `echo 'query { viewer { id name } teams(first:1){nodes{id name key}} }' | ./zig-out/bin/linear --config /tmp/linear-cli-qa.json gql --fields viewer`.
- Vars file/path: `./zig-out/bin/linear --config /tmp/linear-cli-qa.json gql --query path/to/query.graphql --vars '{"id":"..."}' --operation-name ...`.

## Global flags & retries
- Trailing globals: `./zig-out/bin/linear --config /tmp/linear-cli-qa.json issues list --json --timeout-ms 2000 --limit 2` (json should work even after subcommand).
- Timeout/retries: `./zig-out/bin/linear --config /tmp/linear-cli-qa.json --timeout-ms 1 --retries 1 me` (should emit timeout). For retry messaging, temporarily point to a mock/bad endpoint or induce 5xx if available.
- `--no-keepalive`: `./zig-out/bin/linear --config /tmp/linear-cli-qa.json --no-keepalive me` should still succeed.

## Issue delete
- Dry run: `./zig-out/bin/linear --config /tmp/linear-cli-qa.json issue delete <IDENTIFIER> --dry-run --reason "QA check"` (should resolve id/identifier/title, print reason, skip mutation; works with `--json` and `--data-only`).
- Real delete (only on throwaway issues): `... issue delete <ID|IDENTIFIER> --yes --reason "QA cleanup"` prints identifier/id and echoes reason.

## Cleanup
- Remove temp config: `rm -f /tmp/linear-cli-qa.json`.
- If any QA issues were created, close/archive them in Linear.
