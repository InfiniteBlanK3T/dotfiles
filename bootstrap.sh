#!/usr/bin/env bash
# ============================================================
# bootstrap.sh — reproduce a workstation from this public repo
# ------------------------------------------------------------
# Safe on existing machines: files are backed up before being
# replaced, symlinks are idempotent, and package installation
# prompts before using sudo.
#
# Usage:
#   ./bootstrap.sh              # links + packages (prompts before sudo)
#   ./bootstrap.sh --all        # links + packages + clone Homelab repos
#   ./bootstrap.sh --links      # symlinks only
#   ./bootstrap.sh --packages   # packages only
#   ./bootstrap.sh --repos      # clone/fetch Homelab repos only
#   ./bootstrap.sh --check      # doctor: verify, change nothing
#   ./bootstrap.sh --yes        # non-interactive sudo
#   ./bootstrap.sh --strict     # with --check: warnings are failures
#   ./bootstrap.sh -h
#
# Secrets are never fetched or written by this script. It prints
# the manual Bitwarden/Vaultwarden restore steps at the end.
# ============================================================
set -uo pipefail

# Resolve the repo root even when this script is symlinked into ~/.local/bin.
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
DOTFILES="$(cd "$(dirname "$SOURCE")" && pwd)"

MODE_LINKS=0
MODE_PACKAGES=0
MODE_REPOS=0
MODE_CHECK=0
ASSUME_YES=0
STRICT=0
ANY_MODE=0

usage() {
  sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//'
}

while (($#)); do
  case "$1" in
    --links)    MODE_LINKS=1; ANY_MODE=1 ;;
    --packages) MODE_PACKAGES=1; ANY_MODE=1 ;;
    --repos)    MODE_REPOS=1; ANY_MODE=1 ;;
    --all)      MODE_LINKS=1; MODE_PACKAGES=1; MODE_REPOS=1; ANY_MODE=1 ;;
    --check)    MODE_CHECK=1; ANY_MODE=1 ;;
    --yes)      ASSUME_YES=1 ;;
    --strict)   STRICT=1 ;;
    -h|--help)  usage; exit 0 ;;
    *)          printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if (( MODE_CHECK )); then
  MODE_LINKS=0; MODE_PACKAGES=0; MODE_REPOS=0
elif (( ! ANY_MODE )); then
  MODE_LINKS=1
  MODE_PACKAGES=1
fi

if [[ -n "${TERMUX_VERSION:-}" ]]; then
  OS="termux"
elif [[ "$(uname -s)" == "Darwin" ]]; then
  OS="macos"
elif [[ -f /etc/fedora-release ]]; then
  OS="fedora"
else
  OS="unsupported"
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$HOME/.dotfiles-backup/$STAMP"
FAILED=0
WARNINGS=0

say()  { printf '%s\n' "$*"; }
ok()   { printf '  [ok]   %s\n' "$*"; }
warn() { printf '  [warn] %s\n' "$*" >&2; WARNINGS=$((WARNINGS + 1)); }
fail() { printf '  [fail] %s\n' "$*" >&2; FAILED=$((FAILED + 1)); }
die()  { printf 'error: %s\n' "$*" >&2; exit 2; }

have() { command -v "$1" >/dev/null 2>&1; }

confirm() {
  local prompt="$1"
  (( ASSUME_YES )) && return 0
  [[ -t 0 ]] || return 1
  local answer
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" == [yY]* ]]
}

read_list() {
  local file="$1" line
  LIST=()
  [[ -f "$file" ]] || return 0
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    LIST+=("$line")
  done < "$file"
}

# ------------------------------------------------------------
# Symlinks
# ------------------------------------------------------------
backup_file() {
  local dest="$1" rel target
  [[ -e "$dest" || -L "$dest" ]] || return 0
  if [[ ! -w "$dest" ]]; then
    fail "not writable: $dest"
    say "         fix with: sudo chown $(id -un):$(id -gn) $dest"
    return 1
  fi
  rel="${dest#"$HOME"/}"
  target="$BACKUP_DIR/$rel"
  mkdir -p "$(dirname "$target")"
  mv "$dest" "$target" && ok "backed up $dest -> $target"
}

safe_symlink() {
  local src="$1" dest="$2"
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    ok "$dest -> $src"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  backup_file "$dest" || return 1
  ln -s "$src" "$dest" && ok "linked $dest -> $src"
}

