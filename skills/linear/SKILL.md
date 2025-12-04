---
name: linear
description: Manages Linear issues, teams, and projects via CLI. Lists issues, creates tasks, views details, links issues, and runs GraphQL queries. Activates for "my Linear issues", "create Linear task", "link issues in Linear", "Linear API query", or any Linear project management request.
---

# Linear CLI

Interacts with Linear for issue tracking and project management using the `linear` command.

## Prerequisites

- Binary: `npm install -g @0xbigboss/linear-cli`
- Auth: `linear auth set` or set `LINEAR_API_KEY` env var

## Hygiene

- **Branches**: Name as `{TICKET}-{short-name}` (e.g., `ENG-123-fix-auth`); prefer git worktrees for parallel work
- **Commits**: Use conventional commits; ticket ID in body or trailer, not subject
- **Assignment**: Assign yourself when starting work (`linear issue update ENG-123 --assignee me --yes`)
- **Sub-issues**: Set parent to associate related work (requires UUID: `linear issue update ENG-123 --parent PARENT_UUID --yes`)
- **Scope creep**: Create separate issues for discovered work; link with blocks relation (requires UUIDs: `linear issue link ISSUE_UUID --blocks OTHER_UUID --yes`)
- **Cycles/projects**: Ask user preference when creating issues

## Quick Recipes

### List my issues
```bash
linear issues list --team TEAM_KEY --human-time
```

### Create an issue
```bash
linear issue create --team TEAM_KEY --title "Fix bug" --yes
# Returns identifier (e.g., ENG-123)
```

### View issue details
```bash
linear issue view ENG-123
```

### Get issue as JSON for processing
```bash
linear issue view ENG-123 --json
```

### Get issue with full context (for agents/analysis)
```bash
linear issue view ENG-123 --fields identifier,title,state,assignee,priority,url,description,parent,sub_issues,comments --json
```

### List all teams
```bash
linear teams list
```

### Verify authentication
```bash
linear auth test
```

## Command Reference

| Command | Purpose |
|---------|---------|
| `linear issues list` | List issues with filters |
| `linear issue view ID` | View single issue |
| `linear issue create` | Create new issue |
| `linear issue update ID` | Update issue (assign, state, priority, parent*) |
| `linear issue link UUID` | Link issues (blocks, related, duplicate)* |
| `linear issue delete ID` | Archive an issue |
| `linear teams list` | List available teams |
| `linear me` | Show current user |
| `linear gql` | Run raw GraphQL |
| `linear help CMD` | Command-specific help |

*`--parent` and `issue link` require UUIDs, not identifiers. See [Finding IDs](#finding-ids).

## Common Flags

- `--team ID\|KEY` - Specify team (required for most commands)
- `--json` - Output as JSON
- `--yes` - Confirm mutations without prompt
- `--human-time` - Show relative timestamps
- `--fields LIST` - Select specific fields
- `--help` - Show command help

## Workflow: Creating and Linking Issues

**Note:** `--parent` and `issue link` require UUIDs. Get UUID with `linear issue view ID --json | jq -r '.issue.id'`

```
Progress:
- [ ] List teams to get TEAM_KEY: `linear teams list`
- [ ] Create parent issue: `linear issue create --team KEY --title "Epic" --yes`
- [ ] Create child issue: `linear issue create --team KEY --title "Task" --yes`
- [ ] Get UUIDs for parent and child: `linear issue view ID --json | jq -r '.issue.id'`
- [ ] Set parent (UUID required): `linear issue update CHILD_ID --parent PARENT_UUID --yes`
- [ ] Create another issue to link: `linear issue create --team KEY --title "Blocked" --yes`
- [ ] Get UUID for new issue: `linear issue view ID --json | jq -r '.issue.id'`
- [ ] Link blocking issue (UUIDs required): `linear issue link ISSUE_UUID --blocks OTHER_UUID --yes`
- [ ] Verify: `linear issue view ISSUE_ID --json`
```

## Common Gotchas

| Problem | Cause | Solution |
|---------|-------|----------|
| Empty results | No team specified | Add `--team TEAM_KEY` |
| 401 Unauthorized | Invalid/missing API key | Run `linear auth test` |
| Mutation does nothing | Missing confirmation | Add `--yes` flag |
| Can't find issue | Using UUID in `issue view` | Use identifier (ENG-123) for view/update/delete main arg |
| issue link fails | Using identifier | `issue link` requires UUIDs for all args |
| --parent fails | Using identifier | `--parent` flag requires UUID, not identifier |

**ID format summary:** Most commands accept identifiers (ENG-123) for the main argument. Exceptions: `issue link` and `--parent` require UUIDs.

## Advanced Operations

For operations not covered by built-in commands, use `linear gql` with GraphQL:

- **Add attachments** - See `graphql-recipes.md` → "Attach URL to Issue"
- **Upload files** - See `graphql-recipes.md` → "Upload File"
- **Add comments** - See `graphql-recipes.md` → "Add Comment"

Note: Linking issues and setting parent are available via `issue link` and `issue update --parent`, but these require UUIDs. Use `linear issue view ID --json` to get UUIDs.

## Finding IDs

**Important:** `issue link` and `issue update --parent` require UUIDs.

```bash
# Get issue UUID from identifier
linear issue view ENG-123 --json | jq -r '.issue.id'

# Current user UUID
linear me --json | jq -r '.id'

# All teams with UUIDs
linear teams list --json

# Issue full details including UUID
linear issue view ENG-123 --json
```

Or in Linear app: Cmd/Ctrl+K → "Copy model UUID"

## Reference Files

- `graphql-recipes.md` - GraphQL mutations for attachments, relations, comments, file uploads
- `troubleshooting.md` - Common errors and debugging steps

## External Links

- [Linear API Docs](https://linear.app/developers/graphql)
- [Schema Explorer](https://studio.apollographql.com/public/Linear-API/variant/current/schema/reference)
