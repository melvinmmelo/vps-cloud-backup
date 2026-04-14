# lib/state.sh — persist answers between bootstrap runs.
# The state file is a plain shell-sourceable KEY=value file at /etc/vps-cloud-backup/bootstrap.env.
# Secrets are NEVER stored here — rclone owns those in ~/.config/rclone/rclone.conf.

# Load previous answers into the current shell. Called once, before the phases.
state_load() {
    if [[ -r "$STATE_FILE" ]]; then
        local perms owner
        perms=$(stat -c '%a' "$STATE_FILE" 2>/dev/null || echo "")
        owner=$(stat -c '%u:%g' "$STATE_FILE" 2>/dev/null || echo "")
        if [[ -n "$perms" && "$perms" != "600" ]] || \
           [[ -n "$owner" && "$owner" != "0:0" ]]; then
            err_code VCB-BOOT-020 \
                "state file $STATE_FILE must be 0600 root:root, found $owner $perms"
        fi
        # shellcheck disable=SC1090
        source "$STATE_FILE"
        log "Loaded previous answers from $STATE_FILE"
    fi
}

# state_set KEY VALUE
# Updates the in-memory copy and records the key for state_save.
# Keys named matching a known-secret pattern are refused entirely (no
# shell var, no state). Keys starting with _ (transient prompts like
# _NOTIFY_ON, _GO, _TEST) are assigned to the live shell but deliberately
# kept out of the persisted state file.
state_set() {
    local key=$1 val=$2
    case "$key" in
        *SECRET*|*PASSWORD*|*TOKEN*|*KEY_ID*|*ACCESS_KEY*)
            return 0
            ;;
    esac
    printf -v "$key" '%s' "$val"
    case "$key" in
        _*) return 0 ;;
    esac
    # shellcheck disable=SC2034
    VCB_STATE_KEYS[$key]=1
}

# Persistent set of known keys so state_save knows what to write.
declare -gA VCB_STATE_KEYS=()

# Called once, after a successful bootstrap run.
state_save() {
    mkdir -p "$STATE_DIR" || err_code VCB-BOOT-021 "cannot create $STATE_DIR"
    chmod 700 "$STATE_DIR"

    local tmp
    tmp=$(mktemp "${STATE_FILE}.XXXXXX") \
        || err_code VCB-BOOT-021 "cannot create temp file next to $STATE_FILE"
    {
        printf '# Managed by %s %s — edits may be overwritten on re-run.\n' "$VCB_NAME" "$VCB_VERSION"
        printf '# Secrets are NOT stored here; see rclone.conf.\n\n'
        local key
        for key in "${!VCB_STATE_KEYS[@]}"; do
            local val
            eval "val=\${$key:-}"
            printf '%s=%q\n' "$key" "$val"
        done | sort
    } > "$tmp" || err_code VCB-BOOT-021 "cannot write state to $tmp"

    chown root:root "$tmp" 2>/dev/null || true
    chmod 600 "$tmp"
    mv "$tmp" "$STATE_FILE" || err_code VCB-BOOT-021 "cannot rename $tmp -> $STATE_FILE"
    log "Saved answers to $STATE_FILE"
}
