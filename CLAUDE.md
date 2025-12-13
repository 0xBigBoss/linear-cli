# Agent Notes

- Toolchain: Zig 0.15.2, stdlib-only; binary name `linear`. Run `zig fmt` on touched Zig files and prefer `zig build test` for verification (online smoke optional via `LINEAR_ONLINE_TESTS=1` + `LINEAR_API_KEY`).
- Config: `~/.config/linear/config.json` (0600). Precedence: CLI flags > env (`LINEAR_API_KEY`) > config. Defaults: team ``, output `table`, state filter excludes `completed`/`canceled`.
- Auth header must be `Authorization: <key>` (no Bearer). Do not alter endpoint `https://api.linear.app/graphql`.
- Command surface: global `--json`/`--config`/`--help`/`--version`; subcommands `auth set|test`, `me`, `teams list`, `issues list`, `issue view`, `issue create`, `issue comment`, `gql`. Pagination is a stub—warn when more pages remain.
- GraphQL client already handles HTTP status + GraphQL errors; retries only for 5xx with small backoff. Preserve explicit error messaging.
- Tests: offline unit coverage exists for config, flag parsing, printer; keep them passing. Online tests are gated by env and should remain optional.
