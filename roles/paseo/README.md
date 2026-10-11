# paseo role

`paseo` installs upstream's server form, `@getpaseo/cli`, as a mise npm tool with Omarchy's stub
(grilling Q21, Q28). Every Omarchy host is always-on, so there is no desktop-app branch and no gate.
The mise role's `mise up` upgrades it with the other npm globals.

## The daemon

The role owns the `paseo-daemon` systemd user unit, the Mac role's LaunchAgent (DECISIONS Q176).
`files/paseo-daemon.service` runs `bash -lc 'exec paseo daemon run'` with `Restart=always`, and the
role enables and starts it on every run, including a unit someone stopped on purpose. It also turns
on the relay (`daemon.relay.enabled`, off by default): the daemon listens on 127.0.0.1 only, so the
relay is the only way a paired device reaches it. Pairing (`paseo daemon pair`) stays manual, because
the pairing link is a per-host secret.

- **`paseo` is launched by name, through a login shell, on purpose.** `~/.bashrc` exports the
  CLIProxyAPI variables above its interactive guard, and the agent CLIs the daemon spawns need them.
  Launching by name means every start runs whatever install is current.
- **A restart is reserved for three changes:** the unit file, the relay setting, and the daemon
  running a version other than mise's active one. The last covers the mise role's `mise up`, which
  runs before this role and leaves a daemon on code mise will prune after its grace period. The gate
  compares `daemonVersion` from `paseo daemon status --json` with `mise ls --json`, so it fires once
  per upgrade and never on a converged run. A restart kills the daemon's running agents, which is
  why `started` is the default.
- **An active unit is not a running daemon.** With `Restart=always` a daemon that fails on every
  start still shows as active while it loops, as archs-mac-mini's did for a week in 2026-09 (a stale,
  empty `~/.paseo/paseo.pid`). So after starting, the role asks `paseo daemon status --json` for up
  to 60 s. If the daemon is not `running`, it sets the host fact `paseo_daemon_down`, and a `main.yml`
  post_task fails the play on it, so the roles after paseo still run. The post_task is tagged
  `agent-multiplexer`, because untagged post_tasks are skipped in a tag-limited run.

## The paseo-bots plugin

The role installs `npm:@oliexe/paseo-bots` (DECISIONS Q192). Paseo ships with its global
`pluginsEnabled` switch off, and an installed plugin stays `disabled` until it is on, so the role turns
it on first, by the user's choice, made after reading Paseo's warning that plugins are unsandboxed
code. It applies the switch with `paseo reload`, not a unit restart, because a restart kills the
daemon's running agents. Both steps wait for the daemon to be running. The role installs the plugin
only when `paseo plugin ls` lacks it and never runs `paseo plugin update`, because each update trusts
new code. Run that by hand.
