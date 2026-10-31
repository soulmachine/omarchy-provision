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

## Q13 — interactive/herdr-rename-hook — tradeoff

**Question:** The herdr-rename-hook skill's hook, which mirrors a Claude Code or Codex `/rename` onto the calling Herdr pane's agent, pane and tab, was installed on mac-mini-2018-omarchy by hand. Frank asked to put it in this repo so a rebuilt host gets it. Where, and how?
**Options considered:** a new role / the `herdr` role; copy the hook and edit the settings files in Ansible / call the skill's own `install.sh`
**Chosen:** In the `herdr` role, which already installs the herdr skill and runs after `skills`. It calls `~/.agents/skills/herdr-rename-hook/scripts/install.sh` only when `install.sh --check` fails, and reports `changed` when the `--check` output differs before and after. A missing skill prints a message and skips; a hook that stays incomplete (Codex with `[features] hooks` off) prints the `--check` lines. `HERDR_ENV` is cleared for the install, so the installer's in-pane self-check never runs during a play.
**Decided-by:** agent
**Justification:** The installer is the skill's source of truth for the wiring and merges only its own entries, so copying its logic here would drift. The `skills` role adopts `soulmachine/skills` into the store, so the installer is present by the time `herdr` runs. The `claude-code` role merges only its managed keys and never `hooks`, so the two roles do not rewrite each other. Tested here: two runs with the hook installed changed nothing; after `install.sh --uninstall`, run 1 reinstalled it (one change, self-check skipped) and run 2 changed nothing, ending with `--check` clean. Not tested: the missing-skill branch. The purelymail entry, appended in parallel as a second Q11, was renumbered to Q12 by its own session (3663bb7).
**Outcome:** applied
**Ref:** (this commit)

## Q14 — interactive/updates-and-reboot-in-play — tradeoff

**Question:** The nightly sweep's `pacman` role already runs `omarchy-update -y`, but only the Sunday `omarchy-weekly-update` cron (coding-agent Q364) rebooted. A kernel installed on a weeknight therefore ran for up to six days with its module folder deleted. Frank chose "let the macbook-provision, ubuntu-provision and omarchy-provision do the updates job". Where does the reboot go?
**Options considered:** keep the Sunday cron / run the cron's check nightly / reboot from the play itself
**Chosen:** The play. The reboot probe in the `pacman` role now reports `changed` when a reboot is due and notifies the new `pacman` handler "Schedule a reboot". That handler runs after the last role, removes Omarchy's `reboot-required` flag, and starts `systemd-run --on-active=5min --unit=omarchy-provision-reboot systemctl reboot` unless that timer is already active. The `always-on` role no longer installs the Sunday script and cron; it removes both.
**Decided-by:** Frank chose that the provision repos own updates; the agent chose the handler, the 5-minute delay and the flag removal.
**Justification:** One owner for the whole update, as on the Macs and Ubuntu hosts. An immediate reboot would cut off the PLAY RECAP that the sweep waits for in `/tmp/provision.log`, and Arch's tmpfs `/tmp` erases that log at boot, so the sweep would report a failure. Five minutes is well past the sweep's 60 s poll. The flag is removed because nothing in Omarchy clears it, and a stale one would reboot every night. Tested on mac-mini-2018-omarchy: ansible-lint passed on both roles; `always-on` changed 2 then 0, and the crontab now holds only agent-sync; `pacman` in check mode with the flag set notified the handler, while `omarchy-update` and the handler were skipped; the handler's command, with `/bin/true` in place of the reboot, scheduled a 5-minute timer once and exited 0 on a second run. Not tested: a real reboot through the handler.
**Outcome:** applied
**Ref:** supersedes coding-agent Q364's Sunday cron; coding-agent update-packages.cron.md

## Q15 — interactive/provision-repos-agents-sync — deviation

**Question:** Q11 left OpenClaw's onboarding as a manual step. With the agents now ported to macbook-provision and ubuntu-provision (coding-agent Q401), Frank chose to have `cliproxy-tier` run the onboarding on every host. What changes here?
**Options considered:** keep the manual step on this host only / follow the fleet
**Chosen:** Follow the fleet. The `openclaw` role's message now points at `cliproxy-tier <host>`, and the README drops the manual onboarding step. The role also gets the fleet's stale-daemon check: when the daemon's OpenClaw version lags the CLI (after a pacman upgrade here), or its mise Node no longer matches the current one, `openclaw gateway install --force` rewrites and restarts it. Here the service uses the system `/usr/bin/node`, so only the version half can fire.
**Decided-by:** human
**Justification:** Frank's answer in the coding-agent Q401 session. The onboarding writes gateway config, which AGENTS.md assigns to `cliproxy-tier`, so the move also matches the rule that this repo never writes gateway files. Also fixed: the `herdr` role cited DECISIONS Q12 for the rename hook, a number the parallel purelymail entry took; it now cites Q13. Tested here: two `openclaw` role runs changed nothing.
**Outcome:** applied
**Supersedes:** Q11 — only its manual-onboarding part; the roles stand
**Ref:** (this commit); coding-agent Q401

## Q16 — interactive/email-role — gate-resolution

