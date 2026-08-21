# Changelog

Notable changes per release. Versions before 0.3.0 are recorded in the
[GitHub releases](https://github.com/alleneubank/linear-cli/releases).

## Unreleased

### Release engineering

- npm publishing moves to **trusted publishing (OIDC)**. The release workflow
  presents a short-lived, workflow-scoped GitHub identity via
  `id-token: write` and npm exchanges it for publish rights, so there is no
  long-lived `NPM_TOKEN`. The token had gone stale and silently broke npm
  publishing for two releases (v0.2.11 and v0.3.0 both failed with a registry
  404), while the tag, the GitHub release, and the manifests all looked
  correct.
- `scripts/publish-npm.sh` uses `npm publish` rather than `bun publish`: bun
  cannot present an OIDC identity (oven-sh/bun#22423) and fails with "missing
  authentication". `bunfig.toml` existed only to feed bun the token and is
  removed.
- Publishing from a public repo with OIDC also produces provenance
  attestations automatically.
- `flake.nix` provides a dev shell pinned to Zig 0.16.0 with `ziglint` and
  `jq`, so `zig build lint` works instead of failing with `FileNotFound`.
- The 14 findings that surfaced the first time ziglint actually ran are fixed
  (11 `deinit` bodies now poison the struct with `self.* = undefined`, plus one
  `@This()` binding and two error-literal returns), and CI runs `zig build
  lint` through the flake so the tree stays at zero.

## 0.3.0

The first release since v0.2.11, covering the Zig 0.16 migration, a
credential-handling security audit, and a large expansion of the command
surface.

### Breaking

- **`--api-key` removed.** It put the secret on argv, where it is visible in
  `ps` and saved to shell history. Use piped stdin (`echo "$KEY" | linear auth
  set`), the no-echo prompt, `LINEAR_API_KEY`, or a credential helper.
- **`auth show` redacts by default.** It previously printed the full key to
  stdout with `--redacted` as opt-in. `--reveal` is now required, and is
  refused when stdout is not a TTY so the key cannot be piped into a log.
- **`linear gql` requires `--yes` for mutations.** Detection scans top-level
  tokens only, so comments, string literals, and a field named `mutation` do
  not trip it. Adds `--dry-run`.
- **`--endpoint` is allowlisted** to `https` on `api.linear.app` unless
  `LINEAR_ALLOW_INSECURE_ENDPOINT=1`. It previously accepted plain `http://`
  to any host, making it a key-exfiltration channel.
- **`issue view` no longer downloads attachments by default.** It defaulted
  `attachment_dir` to `/tmp`; downloads are now opt-in via `--attachment-dir`
  and written 0600.
- **`issue delete --reason` removed.** `issueDelete` takes only
  `(id, permanentlyDelete)`; the value never reached the API.
- **`search --fields` now selects printed columns**, matching every other list
  command. The old meaning (which fields to search) moved to `--search-fields`.
- **No `auth migrate`.** Scrubbing a key from disk cannot beat APFS
  copy-on-write, snapshots, or backups, so a migrated key has to be rotated
  anyway. Delete `~/.config/linear/config.json` and set up fresh instead.
- A config file of exactly 64 KiB now errors (Zig 0.16 `.limited(n)` semantics).

### Security

- Env-derived keys are no longer written to disk. `auth set` fell back to the
  env key when none was supplied, and the persist gate then passed. The same
  ordering bug silently deleted a *stored* key from disk on any later `save()`
  whenever `LINEAR_API_KEY` was set.
- Config file TOCTOU: created 0644 then `chmod`'d: now created 0600 atomically
  inside a 0700 directory.
- API keys are charset/length validated (`[A-Za-z0-9_-]`, 4-512) at every
  ingestion point, closing CRLF header injection via a tampered config.
- `redactKey` returned the whole secret for short keys; returns a constant
  below a minimum length.
- A failed `disableEcho` now aborts instead of continuing to read with echo on.

### Added

- **Credential provider chain**: `LINEAR_API_KEY` -> `credential_helper` ->
  macOS keychain -> config file (deprecated, warns). `credential_helper` runs
  an argv array (never a shell) whose stdout is the key, covering 1Password,
  `pass`, `gopass`, `secret-tool`, and Vault with no platform-specific code.
- `auth status` (offline backend report) and `auth set --to keychain|file`.
- New commands: `labels list`, `users list`, `states list`, `milestone
  list|view|create|update|delete`, `issue comment list|update|delete`,
  `issue start`, `issue pr`, `issue id|url|title|describe`.
- Real cursor pagination on every list command: `--limit` page size,
  `--pages N`/`--all`, `--cursor`, `--max-items`, with a stderr page summary.
  `gql --paginate` is the generic equivalent for arbitrary documents.
- `issues list --sort FIELD[:asc|desc]` over the full `IssueSortInput` field
  set, plus `--sort-nulls first|last`.
- `--bulk`/`--bulk-file`/`--bulk-stdin` on delete commands; execution is serial.
- `--description-file`/`--body-file`/`--content-file` companions for long-form
  text, where `-` means stdin.
- Git integration: branch-name issue inference, using Linear's own
  `Issue.branchName` rather than local slugification.
- pi package manifest exposing the `linear` skill (`pi install
  git:git@github.com:alleneubank/linear-cli.git`).

### Changed

- **Toolchain: Zig 0.15.2 -> 0.16.0.** 0.15.2 cannot link on macOS 26 - its
  bundled `libSystem.tbd` carries no symbol availability for macOS 26, so every
  libc symbol resolves as undefined. 0.16's explicit `std.Io` now threads
  through every command `Context`, `Config`, and `GraphqlClient`.
- Retry backoff is cancelable, so `error.Canceled` propagates out of `send()`
  instead of being swallowed.

### Release engineering

- GitHub releases now carry per-platform tarballs
  (`linear-<version>-<os>-<arch>.tar.gz` + `.sha256`) for macOS and Linux on
  both architectures, installable via mise's `github:` backend.
- CI runs `zig fmt --check`, the unit suite, the cross-compile targets, and a
  version-manifest consistency gate (`scripts/check-versions.sh`) on every push.
