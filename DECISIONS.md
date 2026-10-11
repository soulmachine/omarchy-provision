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

## Q3 — interactive/omarchy-port-aur — deviation

**Question:** Q1 chose `community.general.pacman` with `executable: yay` for AUR packages. On the box the module fails for `kimi-code-bin` with "target not found": it lists its targets with `--sync --print-format`, which yay answers only for repo packages. How do AUR installs run?
**Options considered:** the pacman module with yay / a `yay -S --needed --noconfirm` command behind a `pacman -Q` probe, shared as `roles/pacman/tasks/aur.yml` / the `kewlfft.aur` Galaxy collection
**Chosen:** `roles/pacman/tasks/aur.yml`, included with `aur_pkg`. No become: yay refuses root and calls sudo itself. Upgrades stay with `omarchy-update`'s `yay -Sua`.
**Decided-by:** agent
**Justification:** Measured on mac-mini-2018-omarchy on 2026-10-11 with `--check`. The task file is twelve lines and no new collection; the three AUR roles (kimi-code, intellij-idea, pacman's Sublime Text) include it.
**Outcome:** applied
**Ref:** 74170fc

## Q4 — interactive/omarchy-port-tailscale — deviation

**Question:** Q1 chose `omarchy-install-service-tailscale` as the tailscale role's installer. Its `sudo tailscale up --accept-routes` has no auth key, so on a host that is not enrolled it prints a login URL and waits for a browser, which an unattended play cannot answer. How does a fresh host get Tailscale?
**Options considered:** call the installer and accept the hang / install the package and tailscaled with pacman and systemd, enrol with `TAILSCALE_AUTH_KEY`, then run the installer once for its extras (operator, Taildrop, bar plugin, web app) gated on the node being Running / replicate the four extras as tasks and never call the installer
**Chosen:** The second. Without an auth key the package is installed, the enrolment is reported as a hand step and the extras follow on the next play. On a host that has the package, which is every host today, the installer is never called.
**Decided-by:** agent
**Justification:** `/usr/bin/omarchy-install-service-tailscale` read on mac-mini-2018-omarchy, 2026-10-11. The installer's `tailscale up` on an enrolled node exits 1 for not restating `--operator`, and the script does not stop on it, so the once-after-enrolment call is safe. A hard failure on a missing key was rejected: it would stop the four roles after tailscale for an optional credential, against main.yml's deferred-failure rule.
**Outcome:** assumed
**Ref:** (this commit)

## Q5 — interactive/omarchy-port-paseo-restart — refinement

**Question:** The Mac paseo role restarts the daemon when the role itself upgraded the CLI. Here the upgrade happens in the mise role's single `mise up`, several roles earlier. What restarts the daemon after an upgrade?
**Options considered:** a fact set by the mise role and read here / compare the daemon's reported `daemonVersion` with mise's active version of `npm:@getpaseo/cli` and restart on a difference / restart on every run
**Chosen:** The version comparison, plus a restart when the unit file or the relay setting changed.
**Decided-by:** agent
**Justification:** No cross-role variable, fires once per upgrade and never on a converged run. `paseo daemon status --json` reports `daemonVersion`, verified 2026-10-11.
**Outcome:** assumed
**Ref:** (this commit)

## Q6 — interactive/omarchy-port-ghostty-config — deviation

**Question:** The Mac ghostty role deploys `files/config`. Port it?
**Options considered:** deploy the Mac config / leave `~/.config/ghostty/config` to Omarchy
**Chosen:** Leave it. Omarchy seeds the file with its theme include when it makes ghostty the default terminal, and the Mac config would overwrite that.
**Decided-by:** agent
**Justification:** `~/.config/ghostty/config` on mac-mini-2018-omarchy is Omarchy's, read 2026-10-11. Reversible by adding one copy task.
**Outcome:** applied
**Ref:** (this commit)

## Q7 — interactive/omarchy-port-cux — deviation

**Question:** The first real run on mac-mini-2018-omarchy failed at `mise use -g npm:@inulute/cux@latest`: mise's npm installer refuses a package with fewer than 1000 weekly downloads, and cux has 57. Install it anyway, or drop it?
**Options considered:** drop cux from the port / install it with `npm install -g` outside mise / pass `allow_low_downloads=true` as a mise tool option, which mise records in config.toml
**Chosen:** The tool option, through a new optional `mise_opts` in the shared mise tool task. Only cux needs it: opencli, paseo, defuddle, playwright and cf are all above the threshold.
**Decided-by:** agent
**Justification:** The guard is against typosquats of unknown packages; cux is the package the Macs already install with npm (macbook-provision roles/claude-extras), so the review mise asks for has been done. One install path per tool stays true (grilling Q5).
**Outcome:** applied
**Ref:** (this commit)

## Q8 — interactive/omarchy-port-opencli — deviation

**Question:** The agent-reach role's OpenCLI step, a mise `npm:@jackwener/opencli` tool, failed the first real run: mise's npm installer reports a trust downgrade, because version 0.1.0 was published with a provenance attestation and 1.8.8 has none. Exempt it or drop it?
**Options considered:** `trust_policy_excludes` on the tool, which exempts the package from the check / `mise settings npm.shell_out=true`, which bypasses every check / drop the step
**Chosen:** Drop the step. The role's README says how to add it back after a review of the release.
**Decided-by:** agent
**Justification:** A provenance drop is the signal the check exists for, and an unattended run should not waive it. OpenCLI's use here, X search through a logged-in Chrome plus a one-time extension click, is not something a headless always-on host does. agent-reach itself installed and reports five channels up. Reversible with one include.
**Outcome:** assumed
**Ref:** (this commit)

## Q9 — interactive/nightly-provision — deviation

**Question:** The nightly `update-packages` sweep on mac-mini-m6 now runs this playbook, and so `omarchy-update -y`, every night (coding-agent Q384). Should the Sunday `omarchy-weekly-update` script still run `omarchy-update -y` itself?
**Options considered:** keep both / script keeps only the reboot check / drop the script and reboot from the play
**Chosen:** The script drops its update call and keeps only the reboot check. Its name, cron entry and log stay.
**Decided-by:** human
**Justification:** Frank, 2026-10-11: run `omarchy-update` only in omarchy-provision. The play never reboots (Q2), so the Sunday check still owns reboots, and the Sunday 02:00 play precedes the 04:30 check, so the reboot sees that night's packages.
**Outcome:** applied
**Ref:** (pending)

## Q10 — interactive/omarchy-port-headless — gate-resolution

**Question:** After the first verified run, keep the three AUR desktop and CLI packages the port carried over from the Mac set (Sublime Text, IntelliJ IDEA Ultimate, kimi-code), and the OpenCLI step left out in Q8?
**Options considered:** keep all three / drop all three / keep kimi-code as the one CLI
**Chosen:** Drop all three and confirm Q8. The `kimi-code` and `intellij-idea` roles, the Sublime Text step and `roles/pacman/tasks/aur.yml`, which then had no caller, are removed. The three packages and the `kimi-yolo` alias were uninstalled from mac-mini-2018-omarchy by hand on 2026-10-11, since the first run had installed them an hour earlier and nothing had used them.
**Decided-by:** human
**Justification:** Frank, in the session after the port was verified: "leave OpenCLI out, drop Sublime Text, IntelliJ Ultimate and kimi-code". A headless always-on host has no use for the two desktop apps. No AUR package remains in the play, so the Q3 mechanism is documented in docs/writing-roles.md rather than kept as dead code.
**Outcome:** applied
**Ref:** (this commit)

## Q11 — interactive/omarchy-agents-gateway — tradeoff

**Question:** mac-mini-2018-omarchy now routes every Omarchy agent it can through CLIProxyAPI (coding-agent Q374, Q375), and Copilot, Crush, Gemini, Grok and OpenClaw were installed there by hand. How should this repo carry them, and what about the two agents with no gateway route and OpenClaw's onboarding?
**Options considered:** leave them as hand installs / one role per agent with Omarchy's own install path / one combined role; for OpenClaw: onboard in the role / report a missing onboarding only
**Chosen:** Five roles, `copilot`, `crush`, `gemini`, `grok` and `openclaw`, placed after `pi` so the agents exist before `skills` fans out. The first four use the mise tool include with Omarchy's stub (`gemini` and `grok` depend on `nodejs`, being npm tools). `openclaw` runs `omarchy-install-openclaw-cli --check`/`--now`, as `hermes` does, and only prints a message when `~/.openclaw/openclaw.json` is missing. Cursor CLI and Muse Code get no role. No role writes gateway config.
**Decided-by:** agent
**Justification:** Frank asked to put the five agents in this repo so a rebuilt host gets them back; without a role, `cliproxy-tier` skips an absent agent without an error. One role per tool is the repo's shape (docs/writing-roles.md §Install layers). AGENTS.md makes the gateway files read-only here, and OpenClaw's onboarding writes its gateway provider, installs an always-on daemon and needs the tunnel up for a test request, so it stays the manual step that `~/.agents/docs/gateway-ops.md` describes. Cursor and Muse were left native by Frank (coding-agent Q375); installing them here would add two agents that skip the gateway.
**Outcome:** applied
**Ref:** (this commit); coding-agent Q374, Q375

## Q12 — interactive/purelymail-cli — gate-resolution

**Question:** How does the `purelymail` CLI (github.com/soulmachine/purelymail, Frank's Rust tool for the Purelymail API) reach every personal host, and where do its credentials live?
**Options considered:** `cargo install purelymail` on each host / a role that installs the GitHub release tarball into `~/.local/bin` / by hand over ssh with nothing in the playbook
**Chosen:** A `purelymail` role modelled on ubuntu-provision's `agent-sync` role: resolve the newest release from the releases/latest redirect, download the tarball for the host's architecture, unpack the one binary into `~/.local/bin`, converge on the reported version. No cargo needed. The two tokens, `PURELYMAIL_API_TOKEN` and `CARGO_REGISTRY_TOKEN`, are free-standing exports placed by hand in ~/.profile (mode 600, outside the dotenv managed block, like `GITHUB_TOKEN`), so the role never touches credentials and the dotenv role cannot clobber them. The host's `~/.bash_profile` gained `[ -f ~/.profile ] && . ~/.profile`, because Arch's default never reads `~/.profile`, so `bash -lc` runs would not have seen the tokens.
**Decided-by:** human
**Justification:** Frank chose the token files on 2026-10-11 (`~/.zshenv` on macOS, `~/.profile` on Linux). The tarball avoids a Rust toolchain on hosts that have none (supermicro, mac-mini-2018-omarchy) and a minute of compile on the rest.
**Outcome:** applied
**Ref:** purelymail DECISIONS Q30, release v0.1.0
