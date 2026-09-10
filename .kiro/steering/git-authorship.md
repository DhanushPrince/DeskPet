---
inclusion: always
---

# Git authorship (strict)

Commits and pushes for this repo must appear as **DhanushPrince only**.

- Author and committer must be **DhanushPrince** `<r.dhanush307@gmail.com>`
  (the repo-local `user.name` / `user.email`).
- Never add a `Co-authored-by:` trailer for any AI/agent tool, and never set the
  author/committer to an agent identity.
- Leave git config unchanged.

Only create commits when the user explicitly asks. After any in-agent commit,
verify the message before pushing:

```bash
git log -1 --format='%B'
```

If an agent trailer slipped in, strip it **before** pushing (do not push the
trailed commit) — prefer a `commit-tree` rewrite so it cannot be re-injected:

```bash
TREE=$(git rev-parse HEAD^{tree})
PARENT=$(git rev-parse HEAD^)
NEW=$(printf '%s\n' "$(git log -1 --format=%s)" | \
  GIT_AUTHOR_NAME='DhanushPrince' GIT_AUTHOR_EMAIL='r.dhanush307@gmail.com' \
  GIT_COMMITTER_NAME='DhanushPrince' GIT_COMMITTER_EMAIL='r.dhanush307@gmail.com' \
  git commit-tree "$TREE" -p "$PARENT")
git reset --hard "$NEW"
```

Do not push directly to `main` unless explicitly asked.
