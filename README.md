# Linear CLI (Zig)

Single-binary Linear client built with Zig 0.15.2. Uses stdlib only, defaults to human-readable tables with a `--json` override, and stores auth securely at `~/.config/linear/config.json` (0600). Use `linear help <command>` to see command-specific flags and examples.

## Build & Test
- Build: `zig build -Drelease-safe` (debug is default). Binary installs to `zig-out/bin/linear`.
- Tests: `zig build test`. Online suite runs with `LINEAR_ONLINE_TESTS=1`: `LINEAR_ONLINE_TESTS=1 LINEAR_TEST_TEAM_ID=<TEAM_ID> zig build online` (requires `LINEAR_API_KEY`; optional `LINEAR_TEST_ISSUE_ID`, `LINEAR_TEST_PROJECT_ID`, `LINEAR_TEST_MILESTONE_ID`; opt-in mutations with `LINEAR_TEST_ALLOW_MUTATIONS=1`).

## Manual QA (Live API)
- Quick start (uses a temp config): 
  ```
  export LINEAR_API_KEY=<paste key>
  export LINEAR_ONLINE_TESTS=1
  export LINEAR_TEST_TEAM_ID=<team-id>
  # Optional for broader coverage:
  # export LINEAR_TEST_ISSUE_ID=<identifier like ENG-123>
  # export LINEAR_TEST_PROJECT_ID=<project id>
  # export LINEAR_TEST_MILESTONE_ID=<milestone id>
  # export LINEAR_TEST_ALLOW_MUTATIONS=1  # enables create/delete tests
  rm -f /tmp/linear-cli-qa.json
  echo "$LINEAR_API_KEY" | ./zig-out/bin/linear --config /tmp/linear-cli-qa.json auth set
  ./zig-out/bin/linear --config /tmp/linear-cli-qa.json auth test
  zig build test
  LINEAR_ONLINE_TESTS=1 LINEAR_TEST_TEAM_ID=$LINEAR_TEST_TEAM_ID zig build online
  ```
- Finding IDs quickly:
  - Team: `./zig-out/bin/linear --config /tmp/linear-cli-qa.json teams list --json | jq -r '.nodes[0].id'`
  - Issue identifier: `./zig-out/bin/linear --config /tmp/linear-cli-qa.json issues list --limit 1 --quiet`
  - Project/milestone: `./zig-out/bin/linear --config /tmp/linear-cli-qa.json issues list --include-projects --fields project,milestone --limit 1 --json`
  - If no suitable issue exists and mutations are allowed: `LINEAR_TEST_ALLOW_MUTATIONS=1 ./zig-out/bin/linear --config /tmp/linear-cli-qa.json issue create --team <TEAM_KEY_OR_ID> --title "CLI QA seed" --quiet`

## Config & Auth
- Config path: `~/.config/linear/config.json` (override with `--config PATH` or env `LINEAR_CONFIG`).
- Precedence: CLI flags > env (`LINEAR_API_KEY`) > config file. Keys loaded from env are not written back to disk.
- Keys:
  - `api_key` (or env `LINEAR_API_KEY`; `auth set` accepts `--api-key`, piped stdin, or an interactive prompt with echo disabled)
  - `default_team_id` (default ``)
  - `default_output` (`table`|`json`, default `table`)
  - `default_state_filter` (default `["completed","canceled"]`)
  - `team_cache` (auto-populated key->id cache from `issue create`)
- Files are saved with 0600 perms; the CLI warns if permissions drift. `auth show [--redacted]` surfaces the configured key without leaking the full token. `auth test` pings `viewer` to validate the current key.

## CLI Overview
Global flags:
- `--json` — force JSON output (default follows `config.default_output`)
- `--config PATH` or env `LINEAR_CONFIG` — choose config file
- `--endpoint URL` — override the GraphQL endpoint (useful for QA/mocking)
- `--retries N` — retry 5xx responses up to N times with a small backoff
- `--timeout-ms MS` — request timeout flag (plumbed for future enforcement)
- `--no-keepalive` — disable HTTP keep-alive reuse
- `--help`/`--version` — version includes git hash and build mode
- `linear help <command>` — show command-specific help with examples

