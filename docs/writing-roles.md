# Writing roles

## Add a role

1. Create `roles/<name>/tasks/main.yml`.
2. Add the name to the `roles:` list in `main.yml`, and a row at the same position in README's role
   table. `scripts/check-readme-roles.sh` checks that the two orders match.
3. If it depends on another role, list that role under `dependencies:` in `meta/main.yml`.
4. Verify it with the repo's `ansible-idempotency-check` skill
   (`.claude/skills/ansible-idempotency-check/`), which runs each changed role standalone, twice.

## Install layers

Pick the first layer that applies. Each has one shape, shown by an existing role.

| What | How | Example |
|---|---|---|
| a tool Omarchy already manages with mise (agent CLIs, gh, cf, node, uv) or an npm global | `include_role: name: mise, tasks_from: tool` with `mise_tool`, and `mise_cmd` when a `~/.local/bin` stub is wanted; the stub is Omarchy's own `omarchy-mise-install` shape | `roles/claude-code` |
| something Omarchy has an installer for (`omarchy-install-*`) | run the installer, gated on a `pacman -Q` probe so it runs once; no `become`, the script calls sudo itself | `roles/ghostty` |
| an Arch repo package | `community.general.pacman` with `become: true` and `state: present` | `roles/pacman` |
| an AUR package | none today (DECISIONS Q10). If one returns: a `yay -S --needed --noconfirm` command behind a `pacman -Q` probe, no `become`; the pacman module's yay mode cannot see AUR packages (DECISIONS Q3) | |
| none of the above | the upstream installer behind a probe, as in ubuntu-provision | `roles/multica-cli` |

`mise up` in the `mise` role and `omarchy-update -y` in the `pacman` role do every upgrade. A
tool role adds its tool when missing and nothing else.

## Conventions

- **Secrets come from the environment.** Gate on `lookup('env', 'VAR') | length > 0`. Only the
  Tailscale variables are in `.env`; see [secrets.md](secrets.md).
- **Sudo is passwordless.** `bootstrap.sh` installs `/etc/sudoers.d/zz-<user>-nopasswd`, with
  `verifypw=any` so `sudo -v` passes too. `ansible.cfg` keeps plain `become_flags = -H`.
- **bash startup files.** A hook, alias or function line goes at the end of `~/.bashrc`, below
  Omarchy's interactive guard `[[ $- != *i* ]] && return`. Only the `dotenv` block goes above it.
  There is no `.zshrc`, `.zprofile` or `.zshenv`.
- **Expected failures use `failed_when: false`, not `ignore_errors: true`.** `ignore_errors` still
  prints a red `fatal:` block, so a real failure hides among routine ones. Pair `failed_when: false`
  with a `when: rc != 0` debug task that reports the outcome.
- **A read-only probe that a later task reads gets `check_mode: false`.** `command` tasks skip under
  `--check`, which leaves their register undefined and breaks the `when:` below. Leave the flag off
  the task that writes.
- **Reads of files that hold keys are `no_log: true`**, and the write goes back at 0600:
  `~/.claude/settings.json`, `~/.config/opencode/opencode.json`, `~/.codex/config.toml`.
- **A deferred failure is a fact, not a `fail`.** The first roles must not stop the rest. Set a
  host fact (`pacman_upgrade_failed`, `skills_partial_failures`, `paseo_daemon_down`), print it,
  and let `main.yml`'s `post_tasks` fail the play.
- **A `debug` task's `changed_when` is invisible in ad-hoc output.** Put `changed_when` on the task
  that measures (a `slurp`, `find` or `command`).

## Self-update tasks: diff state, don't grep output

A task that calls a tool's own installer decides `changed` from state measured before and after:
a version, a ledger file, `mise ls --json`. Matching a phrase in stdout is not equivalent: these
installers exit 0 on every path, each has no-op branches that print nothing, and GitHub's
anonymous API limit (60 calls an hour per IP, shared by every tool on the box) turns a check into
silence several times a day. A negated sentinel (`'already' not in stdout`) then reports a phantom
change on a converged host forever. The one exception is agent-reach, which has no version and
matches a positive sentinel; see `roles/agent-reach/README.md`.
