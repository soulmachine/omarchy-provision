# Secrets, `.env` and the tokens in `~/.bashrc`

## `.env`

`.env` and `.envrc` are optional, gitignored and per-machine. `.env.example` lists every variable.
Today that is `TAILSCALE_AUTH_KEY` and the `TAILSCALE_OAUTH_CLIENT_ID` + `_SECRET` pair, read by
the `tailscale` role. Values legitimately differ across hosts: an auth key is tailnet-scoped.

**`GITHUB_TOKEN` and `TYPESAFE_API_KEY` are not in `.env` on Frank's hosts.** `gh-token-fleet` and
`jev-fleet` (both on mac-mini-m6) own them and export them from their own block in `~/.bashrc`,
above the interactive guard. A copy in `.env` would give each variable two writers, which is what
broke `GITHUB_TOKEN` on the Macs in October 2026. The `github`, `typesafe` and `mise` roles read
them with `lookup('env', ...)`, so they work from either place; a host without those fleet tools
may set `TYPESAFE_API_KEY` in `.env` instead. See `~/.agents/docs/github-auth.md`.

## The `dotenv` role

direnv loads `.env` only in an interactive shell: `.envrc` runs `dotenv_if_exists .env`, and the
hook sits at the end of `~/.bashrc`. Every other shell sees none of it: `ssh host 'cmd'`, git
hooks, cron, and the `bash -lc "… ansible-playbook …"` form in AGENTS.md, which is a login shell
but not an interactive one. Roles that gate on `lookup('env', VAR) | length > 0` then skip
silently. So the role exports `.env` into `~/.bashrc` inside a managed block placed **above** the
guard line `[[ $- != *i* ]] && return`, where Omarchy puts exports that every shell must see.

Three things are load-bearing, carried over from the Mac role:

- **It reads the `.env` file, never `lookup('env', ...)`.** The lookup reads the ambient
  environment, which is exactly what is missing. On a fresh host it would write an empty block.
- **An empty parse fails the play.** `blockinfile` would write a block with no exports. A `.env`
  that yields no assignment is a parse bug, so an `assert` stops it. A missing `.env` is
  legitimate and is reported, not failed.
- **`no_log: true` is affordable only because of `validate: bash -n %s`.** The block is the
  credentials, so without `no_log` a `--diff` prints them, but `no_log` also hides a failure. The
  validation checks the candidate before anything is written, and a broken `~/.bashrc` breaks every
  shell on the host.

The markers are `# --- omarchy-provision .env (managed) ---` and `# --- end omarchy-provision .env ---`.
The hand-written blocks beside it (`jev-browser-use-mcp (managed)`, `m6 credentials`) are not
touched.

## GitHub's rate limit

The anonymous GitHub API allows 60 calls an hour per IP, shared by every tool on the box, and
mise's `github:` backend, `mise up` and the agent-sync release lookup all spend it. An
authenticated call gets 5000. mise reads `GITHUB_API_TOKEN`, not `GITHUB_TOKEN`, so the `mise`
role passes the fleet PAT under that name. Where a role shells out to `gh auth token` as a
fallback, it blanks `GH_TOKEN` and `GITHUB_TOKEN` for that call, or gh echoes back the very value
the fallback exists to replace.
