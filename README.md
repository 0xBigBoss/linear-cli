# Linear CLI (Zig)

A lightweight Linear command-line client written in Zig. Goals: single static binary, zero external deps, fast issue workflows (list, view, create), human-readable output by default with a `--json` switch, and safe auth handling via env/config. Tooling/target: Zig 0.15.2, prefer stdlib helpers, macOS-focused default build (no custom flags for now).

## Current status
- Planning and API reconnaissance only (no scaffold yet).
- Verified auth: use `Authorization: $LINEAR_API_KEY` header (no Bearer/Linear prefix) against `https://api.linear.app/graphql`.
- Workspace sample: team `Send` (key `SEN`, id ``) with states Backlog, Todo, In Progress, In Review, Done, Canceled, Duplicate.
- Issue queries tested: pagination works (`pageInfo.hasNextPage/endCursor`), filtering by `team.key` and by `state.type` (e.g., exclude `completed`/`canceled`), fields include identifier/title/state/assignee/priorityLabel/url/timestamps.

## Planned command surface (v0)
- `linear gql` — send an arbitrary GraphQL query/mutation to Linear; useful for debugging and capturing fixtures.
- `linear auth set` / `auth test` — set key in config, validate reachability.
- `linear me` — show current user.
- `linear teams list` — list team ids, keys, names.
- `linear issues list` — default team from config; flags: `--team KEY|ID`, `--state STATE|type`, `--limit N`, `--json`. Default filter: exclude completed/canceled.
- `linear issue view ID|IDENT` — fetch a single issue by id or identifier.
- `linear issue create` — required: `--team`; options: `--title`, `--description`, `--priority`, `--state`, `--assignee`, `--labels`. Returns identifier/url.

## Tooling and build target
- Zig 0.15.2.
- macOS default target; no extra/custom flags initially.
- Single static binary named `linear` via `build.zig`; prefer stdlib (`std.build`, `std.cli`, `std.fs`, `std.http`, `std.json`) wherever possible.

## Config & defaults
- Config file: `~/.config/linear/config.json` (chmod 600).
- Keys: `api_key` (required unless `LINEAR_API_KEY` set), `default_team_id` (initially ``), optional `default_output` (`table`|`json`), `default_state_filter` (e.g., `["completed","canceled"]` to exclude).
- Precedence: CLI flags > env (`LINEAR_API_KEY`) > config.
- Pagination default: 25; expose `--limit` and follow `pageInfo.endCursor` when pagination is implemented.

## Output & UX
- Default: table with identifier, title, state, assignee, priority, updated.
- `--json` outputs structured JSON matching query shape.
- Errors surfaced with clear messages; token missing or 401 explains how to set `LINEAR_API_KEY` or run `auth set`.

## Planned project layout
- `build.zig` — single binary build; standard debug/release-fast/release-safe modes.
- `src/main.zig` — entry point; parses global flags, dispatches subcommands, loads config, initializes the GraphQL client, and routes output format preference.
- `src/config.zig` — read/write config file, apply env overrides, enforce perms, provide defaults for team/output/state filters, resolve API key from env/config/flag.
- `src/graphql_client.zig` — wrapper over `std.http.Client`; configures endpoint (`https://api.linear.app/graphql`), Authorization header, timeouts/backoff slots, and helpers to send queries/mutations and surface GraphQL errors.
- `src/print.zig` — table and JSON rendering helpers; central place for formatting issue/user/team rows and timestamps.
- `src/commands/` — one module per command group:
  - `auth.zig` — `auth set`, `auth test`; writes config, validates key via a ping query.
  - `me.zig` — current user.
  - `teams.zig` — list teams.
  - `issues.zig` — list issues (filters, pagination stub).
  - `issue_view.zig` — view a single issue by id/identifier.
  - `issue_create.zig` — create issue, return identifier/url.
- `src/tests/` — focused unit tests for config parsing/writing, CLI flag parsing, printer shapes; optional online smoke tests guarded by env.

