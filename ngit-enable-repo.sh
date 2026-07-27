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
# IMPORTANT — why this ordering matters:
#   `ngit init` rewrites `origin`'s URL to the `nostr://` remote and leaves the
#   GitHub/Radicle URLs only as pushurls. If we leave it that way, `git pull`
#   fetches from Nostr (which can be empty or offline) and fails with
#   "no such ref was fetched". So we ALWAYS restore `origin.fetch` to GitHub
#   (the source of truth) and keep GitHub + Radicle + Nostr as pushurls only.
#
# After this, `git pull` works from GitHub and `git push` keeps GitHub +
# Radicle + Nostr (gitworkshop) in sync natively — no hook, no per-push
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

# 3. Push to all configured remotes (GitHub, Radicle, Nostr).
git push

echo "==> Done. '$REPO_NAME' is now published to Nostr (gitworkshop)."
echo "    View at: https://gitworkshop.dev/${NOSTR_URL#nostr://}"
