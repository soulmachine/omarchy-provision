<!-- AI-maintained, append-only -->
# Decisions

## Q1 — interactive/omarchy-port-grilling — gate-resolution

**Question:** How does macbook-provision port to Omarchy: scope, hosts, tooling, package layers, shell, role set, secrets, upgrades, verification and workflow?
**Options considered:** 34 questions over four grilling rounds on 2026-10-11, each with a recommended answer
**Chosen:** A tool-set port plus one `always-on` role. Every Omarchy host is an always-on server, so there is no host-facts role and no gate: hermes, ponytail's Hermes half and paseo's daemon run everywhere. Ansible per host on localhost; `bootstrap.sh` installs Arch's `ansible` and a `zz-<user>-nopasswd` sudoers file with `verifypw=any`. Repo packages go through `community.general.pacman`, AUR packages through the same module with `executable: yay`, and Omarchy's own installer is used where it has one (terminal, tailscale, hermes CLI, VS Code, dev-env for bun, go, java and rust). Agent CLIs and npm globals are mise tools with Omarchy's `~/.local/bin` stubs; one `mise up` in the mise role upgrades them all. The shell stays bash: the dotenv block sits above the interactive guard in `~/.bashrc`, hooks and aliases below it; the Mac `shell` and `omarchy` roles are not ported, since Omarchy provides them. Dropped roles: host-facts, shell, omarchy, apple-container, cua, cmux, moshi, cc-switch. AUR picks: kimi-code-bin, intellij-idea-ultimate-edition, sublime-text-4. paseo comes from mise `npm:@getpaseo/cli` with a systemd user unit for the daemon. `.env` holds only the Tailscale auth key and OAuth pair; `GITHUB_TOKEN` and `TYPESAFE_API_KEY` stay with gh-token-fleet and jev-fleet. Out of scope and hand-applied: the CLIProxyAPI bar patches (`gateway/omarchy/` stays in macbook-provision), the arch-mact2 hook, Sunshine and the `*-gw` wrappers, which `cliproxy-tier-host.py` owns. Verification: `--check`, a real run, a second run with `changed=0` on mac-mini-2018-omarchy. Commits go to `main` directly; one line in `~/.agents/docs/fleet-ssh.md` follows.
**Decided-by:** human
**Justification:** Frank answered every question in the grilling session; his overrides on that session's Q1, Q2, Q15, Q20 and Q21 are what the text above reflects.
**Outcome:** applied
**Ref:** (this commit)

## Q2 — interactive/omarchy-port-upgrade — deviation

**Question:** The grilling (its Q6) chose `pacman -Syu` and `yay -Sua` as the pacman role's upgrade step, with `omarchy-update` left to the Sunday cron. `/usr/bin/omarchy-update` on the box runs `omarchy-migrate` straight after the package upgrade and documents that the two must not be separated, and its pacman call needs `--overwrite '/usr/share/omarchy/*'`. Keep the bare upgrade?
**Options considered:** bare `pacman -Syu` with the overwrite flag, then `omarchy-migrate` / `omarchy-update -y` as the role's upgrade step / no upgrade in the play, cron only
**Chosen:** `omarchy-update -y`. It upgrades the repos, AUR and mise tools, runs the migrations and hooks, and never reboots. The role diffs `pacman -Q` and `mise ls --json` around it for `changed`, records a failure for main.yml's post_tasks, and prints a notice when a reboot is due.
**Decided-by:** agent
**Justification:** `/usr/bin/omarchy-update`'s own comment on the migration ordering, read 2026-10-11. Re-implementing its sequence in the play would copy five of its scripts. Reversible by replacing one task, and the Sunday cron keeps running the same command, so nothing is lost either way.
**Outcome:** assumed
**Ref:** (this commit)
