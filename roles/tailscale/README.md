# tailscale role

**Scope:** Tailscale is only a network layer here (private mesh + MagicDNS). The role does not enable
Tailscale SSH; standard OpenSSH handles remote shells. That is why there is no `--ssh` flag, no tag
advertisement and no ACL `tagOwners` management.

- **An online node with its extras ends the role at once.** The first tasks run
  `tailscale status --json` and stat `~/.local/share/applications/Tailscale.desktop`, the web app
  that is the installer's last step. On rc 0 with `BackendState: Running` and that file present,
  `meta: end_role` skips everything below: the package, the service, `tailscale up`, the extras and
  key-expiry. Key-expiry therefore runs only on a run that starts offline or without the extras, in
  practice the enrolment run. To re-apply it on an online node, run the API calls by hand or
  `tailscale down` first. Same as macbook-provision Q295.
- **Omarchy owns the install.** `omarchy-install-service-tailscale` installs the package, enables
  `tailscaled`, runs `tailscale up`, sets `--operator=$USER`, enables Taildrop receiving into
  `~/Downloads`, adds the bar plugin and the admin-console web app. Its `tailscale up` carries no
  auth key, so on an unenrolled host it prints a login URL and waits for a browser. The role never
  runs it in that state: on a host without the package it installs `tailscale` from the repo, starts
  `tailscaled`, enrols the node with `TAILSCALE_AUTH_KEY`, and only then runs Omarchy's installer
  for the extras. There the installer's own `tailscale up --accept-routes` is refused at once for not
  restating `--operator` (the script does not stop on it) and the rest of the script runs. Without
  an auth key on such a host, the role reports the hand-run `tailscale up` and goes on rather than
  hang. The installer runs on any play that finds the web app missing and the node Running, so a
  host enrolled by hand gets the extras on its next play.
- **Auto-login when `TAILSCALE_AUTH_KEY` is set.** The role runs `tailscale up --accept-dns
  --accept-routes --operator=$USER --auth-key=...` under `become: true`, skipped when the node is
  already `BackendState: Running`. `tailscale up` rejects a call that drops a previously set
  non-default flag (it needs `--reset` or every non-default flag restated), so the role lists every
  non-default flag the daemon was last brought up with.
- **Key-expiry disable takes an OAuth client and nothing else.** With `TAILSCALE_OAUTH_CLIENT_ID` and
  `TAILSCALE_OAUTH_CLIENT_SECRET` both set, the role form-`POST`s them to `/api/v2/oauth/token` (no
  `grant_type`; Tailscale's documented curl omits it), reads `Self.ID` from `tailscale status --json`,
  and `POST`s `keyExpiryDisabled: true` to `/api/v2/device/{id}/key`. The bearer token lives exactly
  one hour. The client needs only the `devices:core` scope.
  - **No personal access token.** A PAT carries no scopes and expires after 90 days, which made this
    task a 401 on a timer. An OAuth client secret does not expire, belongs to the tailnet, and is
    revocable alone.
  - **Half a pair fails the play.** A half-configured host would otherwise silently skip key-expiry
    disable and drift back to expiring keys.
- **The two credentials gate different halves of the role, deliberately unchained.**
  `TAILSCALE_AUTH_KEY` enrols the node once; the OAuth client authenticates control-plane calls
  ongoing. The key-expiry block reads `Self.ID` first, before minting a token, and no-ops with a
  note when there is none: an unenrolled machine is a legitimate mid-setup state. It also no-ops
  when the client gets 403 or 404 for the node, which means the node is on another tailnet than the
  client.
- **The key-expiry POST is gated on a read.** `GET /api/v2/device/{id}?fields=all` returns
  `keyExpiryDisabled` (only with `?fields=all`), and the POST is skipped when it is already `true`.
- **The OAuth and device-read `uri` tasks carry `check_mode: false`;** the final POST does not, so it
  stays skipped under `--check`.
