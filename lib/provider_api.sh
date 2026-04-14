# lib/provider_api.sh — provider discovery + dispatch.
#
# A "provider" is a shell file under lib/providers/<name>.sh that defines a
# set of functions named provider_<name>_<verb>. The dispatcher never cares
# what's inside; it only calls those functions by name.
#
# REQUIRED functions every provider must define:
#
#   provider_<name>_label            # echoes human label (e.g. "Google Drive")
#   provider_<name>_description      # echoes one-sentence summary
#   provider_<name>_deps             # echoes required commands, space-separated
#   provider_<name>_rclone_backend   # echoes rclone backend name (or empty)
#   provider_<name>_prompt_config    # asks for config, populates globals via state_set
#   provider_<name>_configure        # creates/updates the rclone remote idempotently
#   provider_<name>_verify           # 0 if the remote is reachable
#   provider_<name>_remote_uri       # echoes "REMOTE:DEST/" used by the backup script
#
# OPTIONAL:
#
#   provider_<name>_uninstall_hint   # echoes extra cleanup notes for the summary
#   provider_<name>_credentials_doc  # echoes a path to a credentials walkthrough md

# Emits the names of available providers, one per line.
provider_list() {
    local file name
    shopt -s nullglob
    for file in "${VCB_LIB_DIR}/providers"/*.sh; do
        name=$(basename "$file" .sh)
        if declare -F "provider_${name}_label" >/dev/null 2>&1; then
            printf '%s\n' "$name"
        fi
    done
    shopt -u nullglob
}

# provider_has NAME VERB
# Returns 0 if provider_<NAME>_<VERB> is a defined function.
provider_has() {
    local name=$1 verb=$2
    declare -F "provider_${name}_${verb}" >/dev/null 2>&1
}

# provider_call NAME VERB [args...]
# Invokes provider_<NAME>_<VERB>. Errors out if the function is not defined
# AND the verb is known to be required.
provider_call() {
    local name=$1 verb=$2
    shift 2
    if ! provider_has "$name" "$verb"; then
        err "Provider '$name' does not implement '$verb'."
        return 1
    fi
    "provider_${name}_${verb}" "$@"
}

# Interactive provider selection. Sets PROVIDER_NAME.
provider_select_interactive() {
    local -a opts=()
    local name label
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        label=$(provider_call "$name" label 2>/dev/null || echo "$name")
        opts+=("${name}|${label}")
    done < <(provider_list)

    if [[ ${#opts[@]} -eq 0 ]]; then
        err "No providers registered. Check ${VCB_LIB_DIR}/providers/*.sh"
        return 1
    fi

    ask_choice PROVIDER_NAME "Pick a backup destination" "${opts[@]}"
}
