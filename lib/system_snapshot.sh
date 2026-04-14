# lib/system_snapshot.sh — pre-install system snapshot via timeshift.
#
# Sourced by bootstrap.sh. Called from phase_2b as a mandatory safety net
# before any package install or config write. If a bootstrap run breaks
# the system, the user runs `sudo timeshift --restore`, picks the snapshot
# whose comment contains the label below, and is back to the pre-install
# state. Not called by --reconfigure (reconfigure edits an existing
# install and does not warrant a fresh rollback point).

# Exposed to bootstrap.sh phase_10_summary. Empty means "no snapshot taken
# on this run" (e.g. the reconfigure path, which skips phase_2b).
SYSTEM_SNAPSHOT_LABEL=""

# system_snapshot_create
# If timeshift is already installed, creates an on-demand snapshot tagged
# with an identifying label. If timeshift is NOT installed, asks the user
# whether to install it first — installing adds a new system package plus
# its own scheduled-snapshot cron job, which the user may not want on a
# production VPS. Declining leaves SYSTEM_SNAPSHOT_LABEL empty and the
# bootstrap proceeds without a rollback safety net (the user is warned
# loudly). Fatal only on an install-accepted-but-failed or snapshot-create
# failure.
system_snapshot_create() {
    local label comment
    label="vcb-preinstall-$(date +%Y%m%d-%H%M%S)-${HOSTNAME_LC}"
    comment="vps-cloud-backup pre-install snapshot (${label})"

    if ! command -v timeshift >/dev/null 2>&1; then
        warn "timeshift is not installed on this system."
        warn "timeshift provides a rollback safety net: if the bootstrap"
        warn "breaks something, 'sudo timeshift --restore' reverts to the"
        warn "pre-install state. Installing it adds a new system package"
        warn "and its own scheduled-snapshot cron job."
        ask_yes_no _INSTALL_TIMESHIFT "y" \
            "Install timeshift now to create a pre-install snapshot?"
        if [[ "$_INSTALL_TIMESHIFT" != "y" ]]; then
            warn "Proceeding WITHOUT a pre-install snapshot. If the"
            warn "bootstrap breaks something you will have to roll it back"
            warn "manually (uninstall.sh + manual cleanup of any installed"
            warn "packages). Continue at your own risk."
            SYSTEM_SNAPSHOT_LABEL=""
            return 0
        fi
        ensure_cmd timeshift timeshift \
            || err_code VCB-BOOT-006 \
               "timeshift install failed — enable 'universe' (Debian/Ubuntu) or EPEL (RHEL) and retry"
    fi

    log "creating pre-install system snapshot: ${label}"
    # --tags O = "on-demand", which timeshift's scheduled rotation never
    # prunes. --yes skips the interactive confirmation. Timeshift writes
    # its own progress to stderr; we let it pass through.
    if ! timeshift --create --comments "${comment}" --tags O --yes >&2; then
        err_code VCB-BOOT-007 \
            "timeshift could not create snapshot — check disk space and 'sudo timeshift --check'"
    fi

    SYSTEM_SNAPSHOT_LABEL="${label}"
    log "snapshot created: ${label}"
    log "to restore later: sudo timeshift --list ; sudo timeshift --restore"
}
