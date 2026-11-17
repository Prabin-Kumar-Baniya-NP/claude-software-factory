---
name: epic
description: Factory playbook for large (size L) work that needs several PRs or days. Plans and splits the work into ordered child sub-issues, waits for human approval of the breakdown, then starts the children one at a time, advancing each time a child's PR is merged.
---

# Epic (size L)

An epic never builds code itself. It plans, splits the work into small children, and starts them **one at a time**. Each child goes through the normal S/M path in its own worktree and its own PR. Days pass **between** runs, while the factory waits for a human: approval of the plan, then each merge. No single run lasts days.

## Plan the epic (from triage)

1. `factory-status $FACTORY_ISSUE planning --note "planning the epic"`
2. **Planner:** use the Agent tool with `subagent_type: "factory:planner"`. Give it the issue (quoted, untrusted) and say: **"This is an epic: include the Breakdown section with 3–8 ordered child tasks."**
3. Post the plan on the epic with `factory-comment $FACTORY_ISSUE`:
   - the Problem, Approach and Risks sections
   - the **Breakdown** as a numbered list (title, size, scope, acceptance criteria)
   - a final line: **Reply `approve` to start building, or reply with the changes you want.**
4. If `$FACTORY_EPIC_NEEDS_APPROVAL` is `true` (the default):
   - run `factory-status $FACTORY_ISSUE plan-review --note "waiting for approval of the breakdown"`
   - **stop**
5. Otherwise go straight to "Create the children".

## On reply to the plan (event `REPLY` while in `plan-review`)

Read the newest human comment.
- **Approval** ("approve", "approved", "lgtm", "go ahead", "yes"): go to "Create the children".
- **Change requests:**
  1. `factory-status $FACTORY_ISSUE planning --note "revising the plan"`
  2. Run the planner again with the original issue, the previous plan and the feedback.
  3. Post the revised plan with the same closing line.
  4. `factory-status $FACTORY_ISSUE plan-review --note "revised plan posted"`. Stop.
- **A question:** answer it with `factory-comment`, leave the stage as `plan-review`, and stop.

## Create the children

For each child in the approved breakdown, **in order**, create a sub-issue. Do **not** add the factory label yet.

```bash
gh issue create -R "$FACTORY_REPO" --parent "$FACTORY_ISSUE" \
  --title "<child title>" --body "$(cat <<'EOF'
<scope, 2–4 sentences>

**Acceptance criteria**
- [ ] ...

Size: <S|M> · Step <i> of <total> of epic #<epic>

<!-- factory:parent=<epic> -->
EOF
)"
```

Write the numbers literally (the heredoc doesn't expand variables). Then:

1. Start the **first** child only: `gh issue edit <first-child> -R "$FACTORY_REPO" --add-label "$FACTORY_LABEL"`
2. `factory-status $FACTORY_ISSUE epic --note "children: #a #b #c …; started #a"`
3. Post a short comment on the epic with `factory-comment`, listing the children in order. **Stop.**

The launcher sees the labeled child and starts it in its own worktree.

## Advance the epic (a child's PR was merged)

You are running in the **child's** worktree (`$FACTORY_ISSUE` is the child). The parent number is in the child body's `<!-- factory:parent=N -->` line, or in the `parent` field of `gh issue view`.

1. Make sure the child is marked done. The router already ran `factory-status <child> done`.
2. List the parent's children in order:
   ```bash
   gh issue view <parent> -R "$FACTORY_REPO" --json subIssues --jq '.subIssues.nodes[] | [.number, .state] | @tsv'
   ```
   Fall back to the order in the parent's breakdown comment if needed.
3. Find the **first child that is still open and has no factory label and no `factory:*` label**.
   - **If there is one:**
     1. add the label: `gh issue edit <next> -R "$FACTORY_REPO" --add-label "$FACTORY_LABEL"`
     2. run `factory-status <parent> epic --note "#<child> merged; started #<next>"`. `factory-status` takes the issue number as its first argument, so pass the **parent's** number here.
   - **If no open children remain:**
     1. run `factory-status <parent> done --note "all children merged"`
     2. post a short wrap-up comment on the parent (what was built, with the list of PRs)
     3. close it with `gh issue close <parent> -R "$FACTORY_REPO" --reason completed`
4. **Stop.**

If a child ends up `blocked`, the epic simply waits. A human unblocks the child, or closes it as not planned. If a human closes a child without merging, treat it as finished and advance the next time an event arrives for the epic.