## CLI and flow design (planned)
- Global flags: `--json` (output override), `--config PATH` (optional override), `--help`, `--version`.
- Dispatch: `linear <group> <command> [flags]`. `group` defaults to `issues` when a lone identifier is supplied? (initial pass: require group for clarity).
- Common flow per command:
  1. Parse flags/args with `std.cli`. Provide clear usage strings per module.
  2. Load config (respect `--config` if present) and merge env overrides (`LINEAR_API_KEY`).
  3. Resolve API key (fail with guidance if missing).
  4. Initialize GraphQL client (timeout/backoff defaults).
  5. Execute query/mutation; map errors to user-friendly messages.
  6. Render via `print.zig` respecting `--json`/config default.
- `auth set`: accept `--api-key` or prompt? (initial: flag or env only); writes config with 600 perms.
- `auth test`: performs a lightweight query (e.g., `viewer { id name }`) to validate key.
- `me`: fetch viewer fields and print.
- `teams list`: fetch teams (id/key/name).
- `issues list`: default team id from config; flags `--team`, `--state`, `--limit`. Apply default state exclusion (`completed`,`canceled`). Pagination stub acknowledges `pageInfo`.
- `issue view`: accept identifier or id; fetch issue core fields plus description/url/timestamps.
- `issue create`: flags for team/title/description/priority/state/assignee/labels; returns identifier/url.
- `gql`: accepts query via `--query FILE` or stdin; optional variables via `--vars JSON` or `--vars-file FILE`; outputs JSON (pretty by default) with `--data-only` to strip the envelope; exits non-zero on HTTP/GraphQL errors. TODO: add `--operation-name` switch if needed. This will be built first to validate the GraphQL client and collect fixtures for other commands.

## GraphQL client plan
- Constants: endpoint, default timeout, max retries/backoff cap, default headers.
- API key header: `Authorization: <key>` (no Bearer).
- Helper: `init(allocator, api_key)` returning a client struct; `deinit` closes HTTP client resources.
- `send(query, variables)` returning parsed JSON value plus GraphQL `errors` propagation; capture HTTP status and meaningful error messages.
- Retry policy: stub hooks with TODO; implement capped exponential backoff for 429/5xx later.

## Config plan
- Path resolution: expand `~/.config/linear/config.json` unless `--config` provided.
- Loading: read file if present, parse JSON into struct with optional fields, validate types.
- Env overrides: `LINEAR_API_KEY` takes precedence over file; CLI flags override both.
- Writing: ensure parent dir exists, create file with 0600 perms, serialize JSON with minimal formatting.
- Defaults: `default_team_id = `, `default_output = table`, `default_state_filter = ["completed","canceled"]`, pagination = 25.

## Output plan
- Table rendering: compute column widths for identifier/title/state/assignee/priority/updated; truncate long titles; consistent ordering of state values.
- JSON rendering: pass through parsed payloads, optionally shape minimal structs for stability.
- Time formatting: human-friendly (e.g., relative or ISO); start with ISO 8601 strings.

## Testing plan
- Offline tests: config load/save/precedence, CLI flag parsing per command, print width handling.
- Online smoke (optional): gated by `LINEAR_API_KEY` and `LINEAR_ONLINE_TESTS=1`; hit `/graphql` with viewer query; skipped by default.
- `zig test` wiring in `build.zig` to run offline tests; online tests separated or runtime-gated.

## Next steps
1) Scaffold Zig project layout (`build.zig`, `src/main.zig`, module stubs) using Zig 0.15.2 and stdlib-first components; keep the build standard/macOS-focused for now.  
2) Implement config loader/saver with 600 perms and env overrides.  
3) Add GraphQL client wrapper (headers, timeouts, retries, error surfacing).  
4) Implement `auth test`, `me`, `teams list`, `issues list`, `issue view/create` with table/JSON output.  
5) Document command examples and add smoke test instructions (env-based).  
6) Iterate on pagination and additional filters once core flows are stable.
