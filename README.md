# ngit-enable-repo

Enable a Git repo for Nostr (ngit) so `git push` also publishes to Nostr/gitworkshop.

Run from inside the target repo (requires a GitHub `origin` remote).

## What the script does now

1. `ngit init -d --name <repo>` — announce the repo to Nostr (sets the `nostr://` origin URL + NIP-34 event at HEAD).
2. Restore GitHub as the **fetch** source of truth on `origin`, and rebuild `origin` pushurls so `git push` reaches **GitHub, Radicle (if present), and Nostr** — no duplicates.
3. Split pull/push directions so `ngit init`'s remote rewrite can't reintroduce the blind-pull trap:
   - `github` remote = **fetch-only** (PRs merge here).
   - `origin` = **push target** (the triple-mirror pushurls).
   - `branch.<main>.remote = github` → `git pull` reads GitHub.
   - `remote.pushDefault = origin` → `git push` hits the mirror.
   - `push.default = current` → no-arg `git push` hits `origin` even if your global `push.default` is `upstream`.
4. `git push` to sync everything.

## Resulting day-to-day workflow

- Open a PR: `git push -u github <branch>` (GitHub only — never leaks to the mirror).
- After merge: `git pull` (from GitHub) → `git push` (to GitHub + Radicle + Nostr).
- Clean up the branch when done.

## Why

`ngit init` repoints `origin` at the Nostr network. Left as-is, `git pull` fetches from Nostr (often empty/offline) and a GitHub-merged PR is invisible until `git push` rejects with non-fast-forward. Splitting pull (GitHub) from push (mirror) removes that trap.

## Requirements

- `ngit` installed with `git-remote-nostr` on PATH; nsec configured (`git config --global nostr.nsec`, or a bunker reference).
- GitHub `origin` remote present before running.
