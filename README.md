# dotfiles

Personal workstation configuration for **Fedora**, **macOS**, and **Termux** — Zsh +
Oh My Zsh + Powerlevel10k, a curated CLI toolset, SSH client config, and an idempotent
bootstrap script.

This repository is **public**. Treat everything committed here as world-readable.

## Security model

| Belongs in this repo | Belongs outside this repo |
|---|---|
| Shell, editor, git *preferences* | Git name and email (`~/.gitconfig.local`) |
| Portable SSH client config | Private keys, host-specific SSH entries (`~/.ssh/config.local`) |
| Package and tool manifests | Tokens, kubeconfigs, vault passwords (`zsh/local.zsh`) |
| Desktop package snapshots | Desktop settings with account data (`gui/dconf.ini`) |

Rules:

- Never commit private keys, tokens, kubeconfigs, or vault data.
- Git identity is machine-local, not published. `~/.gitconfig` includes `~/.gitconfig.local`.
- Host-specific SSH entries go in `~/.ssh/config.local`, which is gitignored.
- Before publishing a fork or a new history, run `gitleaks detect` and review `git log -p`.

## Quick start

### Fedora

```bash
git clone https://github.com/InfiniteBlanK3T/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./bootstrap.sh --all
```

### macOS

```bash
xcode-select --install                          # git
git clone https://github.com/InfiniteBlanK3T/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./bootstrap.sh --all
```

Install Homebrew first if it is missing; the script does not install it for you.

### Termux

```bash
pkg install -y git
git clone https://github.com/InfiniteBlanK3T/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./bootstrap.sh --links --packages
```

Termux cannot run Docker, Terraform, or Kubernetes tooling. `--all` is intentionally not
recommended there; clone repositories only if you need the files on the device.

## What the bootstrap does

```
./bootstrap.sh              # symlinks + packages (prompts before sudo)
./bootstrap.sh --all        # symlinks + packages + clone Homelab repositories
./bootstrap.sh --links      # symlinks only
./bootstrap.sh --packages   # packages only
./bootstrap.sh --repos      # clone/fetch Homelab repositories only
./bootstrap.sh --check      # doctor: verify, change nothing
./bootstrap.sh --yes        # non-interactive sudo
./bootstrap.sh --strict     # with --check: warnings count as failures
```

It performs, in order:

1. Symlinks `~/.zshrc`, `~/.zprofile`, `~/.gitconfig`, `~/.p10k.zsh`, `~/.ssh/config`.
2. Creates `~/.gitconfig.local` (prompts for name/email), `zsh/local.zsh`, `~/.ssh/config.local`.
3. Installs packages: `dnf` + third-party repos on Fedora, `brew bundle` on macOS, `pkg` on Termux.
4. Sets Zsh as the default login shell on Fedora/macOS (Termux keeps its own init).
5. Installs the Bitwarden CLI, pinned `argocd`, the Nerd Font, Oh My Zsh and its plugins.
6. With `--all`, clones the Homelab wrapper and then the workspace repositories.

Properties:

- **Idempotent.** Re-running is safe; existing files are backed up to
  `~/.dotfiles-backup/<timestamp>/` with their relative paths preserved.
- **Not transactional.** Each step is independent; a failed step is reported and the run continues.
- **No secrets.** The script never logs in to a vault, fetches a secret, or writes a private key.
- **No destructive desktop changes.** GNOME settings are snapshotted, never applied.

After bootstrap, **log out and back in** (or run `exec zsh`) so the session switches from bash
to Zsh, then run `p10k configure` to personalise the prompt.

### Existing machine

Nothing is silently overwritten; files are backed up first. A safe sequence:

```bash
./bootstrap.sh --links             # symlinks only, no package installs or shell change
diff ~/.dotfiles-backup/<timestamp>/.zshrc ~/.dotfiles/zsh/.zshrc
# move machine-specific values into zsh/local.zsh
exec zsh
```

`--links` skips both package installation and the default-shell change. If Zsh is not your
login shell yet, run `chsh -s "$(command -v zsh)"` yourself.

## Manual steps after bootstrap

1. **SSH key for Gitea**

   ```bash
   cd ~/Documents/Homelab
   ./scripts/clone-all.sh --gen-key
   # paste the printed public key into Gitea -> Settings -> SSH / GPG Keys
   ```

