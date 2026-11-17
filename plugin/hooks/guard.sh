#!/usr/bin/env bash
# Guard rails for unattended factory runs (PreToolUse hook).
# Exit 2 blocks the tool call; the message on stderr is shown to Claude.
# These rules hold whatever the model decides. GitHub branch protection is the backstop behind them.

input="$(cat)"
tool="$(jq -r '.tool_name // ""' <<<"$input")"
cwd="$(jq -r '.cwd // ""' <<<"$input")"
prefix="${FACTORY_BRANCH_PREFIX:-factory/}"
branch="${FACTORY_BRANCH:-}"
allow_workflows="${FACTORY_ALLOW_WORKFLOWS:-0}"

block() { printf 'factory guard: %s\n' "$*" >&2; exit 2; }

# ---------- file tools ----------
if [[ "$tool" =~ ^(Edit|Write|MultiEdit|NotebookEdit)$ ]]; then
  path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")"
  if [ "$allow_workflows" != 1 ] && [[ "$path" == *"/.github/workflows/"* || "$path" == ".github/workflows/"* ]]; then
    block "changing .github/workflows is not allowed in factory runs"
  fi
  if [ -n "${FACTORY_WORKTREE:-}" ] && [[ "$path" == /* ]] \
     && [[ "$path" != "$FACTORY_WORKTREE"/* ]] && [[ "$path" != /tmp/* ]]; then
    block "edits must stay inside this issue's worktree ($FACTORY_WORKTREE), not $path"
  fi
  exit 0
fi

[ "$tool" = Bash ] || exit 0
cmd="$(jq -r '.tool_input.command // ""' <<<"$input")"
flat="$(tr '\n' ' ' <<<"$cmd")"
W='(^|[^[:alnum:]_./-])'   # start of a command word

# ---------- whole-command rules ----------
grep -Eq "${W}gh[[:space:]]+pr[[:space:]]+(merge|ready)([[:space:]]|\$)" <<<"$flat" \
  && block "merging a PR or marking it ready is a human decision"
grep -Eq "${W}gh[[:space:]]+repo[[:space:]]+(delete|edit|rename|archive|transfer|set-default)([[:space:]]|\$)" <<<"$flat" \
  && block "changing repository settings is not allowed"
grep -Eq "${W}gh[[:space:]]+(secret|variable|auth|ssh-key|gpg-key|ruleset)([[:space:]]|\$)" <<<"$flat" \
  && block "secrets, auth, keys and rulesets are off limits"
grep -Eq "${W}gh[[:space:]]+(release[[:space:]]+(create|delete|edit|upload)|workflow[[:space:]]+(run|enable|disable))([[:space:]]|\$)" <<<"$flat" \
  && block "releases and workflow runs are human decisions"
if grep -Eq "${W}gh[[:space:]]+api([[:space:]]|\$)" <<<"$flat"; then
  grep -Eiq '(-X|--method)[[:space:]=]*(DELETE|PUT)([[:space:]]|$)' <<<"$flat" \
    && block "gh api DELETE/PUT calls are not allowed"
  grep -Eq '/(merge|protection|rulesets|hooks|keys|secrets|variables|collaborators|transfer)([/?[:space:]]|$)' <<<"$flat" \
    && block "that GitHub API endpoint is off limits"
fi
grep -Eq "${W}git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?remote[[:space:]]+(add|set-url|rename|remove)([[:space:]]|\$)" <<<"$flat" \
  && block "changing git remotes is not allowed"
grep -Eq 'insteadOf' <<<"$flat" && block "git URL rewrites are not allowed"
grep -Eq "${W}(sudo|su|doas)[[:space:]]" <<<"$flat" && block "sudo is not allowed"
grep -Eq "${W}im[[:space:]]+(ask|show|wait)([[:space:]]|\$)" <<<"$flat" \
  && block "factory runs talk to people only on GitHub (factory-comment), never through Interrupt Me or chat"
grep -Eq 'rm[[:space:]]+-[[:alpha:]]*[rR][[:alpha:]]*[[:space:]]+(/|~|\$HOME)/?([[:space:]]|$)' <<<"$flat" \
  && block "refusing to delete / or the home directory"
if [ "$allow_workflows" != 1 ] && grep -Eq '\.github/workflows' <<<"$flat" \
   && grep -Eq '(>|[[:space:]]tee[[:space:]]|[[:space:]]cp[[:space:]]|[[:space:]]mv[[:space:]]|sed[[:space:]]+-i|[[:space:]]install[[:space:]])' <<<"$flat"; then
  block "changing .github/workflows is not allowed in factory runs"
fi

# ---------- git push: only this run's own branch, to origin, no force ----------
segments="$(sed -E 's/(&&|\|\||;|\||&)/\n/g' <<<"$cmd")"
while IFS= read -r seg; do
  read -ra w <<<"$seg"
  i=0
  while [[ "${w[$i]:-}" == *=* && "${w[$i]}" != -* ]]; do i=$((i + 1)); done   # VAR=value prefixes
  [[ "${w[$i]:-}" =~ ^(command|exec|nohup|timeout)$ ]] && i=$((i + 1))
  [[ "${w[$i]:-}" == git || "${w[$i]:-}" == */git ]] || continue
  i=$((i + 1))
  while [[ "${w[$i]:-}" == -* ]]; do
    case "${w[$i]}" in -C|-c) i=$((i + 2)) ;; *) i=$((i + 1)) ;; esac
  done
  [ "${w[$i]:-}" = push ] || continue
  i=$((i + 1)); remote=""; refs=()
  for ((; i < ${#w[@]}; i++)); do
    a="${w[$i]}"
    case "$a" in
      -u|--set-upstream|-q|--quiet|-v|--verbose|--progress|--no-verify) ;;
      -*) block "git push option '$a' is not allowed (use: git push -u origin ${branch:-${prefix}issue-N})" ;;
      *) if [ -z "$remote" ]; then remote="$a"; else refs+=("$a"); fi ;;
    esac
  done
  [ "$remote" = origin ] || block "push only to 'origin' (got '${remote:-nothing}')"
  [ ${#refs[@]} -gt 0 ] || block "name the branch explicitly: git push -u origin ${branch:-${prefix}issue-N}"
  for r in "${refs[@]}"; do
    [[ "$r" == +* ]] && block "force-push refspec '$r' is not allowed"
    dst="${r#*:}"; dst="${dst#refs/heads/}"
    if [ -n "$branch" ]; then
      [ "$dst" = "$branch" ] || block "this run may only push its own branch '$branch' (got '$dst')"
    else
      [[ "$dst" == "$prefix"* ]] || block "only ${prefix}* branches may be pushed (got '$dst')"
    fi
  done
  if [ "$allow_workflows" != 1 ] && [ -n "$cwd" ]; then
    base="origin/${FACTORY_DEFAULT_BRANCH:-main}"
    if git -C "$cwd" diff --name-only "$base...HEAD" 2>/dev/null | grep -q '^\.github/workflows/'; then
      block "this branch changes .github/workflows, which factory runs may not push (FACTORY_ALLOW_WORKFLOWS=0)"
    fi
  fi
done <<<"$segments"

exit 0
