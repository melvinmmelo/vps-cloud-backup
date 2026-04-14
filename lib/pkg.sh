# lib/pkg.sh — distro-agnostic package install helpers.

_PKG_UPDATED=0

pkg_update_once() {
    [[ $_PKG_UPDATED -eq 1 ]] && return 0
    case "$PKG_MGR" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            ;;
        dnf) dnf makecache -q >/dev/null 2>&1 || true ;;
        yum) yum makecache -q >/dev/null 2>&1 || true ;;
        *)
            err "Unknown package manager: $PKG_MGR"
            return 1
            ;;
    esac
    _PKG_UPDATED=1
}

# pkg_install pkg1 [pkg2 ...]
pkg_install() {
    pkg_update_once
    case "$PKG_MGR" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -y -qq "$@"
            ;;
        dnf) dnf install -y -q "$@" ;;
        yum) yum install -y -q "$@" ;;
    esac
}

# ensure_cmd COMMAND [PACKAGE]
# Installs PACKAGE (or COMMAND if PACKAGE omitted) if COMMAND is missing.
# Prefix COMMAND with `?` to make it best-effort (warn on failure, don't abort).
ensure_cmd() {
    local arg=$1
    local optional=0
    if [[ "$arg" == \?* ]]; then
        optional=1
        arg=${arg#\?}
    fi
    local cmd=$arg pkg=${2:-$arg}
    if command -v "$cmd" >/dev/null 2>&1; then
        log "$cmd already present — skipping"
        return 0
    fi
    log "Installing $pkg..."
    if ! pkg_install "$pkg"; then
        if [[ $optional -eq 1 ]]; then
            warn "Optional package $pkg failed to install — continuing."
            return 0
        fi
        return 1
    fi
}

# rclone is installed from the official script because distro packages are
# frequently months behind. This is the ONLY curl|bash in the whole project.
ensure_rclone() {
    if command -v rclone >/dev/null 2>&1; then
        log "rclone already present: $(rclone version 2>/dev/null | head -1)"
        return 0
    fi
    log "Installing rclone from https://rclone.org/install.sh (latest stable)..."
    curl -fsSL https://rclone.org/install.sh | bash
}
