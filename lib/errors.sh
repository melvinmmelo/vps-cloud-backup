# lib/errors.sh — stable error codes for bash-side failures.
#
# Every error the bootstrap can raise has a code in the VCB-BOOT-xxx range
# so that logs can be grepped and docs/errors.md can cross-reference them.
# Keep this file in sync with docs/errors.md.

declare -gA VCB_ERROR_CODES=(
    [VCB-BOOT-001]="bootstrap must run as root"
    [VCB-BOOT-002]="unsupported distribution"
    [VCB-BOOT-003]="no supported package manager (apt/dnf/yum) found"
    [VCB-BOOT-004]="public IP detection failed on every backend"
    [VCB-BOOT-005]="required dependency could not be installed"
    [VCB-BOOT-010]="rclone config produced no remote"
    [VCB-BOOT-011]="rclone remote verification failed"
    [VCB-BOOT-020]="state file could not be read or has unsafe permissions"
    [VCB-BOOT-021]="state file could not be written"
    [VCB-BOOT-030]="systemd unit install failed"
    [VCB-BOOT-031]="systemd timer could not be enabled"
    [VCB-BOOT-040]="template rendering failed"
    [VCB-BOOT-050]="db.conf could not be written with correct permissions"
    [VCB-BOOT-051]="database client tool missing after install"
    [VCB-BOOT-060]="notifications.conf could not be written with correct permissions"
    [VCB-BOOT-070]="invalid OnCalendar expression"
    [VCB-BOOT-999]="unexpected error, see trap output"
)

# err_code CODE "human message"
# Prints the code + message to stderr in the standard error format and exits.
err_code() {
    local code=$1 msg=$2
    local known=${VCB_ERROR_CODES[$code]:-"(undocumented code)"}
    err "${code}: ${msg}"
    err "       reference: ${known}"
    err "       see docs/errors.md#${code,,}"
    exit 1
}

# warn_code CODE "human message"
# Same as err_code but warning-level, does not exit.
warn_code() {
    local code=$1 msg=$2
    warn "${code}: ${msg}"
}
