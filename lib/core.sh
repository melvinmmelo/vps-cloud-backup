# lib/core.sh — global state, traps, template renderer.
# Sourced by bootstrap.sh before any other lib file.

VCB_VERSION="0.1.0"
VCB_NAME="vps-cloud-backup"
VCB_PREFIX="vcb"

# Paths the bootstrap reads/writes. Override-able from the CLI via flags.
STATE_DIR="/etc/${VCB_NAME}"
STATE_FILE="${STATE_DIR}/bootstrap.env"
DB_CONF_FILE="${STATE_DIR}/db.conf"
NOTIFICATIONS_CONF_FILE="${STATE_DIR}/notifications.conf"
BACKUP_SCRIPT="/usr/local/bin/${VCB_PREFIX}-backup.sh"
BACKUP_SERVICE="/etc/systemd/system/${VCB_PREFIX}-backup.service"
BACKUP_TIMER="/etc/systemd/system/${VCB_PREFIX}-backup.timer"
BACKUP_LOG="/var/log/${VCB_PREFIX}-backup.log"
STAGING_DIR="/var/backups/vcb-staging"

# Repo layout — set by bootstrap.sh before sourcing the lib files.
VCB_ROOT="${VCB_ROOT:-}"
VCB_LIB_DIR="${VCB_LIB_DIR:-}"

# CLI-flag globals. Defaults set here; parse_args may override.
YES_MODE=0
FORCE_RECONFIGURE=0
PROVIDER_OVERRIDE=""

# Runtime globals populated by phases. Declared here so `set -u` is happy
# even if a phase skips setting one.
DISTRO_ID=""; DISTRO_VERSION=""; DISTRO_NAME=""
PKG_MGR=""; ARCH=""; HOSTNAME_LC=""; CLOUD=""; PUBLIC_IP=""
PROVIDER_NAME=""; REMOTE_NAME=""
SOURCES_STR=""; DEST=""; RETENTION_DAYS=""
SCHEDULE_PRESET=""; RUNTIME=""; SCHEDULE_CUSTOM=""
BACKUP_MODE=""
INCLUDE_FILESYSTEM=""; INCLUDE_DATABASES=""
MYSQL_ENABLED=""; MYSQL_AUTH=""; MYSQL_USER=""; MYSQL_HOST=""; MYSQL_PORT=""
MYSQL_INCLUDE=""; MYSQL_EXCLUDE=""; MYSQL_PASSWORD=""
POSTGRES_ENABLED=""; POSTGRES_AUTH=""; POSTGRES_USER=""; POSTGRES_HOST=""
POSTGRES_PORT=""; POSTGRES_INCLUDE=""; POSTGRES_EXCLUDE=""; POSTGRES_PASSWORD=""
SQLITE_ENABLED=""; SQLITE_PATHS=""
SELECTED_NOTIFIERS=""
GMAIL_USER=""; GMAIL_APP_PASSWORD=""; GMAIL_TO=""; GMAIL_FROM_NAME=""
GMAIL_EVENTS=""; GMAIL_ALERT_SUCCESS=""

require_root() {
    if [[ $EUID -ne 0 ]]; then
        err_code VCB-BOOT-001 "run as root:  sudo $0 $*"
    fi
}

# render_template SRC DEST KEY1 VAL1 KEY2 VAL2 ...
# Substitutes every @KEY@ in SRC with VAL, writes the result to DEST.
# Uses `|` as the sed delimiter; `|` and `&` in values are escaped so they
# cannot break out of the substitution.
render_template() {
    local src=$1 dst=$2
    shift 2
    if [[ ! -r "$src" ]]; then
        err_code VCB-BOOT-040 "template not readable: $src"
    fi
    local sed_args=() key val escaped
    while (($#)); do
        key=$1; val=$2; shift 2
        # Escape both the sed delimiter `|` and the replacement metacharacter `&`.
        escaped=${val//\\/\\\\}
        escaped=${escaped//&/\\&}
        escaped=${escaped//|/\\|}
        sed_args+=(-e "s|@${key}@|${escaped}|g")
    done
    sed "${sed_args[@]}" "$src" > "$dst" \
        || err_code VCB-BOOT-040 "sed failed while rendering $src -> $dst"
}

parse_args() {
    while (($#)); do
        case "$1" in
            -y|--yes)              YES_MODE=1 ;;
            --force-reconfigure)   FORCE_RECONFIGURE=1 ;;
            --provider)            PROVIDER_OVERRIDE=$2; shift ;;
            --state-file)          STATE_FILE=$2; STATE_DIR=$(dirname "$2"); shift ;;
            -v|--version)          printf '%s %s\n' "$VCB_NAME" "$VCB_VERSION"; exit 0 ;;
            -h|--help)             print_help; exit 0 ;;
            *)                     err "Unknown flag: $1"; print_help; exit 2 ;;
        esac
        shift
    done
}

print_help() {
    cat <<EOF
${VCB_NAME} ${VCB_VERSION}

Usage: sudo ./bootstrap.sh [flags]

Flags:
  -y, --yes                Accept all defaults from state file (non-interactive).
  --force-reconfigure      Re-run provider config even if a remote already exists.
  --provider NAME          Skip the provider menu, use this provider directly.
  --state-file PATH        Use an alternate state file (default: ${STATE_FILE}).
  -v, --version            Print version and exit.
  -h, --help               Print this help and exit.
EOF
}

# Installed by bootstrap.sh before phases run.
core_install_trap() {
    set -E
    trap 'err "Failed at ${BASH_SOURCE[1]:-?}:${LINENO} (exit $?)"; exit 1' ERR
}
