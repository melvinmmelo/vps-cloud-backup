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
# Ensures timeshift is installed, then creates an on-demand snapshot
# tagged with an identifying label. Fatal on failure — phase_2b is
# non-skippable by design.
system_snapshot_create() {
    local label comment
    label="vcb-preinstall-$(date +%Y%m%d-%H%M%S)-${HOSTNAME_LC}"
    comment="vps-cloud-backup pre-install snapshot (${label})"

    ensure_cmd timeshift timeshift \
        || err_code VCB-BOOT-006 \
           "timeshift install failed — enable 'universe' (Debian/Ubuntu) or EPEL (RHEL) and retry"

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
