# platform.zsh — sourced first, sets OS_TYPE and platform-specific env
case "$(uname -s)" in
  Darwin)
    export OS_TYPE="macos"
    # Guard: login shells already ran brew shellenv via .zprofile — avoid double PATH entries
    [[ -z "$HOMEBREW_PREFIX" ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
    ;;
  Linux)
    # Termux runs on Linux but needs its own prefix; detect it first
    if [[ -n "${TERMUX_VERSION:-}" ]]; then
      export OS_TYPE="termux"
      export PATH="${PREFIX}/bin:$PATH"
    else
      export OS_TYPE="linux"
      export PATH="$HOME/.local/bin:$PATH"
    fi
    ;;
esac
