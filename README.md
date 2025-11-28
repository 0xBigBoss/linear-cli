# Linear CLI (Zig)

Single-binary Linear client built with Zig 0.15.2. Uses stdlib only, defaults to human-readable tables with a `--json` override, and stores auth securely at `~/.config/linear/config.json` (0600). Use `linear help <command>` to see command-specific flags and examples.

## Build & Test
- Build: `zig build -Drelease-safe` (debug is default). Binary installs to `zig-out/bin/linear`.
- Tests: `zig build test`. Online smoke runs only if `LINEAR_ONLINE_TESTS=1` and `LINEAR_API_KEY` are set.

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
- `issues list [--team ID|KEY] [--state TYPES] [--created-since TS] [--updated-since TS] [--limit N] [--cursor CURSOR] [--pages N|--all] [--fields ...] [--plain] [--no-truncate] [--human-time]` — defaults to the config team; excludes completed/canceled unless `--state` is provided; supports parent/sub-issue columns and paginates with cursor support plus page summaries.
- `issue view <ID|IDENTIFIER> [--fields LIST] [--quiet] [--data-only] [--human-time]` — show a single issue; `--fields` filters output (identifier,title,state,assignee,priority,url,created_at,updated_at,description); `--quiet` prints only the identifier, `--data-only` emits tab-separated fields or JSON.
- `issue create --team ID|KEY --title TITLE [--description TEXT] [--priority N] [--state STATE_ID] [--assignee USER_ID] [--labels ID,ID] [--yes] [--quiet] [--data-only]` — resolves team key to id when needed, caches lookups, and returns identifier/url; requires `--yes`/`--force` to proceed (otherwise exits with a message).
- `issue delete <ID|IDENTIFIER> [--yes] [--quiet] [--data-only]` — archives an issue by id/identifier; requires `--yes`/`--force` to proceed.
- `gql [--query FILE] [--vars JSON|--vars-file FILE] [--operation-name NAME] [--fields LIST] [--data-only]` — arbitrary GraphQL; non-zero on HTTP/GraphQL errors.

## Output
- Tables for lists; key/value blocks for detail views.
- `--json` prints parsed JSON (gql honors `--fields` when present).
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