Commands:
- `auth set [--api-key KEY]` — save key to config (stdin/interactive fallback when the flag is omitted).
- `auth test` — ping `viewer` to validate the key.
- `auth show [--redacted]` — view the configured key (masked when requested).
- `me` — show current user.
- `teams list [--fields id,key,name] [--plain] [--no-truncate]` — list teams with optional column and formatting controls.
- `search <query> [--team ID|KEY] [--fields title,description,comments,identifier] [--state-type TYPES] [--assignee USER_ID|me] [--limit N] [--case-sensitive]` — server-side search over titles/descriptions/comments or identifiers (identifier filter matches issue numbers; pagination warns when more results remain).
- `issues list [--team ID|KEY] [--state TYPES] [--created-since TS] [--updated-since TS] [--project ID] [--milestone ID] [--limit N] [--max-items N] [--sub-limit N] [--cursor CURSOR] [--pages N|--all] [--fields ...] [--include-projects] [--plain] [--no-truncate] [--human-time]` — defaults to the config team; excludes completed/canceled unless `--state` is provided; project/milestone filters available; parent/sub-issue columns stay opt-in and can be disabled entirely via `--sub-limit 0`; `--include-projects` (or fields) adds project/milestone context; `--max-items` stops mid-page when needed; paginates with cursor support plus page summaries.
- `issue view <ID|IDENTIFIER> [--fields LIST] [--quiet] [--data-only] [--human-time] [--sub-limit N]` — show a single issue; `--fields` filters output (identifier,title,state,assignee,priority,url,created_at,updated_at,description,project,milestone,parent,sub_issues); `--sub-limit` controls sub-issue expansion when requested; `--quiet` prints only the identifier, `--data-only` emits tab-separated fields or JSON.
- `issue create --team ID|KEY --title TITLE [--description TEXT] [--priority N] [--state STATE_ID] [--assignee USER_ID] [--labels ID,ID] [--yes] [--quiet] [--data-only]` — resolves team key to id when needed, caches lookups, and returns identifier/url; requires `--yes`/`--force` to proceed (otherwise exits with a message).
- `issue delete <ID|IDENTIFIER> [--yes] [--dry-run] [--reason TEXT] [--quiet] [--data-only]` — archives an issue by id/identifier; requires `--yes`/`--force` to proceed; `--dry-run` validates the target without sending the mutation and echoes the reason/title for auditing.
- `gql [--query FILE] [--vars JSON|--vars-file FILE] [--operation-name NAME] [--fields LIST] [--data-only]` — arbitrary GraphQL; non-zero on HTTP/GraphQL errors.

## Output
- Tables for lists; key/value blocks for detail views.
- `--json` prints parsed JSON (gql honors `--fields` when present).
 - `issues list --json` adds top-level `pageInfo` plus limit/sort metadata (and `maxItems` when set); `--data-only --json` emits a nodes array with a sibling `pageInfo`.
- `--plain` disables padding/truncation; `--no-truncate` keeps full cell text.
- `--human-time` renders issue timestamps relative to now.
- `--data-only` on `issue view|create` emits tab-separated fields (or JSON); `--quiet` prints only the identifier. On `gql`, `--data-only` strips the GraphQL envelope.

## GraphQL Client
- Endpoint: `https://api.linear.app/graphql`.
- Auth header: `Authorization: <key>` (no Bearer).
- Shared HTTP client with keep-alive (toggle with `--no-keepalive`).
- Retries 5xx responses with a small backoff; timeout flag is wired for future use.
- Surfaces HTTP status and first GraphQL error when available; 401s nudge to set `LINEAR_API_KEY` or run `auth set`.

## Defaults
- Default team id: ``.
- Default output: table.
- Default state exclusion: `completed`, `canceled`.
- Pagination: 25 items per page; `--cursor`, `--pages`, and `--all` drive additional page fetches, and stderr reports fetched counts with `hasNextPage` status.

## Claude Code Integration

Install as a Claude Code plugin to let Claude manage Linear issues for you.

### Prerequisites

Install the `linear` binary first:
```bash
npm install -g @0xbigboss/linear-cli
linear auth set  # configure your API key
```

### Install the Plugin

**1. Add the marketplace:**
```
/plugin marketplace add https://github.com/0xbigboss/linear-cli
```

**2. Install the plugin:**
```
/plugin install linear-cli@linear-cli-marketplace
```

**3. Restart Claude Code** to load the plugin.

### What It Does

The plugin provides a skill that teaches Claude how to use the Linear CLI. Once installed, Claude will automatically use the CLI when you ask about:
- Listing, viewing, or creating issues
- Managing teams and projects
- Linking issues, adding attachments, or comments
- Any Linear-related task

Example prompts:
- "List my Linear issues"
- "Create an issue in the ENG team titled 'Fix login bug'"
- "Show me issue ENG-123"
- "Link ENG-123 as blocking ENG-456"