init_local_files() {
  if [[ ! -f "$DOTFILES/zsh/local.zsh" ]]; then
    cp "$DOTFILES/zsh/local.zsh.example" "$DOTFILES/zsh/local.zsh"
    ok "created zsh/local.zsh from example"
  fi

  if [[ ! -f "$HOME/.ssh/config.local" ]]; then
    cp "$DOTFILES/ssh/config.local.example" "$HOME/.ssh/config.local"
    chmod 600 "$HOME/.ssh/config.local"
    ok "created ~/.ssh/config.local"
  fi

  if [[ ! -f "$HOME/.gitconfig.local" ]]; then
    if [[ -t 0 ]]; then
      local git_name git_email
      read -r -p "Git author name: " git_name
      read -r -p "Git author email: " git_email
      printf '[user]\n\tname = %s\n\temail = %s\n' "$git_name" "$git_email" > "$HOME/.gitconfig.local"
      chmod 600 "$HOME/.gitconfig.local"
      ok "created ~/.gitconfig.local"
    else
      warn "create ~/.gitconfig.local with [user] name and email"
    fi
  fi
}

do_links() {
  say "==> Linking dotfiles ($OS)"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  safe_symlink "$DOTFILES/zsh/.zshrc"      "$HOME/.zshrc"
  safe_symlink "$DOTFILES/git/.gitconfig"  "$HOME/.gitconfig"
  safe_symlink "$DOTFILES/zsh/p10k.zsh"    "$HOME/.p10k.zsh"

  if [[ "$OS" != "termux" ]]; then
    safe_symlink "$DOTFILES/zsh/.zprofile" "$HOME/.zprofile"
  fi

  safe_symlink "$DOTFILES/ssh/config" "$HOME/.ssh/config"
  chmod 600 "$HOME/.ssh/config" 2>/dev/null || true

  mkdir -p "$HOME/.local/bin"
  safe_symlink "$DOTFILES/bin/bw-pull" "$HOME/.local/bin/bw-pull"

  init_local_files
}

# ------------------------------------------------------------
# Packages
# ------------------------------------------------------------
install_binaries() {
  local name version url sha dest tmp
  [[ -f "$DOTFILES/manifest/binaries.tsv" ]] || return 0
  while IFS='|' read -r name version url sha dest; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    dest="${dest/\$HOME/$HOME}"
    if [[ -x "$dest" ]] && "$dest" version --client 2>/dev/null | grep -q "$version"; then
      ok "$name $version already installed"
      continue
    fi
    say "  [get]  $name $version"
    tmp="$(mktemp)"
    if ! curl -fsSL "$url" -o "$tmp"; then
      fail "$name download failed"
      rm -f "$tmp"
      continue
    fi
    if ! printf '%s  %s\n' "$sha" "$tmp" | sha256sum -c - >/dev/null 2>&1; then
      fail "$name checksum mismatch"
      rm -f "$tmp"
      continue
    fi
    mkdir -p "$(dirname "$dest")"
    install -m 0755 "$tmp" "$dest" && ok "installed $name -> $dest"
    rm -f "$tmp"
  done < "$DOTFILES/manifest/binaries.tsv"
}

install_font() {
  local font_dir tmp
  case "$OS" in
    fedora)
      font_dir="$HOME/.local/share/fonts/JetBrainsMono"
      if [[ -d "$font_dir" ]] && [[ -n "$(ls -A "$font_dir" 2>/dev/null)" ]]; then
        ok "JetBrains Mono Nerd Font present"
        return 0
      fi
      tmp="$(mktemp -d)"
      if curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" -o "$tmp/font.zip"; then
        mkdir -p "$font_dir"
        unzip -oq "$tmp/font.zip" '*.ttf' -d "$font_dir" && fc-cache -f "$font_dir" >/dev/null 2>&1
        ok "installed JetBrains Mono Nerd Font"
      else
        warn "font download failed"
      fi
      rm -rf "$tmp"
      ;;
    termux)
      if [[ -f "$HOME/.termux/font.ttf" ]]; then
        ok "Termux font present"
        return 0
      fi
      tmp="$(mktemp -d)"
      if curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" -o "$tmp/font.zip"; then
        mkdir -p "$HOME/.termux"
        unzip -p "$tmp/font.zip" "JetBrainsMonoNerdFont-Regular.ttf" > "$HOME/.termux/font.ttf"
        ok "installed Termux font"
      else
        warn "font download failed"
      fi
      rm -rf "$tmp"
      ;;
    macos)
      ok "font is handled by the Brewfile cask"
      ;;
  esac
}

