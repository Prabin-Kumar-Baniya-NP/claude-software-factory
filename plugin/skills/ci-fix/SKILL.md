---
name: ci-fix
description: Factory playbook for failed CI on one of the factory's own pull requests. Diagnoses the failing checks; fixes the code only when the code is the cause (max 2 attempts per PR), otherwise explains.
---

# CI fix

The PR number is in the event (`CI_FAILED pr <p>`). Its branch is this worktree's branch.

1. **Count earlier attempts:** look for factory comments on the PR that start with "CI fix attempt".
   ```bash
   gh pr view <p> -R "$FACTORY_REPO" --json comments --jq '[.comments[].body | select(startswith("CI fix attempt"))] | length'
   ```
   If that is already **2 or more**:
   - post on the PR that automatic fixing has stopped, with the failing checks and their links
   - run `factory-status $FACTORY_ISSUE blocked --note "CI still failing after 2 attempts"`
   - stop
2. **Diagnose:**
   ```bash
   gh pr checks <p> -R "$FACTORY_REPO"
   gh run view <run-id> -R "$FACTORY_REPO" --log-failed
   ```
   Decide the cause:
   - **Code** (a test, typecheck, lint or build failure caused by the PR's changes): fix it, step 3.
   - **Flaky, infrastructure, or CI configuration:** don't change code. Comment on the PR what failed and why a code change won't help, then run `factory-status $FACTORY_ISSUE pr-open --note "CI failure not caused by code"`. Stop.
   - **No readable logs:** list the failing checks with their links, and say the cause is unknown and a human should look. Set `pr-open` and stop.
3. **Fix:**
   1. Post `CI fix attempt <k>: <one line diagnosis>` on the PR with `factory-comment <p>`.
   2. `factory-status $FACTORY_ISSUE building --note "fixing CI (attempt <k>)"`
   3. Use the **builder** (`factory:builder`) with the failing log excerpt, the diagnosis and the original acceptance criteria. Get them from the issue's plan comment, or derive them from the issue.
   4. Load **factory:deliver**. It reviews, pushes to the same branch (which updates the PR) and sets the stage back to `pr-open`.
