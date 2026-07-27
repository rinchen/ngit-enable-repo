# ngit-enable-repo

Script to enable a Git repository for Nostr (ngit) so that `git push` also publishes the repo to Nostr / gitworkshop. This is the Nostr counterpart to [`rad-enable-repo`](https://github.com/rinchen/rad-enable-repo).

## Usage

```bash
./ngit-enable-repo.sh
```

Run from **inside** the target Git repository. It will:

1. `ngit init -d --name <repo>` — announce the repo to Nostr (sets the `nostr://` origin URL and the NIP-34 repo event pointing at HEAD).
2. Add the `nostr://` URL as a pushurl on `origin` so a normal `git push` pushes to GitHub, Radicle (if present), **and** Nostr.
3. `git push` to sync everything.

After running it, a plain `git push` keeps GitHub + Radicle + Nostr (gitworkshop) in sync natively — no hook, no per-push `ngit init`.

## Requirements

- [ngit](https://gitworkshop.dev/ngit) installed, with `git-remote-nostr` on PATH
- An nsec configured (`git config --global nostr.nsec`, or a bunker reference)
- An existing Git repository with a GitHub `origin` remote

## How it works (vs. the wrong approach)

`ngit sync` only pushes git refs and does **not** update the NIP-34 announcement gitworkshop reads. Likewise, `ngit send` opens a PR. The correct, native path is:

- `ngit init` announces the repo (run once, or re-run to re-point HEAD).
- Adding `nostr://` as a **pushurl** means `git push` drives the `git-remote-nostr` helper, which updates the announcement on every push.
