---
name: follow-up
description: Factory playbook for human feedback on one of the factory's pull requests (review comments, inline comments, @factory requests). Addresses every point on the same branch, re-reviews, pushes, and replies.
---

# Follow-up on PR feedback

The PR number is in the event (`PR_FEEDBACK pr <p>`).

1. **Collect the feedback that has no factory reply yet:**
   ```bash
   gh pr view <p> -R "$FACTORY_REPO" --json comments,reviews --jq '(.comments[], .reviews[]) | select(.body != "") | {author: .author.login, body}'
   gh api "repos/$FACTORY_REPO/pulls/<p>/comments" --jq '.[] | {id, path, line, body}'
   ```
   Ignore comments containing `<!-- factory`. Those are the factory's own.
2. Sort each point into one of:
   - **a change request:** do it
   - **a question:** answer it
   - **a disagreement with the approach:** explain the trade-off. If it changes the plan, do it.
3. If there are no change requests:
   - reply to the points in one comment with `factory-comment <p>`
   - run `factory-status $FACTORY_ISSUE pr-open --note "answered PR questions"`
   - stop
4. `factory-status $FACTORY_ISSUE building --note "addressing PR feedback"`
5. **Builder** (`factory:builder`): give it the original acceptance criteria plus **every** change request verbatim, with file and line where given.
6. Load **factory:deliver**. It re-reviews, pushes to the same branch and posts a summary on the PR.
7. **Reply on the PR** with `factory-comment <p>`: one bullet per feedback point, saying what was done (or why not), with the commit SHA.
   - Optionally, reply under an inline thread with `gh api "repos/$FACTORY_REPO/pulls/<p>/comments/<id>/replies" -f body="… <!-- factory -->"`. Always include the `<!-- factory -->` marker in such replies.