install_shell_stack() {
  local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    say "  [get]  Oh My Zsh"
    if ! RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; then
      fail "Oh My Zsh install failed"
    fi
  else
    ok "Oh My Zsh present"
  fi

  if [[ ! -d "$zsh_custom/themes/powerlevel10k" ]]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$zsh_custom/themes/powerlevel10k" >/dev/null 2>&1 \
      && ok "installed powerlevel10k" || fail "powerlevel10k clone failed"
  else
    ok "powerlevel10k present"
  fi

  if [[ ! -d "$zsh_custom/plugins/zsh-autosuggestions" ]]; then
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$zsh_custom/plugins/zsh-autosuggestions" >/dev/null 2>&1 \
      && ok "installed zsh-autosuggestions" || fail "zsh-autosuggestions clone failed"
  else
    ok "zsh-autosuggestions present"
  fi

  if [[ ! -d "$zsh_custom/plugins/zsh-syntax-highlighting" ]]; then
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$zsh_custom/plugins/zsh-syntax-highlighting" >/dev/null 2>&1 \
      && ok "installed zsh-syntax-highlighting" || fail "zsh-syntax-highlighting clone failed"
  else
    ok "zsh-syntax-highlighting present"
  fi
}

set_default_shell() {
  local zsh_bin current
  [[ "$OS" == "termux" ]] && return 0

  zsh_bin="$(command -v zsh || true)"
  if [[ -z "$zsh_bin" ]]; then
    warn "zsh not found; default shell unchanged"
    return 0
  fi

  current="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
  [[ -z "$current" ]] && current="${SHELL:-}"

  if [[ "$current" == "$zsh_bin" ]]; then
    ok "default shell is $zsh_bin"
    return 0
  fi

  if ! grep -qx "$zsh_bin" /etc/shells 2>/dev/null; then
    if (( ASSUME_YES )); then
      if ! printf '%s\n' "$zsh_bin" | sudo tee -a /etc/shells >/dev/null; then
        warn "could not add $zsh_bin to /etc/shells"
        return 0
      fi
    else
      warn "run: echo $zsh_bin | sudo tee -a /etc/shells && chsh -s $zsh_bin"
      return 0
    fi
  fi

  if chsh -s "$zsh_bin"; then
    ok "default shell changed to $zsh_bin"
  else
    warn "chsh failed; run: chsh -s $zsh_bin"
  fi
}

