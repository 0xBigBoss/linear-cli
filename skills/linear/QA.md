# Linear CLI Skill QA

Prompt for Claude Code to verify skill documentation accuracy.

## Usage

From the repo root, start a Claude Code session with the QA prompt pre-filled:

```bash
claude "$(cat skills/linear/QA.md | sed -n '/^~~~$/,/^~~~$/p' | sed '1d;$d')"
```

Or manually: start a new session and paste the prompt below.

---

## Prompt

~~~
I need to QA the linear-cli skill to verify the documentation is accurate.

## Step 1: INVOKE THE SKILL FIRST

**STOP. DO NOT RUN ANY COMMANDS YET.**

Your VERY FIRST action must be to invoke the skill using the Skill tool:

```
Skill tool: skill: "linear-cli:linear"
```

This loads the documentation you will be testing. Do NOT read skill files directly from the repo - this simulates how agents actually use the skill in practice.

**Invoke the skill NOW before proceeding to Step 2.**

## Step 2: Pre-flight Checks

After the skill documentation has loaded, run these checks and confirm with me:

1. Run `linear auth test` - is a test API key configured?
2. Run `linear teams list` - which team should I use for testing?
3. Do I have permission to create/delete test issues in this workspace?

Stop and wait for my answers before proceeding to Step 3.

## Step 3: Test Scope

After I confirm:
1. Review the expanded skill documentation from Step 1
2. Verify every documented command produces the expected output

Note: The skill includes references to additional files (graphql-recipes.md, troubleshooting.md). Test those recipes as well.

## Test Plan

### Phase 1: Quick Recipes (SKILL.md)
Test each recipe exactly as documented:
- [ ] `linear issues list --team TEAM_KEY --human-time`
- [ ] `linear issue create --team TEAM_KEY --title "QA Test" --yes`
- [ ] `linear issue view IDENTIFIER`
- [ ] `linear issue view IDENTIFIER --json`
- [ ] `linear teams list`
- [ ] `linear auth test`

### Phase 2: Command Reference Table
Verify each command in the table works:
- [ ] `linear issues list`
- [ ] `linear issue view ID`
- [ ] `linear issue create` (with required flags)
- [ ] `linear issue update ID` (with at least one field)
- [ ] `linear issue link ID` (with relation flag)
- [ ] `linear issue delete ID` (dry-run first)
- [ ] `linear teams list`
- [ ] `linear me`
- [ ] `linear gql`
- [ ] `linear help CMD`

### Phase 3: Common Flags
- [ ] `--json` produces valid JSON
- [ ] `--yes` allows mutations without prompt
- [ ] `--human-time` shows relative times
- [ ] `--fields LIST` filters output
- [ ] `--help` shows usage

### Phase 4: Common Gotchas Table
Verify each error scenario:
- [ ] No team specified → empty results
- [ ] Missing --yes → mutation exits without action
- [ ] Invalid issue ID → appropriate error message

### Phase 5: Issue Update Command
Test issue update functionality:
- [ ] `linear issue update ID --assignee me --yes` - assigns to current user
- [ ] `linear issue update ID --priority 1 --yes` - sets priority
- [ ] `linear issue update ID --state STATE_ID --yes` - changes state
- [ ] `linear issue update ID --title "New Title" --yes` - updates title
- [ ] `linear issue update ID --parent PARENT_ID --yes` - sets parent (sub-issue)
- [ ] `linear issue update ID --yes` (no fields) → error "at least one field"
- [ ] `linear issue update ID --priority 1` (no --yes) → error "confirmation required"

### Phase 6: Issue Link Command
Test issue linking functionality:
- [ ] `linear issue link ID --blocks OTHER_ID --yes` - creates blocks relation
- [ ] `linear issue link ID --related OTHER_ID --yes` - creates related relation
- [ ] `linear issue link ID --duplicate OTHER_ID --yes` - marks as duplicate
- [ ] `linear issue link ID --yes` (no relation) → error "exactly one of --blocks"
- [ ] `linear issue link ID --blocks A --related B --yes` → error "only one of --blocks"

### Phase 7: Hygiene Section
Verify hygiene examples from SKILL.md work:
- [ ] Assignment workflow: `linear issue update ENG-123 --assignee me --yes`
- [ ] Sub-issue workflow: `linear issue update ENG-123 --parent ENG-100 --yes`
- [ ] Blocking workflow: `linear issue link ENG-123 --blocks ENG-456 --yes`

### Phase 8: GraphQL Recipes (graphql-recipes.md)
Test at least these recipes:
- [ ] Viewer query: `echo 'query { viewer { id name } }' | linear gql --json`
- [ ] Teams query: `echo 'query { teams { nodes { id key } } }' | linear gql --json`
- [ ] Add comment (commentCreate) - on a test issue
- [ ] Attach URL (attachmentCreate) - on a test issue

Note: Link issues and set parent are now covered by direct CLI commands in Phases 5-6.

### Phase 9: Troubleshooting Scenarios
Verify error handling matches documentation:
- [ ] 401 error format (if safe to test)
- [ ] "Issue not found" error message
- [ ] Missing required fields error

### Phase 10: External Links
Verify links are valid:
- [ ] Linear API Docs link
- [ ] Apollo Studio link

## Reporting

For each test:
1. Run the exact command from the docs
2. Compare output to documented expectation
3. Mark PASS or FAIL

Provide final summary:
- Total: X/Y passed
- Failed tests with actual vs expected
- Suggested documentation fixes

Fix any documentation errors directly in the skill files.

## Cleanup

Delete any test issues created during QA.
~~~
