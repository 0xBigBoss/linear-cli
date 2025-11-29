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

### Phase 5: GraphQL Recipes (graphql-recipes.md)
Test at least these recipes:
- [ ] Viewer query: `echo 'query { viewer { id name } }' | linear gql --json`
- [ ] Teams query: `echo 'query { teams { nodes { id key } } }' | linear gql --json`
- [ ] Link issues (issueRelationCreate) - if I have two test issues
- [ ] Add comment (commentCreate) - on a test issue
- [ ] Attach URL (attachmentCreate) - on a test issue

### Phase 6: Troubleshooting Scenarios
Verify error handling matches documentation:
- [ ] 401 error format (if safe to test)
- [ ] "Issue not found" error message
- [ ] Missing required fields error

### Phase 7: External Links
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
