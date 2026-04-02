Push all changes to the remote.

## Steps

0. Update README.md and CLAUDE.md, and depoly script (if exist)
1. Detect the current branch name with `git branch --show-current`.
2. Modify .gitignore if neccessary.
3. If the user provided arguments ($ARGUMENTS), use that as the commit message. Otherwise, run `git diff --cached --stat` and `git diff --stat` to inspect changes and generate a concise commit message summarizing what changed.
4. Execute in a single chained Bash command (so the user only approves once):

```
git add . && git commit -m "<message>" && git push origin <branch>
```

If there are no changes to commit, say so and stop.
