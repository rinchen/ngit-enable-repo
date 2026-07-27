#!/bin/bash
# ngit-enable-repo
#
# Enable a Git repository for Nostr (ngit) so that `git push` also publishes
# the repo to Nostr/gitworkshop. Run from INSIDE the target repository.
#
# What it does:
#   1. `ngit init -d --name <repo>`  — announce the repo to Nostr (sets the
#      `nostr://` origin URL and the local NIP-34 repo event pointing at HEAD).
#   2. Add the `nostr://` URL as a pushurl on `origin` so a normal
#      `git push` pushes to GitHub, Radicle (if present), AND Nostr.
#   3. `git push` to sync everything.
#
# After this, `git push` keeps GitHub + Radicle + Nostr (gitworkshop) in sync
# natively — no hook, no `ngit init` per push.
#
# Requirements:
#   - ngit installed (https://gitworkshop.dev/ngit) with `git-remote-nostr`
#     on PATH, and an nsec configured (git config --global nostr.nsec, or a
#     bunker reference).
#   - An existing Git repo with an `origin` remote (GitHub).

set -euo pipefail

# Must be run from inside a git repo.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: run this from inside a Git repository." >&2
  exit 1
fi

REPO_NAME="$(basename "$(git rev-parse --show-toplevel)")"

echo "==> Enabling Nostr for '$REPO_NAME'"

# Capture the pre-existing GitHub pushurl (if any) BEFORE ngit init rewrites
# the remote, so we can preserve it afterwards.
GITHUB_PUSHURL="$(git remote get-url --push origin 2>/dev/null | grep -E '^git@github.com|^https://github.com' | head -1 || true)"

# 1. Announce to Nostr (sets nostr:// origin URL + NIP-34 event at HEAD).
ngit init -d --name "$REPO_NAME"

# 2. Add the nostr:// URL as a pushurl so `git push` reaches Nostr too.
NOSTR_URL="$(git remote get-url origin)"
if [[ "$NOSTR_URL" != nostr://* ]]; then
  echo "ERROR: expected a nostr:// origin URL after ngit init, got: $NOSTR_URL" >&2
  exit 1
fi

# Re-add the GitHub pushurl if ngit init dropped it.
if [[ -n "$GITHUB_PUSHURL" ]]; then
  if ! git remote get-url --push origin 2>/dev/null | grep -qxF "$GITHUB_PUSHURL"; then
    git remote set-url --add --push origin "$GITHUB_PUSHURL"
    echo "==> Restored GitHub pushurl on origin"
  fi
fi

# Add the Nostr pushurl (idempotent).
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
