# lib/detect.sh — environment detection (distro, package manager, public IP, cloud).
# Each function writes to a specific global. No side effects beyond that.

detect_distro() {
    if [[ ! -r /etc/os-release ]]; then
        err "/etc/os-release missing — unsupported system."
        return 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_VERSION="${VERSION_ID:-unknown}"
    DISTRO_NAME="${PRETTY_NAME:-$DISTRO_ID $DISTRO_VERSION}"
}

detect_pkgmgr() {
    if   command -v apt-get >/dev/null 2>&1; then PKG_MGR=apt
    elif command -v dnf     >/dev/null 2>&1; then PKG_MGR=dnf
    elif command -v yum     >/dev/null 2>&1; then PKG_MGR=yum
    else
        err "No supported package manager (apt/dnf/yum) found."
        return 1
    fi
}

detect_arch() {
    ARCH=$(uname -m)
}

detect_hostname() {
    HOSTNAME_LC=$(hostname)
}

detect_cloud() {
    CLOUD="Generic/VPS"
    local vendor=""
    if [[ -r /sys/class/dmi/id/sys_vendor ]]; then
        vendor=$(tr -d '\0' < /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
    fi
    case "$vendor" in
        *Amazon*|*amazon*) CLOUD="AWS EC2"; return 0 ;;
        *Google*|*google*) CLOUD="Google Cloud"; return 0 ;;
        *DigitalOcean*)    CLOUD="DigitalOcean"; return 0 ;;
    esac
    if curl -sf -m 1 http://169.254.169.254/latest/meta-data/ >/dev/null 2>&1; then
        CLOUD="AWS EC2"
    elif curl -sf -m 1 -H "Metadata-Flavor: Google" \
            http://metadata.google.internal/computeMetadata/v1/ >/dev/null 2>&1; then
        CLOUD="Google Cloud"
    fi
}

detect_public_ip() {
    PUBLIC_IP=""

    # AWS IMDSv2 (token-based)
    local token
    token=$(curl -s -X PUT -m 2 "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
    if [[ -n "$token" ]]; then
        PUBLIC_IP=$(curl -s -m 2 -H "X-aws-ec2-metadata-token: $token" \
            http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)
    fi

    # AWS IMDSv1 fallback
    [[ -z "$PUBLIC_IP" ]] && PUBLIC_IP=$(curl -s -m 2 \
        http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)

    # Google Cloud metadata
    [[ -z "$PUBLIC_IP" ]] && PUBLIC_IP=$(curl -s -m 2 -H "Metadata-Flavor: Google" \
        http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip \
        2>/dev/null || true)

    # Public fallbacks — force IPv4 first so we match what cloud dashboards show.
    # On a dual-stack host, curl's default is "whatever routes first," which
    # often ends up being IPv6 and echoes back an address that doesn't match
    # the user's mental model of "my VPS IP."
    [[ -z "$PUBLIC_IP" ]] && PUBLIC_IP=$(curl -4 -s -m 5 https://ifconfig.me 2>/dev/null || true)
    [[ -z "$PUBLIC_IP" ]] && PUBLIC_IP=$(curl -4 -s -m 5 https://api.ipify.org 2>/dev/null || true)

    # IPv6-only fallback — only reached if every IPv4 attempt above failed.
    [[ -z "$PUBLIC_IP" ]] && PUBLIC_IP=$(curl -6 -s -m 5 https://ifconfig.me 2>/dev/null || true)
    [[ -z "$PUBLIC_IP" ]] && PUBLIC_IP=$(curl -6 -s -m 5 https://api6.ipify.org 2>/dev/null || true)

    PUBLIC_IP=${PUBLIC_IP:-unknown}
}
