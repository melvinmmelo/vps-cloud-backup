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

    # Accept IPv4 or IPv6 only. Rejects injected HTML, header lines,
    # shell metacharacters, and anything else a hijacked public echo
    # service could return.
    local ipv4_re='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    local ipv6_re='^[0-9a-fA-F:]+$'

    # AWS IMDSv2 (token-based). IMDS uses HTTP at 169.254.169.254 by design
    # — AWS does not publish a TLS endpoint for link-local metadata, so
    # this is not a downgrade.
    local token
    token=$(curl -sf -X PUT -m 2 "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
    if [[ -n "$token" ]]; then
        PUBLIC_IP=$(curl -sf -m 2 -H "X-aws-ec2-metadata-token: $token" \
            http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)
    fi

    # AWS IMDSv1 fallback (older AMIs without IMDSv2).
    [[ -z "$PUBLIC_IP" ]] && PUBLIC_IP=$(curl -sf -m 2 \
        http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)

    # Google Cloud metadata
    [[ -z "$PUBLIC_IP" ]] && PUBLIC_IP=$(curl -sf -m 2 -H "Metadata-Flavor: Google" \
        http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip \
        2>/dev/null || true)

    # Public fallbacks — force IPv4 first so we match what cloud dashboards show.
    # On a dual-stack host, curl's default is "whatever routes first," which
    # often ends up being IPv6 and echoes back an address that doesn't match
    # the user's mental model of "my VPS IP."
    local candidate
    _public_ip_try() {
        [[ -z "$PUBLIC_IP" ]] || return 0
        candidate=$(curl "$1" -sf -m 5 "$2" 2>/dev/null || true)
        # Strip trailing whitespace/CR the echo services sometimes append.
        candidate=${candidate//[$'\r\n\t ']/}
        if [[ "$candidate" =~ $ipv4_re ]] || [[ "$candidate" =~ $ipv6_re && ${#candidate} -le 45 ]]; then
            PUBLIC_IP=$candidate
        fi
    }

    _public_ip_try -4 https://ifconfig.me
    _public_ip_try -4 https://api.ipify.org
    # IPv6-only fallback — only reached if every IPv4 attempt above failed.
    _public_ip_try -6 https://ifconfig.me
    _public_ip_try -6 https://api6.ipify.org

    unset -f _public_ip_try

    # Final sanity check — IMDS / GCP metadata usually returns a clean IP,
    # but belt-and-suspenders against a spoofed link-local response that
    # would otherwise land in notification email subjects.
    if [[ -n "$PUBLIC_IP" ]]; then
        PUBLIC_IP=${PUBLIC_IP//[$'\r\n\t ']/}
        if ! [[ "$PUBLIC_IP" =~ $ipv4_re ]] && ! [[ "$PUBLIC_IP" =~ $ipv6_re && ${#PUBLIC_IP} -le 45 ]]; then
            warn "discarding malformed public IP reply"
            PUBLIC_IP=""
        fi
    fi
    PUBLIC_IP=${PUBLIC_IP:-unknown}
}
