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
- **Sub-issues**: Set parent to associate related work (`linear issue update ENG-123 --parent ENG-100 --yes`)
- **Scope creep**: Create separate issues for discovered work; link with blocks relation (`linear issue link ENG-123 --blocks ENG-456 --yes`)
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
| `linear issue update ID` | Update issue (assign, parent, state, priority) |
| `linear issue link ID` | Link issues (blocks, related, duplicate) |
| `linear issue delete ID` | Archive an issue |
| `linear teams list` | List available teams |
| `linear me` | Show current user |
| `linear gql` | Run raw GraphQL |
| `linear help CMD` | Command-specific help |

## Common Flags

- `--team ID\|KEY` - Specify team (required for most commands)
- `--json` - Output as JSON
- `--yes` - Confirm mutations without prompt
- `--human-time` - Show relative timestamps
- `--fields LIST` - Select specific fields
- `--help` - Show command help

## Workflow: Creating and Linking Issues

```
Progress:
- [ ] List teams to get TEAM_KEY: `linear teams list`
- [ ] Create parent issue: `linear issue create --team KEY --title "Epic" --yes`
- [ ] Create child issue: `linear issue create --team KEY --title "Task" --yes`
- [ ] Link issues (see graphql-recipes.md for issueRelationCreate)
- [ ] Verify: `linear issue view ISSUE_ID --json`
```

## Common Gotchas

| Problem | Cause | Solution |
|---------|-------|----------|
| Empty results | No team specified | Add `--team TEAM_KEY` |
| 401 Unauthorized | Invalid/missing API key | Run `linear auth test` |
| Mutation does nothing | Missing confirmation | Add `--yes` flag |
| Can't find issue | Using wrong ID format | Use identifier (ENG-123) not UUID |

## Advanced Operations

For operations not covered by built-in commands, use `linear gql` with GraphQL:

- **Link issues** - See `graphql-recipes.md` → "Link Two Issues"
- **Add attachments** - See `graphql-recipes.md` → "Attach URL to Issue"
- **Upload files** - See `graphql-recipes.md` → "Upload File"
- **Add comments** - See `graphql-recipes.md` → "Add Comment"
- **Set parent/child** - See `graphql-recipes.md` → "Set Issue Parent"

## Finding IDs

```bash
# Current user
linear me --json

# All teams
linear teams list --json

# Issue by identifier
linear issue view ENG-123 --json --fields id
```

Or in Linear app: Cmd/Ctrl+K → "Copy model UUID"

## Reference Files

- `graphql-recipes.md` - GraphQL mutations for attachments, relations, comments, file uploads
- `troubleshooting.md` - Common errors and debugging steps

## External Links

- [Linear API Docs](https://linear.app/developers/graphql)
- [Schema Explorer](https://studio.apollographql.com/public/Linear-API/variant/current/schema/reference)
