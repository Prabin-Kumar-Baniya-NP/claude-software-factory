# Claude Software Factory

Label a GitHub issue `factory`, and headless **Claude Code (Opus)** takes it from there:
- triages it
- asks questions when the issue is unclear
- plans the work and builds it in its own git worktree
- gets the work checked by an independent reviewer
- opens a **draft PR**

Big tasks are split into child issues and shipped one PR at a time. **You review and merge.**

It is two small pieces:

| Piece | What it is | Job |
|---|---|---|
| `bin/factory` | ~350 lines of **Bash** | The **alarm clock**. Polls GitHub with `gh` (read-only). When an issue needs work, it prepares that issue's git worktree and starts `claude -p` there with a one-line event. |
| `plugin/` | A Claude Code plugin (Markdown + 3 scripts) | The **handbook**: skills (how to handle each kind of work), subagents (planner, builder, reviewer), guard hooks (hard safety rules), and helpers to update labels, comments and the board. |

Claude does all GitHub work itself (comments, labels, push, draft PR, board) with `gh`. The launcher never writes to GitHub and never reads Claude's output.

```
GitHub ──(gh, read-only, every 60s)──▶ bin/factory ──▶ worktree issue-42 ──▶ claude -p "factory event: NEW_ISSUE 42"
   ▲                                                                              │  (plugin: router → playbook
   └───────────── labels · comments · push factory/issue-42 · draft PR · board ◀──┘   → planner/builder/reviewer)
```

## Requirements

- Linux or macOS with `bash`, `git`, `jq`, `flock`, `timeout` (coreutils)
- [`gh`](https://cli.github.com) logged in (`gh auth login`). For the board you also need `gh auth refresh -s project`.
- [Claude Code](https://code.claude.com) installed and **logged in** (`claude` → `/login`). No API key needed: runs use your logged-in account.

## Quick start

```bash
git clone https://github.com/<you>/claude-software-factory && cd claude-software-factory
cp factory.env.example factory.env          # set FACTORY_REPOS=owner/repo (and anything else)

bin/factory-setup owner/repo --board --protect   # labels, Project board, branch protection
#  → put the printed FACTORY_PROJECT=... into factory.env

bin/factory run                              # leave it running (tmux, nohup, or systemd)
```

Then open an issue in that repo and add the **`factory`** label.

## Commands

| Command | What it does |
|---|---|
| `bin/factory run` | Poll forever (the normal mode) |
| `bin/factory once` | Poll once, start what's needed, exit |
| `bin/factory kick owner/repo 42 ["NEW_ISSUE 42"]` | Start a run for an issue right now |
| `bin/factory status` | Show running runs and the recent launcher log |
| `bin/factory logs owner/repo 42` | Show what Claude did in the latest run for an issue |
| `bin/factory cleanup` | Remove worktrees of closed issues |
| `bin/factory-setup owner/repo [--board] [--protect]` | One-time repo setup |

## How work flows

1. **Triage:** the router skill reads the issue and picks a **type** (bug, feature, chore, security, question) and a **size** (S, M, L).
2. **Playbook**, by size and type:

   | Size or type | Playbook | What happens |
   |---|---|---|
   | **S** | `quick-fix` | builder (bugs: failing test first) → reviewer → draft PR |
   | **M**, and all security work | `standard` | planner (plan + acceptance criteria, posted on the issue) → builder → reviewer → draft PR |
   | **L** | `epic` | planner splits the work into 3–8 child sub-issues → **you reply "approve"** → the children run one at a time, each as its own S or M issue and PR. The next child starts when you merge the previous one. |
   | question | `question` | answered in a comment, no code |
   | unclear | (router) | questions posted, `factory:needs-info`; your reply wakes it up again |

3. **Review loop:** an independent reviewer (fresh context, sees only the diff and the criteria) can request changes up to `FACTORY_MAX_REVIEW_ROUNDS` times. After that the issue becomes `factory:blocked`, with the findings posted.
4. **After the PR:** failed CI on a factory PR leads to a diagnosis and a fix (at most 2 tries). Your review comments are addressed on the same branch. When you merge, the issue is done, and an epic starts its next child.

**State lives on GitHub:** `factory:*` labels, one **Factory status** comment per issue (stage + timeline), and the **Project board** (columns by Stage). Restarting anything is safe.

| You do | When |
|---|---|
| Add the `factory` label | to hand over work |
| Reply on the issue | when it asks questions, or to `approve` an epic plan |
| Review, comment on, and **merge** the draft PR | only you merge |
| Look at `factory:blocked` issues | when it's stuck |
| Write `@factory …` in a comment | to ask it something on any issue or PR |

## Configuration

All settings are environment variables, usually in `factory.env`. See [`factory.env.example`](factory.env.example). The main ones:

| Variable | Default | Meaning |
|---|---|---|
| `FACTORY_REPOS` | (required) | `owner/repo,owner/repo2` |
| `FACTORY_LABEL` | `factory` | Label that hands an issue to the factory |
| `FACTORY_MODEL` / `FACTORY_EFFORT` | `opus` / `high` | Model and effort for every run and subagent |
| `FACTORY_MAX_PARALLEL` | `2` | Claude runs at once |
| `FACTORY_POLL_SECONDS` | `60` | Poll interval |
| `FACTORY_RUN_TIMEOUT` | `90m` | Stop a single run after this |
| `FACTORY_EPIC_NEEDS_APPROVAL` | `true` | Epics wait for your "approve" |
| `FACTORY_PROJECT` | (empty) | Board as `owner/number` |
| `FACTORY_HOME` | `~/factory` | Clones, worktrees, logs, state |

## Safety

Claude runs unattended (`--permission-mode dontAsk`). These layers keep it in bounds:

- **Guard hook** (`plugin/hooks/guard.sh`, runs before every command and file edit, subagents included). It refuses:
  - pushes to anything but the issue's own `factory/issue-N` branch, and force pushes
  - `gh pr merge` and `gh pr ready`
  - repo settings, secrets, releases and workflow runs
  - `gh api` PUT/DELETE
  - changes to git remotes
  - `sudo`
  - edits outside the worktree
  - changes to `.github/workflows/` (unless `FACTORY_ALLOW_WORKFLOWS=1`)
- **Deny rules** in `config/settings.json` repeat the most important of these.
- **Branch protection** on the default branch (`factory-setup --protect`), with admins included, because runs act as your `gh` user. Private repos on a free GitHub plan can't use it. There the guard hook is the main protection.
- **Untrusted text:** the launcher passes Claude only event names and numbers. The skills treat issue and comment text as data.
- **Only you merge.**

Runs use your machine and your accounts. For stronger isolation, run the launcher on a separate VM or under a separate user.

## Layout

```
bin/factory              launcher (bash)
bin/factory-setup        one-time repo setup (labels, board, branch protection)
config/settings.json     permissions for unattended runs
config/system-prompt.md  rules appended to every run's system prompt
plugin/                  the factory plugin (loaded with --plugin-dir)
  skills/                router, quick-fix, standard, deliver, epic, question, ci-fix, follow-up
  agents/                planner, builder, reviewer  (all Opus)
  hooks/                 guard rails
  bin/                   factory-status, factory-comment
docs/ARCHITECTURE.md     design notes
```