**Question:** How do the Himalaya CLI (github.com/pimalaya/himalaya), its OAuth helper ortie (github.com/pimalaya/ortie) and Proton Mail Bridge (proton.me/mail/bridge) reach mac-mini-2018-omarchy?
**Options considered:** `extra/protonmail-bridge` (Qt GUI) / `extra/protonmail-bridge-core` (headless); ortie from the AUR (`ortie` 2.2.0, behind upstream's v2.3.0) / from its GitHub release tarball
**Chosen:** One `email` role. himalaya and `protonmail-bridge` are `extra` packages, installed with pacman and upgraded by `omarchy-update` (Q2). ortie comes from its GitHub release through `tasks/pimalaya.yml`, the same parametrised copy of the purelymail role (Q12) that ubuntu-provision uses, because this repo has no AUR layer (Q10) and the AUR package lags. Accounts are configured by hand.
**Decided-by:** human
**Justification:** Frank chose the full Bridge package on 2026-10-12: the host has a Hyprland desktop, and it matches the macOS cask and the Ubuntu .deb, which are GUI builds too.
**Outcome:** applied
**Ref:** macbook-provision Q223, ubuntu-provision Q28

## Q17 — interactive/whats-next-audit — gate-resolution

**Question:** The port's four `assumed` calls, Q2 (`omarchy-update -y` as the upgrade step), Q4 (tailscale with an auth key), Q5 (paseo daemon restart after `mise up`) and Q8 (OpenCLI's npm trust downgrade), were listed to Frank on 2026-10-12. Ratify them?
**Options considered:** ratify all four / revisit any / leave them assumed
**Chosen:** Ratified all four as applied, in one batch.
**Decided-by:** human
**Justification:** Each has been running in the nightly sweep on mac-mini-2018-omarchy since the port; none was questioned.
**Outcome:** applied
**Ref:** (this commit); macbook-provision Q224
**Supersedes:** Q2, Q4, Q5, Q8 — assumed calls ratified by the user

## Q18 — interactive/lcu-role — scope

