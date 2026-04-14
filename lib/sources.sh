# lib/sources.sh — source abstraction (filesystem paths, databases, ...).
#
# Sources are what GETS backed up. Destinations (lib/providers/) are where
# it goes. Sources and destinations are orthogonal.
#
# Each file under lib/sources/*.sh defines these functions:
#
#   source_<name>_label              human label
#   source_<name>_description        one-line summary
#   source_<name>_deps               space-separated tool deps
#   source_<name>_prompt_config      populates state keys including INCLUDE_<NAME>
#   source_<name>_verify             exit 0 if healthy
#   source_<name>_contributes_paths  echoes space-separated paths the backup
#                                    script should treat as sources
#
# Unlike destinations, sources are NOT mutually exclusive. The bootstrap asks
# yes/no for each source independently.

sources_list() {
    local file name
    shopt -s nullglob
    for file in "${VCB_LIB_DIR}/sources"/*.sh; do
        name=$(basename "$file" .sh)
        if declare -F "source_${name}_label" >/dev/null 2>&1; then
            printf '%s\n' "$name"
        fi
    done
    shopt -u nullglob
}

sources_has() {
    local name=$1 verb=$2
    declare -F "source_${name}_${verb}" >/dev/null 2>&1
}

sources_call() {
    local name=$1 verb=$2
    shift 2
    if ! sources_has "$name" "$verb"; then
        err "source '$name' does not implement '$verb'"
        return 1
    fi
    "source_${name}_${verb}" "$@"
}