do_packages() {
  say "==> Packages ($OS)"

  case "$OS" in
    fedora)
      if ! confirm "Install Fedora packages and repositories (uses sudo)?"; then
        warn "packages skipped (pass --yes for non-interactive)"
        return 0
      fi
      bash "$DOTFILES/manifest/fedora-repos.sh" || fail "repository setup reported errors"

      read_list "$DOTFILES/manifest/fedora-packages.txt"
      if ((${#LIST[@]})); then
        if ! sudo dnf install -y "${LIST[@]}"; then
          fail "dnf install reported errors"
        fi
      fi

      if have flatpak; then
        sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
        read_list "$DOTFILES/manifest/fedora-flatpaks.txt"
        if ((${#LIST[@]})); then
          flatpak install -y flathub "${LIST[@]}" || warn "some flatpaks were not installed"
        fi
      else
        warn "flatpak is missing; skipping flatpaks"
      fi
      ;;

    macos)
      if ! have brew; then
        fail "Homebrew is required on macOS; install it first"
      elif confirm "Install macOS packages with Homebrew?"; then
        brew bundle --file "$DOTFILES/manifest/macos/Brewfile" || fail "brew bundle reported errors"
      else
        warn "packages skipped"
      fi
      ;;

    termux)
      if ! confirm "Install Termux packages (pkg)?"; then
        warn "packages skipped"
        return 0
      fi
      read_list "$DOTFILES/manifest/termux-packages.txt"
      if ((${#LIST[@]})); then
        pkg install -y "${LIST[@]}" || fail "pkg install reported errors"
      fi
      ;;

    *)
      warn "unsupported OS; install packages manually"
      return 0
      ;;
  esac

  if [[ "$OS" == "fedora" || "$OS" == "macos" ]]; then
    set_default_shell
  fi

  if have npm; then
    read_list "$DOTFILES/manifest/npm-globals.txt"
    if ((${#LIST[@]})); then
      local pkg
      for pkg in "${LIST[@]}"; do
        npm install -g --prefix "$HOME/.local" "$pkg" >/dev/null 2>&1 \
          && ok "npm: $pkg" || fail "npm install failed: $pkg"
      done
    fi
  fi

  if [[ "$OS" == "fedora" ]]; then
    install_binaries
  fi

  if ! have opencode; then
    if confirm "Install opencode (official installer)?"; then
      curl -fsSL https://opencode.ai/install | bash || fail "opencode install failed"
    else
      warn "opencode not installed"
    fi
  else
    ok "opencode present ($(opencode --version 2>/dev/null | head -1))"
  fi

  install_font
  install_shell_stack
}

# ------------------------------------------------------------
# Repos
# ------------------------------------------------------------
do_repos() {
  local homelab_dir="${HOMELAB_DIR:-$HOME/Documents/Homelab}"
  local gitea_url="${GITEA_URL_BASE:-https://gitea.local.thomasvoishere.com}"

  say "==> Homelab repositories ($homelab_dir)"

  if [[ -x "$homelab_dir/scripts/clone-all.sh" ]]; then
    bash "$homelab_dir/scripts/clone-all.sh" || warn "clone-all reported problems"
    return 0
  fi

  if [[ -d "$homelab_dir/.git" ]]; then
    warn "Homelab repo found but scripts/clone-all.sh is missing (pull it first)"
    return 0
  fi

  mkdir -p "$(dirname "$homelab_dir")"
  if ! git clone "$gitea_url/blank3t/Homelab.git" "$homelab_dir"; then
    fail "could not clone the Homelab wrapper repo"
    return 0
  fi
  ok "cloned Homelab wrapper"

  if [[ -x "$homelab_dir/scripts/clone-all.sh" ]]; then
    bash "$homelab_dir/scripts/clone-all.sh" || warn "clone-all reported problems"
  fi
}

# ------------------------------------------------------------
# Doctor
# ------------------------------------------------------------
CHECK_FAIL=0
CHECK_WARN=0
c_ok()   { printf '  [ok]   %s\n' "$*"; }
c_warn() { printf '  [warn] %s\n' "$*"; CHECK_WARN=$((CHECK_WARN + 1)); }
c_fail() { printf '  [fail] %s\n' "$*"; CHECK_FAIL=$((CHECK_FAIL + 1)); }

check_link() {
  local dest="$1" src="$2"
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    c_ok "$dest"
  else
    c_fail "$dest is not linked to $src"
  fi
}

do_check() {
  say "==> Doctor ($OS)"

  check_link "$HOME/.zshrc" "$DOTFILES/zsh/.zshrc"
  check_link "$HOME/.gitconfig" "$DOTFILES/git/.gitconfig"
  check_link "$HOME/.p10k.zsh" "$DOTFILES/zsh/p10k.zsh"
  if [[ "$OS" != "termux" ]]; then
    check_link "$HOME/.zprofile" "$DOTFILES/zsh/.zprofile"
  fi
  if [[ -e "$HOME/.ssh/config" ]]; then
    if [[ -L "$HOME/.ssh/config" && "$(readlink "$HOME/.ssh/config")" == "$DOTFILES/ssh/config" ]]; then
      c_ok "$HOME/.ssh/config"
    else
      c_warn "$HOME/.ssh/config is not managed by dotfiles (root-owned?)"
    fi
  else
    c_fail "$HOME/.ssh/config is missing"
  fi

  if [[ -f "$HOME/.gitconfig.local" ]] && git config --get user.email >/dev/null 2>&1; then
    c_ok "git identity: $(git config --get user.email)"
  else
    c_fail "git identity missing (create $HOME/.gitconfig.local)"
  fi

  if git config --global --path --get-all include.path 2>/dev/null | grep -qxF "$HOME/.gitconfig.local"; then
    c_ok "gitconfig includes $HOME/.gitconfig.local"
  else
    c_fail "$HOME/.gitconfig does not include $HOME/.gitconfig.local"
  fi

  if [[ -f "$HOME/.ssh/id_ed25519_personal" ]]; then
    c_ok "personal SSH key present"
    local mode
    mode="$(stat -c '%a' "$HOME/.ssh/id_ed25519_personal" 2>/dev/null || stat -f '%Lp' "$HOME/.ssh/id_ed25519_personal" 2>/dev/null || true)"
    [[ "$mode" == "600" ]] || c_warn "SSH key mode is ${mode:-unknown}, expected 600"
  else
    c_warn "personal SSH key missing (run clone-all.sh --gen-key)"
  fi

  if [[ -e "$HOME/.ssh/config" ]] && [[ ! -w "$HOME/.ssh/config" ]]; then
    c_fail "$HOME/.ssh/config is not writable (sudo chown $(id -un):$(id -gn) $HOME/.ssh/config)"
  fi

  local c
  for c in git zsh nvim bw opencode; do
    if have "$c"; then
      c_ok "$c"
    else
      c_warn "$c missing"
    fi
  done

  if [[ -d "$HOME/.config/opencode/node_modules/@opencode-ai/plugin" ]]; then
    c_ok "opencode plugin dependency"
  else
    c_warn "opencode plugin dependency missing (run Homelab-Learning install script)"
  fi

  if [[ -x "$HOME/.local/bin/bw-pull" ]]; then
    c_ok "bw-pull helper"
  else
    c_warn "bw-pull missing (run bootstrap.sh --links)"
  fi

  local homelab_dir="${HOMELAB_DIR:-$HOME/Documents/Homelab}"
  local repo missing=0
  for repo in Homelab-Automation Homelab-Doc Homelab-GitOps Homelab-Learning Homelab-Stacks Homelab-Terraform MLOps/MLOps.GenAI-Gateway MLOps/MLOps.Model-Delivery-Platform; do
    [[ -d "$homelab_dir/$repo/.git" ]] || { c_warn "repo missing: $repo"; missing=1; }
  done
  (( missing == 0 )) && c_ok "all workspace repos present"

  if [[ -f "$HOME/.kube/config-homelab-k3s" ]]; then
    local kmode
    kmode="$(stat -c '%a' "$HOME/.kube/config-homelab-k3s" 2>/dev/null || stat -f '%Lp' "$HOME/.kube/config-homelab-k3s" 2>/dev/null || true)"
    [[ "$kmode" == "600" ]] && c_ok "kubeconfig present (600)" || c_warn "kubeconfig mode is ${kmode:-unknown}, expected 600"
  else
    c_warn "kubeconfig missing (~/.kube/config-homelab-k3s)"
  fi

  if have bw; then
    local bw_status
    bw_status="$(timeout 4 bw status 2>/dev/null | sed -n 's/.*"status":"\([^"]*\)".*/\1/p' | head -1)"
    case "$bw_status" in
      unlocked) c_ok "Bitwarden unlocked" ;;
      locked)   c_warn "Bitwarden locked (bw unlock)" ;;
      *)        c_warn "Bitwarden not logged in (bw login)" ;;
    esac
  else
    c_warn "bw CLI missing"
  fi

  if have tailscale; then
    if tailscale status >/dev/null 2>&1; then
      c_ok "Tailscale connected"
    else
      c_warn "Tailscale not connected"
    fi
  fi

  say ""
  say "==> Doctor summary: failures=$CHECK_FAIL warnings=$CHECK_WARN"
  if (( CHECK_FAIL > 0 )); then
    return 1
  fi
  if (( STRICT )) && (( CHECK_WARN > 0 )); then
    return 1
  fi
  return 0
}

# ------------------------------------------------------------
# Manual checklist
# ------------------------------------------------------------
print_manual() {
  say ""
  say "==> Manual steps (never automated)"
  say "    1. SSH key in Gitea:  ./scripts/clone-all.sh --gen-key"
  say "    2. Bitwarden:"
  say "         bw config server https://vault.local.thomasvoishere.com"
  say "         bw login && bw sync"
  say "         export BW_SESSION=\"\$(bw unlock --raw)\""
  say "         bw-pull attachment \"Homelab/kubeconfig-k3s\" kubeconfig-k3s.yaml ~/.kube/config-homelab-k3s"
  say "         bw-pull note \"Homelab/ansible-vault-pass\" ~/.ansible-vault-pass"
  say "         bw lock; unset BW_SESSION"
  say "    3. Tailscale: tailscale up (if off-LAN)"
  say "    4. VS Code: sign in to Settings Sync"
  say "    5. Start a new shell: exec zsh"
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
say "dotfiles: $DOTFILES"
say "os:       $OS"

if (( MODE_CHECK )); then
  if do_check; then
    exit 0
  fi
  exit 1
fi

(( MODE_LINKS ))    && do_links
(( MODE_PACKAGES )) && do_packages
(( MODE_REPOS ))    && do_repos

print_manual

say ""
if (( FAILED > 0 )); then
  say "==> Completed with $FAILED failure(s), $WARNINGS warning(s)"
  exit 1
fi
say "==> Completed with $WARNINGS warning(s)"
exit 0
