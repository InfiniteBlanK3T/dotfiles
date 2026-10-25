#!/usr/bin/env bash
# Configure third-party dnf repositories used by fedora-packages.txt.
# Idempotent: skips repos whose .repo file already exists.
set -uo pipefail

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  SUDO="sudo"
fi

FAILED=0

add_repo() {
  local name="$1" url="$2"
  if [[ -f "/etc/yum.repos.d/${name}.repo" ]]; then
    printf '  [skip] %s repo already present\n' "$name"
    return 0
  fi
  printf '  [add]  %s\n' "$name"
  if ! $SUDO dnf config-manager addrepo \
      --from-repofile="$url" \
      --save-filename="${name}.repo" \
      --set=enabled=1 >/dev/null; then
    printf '  [fail] %s repo\n' "$name" >&2
    FAILED=1
  fi
}

add_repo docker-ce "https://download.docker.com/linux/fedora/docker-ce.repo"
add_repo hashicorp "https://rpm.releases.hashicorp.com/fedora/hashicorp.repo"
add_repo tailscale "https://pkgs.tailscale.com/stable/fedora/tailscale.repo"

if [[ ! -f /etc/yum.repos.d/vscode.repo ]]; then
  printf '  [key]  microsoft\n'
  $SUDO rpm --import https://packages.microsoft.com/keys/microsoft.asc || FAILED=1
fi
add_repo vscode "https://packages.microsoft.com/yumrepos/vscode/vscode.repo"

exit "$FAILED"
