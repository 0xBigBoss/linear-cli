# Linear CLI (Zig)

Single-binary Linear client built with Zig 0.15.2. Uses stdlib only, defaults to human-readable tables with a `--json` override, and stores auth securely at `~/.config/linear/config.json` (0600).

## Build & Test
- Build: `zig build -Drelease-safe` (debug is default). Binary installs to `zig-out/bin/linear`.
- Tests: `zig build test`. Online smoke runs only if `LINEAR_ONLINE_TESTS=1` and `LINEAR_API_KEY` are set.

## Config & Auth
- Config path: `~/.config/linear/config.json` (override with `--config PATH`).
- Keys:
  - `api_key` (or env `LINEAR_API_KEY`)
  - `default_team_id` (default ``)
  - `default_output` (`table`|`json`, default `table`)
  - `default_state_filter` (default `["completed","canceled"]`)
- Precedence: CLI flags > env > config file.
- Files are saved with 0600 perms; missing keys surface a friendly error.

## CLI Overview
Global flags: `--json`, `--config PATH`, `--help`, `--version`.

Commands:
- `auth set --api-key KEY` — save key to config (stdin fallback).
- `auth test` — ping `viewer` to validate the key.
- `me` — show current user.
- `teams list` — list team id/key/name.
- `issues list [--team ID|KEY] [--state TYPES] [--limit N]` — defaults to config team; excludes completed/canceled unless `--state` is provided. Emits a hint if more pages exist (pagination stub).
- `issue view <ID|IDENTIFIER>` — show a single issue with description and timestamps.
- `issue create --team ID|KEY --title TITLE [--description TEXT] [--priority N] [--state STATE_ID] [--assignee USER_ID] [--labels ID,ID]` — resolves team key to id when needed; returns identifier/url.
- `gql [--query FILE] [--vars JSON|--vars-file FILE] [--operation-name NAME] [--data-only]` — arbitrary GraphQL; non-zero on HTTP/GraphQL errors.

Output:
- Tables for lists; key/value blocks for detail views.
- `--json` prints parsed JSON; `--data-only` on `gql` strips the envelope.
- Errors include HTTP status and first GraphQL error when available; 401s nudge to set `LINEAR_API_KEY` or run `auth set`.

## GraphQL Client
- Endpoint: `https://api.linear.app/graphql`.
- Auth header: `Authorization: <key>` (no Bearer).
- Simple 5xx retry with a small backoff; timeout hook is stubbed for now.
- Surfaces `status`, parsed payload, and GraphQL errors.

## Defaults
- Default team id: ``.
- Default output: table.
- Default state exclusion: `completed`, `canceled`.
- Pagination: 25 items per page; additional pages currently reported as a warning.
