# orca role

[Orca](https://onorca.dev) is an IDE that runs coding agents across worktrees. The Mac role puts
the desktop app on MacBooks and the Orca server on always-on Macs. Every Omarchy host is always-on,
so every host gets the app and the server (DECISIONS Q26, macbook-provision Q243).

## The AUR package

Orca has no separate server package. The CLI and `orca serve` ship inside the app. Frank asked for
the AUR package `stably-orca-bin`, the first AUR package since Q10. It extracts upstream's AppImage to
`/opt/stably-orca`, so it needs no FUSE. The role installs it with `yay -S --needed --noconfirm`
when `pacman -Q` lacks it. `omarchy-update -y` in the pacman role upgrades it. The package adds only
a GUI wrapper, `/usr/bin/stably-orca`. The CLI is `/opt/stably-orca/resources/bin/orca-ide` and is
not on PATH, so the role calls it by full path and passes the same path as `--command` to the
service installer.

## The server

The role does not write its own unit. It runs upstream's `orca-ide serve service install --port
6768`, which writes, enables and restarts the systemd user unit `orca-serve.service`. That unit runs
`orca-ide serve --supervise --no-pairing`. The supervisor restarts the server with growing delays
and waits while an update replaces the app, so an `omarchy-update` needs no restart from the role.
After 6 failures in 15 minutes it gives up. `serve service install` is also what clears a
supervisor that gave up.

- **It installs only when `serve service status --json` is not `live`.** A reinstall restarts the
  server and kills its sessions. A change of flags (port, address, PATH) needs a manual reinstall.
- **Port 6768 is fixed,** so paired clients keep their address across restarts.
- **It advertises the host's Tailscale IPv4** (`tailscale ip -4`) with `--pairing-address`, so a
  pairing offer names an address that macbook-pro-m3 reaches. It is an IP, not a MagicDNS name,
  because one fleet host answers `*.ts.net` from a fake-IP resolver. Without Tailscale, the role
  leaves the flag out.
- **It runs through `bash -lc`.** The unit pins the PATH it was installed with, and the agent CLIs
  the server spawns live on mise's shims.
- **An active unit is not a live server.** After installing, the role polls the status for up to 60
  s. If the server is not `live`, it sets `orca_serve_down`, and a `main.yml` post_task tagged
  `agent-multiplexer` fails the play after the other roles have run.
- **Orca 1.4.224 has no `serve service`.** The subcommand and `--supervise` landed upstream on
  2026-10-12 (stablyai/orca #27716, #27744), after the latest release. Until a release has them, the
  CLI answers `invalid_argument`, and the role skips the server with a message instead of failing.

## By hand

- **Pairing.** The service never prints a pairing link. When the Orca app is open on the server,
  pair from it: Settings → Remote Orca Servers → Advertise this app as a server → **New Link**,
  pick the `100.x.y.z` address, then **Generate Access Link**. Otherwise, on the server, with
  `cli=/opt/stably-orca/resources/bin/orca-ide`:
  1. `$cli serve service uninstall`, which frees the profile.
  2. `$cli serve --port 6768 --pairing-address <tailscale-ip>` in a terminal. It prints a pairing link.
  3. On the client, paste the link into **Add Server**, or run
     `orca environment add --name <host> --pairing-code '<link>'`.
  4. Ctrl+C the server, then `$cli serve service install --port 6768 --command $cli
     --pairing-address <tailscale-ip>`.

  The link is a secret: do not paste it into a file or a chat. Do not run step 2 while the app
  serves the same profile, because `serve` then exits with code 3. Each client gets its own
  grant: revoke one in the server's app under **Shared Server Access**. A new link replaces the
  last unused one. If the client shows the server as Disconnected, click **Connect**.
- **Agent accounts and skills** must be set up in the server's own shell, because a paired client
  disables Add account, and remote sessions use the server's PATH, home and logins:
  `$cli account add --agent claude|codex`, `$cli skills install --skill orca-cli --skill
  orchestration`, and later `$cli skills update --all`.

Source for the steps: <https://www.onorca.dev/docs/remote-servers>.
