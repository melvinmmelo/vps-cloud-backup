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
RECONFIGURE_SECTION=""

# Sections accepted by --reconfigure. Order here is the order printed by
# `--reconfigure help`. Adding a new section means adding a case arm in
# run_reconfigure in bootstrap.sh.
VCB_RECONFIGURE_SECTIONS=(provider sources policy schedule notifier)

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
# Uses bash literal substitution (${content//needle/replacement}) so no
# character in VAL — including $, backtick, double-quote, newline, or
# sed metacharacters — can break out of the replacement or confuse the
# substitution engine. Note: VALs that happen to contain shell
# metacharacters still land verbatim in the output file, so callers
# writing to shell scripts must validate inputs at prompt time if the
# target context is unquoted.
#
# The substitution runs in a subshell so `shopt -u patsub_replacement`
# is local: bash 5.2+ enables that shopt by default, and with it a bare
# `&` in the replacement string expands to the matched pattern (e.g. a
# value of `foo&bar` becomes `foo@KEY@bar`). Disabling it makes every
# character in VAL land verbatim. On bash < 5.2 the option does not
# exist and `shopt -u` is a silent no-op, so the same code works there.
render_template() {
    local src=$1 dst=$2
    shift 2
    if [[ ! -r "$src" ]]; then
        err_code VCB-BOOT-040 "template not readable: $src"
    fi
    (
        shopt -u patsub_replacement 2>/dev/null || true
        local content key val
        content=$(<"$src") || exit 1
        while (($#)); do
            key=$1; val=$2; shift 2
            content=${content//@${key}@/${val}}
        done
        # $(<FILE) strips trailing newlines; restore one so the output
        # file ends cleanly (systemd units and shell scripts expect it).
        printf '%s\n' "$content"
    ) > "$dst" || err_code VCB-BOOT-040 "render failed: $src -> $dst"
}

parse_args() {
    while (($#)); do
        case "$1" in
            -y|--yes)              YES_MODE=1 ;;
            --force-reconfigure)   FORCE_RECONFIGURE=1 ;;
            --provider)            PROVIDER_OVERRIDE=$2; shift ;;
            --reconfigure)
                if (( $# < 2 )); then
                    err "--reconfigure requires a SECTION (use '--reconfigure help')"
                    exit 2
                fi
                RECONFIGURE_SECTION=$2
                shift
                if [[ "$RECONFIGURE_SECTION" == "help" || "$RECONFIGURE_SECTION" == "list" ]]; then
                    print_reconfigure_help
                    exit 0
                fi
                ;;
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
  --reconfigure SECTION    Only re-run the phases for SECTION, then re-render
                           the backup script and systemd units. Requires a
                           prior successful bootstrap. Use '--reconfigure help'
                           to list valid sections.
  --state-file PATH        Use an alternate state file (default: ${STATE_FILE}).
  -v, --version            Print version and exit.
  -h, --help               Print this help and exit.
EOF
}

print_reconfigure_help() {
    cat <<EOF
${VCB_NAME} ${VCB_VERSION} — --reconfigure sections

Re-run only the phases for a single section of a previously bootstrapped
install. Re-renders /usr/local/bin/vcb-backup.sh and the systemd units
when done.

Usage: sudo ./bootstrap.sh --reconfigure SECTION

Sections:
  provider    Pick a new destination or re-auth the current one.
              Runs: select provider, prompt config, install provider deps,
              configure rclone remote, verify.
  sources     Change which filesystem paths and databases are backed up.
              Runs: source select + db discovery, rewrite db.conf.
  policy      Change the destination folder, retention days, or backup mode
              (mirror vs snapshot). Does not touch the schedule.
  schedule    Change the OnCalendar schedule only.
  notifier    Pick a different notification channel or update its settings.
              Rewrites notifications.conf.

Examples:
  sudo ./bootstrap.sh --reconfigure schedule
  sudo ./bootstrap.sh --reconfigure provider
EOF
}

# Installed by bootstrap.sh before phases run.
core_install_trap() {
    set -E
    trap 'err "Failed at ${BASH_SOURCE[1]:-?}:${LINENO} (exit $?)"; exit 1' ERR
}
