---
name: question
description: Factory playbook for questions. Answers from the repository's code and docs in one issue comment, citing files, without changing any code.
---

# Question

1. Research the answer in the repository in the current directory: read code, docs and tests, and run read-only commands. Use the web only for facts about outside libraries, and cite them.
2. Post the answer with `factory-comment $FACTORY_ISSUE`:
   - a direct answer first, then the supporting details
   - cite files as `path/to/file.ext:line`
   - say plainly what you could not determine
   - if the question implies a change is needed, suggest opening an issue with the factory label
3. `factory-status $FACTORY_ISSUE done --type question --note "answered"`. Leave the issue open, so the asker can close it or follow up with `@factory`.
4. No branch, commits or PR. **Stop.**
