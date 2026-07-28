#!/bin/bash
# ngit-enable-repo
#
# Enable a Git repository for Nostr (ngit) so that `git push` also publishes
# the repo to Nostr/gitworkshop. Run from INSIDE the target repository.
#
# What it does:
#   1. `ngit init -d --name <repo>`  — announce the repo to Nostr (sets the
#      `nostr://` origin URL and the local NIP-34 repo event pointing at HEAD).
#   2. Restore GitHub as the FETCH source of truth on `origin`, and rebuild
#      `origin` pushurls so a normal `git push` reaches GitHub, Radicle (if
#      present), AND Nostr — in that order, with no duplicates.
#   3. `git push` to sync everything.
#
# IMPORTANT — why this matters:
#   `ngit init` rewrites `origin`'s URL to the `nostr://` remote and leaves the
#   GitHub/Radicle URLs only as pushurls. If we leave it that way, `git pull`
#   fetches from Nostr (which can be empty or offline) and fails with
#   "no such ref was fetched". Worse, if a PR merges on GitHub, `git pull`
#   (fetching Nostr) reports "Already up to date" and the divergence is invisible
#   until `git push` rejects with non-fast-forward.
#
# DURABLE FIX — we split the two directions explicitly so ngit's remote rewriting
# can't reintroduce the trap:
#   * `github` remote = FETCH-ONLY source of truth (PRs merge here).
#   * `origin` = PUSH target only (GitHub + Radicle + Nostr pushurls).
#   * `branch.<main>.remote = github`  -> `git pull` consults GitHub.
#   * `remote.pushDefault = origin`    -> `git push` hits the triple mirror.
# Two independent knobs; ngit's `origin` rewrite no longer affects pulls.
#
# After this, `git pull` works from GitHub (sees merged PRs) and `git push` keeps
# GitHub + Radicle + Nostr (gitworkshop) in sync natively — no hook, no per-push
# `ngit init`.
#
# Requirements:
#   - ngit installed (https://gitworkshop.dev/ngit) with `git-remote-nostr`
#     on PATH, and an nsec configured (git config --global nostr.nsec, or a
#     bunker reference).
#   - A GitHub `origin` remote already configured (this is the source of truth).

set -euo pipefail

# Must be run from inside a git repo.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: run this from inside a Git repository." >&2
  exit 1
fi

REPO_NAME="$(basename "$(git rev-parse --show-toplevel)")"

echo "==> Enabling Nostr for '$REPO_NAME'"

# Capture the pre-existing GitHub URL BEFORE ngit init rewrites the remote.
# This is used as both the fetch URL and the first pushurl (source of truth).
GITHUB_URL="$(git remote get-url origin 2>/dev/null | grep -E '^git@github.com|^https://github.com' | head -1 || true)"
if [[ -z "$GITHUB_URL" ]]; then
  echo "ERROR: origin must be a GitHub remote (git@github.com or https://github.com) before running this script." >&2
  exit 1
fi

# Capture any pre-existing Radicle pushurl so we can preserve it.
RAD_PUSHURL="$(git remote get-url --push origin 2>/dev/null | grep -E '^rad://' | head -1 || true)"

# 1. Announce to Nostr (sets nostr:// origin URL + NIP-34 event at HEAD).
ngit init -d --name "$REPO_NAME"

# Capture the nostr:// URL ngit init just set (it is `origin` right now).
NOSTR_URL="$(git remote get-url origin)"
if [[ "$NOSTR_URL" != nostr://* ]]; then
  echo "ERROR: expected a nostr:// origin URL after ngit init, got: $NOSTR_URL" >&2
  exit 1
fi

# 2. Restore GitHub as the FETCH source of truth (this is the fix that keeps
#    `git pull` working). Then rebuild pushurls cleanly with no duplicates.
git remote set-url origin "$GITHUB_URL"
git config --unset-all remote.origin.pushurl 2>/dev/null || true
git remote set-url --add --push origin "$GITHUB_URL"
if [[ -n "$RAD_PUSHURL" ]]; then
  if ! git remote get-url --push origin 2>/dev/null | grep -qxF "$RAD_PUSHURL"; then
    git remote set-url --add --push origin "$RAD_PUSHURL"
    echo "==> Preserved Radicle pushurl on origin"
  fi
fi
if ! git remote get-url --push origin 2>/dev/null | grep -qxF "$NOSTR_URL"; then
  git remote set-url --add --push origin "$NOSTR_URL"
  echo "==> Added Nostr as a pushurl on origin"
else
  echo "==> Nostr pushurl already present; skipping"
fi

# 4. Split pull/push directions so ngit's `origin` rewrite can't reintroduce
#    the blind-`git-pull` trap. `github` = fetch-only source of truth (PRs land
#    here); `origin` = PUSH target (triple mirror). `remote.pushDefault=origin`
#    keeps `git push` off `github`; `branch.<main>.remote=github` points pulls
#    at GitHub. Scoped fetch avoids registering every upstream branch.
BR="$(git rev-parse --abbrev-ref HEAD)"
if ! git remote get-url github >/dev/null 2>&1; then
  git remote add github "$GITHUB_URL"
  echo "==> Added GitHub as a FETCH-ONLY remote"
fi
git config branch."$BR".remote github
git config branch."$BR".merge "refs/heads/$BR"
git config remote.pushDefault origin
# Per-repo push.default=current so `git push` (no arg) always hits origin (the
# triple mirror), regardless of any inherited push.default=upstream from the
# user's global config. Without this, `branch.<main>.remote=github` + upstream
# mode makes `git push` refuse origin ("not the upstream of your branch").
git config push.default current
git config remote.github.fetch "+refs/heads/$BR:refs/remotes/github/$BR"
echo "==> git pull -> github (PRs), git push -> origin (GitHub+Radicle+Nostr)"

# 5. Push to all configured remotes (GitHub, Radicle, Nostr).
git push

echo "==> Done. '$REPO_NAME' is now published to Nostr (gitworkshop)."
echo "    View at: https://gitworkshop.dev/${NOSTR_URL#nostr://}"