**Question:** Upstream macbook-provision Q228 adds an `lcu` role (Local Computer Use, amontlabs/lcu). Port it?
**Options considered:** a role gated on the ChatGPT app that skips today / no role
**Chosen:** No role. LCU needs the ChatGPT desktop app (a .deb for Ubuntu, no Arch package in this repo's layers) and an X11 desktop with a D-Bus session; mac-mini-2018-omarchy has neither, and its Hyprland desktop is native Wayland, which LCU does not support. README's "不移植的内容" lists it.
**Decided-by:** human
**Justification:** Frank chose "skip the Linux roles" on 2026-10-12 when the prerequisites were laid out; a role that always skips is dead code.
**Outcome:** applied
**Ref:** (this commit); macbook-provision Q228, ubuntu-provision Q32

## Q19 — interactive/removemacai — scope

**Question:** Upstream macbook-provision Q229 adds a `removemacai` role (RemoveMacAI's CLI, its configuration profile and per-user tweaks). Port it?
**Options considered:** port it / no role
**Chosen:** No role. RemoveMacAI changes macOS settings only: Apple Intelligence, a macOS configuration profile, and Finder, Dock and macOS defaults. Omarchy has none of them. README's list of roles not ported names it.
**Decided-by:** agent
**Justification:** Precedent macbook-provision Q222 (`1password`): a macOS-only role is not ported, and the sibling repos list it among the roles they leave out.
**Outcome:** applied
**Ref:** (this commit); macbook-provision Q229, ubuntu-provision Q33

## Q20 — interactive/browseros-neo — gate-resolution

**Question:** Upstream macbook-provision Q237 adds `browseros-neo`, and Frank wants it on mac-mini-2018-omarchy. Upstream's docs say neo has no Linux build yet. Which artifact does the role install, and what upgrades it?
**Options considered:** upstream's undocumented AppImage on the CDN / AUR `browseros-neo-bin` / the `.deb` unpacked by hand
**Chosen:** The AppImage at `https://cdn.browseros.com/download/BrowserOS_neo.AppImage`, fetched by `get_url` with `force: true` into `~/.local/share/browseros-neo/`, plus pacman `fuse2` and a launcher `.desktop` file. The MCP entry and skill steps are upstream's.
**Decided-by:** agent
**Justification:** On 2026-10-12, the AUR package was one maintainer's, had 0 votes and was a release behind (0.50.5 against 0.51.0). The AppImage is upstream's own build. `omarchy-update` upgrades only pacman, AUR and mise packages, so this role's re-download is the upgrade path. That departs from "a tool role adds its tool when missing and nothing else" (docs/writing-roles.md), and it costs 218 MB a run. get_url reports changed only when the bytes differ.
**Outcome:** applied
**Ref:** (this commit); macbook-provision Q237, ubuntu-provision Q34

## Q21 — interactive/browseros-neo — deviation

**Question:** Upstream macbook-provision Q240 registers neo's MCP server in every agent and corrects two parts of upstream Q237: the port and the skill refresh. Port it?
**Options considered:** port it as is / keep Q237's shape
**Chosen:** Ported as is: URL `http://127.0.0.1:9010/mcp`; the same `mcp add` and JSON-merge tables; an entry with another URL is replaced; the skill installs only when missing. This repo's install steps are unchanged.
**Decided-by:** human (the other agents: Frank, 2026-10-12); agent (the port)
**Justification:** The Linux build is the same Chromium with the same `kDefaultProxyPort = 9010` patch, so the port fix applies here too. The agents and their config paths are the same as on macOS.
**Outcome:** applied
**Ref:** (this commit); macbook-provision Q240, omarchy-provision Q20
**Supersedes:** omarchy-provision Q20 — its MCP port 9200 and its skill refresh on every play

## Q22 — interactive/bitwarden — gate-resolution

**Question:** Upstream macbook-provision Q242 adds a `bitwarden` role: the Electron app, `bw` and `rbw`. Frank wants the app skipped on headless Linux hosts, and Q10 calls the Omarchy hosts headless always-on servers. Where do the clients come from, and does an Omarchy host get the app?
**Options considered:** pacman `extra` / mise or npm for `bw`; the app on every host / on hosts with a desktop session file / on no Omarchy host
**Chosen:** pacman `bitwarden-cli` and `rbw`, and pacman `bitwarden` when `/usr/share/xsessions` or `/usr/share/wayland-sessions` holds a `*.desktop` file. This is the same test as ubuntu-provision Q36. Omarchy's Hyprland session passes it, so the Omarchy hosts get the app, as they get obsidian and BrowserOS neo.
**Decided-by:** human (the headless rule, and that it counts Omarchy as having a desktop: Frank, 2026-10-12); agent (the sources)
**Justification:** All three are in Arch's `extra`, the repo's first install layer (docs/writing-roles.md), and `omarchy-update` upgrades them (Q2). The Arch `bitwarden` build trails upstream by a few releases, which the extra-repo layer accepts in exchange for one upgrade path.
**Outcome:** applied
**Ref:** (this commit); macbook-provision Q242

## Q23 — interactive/bitwarden — deviation

**Question:** Q22 installs `bw` from pacman `bitwarden-cli`. On mac-mini-2018-omarchy that package depends on `nodejs-lts-jod`, which conflicts with the installed `nodejs`, so pacman stops with "unresolvable package conflicts". Where does `bw` come from?
**Options considered:** replace `nodejs` with `nodejs-lts-jod` / mise `npm:@bitwarden/cli` with a stub / the release zip
**Chosen:** The mise tool `npm:@bitwarden/cli` with the `bw` stub, through `mise/tasks/tool.yml`. rbw and the desktop app stay on pacman.
**Decided-by:** agent
**Justification:** An npm global is the repo's first install layer (docs/writing-roles.md), as for gemini and defuddle. Swapping the system Node for an LTS build would change Node for every other tool on the host to suit one CLI. `mise up` in the mise role upgrades it.
**Outcome:** applied
**Ref:** (this commit)
**Supersedes:** Q22 — only its pacman source for `bw`

## Q24 — interactive/upstream-macos-only — scope

**Question:** Upstream macbook-provision adds `macos-connectors` (Q236, CLIs for the Apple apps) and `ego-browser` (Q239 and Q241, the Ego Lite browser and its skill). Port them?
**Options considered:** port them / no role
**Chosen:** No role for either, and no `citrolabs/ego-lite` entry in the skills role. README lists both with the omitted roles.
**Decided-by:** agent
**Justification:** The connector CLIs drive macOS apps. Ego Lite ships no Linux build: its skill's `scripts/install.sh` downloads only macOS DMGs, and lite.ego.app offers only macOS and Windows (checked 2026-10-12). Precedent Q19 (`removemacai`). ubuntu-provision records the same calls as Q38 and Q39.
**Outcome:** applied
**Ref:** (this commit); macbook-provision Q236, Q239, Q241

## Q25 — interactive/bitwarden — deviation

**Question:** Upstream macbook-provision Q244 has the `bitwarden` role point `bw` and `rbw` at Vaultwarden, except on archs-mac-mini. Port it?
**Options considered:** port it as is / keep install-only
**Chosen:** Ported: the same `tasks/config.yml` (read, write only when different, report a `bw` that is logged in to another server) and the same URL and email vars. No host gate: archs-mac-mini, the one host with its own Vaultwarden, is a Mac.
**Decided-by:** human (configure every host except archs-mac-mini: Frank, 2026-10-12); agent (the port)
**Justification:** `bw config server` and `rbw config` behave the same on Linux. Frank already had both set by hand on this repo's hosts, so the role keeps that across a rebuild.
**Outcome:** applied
**Ref:** (this commit); macbook-provision Q244
**Supersedes:** Q22 — only its "install only" part

## Q26 — interactive/orca — deviation

**Question:** Upstream macbook-provision Q243 adds an `orca` role: the desktop app on MacBooks, plus the server from upstream's `orca serve service install` on always-on Macs. Frank named the AUR package `stably-orca-bin` for Arch. Q10 removed every AUR package. Where does Orca come from here, and which hosts run the server?
**Options considered:** AUR `stably-orca-bin` / the AppImage from the GitHub release; the server on every host / none
**Chosen:** AUR `stably-orca-bin`, installed with `yay -S --needed --noconfirm` behind a `pacman -Q` probe, and the server on every host through `/opt/stably-orca/resources/bin/orca-ide serve service install --port 6768 --command <same path>`. As upstream does, the role skips the server with a message while the installed Orca predates `serve service`. docs/writing-roles.md and README now name the package.
**Decided-by:** human (the AUR package, the server on always-on hosts, and waiting for the upstream installer: Frank, 2026-10-12); agent (the CLI path)
**Justification:** Frank's request names the AUR command, which overrides Q10's "no AUR package" for this one package. docs/writing-roles.md already gave the shape for one. Every Omarchy host is always-on. `omarchy-update -y` (Q2) upgrades AUR packages, so the role needs no upgrade step. The package installs no `orca-ide` on PATH, so the role pins the CLI's path inside the app tree, which stays the same across upgrades. Linger was already on for the host (checked 2026-10-12), so the role adds no linger task.
**Outcome:** applied
**Ref:** (this commit); macbook-provision Q243

## Q27 — interactive/1password — deviation

**Question:** Frank asked for the `1password` role here too (upstream Q245 drops its `~/personal-agent` gate): the desktop app, the `op` CLI and the Claude Code plugin. Which install layer?
**Options considered:** AUR `1password` / pacman from Omarchy's `omarchy` repo / `omarchy-install-service-1password`
**Chosen:** pacman `1password-cli` on every host, and Omarchy's `omarchy-install-service-1password` for the app when a desktop session exists and `pacman -Q 1password` fails. The installer also adds 1Password's Chromium extension. The plugin steps are upstream's, unchanged.
**Decided-by:** human (every host, plugin too, skip the app when headless: Frank, 2026-10-13); agent (the layer)
**Justification:** docs/writing-roles.md puts an Omarchy installer ahead of a bare package. Both packages are in Omarchy's own repo, so `omarchy-update` upgrades them (Q2) and no AUR build is needed. mac-mini-2018-omarchy already had both from the Omarchy install, so the installer path is untested there.
**Outcome:** applied
**Ref:** (this commit); macbook-provision Q220, Q245
**Supersedes:** the README line that listed `1password` among the roles not ported (upstream Q222)

## Q28 — interactive/1password-token — deviation

**Question:** Port upstream 08751d9, which documents OP_SERVICE_ACCOUNT_TOKEN in .env.example and the 1password role?
**Options considered:** port it / skip it
**Chosen:** Skipped. 08be25d is reverted, and the token stays out of this repo's .env.example and 1password role.
**Decided-by:** human (Frank, 2026-10-16: only the control-plane hosts need headless `op`)
**Justification:** Only mac-mini-m6, mac-mini-m2 and macbook-air get a 1Password service account (~/.agents/docs/1password.md), and all three are Macs. No host this repo provisions gets one.
**Outcome:** applied
**Ref:** (this commit); macbook-provision 08751d9

## Q29 — interactive/open-pstack-removal — deviation

**Question:** Port macbook-provision Q247, which removes open-pstack from every host through retire tasks in the claude-code and codex roles?
**Options considered:** port it / skip it
**Chosen:** Ported unchanged: the claude-code role uninstalls `pstack@open-pstack` and removes the `open-pstack` marketplace where present; the codex role removes the plugin, the marketplace and its hook-trust entry. The install steps are gone.
**Decided-by:** human
**Justification:** open-pstack is on every host, Linux ones included, and the user wants it gone everywhere. Delete the retire tasks once every host is clean.
**Outcome:** applied
**Ref:** (this commit); macbook-provision Q247

## Q30 — interactive/context-mode — gate-resolution

**Question:** Port the macOS context-mode role, and how should the `context-mode` CLI be installed on Omarchy?
**Options considered:** an npm global as on macOS / an Omarchy mise tool (`npm:context-mode` with a ~/.local/bin stub)
**Chosen:** Ported with the mise tool, the way this repo installs every other npm CLI (`mise/tasks/tool.yml`). The agents are Claude Code, Codex, OpenCode, pi, oh-my-pi, Gemini CLI, Copilot CLI and OpenClaw. There is no kimi-code half, because Omarchy does not install kimi-code (Q10). Hermes, Crush and Grok are skipped.
**Decided-by:** agent
**Justification:** The user asked for context-mode in all three provision repos, each agent through its own installer. This repo has no npm_global helper, and its other npm CLIs are mise tools. The reasons for the per-agent calls are in macbook-provision Q248–Q251.
**Outcome:** applied
**Ref:** (this commit); macbook-provision Q248–Q251

## Q31 — interactive/context-mode — tradeoff

**Question:** Should OpenClaw's capability consent for context-mode be given on install and on update?
**Options considered:** install and update / install only / neither
**Chosen:** Install only. A consent refusal on update is tolerated and reported, and the plugin keeps its version.
**Decided-by:** agent
**Justification:** Same call as macbook-provision Q252. On this repo's hosts OpenClaw 2026.10.5 refused the install without `--accept-capabilities` (dev-server-frank, 2026-10-18).
**Outcome:** applied
**Ref:** (this commit); macbook-provision Q252

## Q32 — interactive/context-mode — irreversible-action

**Question:** Trust context-mode's six Codex hooks on this repo's host?
**Options considered:** leave it to the per-host `/hooks` step / trust them headlessly
**Chosen:** Trusted headlessly on mac-mini-2018-omarchy, where the plugin is installed.
**Decided-by:** agent
**Justification:** The user asked for it. Same review, method and revert path as macbook-provision Q253; its hashes matched mac-mini-m6's.
**Outcome:** applied
**Ref:** (this commit); macbook-provision Q253

## Q33 — interactive/pi-default-deepseek — deviation

**Question:** Pi's new default is deepseek-v4.1-flash at thinking level high, but the gateway catalog marks that model non-reasoning, so Pi would ignore "high". Which side should change, and how far should the change reach?
**Options considered:** flip the model to reasoning in Pi's payload / keep it non-reasoning, so "high" applies only to reasoning models; change the three provision repos only / also change the m2 gateway scripts
**Chosen:** In `roles/pi/files/agent`, `defaultModel: cliproxy/deepseek-v4.1-flash` and `defaultThinkingLevel: high`, and the deepseek-v4.1-flash entry gets `reasoning: true`. Only the three provision repos change.
**Decided-by:** human
**Justification:** Frank chose both. A test request through the gateway (Anthropic messages API, thinking enabled) returned a thinking block from deepseek-v4.1-flash, so the flag was wrong. Known conflict: macbook-provision `gateway/cliproxy-assert-pi` still re-asserts `cliproxy/claude-opus-5-5` and `reasoning: false` every hour, and `cliproxy-tier-host.py` reports pi as `DEFAULT=…`. Until those scripts change, the playbook and the hourly job undo each other's change on each host.
**Outcome:** applied
**Ref:** (pending)

## Q34 — interactive/pi-default-deepseek — deviation

**Question:** Pi 1.3.0 ignored `defaultModel: "cliproxy/<id>"` and fell back to the first provider with a key (`anthropic/claude-opus-4-8`). How should the payload name the default?
**Options considered:** keep the combined `provider/id` string / split it into `defaultProvider` + `defaultModel`
**Chosen:** `"defaultProvider": "cliproxy"` and `"defaultModel": "deepseek-v4.1-flash"`.
**Decided-by:** agent
**Justification:** Pi's `dist/core/model-resolver.js` (step 2, "saved default") uses the saved default only when both `defaultProvider` and `defaultModel` are set, and it looks the model up by bare id. A `pi -p --mode json` run afterwards answered from `cliproxy`/`deepseek-v4.1-flash`, with a thinking block. So the earlier `cliproxy/claude-opus-5-5` value probably never took effect either. `cliproxy-assert-pi` and `cliproxy-tier-host.py` still write and check the combined form, so the hourly re-assert would set an id Pi cannot resolve.
**Outcome:** applied
**Ref:** (pending)

## Q35 — interactive/agent-usage-move — deviation

**Question:** The Agents bar's rate-limit feed and the Omarchy patches lived in macbook-provision's `gateway/`, put on mac-mini-2018-omarchy by hand, with m2 pushing over ssh every 5 minutes. Where should they live, and which way should the data flow?
**Options considered:** a new omarchy-provision role where the Omarchy host pulls from m2 / move only the files and keep m2's LaunchAgent pushing from an omarchy-provision clone on m2
**Chosen:** New role `omarchy-cliproxy`. It installs the three patches (launcher, Claude and Codex collectors), the installer, the pacman hook, the probe and a systemd user timer. Every 5 minutes the timer runs the probe on mac-mini-m2 over ssh from stdin. m2 prints only the usage answers, and the host writes them to `~/.local/state/cliproxy/`. m2's LaunchAgent and the macbook-provision copies are removed.
**Decided-by:** human (pull, and move all of `gateway/omarchy/`), agent (role shape)
**Justification:** Only the Agents bar reads these files, and only Omarchy has that bar, so the Omarchy repo owns them. Tokens stay on m2, because m2 runs the probe and returns only the answers. Agent-less `ssh mac-mini-m2` works from the host, and `Linger=yes` lets a user timer run without a login.
**Outcome:** applied
**Ref:** (pending)

## Q36 — interactive/agent-usage-move — gate-resolution

**Question:** Which Omarchy hosts get the role?
**Options considered:** every Omarchy host / only gateway-only hosts
**Chosen:** Only hosts where `~/.local/bin/claude-gw` exists and `~/.claude/.credentials.json` does not. Other hosts skip the role.
**Decided-by:** agent
**Justification:** The launcher patch sends agents to the `-gw` wrappers, and the pushed limits are for hosts with no vendor login. A host with a native Claude login has its own limits and needs neither. `cliproxy-tier-host.py` writes `claude-gw`, so the gate follows the gateway's own record.
**Outcome:** assumed
**Ref:** (pending)

## Q37 — interactive/agent-usage-move — gate-resolution

**Question:** Which Omarchy hosts get the `omarchy-cliproxy` role?
**Options considered:** gateway-only hosts / gateway-only hosts whose Omarchy has the Agents bar
**Chosen:** Gateway-only hosts (Q36's `claude-gw` present, no `~/.claude/.credentials.json`) whose Omarchy ships the Agents bar, which the role checks as `/usr/bin/omarchy-agent-usage-update`.
**Decided-by:** human
**Justification:** Frank confirmed Q36 and added the Agents bar condition. The bar is the only reader of the fetched limits, and the collector patches have no target without it.
**Outcome:** applied
**Ref:** (pending)
**Supersedes:** Q36 — adds the Agents bar condition; the gateway condition stays.

## Q38 — interactive/hindsight-role — tradeoff

**Question:** Port macbook-provision's `hindsight` role (agent CLIs wired to the fleet Hindsight server on mac-mini-m2) and its pi-role change here?
**Options considered:** same role, same files / a Linux-specific variant
**Chosen:** The same files. The role branches only for the relay (a LaunchAgent on macOS, a systemd user unit on Linux), so one copy serves all three repos. The pi role keeps the Hindsight `extensions` entry, as in macbook-provision.
**Decided-by:** agent
**Justification:** Fleet rule: a change in one provisioning repo is synced to the other two. The reasoning is in macbook-provision Q284 and coding-agent Q605–Q610.
**Outcome:** applied
**Ref:** macbook-provision 631f64a

## Q39 — interactive/orca-remote-servers — tradeoff

**Question:** Port macbook-provision Q289 (the Orca service advertises the host's Tailscale IPv4) here?
**Options considered:** same change / skip
**Chosen:** The same change: the install task adds `--pairing-address <tailscale ip -4>` when it reads a `100.x.y.z` address, and the README lists the manual pairing steps. macbook-provision's `/usr/local/bin/orca` fix does not apply, because Linux has no such link.
**Decided-by:** agent
**Justification:** Fleet rule: a change in one provisioning repo is synced to the other two. The reasoning is in macbook-provision Q289.
**Outcome:** applied
**Ref:** 334c7b5, macbook-provision 92a6870

## Q40 — interactive/orca-cli-registration — gate-resolution

**Question:** Frank asked to register the Orca CLI under Settings → General → Orca CLI on every host. What does registering mean on Linux, and how does the role do it?
**Options considered:** a role-owned symlink matching the app's check / clicking Register in each app by hand / a symlink with `force`
**Chosen:** An `ansible.builtin.file` link from `~/.local/bin/orca-ide` to `/opt/stably-orca/resources/bin/orca-ide`, without `force`.
**Decided-by:** agent
**Justification:** In Orca 1.4.239's CLI installer (app.asar), Linux counts the CLI as registered when `~/.local/bin/orca-ide` resolves to the app's `resources/bin/orca-ide`, and the app checks nothing else. Without `force`, a file there that is not a link fails the task, as the app also refuses to replace a non-Orca command. mac-mini-2018-omarchy had no link, so its Settings page read not registered. The link also puts `orca-ide` on PATH, but the role still calls the full path, because the service unit pins it. On macOS the cask's link already counts: Frank saw Registered on macbook-pro-m3, so macbook-provision changed only its README.
**Outcome:** applied
**Ref:** a2bfa3c

## Q41 — interactive/orca-cli-skill — tradeoff

**Question:** Port macbook-provision Q290 (the orca role installs Orca's `orca-cli` skill with Orca's own installer) here?
**Options considered:** same tasks / skip
**Chosen:** The same four tasks, with `bash -lc` and this repo's CLI path.
**Decided-by:** agent
**Justification:** Fleet rule: a change in one provisioning repo is synced to the other two. The reasoning is in macbook-provision Q290.
**Outcome:** applied
**Ref:** 28aac58, macbook-provision f1b98d1

## Q42 — interactive/orca-server-only — deviation

**Question:** On mac-mini-2018-omarchy the desktop app failed with "Another orcad … already owns the data root /home/frank/.config/orca", because the `orca-serve` service holds the profile. How should Linux hosts run Orca?
**Options considered:** the app as a client of the local server, on its own profile / the app as the server, with no service / the server alone, and the launcher hidden / the server alone, with the package swapped for an extracted AppImage
**Chosen:** The server alone. The package stays, and the role writes `~/.local/share/applications/stably-orca.desktop` with `Hidden=true` and `NoDisplay=true`, so the launcher no longer lists Orca. The service, the CLI link and the `orca-cli` skill are unchanged.
**Decided-by:** human
**Justification:** Frank asked for the CLI alone on Linux, with `orca serve` as the remote server and no desktop app. Orca ships no CLI-only build: `resources/bin/orca-ide` is a script that runs the app's Electron binary, and `orca serve` needs the same files, so Frank chose to keep the package and hide its launcher rather than replace it. A user entry with the same name overrides the system one and survives package upgrades. macOS is unchanged: there the desktop app and the service share the profile, and the supervisor waits while the app serves.
**Outcome:** applied
**Ref:** 16495a5

## Q43 — interactive/cliproxy-relay — deviation

**Question:** The remote hosts now reach the CLIProxyAPI gateway by the fleet rule (LAN > Tailscale > reverse SSH tunnel, coding-agent `devops/service-access.md`, Q632 there). Where does the gateway's local relay come from?
**Options considered:** a new role with its own relay copy / the hindsight role's relay tasks looped over a per-service list
**Chosen:** The hindsight role's relay tasks loop over `hindsight_relays` (hindsight 8888 → 18888, cliproxy 8317 → 18317). One binary, `~/.local/bin/hindsight-relay`, installed once in `client.yml`; `relay.yml` and the two templates take the service from the loop var `relay`. Unit names `me.soulmachine.<name>-relay` / `<name>-relay.service`, so the Hindsight units keep their labels.
**Decided-by:** agent
**Justification:** The same tasks, templates and binary already exist in all three provision repos; a list is the smallest change, and a second copy of the relay script would drift. The remote hosts are exactly the hosts the role already gives a relay. Same change in macbook-, ubuntu- and omarchy-provision.
**Outcome:** applied
**Ref:** (pending)

## Q44 — interactive/openclaw-missing-node — gate-resolution

**Question:** macbook-provision Q292 removes Homebrew's `node`, and its `openclaw` role now rewrites the daemon when the daemon's Node is gone, wherever that Node sits in the service's arguments. This repo has the same stale-daemon check. Port it?
**Options considered:** port the check / leave it, since this host family keeps its system or mise Node
**Chosen:** Ported: the check finds the first argument ending in `/node` (falling back to the first argument), and a daemon whose Node no longer exists counts as stale, as does a mise Node that differs from the current one or a version mismatch.
**Decided-by:** agent
**Justification:** The provisioning repos stay in sync (`~/.agents/AGENTS.md`), and a Node pruned by mise or a package upgrade leaves the daemon with nothing to run here too. Same change in macbook-, ubuntu- and omarchy-provision.
**Outcome:** applied
**Ref:** macbook-provision Q292

## Q45 — interactive/omarchy-unattended-prompts — tradeoff

**Question:** `omarchy-update -y` exports `OMARCHY_UPDATE_UNATTENDED=1`, yet `omarchy-update-orphan-pkgs` and `omarchy-update-restart` still ask through `gum confirm`, and `script` gives gum a pty, so the nightly run hangs (coding-agent Q488, Q589). How to stop that?
**Options considered:** run `omarchy-update` without a pty / patch both prompts to honor `OMARCHY_UPDATE_UNATTENDED` / keep reporting the host as unfinished
**Chosen:** Patch both prompts (Frank's choice). Orphan removal takes its existing non-terminal branch (keep and report). `confirm_reboot` prints that a reboot is due and returns, so the play's own reboot check decides (Q14). The patches sit in `/usr/local/share/omarchy-unattended/`, applied by `/usr/local/bin/omarchy-unattended-patch` before the update and by the pacman hook `96-omarchy-unattended.hook` whenever the omarchy package rewrites either file. That hook runs inside `omarchy-update-system-pkgs`' own transaction, before the prompts. A patch that stops applying fails the play at the end, as the CLIProxyAPI patches do.
**Decided-by:** human
**Justification:** The two files are owned by the `omarchy` package in `/usr/bin`, so a one-off edit would be lost at the next upgrade, which happens during the very run that reaches the prompts. The hook pattern is already proven here by `95-omarchy-cliproxy-usage.hook`. Stock interactive behavior is unchanged: without the variable both prompts still ask.
**Outcome:** applied
**Ref:** coding-agent Q488, Q589; roles/pacman/tasks/unattended.yml

## Q46 — interactive/tailscale-early-return — deviation

**Question:** macbook-provision Q295 ends the tailscale role at once when `tailscale status --json` reports `BackendState: Running`. Port it?
**Options considered:** port the early return / keep running the install and key-expiry steps on every play
**Chosen:** Ported: the first task probes `tailscale status --json`, and rc 0 with `Running` runs `meta: end_role`, which skips the package, the service and Omarchy's extras, `tailscale up` and key-expiry. The enrolment block's own probe and its two `Running` conditions are gone.
**Decided-by:** human
**Justification:** The user asked for the early return, and the provisioning repos stay in sync (`~/.agents/AGENTS.md`). The cost is the same as on the Macs: key-expiry now runs only on a run that starts offline, in practice the enrolment run. Linted only; this change has not run on a Linux host.
**Outcome:** applied
**Ref:** macbook-provision Q295

## Q47 — interactive/tailscale-extras-marker — deviation

**Question:** Omarchy's extras (operator, Taildrop, bar plugin, web app) ran only when the package was missing at the start of the play, so a host enrolled by hand never got them. With the Q46 early return, a re-run on such a host now ended before the extras. How should the role know whether the extras are in place?
**Options considered:** keep the package-missing gate / stat `~/.local/share/applications/Tailscale.desktop`, the web app that is the installer's last step / check each extra (systemd unit, plugin, desktop file) separately
**Chosen:** Stat the web-app launcher. The early return now needs Running AND that file. Enrolment is guarded on "not running" again, because a Running node without the extras now continues. The extras block runs whenever the file is missing, and the `pacman -Q tailscale` check it used is gone.
**Decided-by:** human
**Justification:** The user asked for the fix. The installer has no `set -e` and its exit code is the web-app install's, so the launcher shows that the script ran to the end. One stat is enough to say whether to re-run the whole idempotent script. Cost: a user who deletes the web app by hand gets it back on the next play. Verified on mac-mini-2018-omarchy in check mode: with the file present, the role ends after the probes; with the path pointed at a missing file, it skips `tailscale up` and reaches the installer. ubuntu- and macbook-provision have no Omarchy extras, so nothing to sync.
**Outcome:** applied
**Ref:** Q46; macbook-provision Q295

## Q48 — interactive/npm12-allow-scripts — tradeoff

**Question:** npm 12 stops running dependency install scripts unless allowed. Which npm globals should this box allow?
**Options considered:** the Mac list (`opencode-ai`, `@inulute/cux`) / only what this box installs through npm
**Chosen:** Only `@inulute/cux`: the nodejs role writes `allow-scripts=@inulute/cux` to `~/.npmrc`.
**Decided-by:** agent
**Justification:** macbook-provision Q303 measured which globals break under npm 12. Here opencode is a mise tool, not an npm package, so only cux (mise `npm:@inulute/cux`) needs its postinstall. Not tested on Omarchy, and it assumes mise's npm backend reads the user `~/.npmrc`.
**Outcome:** assumed
**Ref:** roles/nodejs/tasks/main.yml (this commit); macbook-provision Q303

## Q49 — interactive/npm12-allow-scripts — deviation

**Question:** Q48 assumed that mise's npm backend reads `allow-scripts` from `~/.npmrc`. Tested on this box on 2026-10-29, it does not. How should cux get its install script?
**Options considered:** keep the `~/.npmrc` line / tool option `allow_builds=@inulute/cux` / `allow_builds=true`
**Chosen:** `mise_opts: allow_low_downloads=true,allow_builds=@inulute/cux` on cux in claude-extras, and the `~/.npmrc` task removed from the nodejs role. On mac-mini-2018-omarchy, cux was fixed by hand with `mise use -g` on the new options and `mise install --force`, because the mise tool task skips a tool that is already installed.
**Decided-by:** agent
**Justification:** mise installs npm tools with its embedded aube by default, and with npm it adds `--ignore-scripts=true` itself. Either way it runs no install scripts until a tool sets `allow_builds` (mise docs, npm backend, "Build scripts"). The live cux on this box had never worked: it printed "Postinstall may have failed". In a throwaway mise data dir, the `~/.npmrc` line left cux broken, and `allow_builds=@inulute/cux` made it run (`cux 0.4.1`). The narrow form was chosen over `true` because it approves one package's script, not the whole tree's. No role here installs with plain npm, so the `~/.npmrc` line did nothing.
**Outcome:** applied
**Ref:** roles/claude-extras/tasks/main.yml, roles/nodejs/tasks/main.yml (this commit)
**Supersedes:** Q48 — its assumption was wrong when tested

## Q50 — interactive/mise-npm-install-scripts — deviation

**Question:** mise runs no install scripts for npm tools (Q49). Besides cux, which mise npm tools on this box break because of it?
**Options considered:** fix only cux / check every `npm:` tool and fix each one that fails
**Chosen:** Checked all 12. Only grok was wrong: `allow_builds=@xai-official/grok` on the grok role, and on mac-mini-2018-omarchy the option was written by hand with `mise install --force`. grok now runs 1.0.70.
**Decided-by:** agent
**Justification:** On 2026-10-29 every `npm:` tool's current version was run, and its package tree was scanned for install scripts. bw, dsh, paseo, playwright-cli, backpass, cf, defuddle, mcporter and playwright have no scripts, or run without them. context-mode skips its scripts, but `context-mode doctor` passes storage and server (as macbook-provision Q251 found on macOS). grok's package said 1.0.70, but `grok` ran 1.0.50 from 2026-10-11: its launcher always runs `~/.grok/bin/grok` once it exists, and only the skipped postinstall moves that file. In a throwaway mise data dir with a temp `GROK_HOME` holding an older binary, the install without `allow_builds` kept running it, and with the option it ran 1.0.70. The old `~/.grok/bin/grok-1.0.50` (about 180 MB) was left in place.
**Outcome:** applied
**Ref:** roles/grok/tasks/main.yml (this commit); macbook-provision Q305

## Q51 — interactive/cf-npm-global — deviation

**Question:** mise resolves `npm:cf@latest` to 0.15.0, which is the old pre-Cloudflare package, because its "latest" skips prereleases and every Cloudflare release is a 1.0.0 beta. How should this box install cf?
**Options considered:** npm global with `become`, as on the Macs and Ubuntu / keep mise and pin `npm:cf` to the `1.0.0-beta` prefix
**Chosen:** An npm global through `community.general.npm` with `become: true`, because pacman's node has its global prefix in `/usr`. The role also runs `mise unuse -g npm:cf` and deletes the `~/.local/bin/cf` stub.
**Decided-by:** human
**Justification:** The user prefers one channel for cf on every host: an npm global, like the macbook-provision and ubuntu-provision cloudflare roles. The pin would need a version variable in `mise/tool.yml`, and it stops matching when cf ships 1.0.0 stable. On 2026-10-30, `mise latest npm:cf` on mac-mini-2018-omarchy printed 0.15.0, while npm's `latest` dist-tag was 1.0.0-beta.26. This is the first role here that installs with plain npm instead of mise.
**Outcome:** applied
**Ref:** roles/cloudflare/tasks/main.yml (this commit)

## Q52 — interactive/github-two-accounts — gate-resolution

**Question:** macbook-provision grew optional secondary-GitHub-account wiring in its github role (its Q309, commits 049c2b4 and c2e5a9f, 2026-10-31). Port it now or wait for the next sync?
**Options considered:** wait / port the two commits now
**Chosen:** Ported now, verbatim except the journal references in secondary.yml now name macbook-provision explicitly: `roles/github/tasks/secondary.yml`, its include in `tasks/main.yml` (gated on `GITHUB_SECONDARY_EMAIL`), and the `GITHUB_SSH_KEY` + `GITHUB_SECONDARY_*` blocks in `.env.example` (GITHUB_SSH_KEY was undocumented here although the role already forwarded it).
**Decided-by:** human
**Justification:** Frank asked for the sync in-session (2026-10-31). No Omarchy host sets the variables yet, so the role's behavior is unchanged everywhere (the include skips); the wiring is OS-agnostic and the dotenv role dequotes values the same way as upstream's. Not runnable on the Mac that authored it: verified by ansible syntax check only, so the first host to set GITHUB_SECONDARY_* should run the github role standalone first.
**Outcome:** applied
**Ref:** (pending); macbook-provision Q307–Q309