2. **Bitwarden / Vaultwarden**

   ```bash
   bw config server https://vault.local.thomasvoishere.com
   bw login && bw sync
   export BW_SESSION="$(bw unlock --raw)"
   bw get item "Homelab kubeconfig (k3s)" --raw | jq -r '.notes' > ~/.kube/config-homelab-k3s
   chmod 600 ~/.kube/config-homelab-k3s
   bw lock
   ```

   Store shared credentials (kubeconfig, ArgoCD admin, Ansible vault password) in the vault.
   Generate private SSH keys per machine; store only the **public** key fingerprint and a
   workstation inventory note.

3. **Tailscale** — `sudo tailscale up` when off-LAN.

4. **VS Code** — sign in to Settings Sync; extensions and settings follow the account.

5. **Shell** — log out and back in, or `exec zsh`.

## Layout

```
bootstrap.sh
manifest/
  fedora-repos.sh        # third-party dnf repositories (idempotent)
  fedora-packages.txt    # curated package set
  fedora-flatpaks.txt
  macos/Brewfile
  termux-packages.txt
  binaries.tsv           # pinned standalone binaries + SHA-256
  npm-globals.txt
zsh/
  .zshrc .zprofile
  platform.zsh path.zsh env.zsh options.zsh history.zsh plugins.zsh
  p10k.zsh               # tracked Powerlevel10k config
  local.zsh.example
git/.gitconfig           # preferences + include of ~/.gitconfig.local
ssh/config               # Gitea host block only
ssh/config.local.example
gui/                     # snapshots, never applied automatically
```

## Zsh load order

```
.zshrc
  platform.zsh   # OS detection + package-manager environment
  path.zsh       # PATH (depends on OS_TYPE)
  env.zsh        # non-secret environment variables
  options.zsh    # setopt flags
  history.zsh    # history configuration
  plugins.zsh    # Oh My Zsh + tool hooks
  local.zsh      # machine-local overrides (untracked)
  ~/.p10k.zsh    # prompt configuration
```

## Prompt

Powerlevel10k configuration is tracked as `zsh/p10k.zsh` and symlinked to `~/.p10k.zsh`.
Re-run `p10k configure` to change it, then copy the result back into the repository:

```bash
cp ~/.p10k.zsh ~/.dotfiles/zsh/p10k.zsh
```

## Font

JetBrains Mono Nerd Font is installed automatically on Fedora and Termux. On macOS it comes
from the Brewfile cask. Select **JetBrainsMono Nerd Font** in your terminal preferences.

## Troubleshooting

**`setopt: command not found` / "Oh My Zsh can't be loaded from: bash"**
You are sourcing `~/.zshrc` from bash. It is a Zsh file. Start Zsh first:

```bash
exec zsh
```

**`chsh: ... is not a valid shell`**
Add Zsh to `/etc/shells`, then retry:

```bash
command -v zsh | sudo tee -a /etc/shells
chsh -s "$(command -v zsh)"
```

**`parse error near '\n'` in `zsh/local.zsh`**
`local.zsh` is copied from the example and is machine-local. Values containing `<`, `>` or
spaces must be quoted, e.g. `export KUBECONFIG="$HOME/.kube/config-<name>"`.

**`~/.ssh/config is not writable`**
The file is owned by another user (often root). Fix it, then re-run `--links`:

```bash
sudo chown "$(id -un):$(id -gn)" ~/.ssh/config
chmod 600 ~/.ssh/config
```

## Known limitations

- **macOS and Termux paths are untested** on real hardware at the time of writing. They are
  syntax-checked and doctor-checked only. Fedora is the verified target.
- `opencode` is installed with its upstream installer. That installer is downloaded and
  executed; review it if you need a fully pinned supply chain.
- `argocd` is a pinned standalone binary (`manifest/binaries.tsv`). Helm and k9s come from
  Fedora repositories on Fedora and Homebrew on macOS.

## Maintenance

- Add a package: edit the relevant manifest, then run `--packages` and `--check`.
- Add a repository: update `Homelab/scripts/clone-all.sh` and root `.gitignore` together.
- Rotate a credential: update the vault item and the workstation inventory note.
- Decommission a machine: remove its public key from Gitea/GitHub and mark the vault note.
