Ansible playbook that provisions an Omarchy (Arch Linux) host with pacman, yay, mise and the
agent installers. A port of macbook-provision; every host runs it on itself. Every Omarchy host
is an always-on server, so no role is gated on the machine.

## Commands

Run them from the repo root: `.env` and the single-role form both resolve against it.

```bash
./bootstrap.sh                                        # fresh host: passwordless sudo, Ansible
ansible-playbook main.yml                             # provision this machine
ansible-playbook main.yml --check                     # dry run
ansible localhost -m include_role -a name=<role>      # one role

# another host: a login shell, because Arch's bash reads ~/.bashrc only for interactive shells
ssh -o BatchMode=yes -o ConnectTimeout=15 <host> \
  'bash -lc "cd ~/github.com/soulmachine/omarchy-provision && git pull && ansible-playbook main.yml"'
```

## Every task

- **Runs per-host only.** `inventory` holds only `127.0.0.1 ansible_connection=local`. The roles
  read `lookup('env', 'HOME')`, which Ansible evaluates on the control node, so a fan-out would
  write one host's `$HOME` and `.env` onto every target. Reach other hosts with the ssh form above.
- **Upgrades are `omarchy-update -y`, once, in the `pacman` role** (DECISIONS Q2). Omarchy couples
  its migrations to the package upgrade, so no role runs `pacman -Syu`, `yay -Sua` or a tool's own
  updater. The `mise` role's `mise up` is the only other upgrade call, for single-role runs.
- **Self-update tasks: diff state, don't grep output.** A task that runs an installer measures a
  version, ledger or `mise ls --json` before and after, and sets `changed_when` on the difference.
- **The gateway files are read-only here.** `~/.local/bin/*-gw`, `/usr/bin/omarchy-agent` and the
  agents' gateway settings belong to `cliproxy-tier-host.py` in macbook-provision, run from
  mac-mini-m2. A role that needs `claude-gw` fails when it is missing, and never writes it.

## Read before you act

| Before you… | Read |
|---|---|
| add a role, or write or change any role's tasks | [docs/writing-roles.md](docs/writing-roles.md) |
| touch `.env`, a secret, `GITHUB_TOKEN`, `TYPESAFE_API_KEY`, or the `dotenv` role | [docs/secrets.md](docs/secrets.md) |
| change agent-reach, paseo, ponytail, tailscale or typesafe | that role's `roles/<name>/README.md`, where one exists |
