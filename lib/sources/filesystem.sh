# lib/sources/filesystem.sh — file/directory source (the default).
#
# Filesystem is always-on in spirit: the user is expected to have at least
# one path to back up. But we still expose it through the source API so
# that a future "docker-volumes" source can coexist cleanly.

source_filesystem_label()       { printf '%s\n' "Filesystem paths"; }
source_filesystem_description() { printf '%s\n' "Directories / files on this VPS (configs, web roots, SQL dump dirs, ...)"; }
source_filesystem_deps()        { printf '%s\n' "tar"; }

source_filesystem_prompt_config() {
    ask_yes_no INCLUDE_FILESYSTEM "y" "Back up filesystem paths?"
    if [[ "$INCLUDE_FILESYSTEM" != "y" ]]; then
        SOURCES_STR=""
        state_set SOURCES_STR ""
        return 0
    fi

    ask_default SOURCES_STR "/etc /home /root /var/www" \
        "Paths to back up (space-separated, no spaces inside paths)"
}

source_filesystem_verify() {
    [[ "${INCLUDE_FILESYSTEM:-y}" != "y" ]] && return 0
    local p ok=0
    for p in $SOURCES_STR; do
        if [[ -e "$p" ]]; then
            ok=1
        else
            warn "filesystem source path does not exist: $p"
        fi
    done
    [[ $ok -eq 1 ]]
}

source_filesystem_contributes_paths() {
    [[ "${INCLUDE_FILESYSTEM:-y}" != "y" ]] && return 0
    printf '%s\n' "$SOURCES_STR"
}
