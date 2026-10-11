#!/bin/bash
# Bootstrap an Omarchy host for the Ansible playbook: passwordless sudo and Ansible.
# Everything else (pacman packages, mise tools, the always-on settings) is the
# playbook's job. Idempotent. One sudo password prompt on a fresh host.
set -euo pipefail

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

if ! grep -qx 'ID=omarchy' /etc/os-release 2>/dev/null; then
  echo "This bootstrap is for Omarchy (ID=omarchy in /etc/os-release)." >&2
  exit 1
fi

# ---------------------------------------------------------------- Passwordless sudo
# `zz-` sorts the file after Omarchy's own /etc/sudoers.d drop-ins: sudo takes the last
# matching rule, so a later Omarchy file with a password rule cannot override this one
# (coding-agent Q358). `verifypw=any` makes `sudo -v` passwordless too: sudo's default
# needs a password for -v unless EVERY rule for the user is NOPASSWD, and Omarchy's
# asdcontrol rule is not. omarchy-update runs `sudo -v` through omarchy-update-stay-awake,
# so without that line an unattended update waits at a prompt forever (coding-agent Q367).
# `sudo test`: /etc/sudoers.d is not readable by the user on Arch.
log "Passwordless sudo"
SUDOERS_FILE="/etc/sudoers.d/zz-$(whoami)-nopasswd"
if ! sudo test -f "$SUDOERS_FILE"; then
  echo "Configuring passwordless sudo for $(whoami) (one-time password prompt)..."
  printf '%s ALL=(ALL) NOPASSWD: ALL\nDefaults:%s verifypw=any\n' "$(whoami)" "$(whoami)" |
    sudo tee "$SUDOERS_FILE" >/dev/null
  sudo chmod 0440 "$SUDOERS_FILE"
  if sudo visudo -cf "$SUDOERS_FILE"; then
    echo "DONE: passwordless sudo enabled for $(whoami)"
  else
    sudo rm -f "$SUDOERS_FILE"
    echo "REVERTED: validation failed, file removed" >&2
    exit 1
  fi
fi

# ------------------------------------------------------------------------ Ansible
# Arch's `ansible` package is the collections bundle (community.general included) on the
# system Python, which is also the interpreter Ansible's modules run under here
# (inventory: ansible_python_interpreter=auto_silent). No pip, no mise Python.
log "Ansible"
sudo pacman -S --needed --noconfirm ansible
ansible --version | head -1

log "Bootstrap complete"
cat <<'MSG'
Next steps:
  1. Optional: copy .env.example to .env, fill in the Tailscale key(s), then `direnv allow`
     once the direnv role has run (the dotenv role exports .env for every shell anyway).
  2. Run the playbook:
       ansible-playbook main.yml
MSG
