# lib/sources/database.sh — the database source.
#
# Driven by lib/db/{mysql,postgres,sqlite}.sh — one bash file per engine.
# Writes /etc/vps-cloud-backup/db.conf and installs the Python dumper.
# The generated backup script invokes `python3 -m vcb_dumper run` as the
# first step of every run when INCLUDE_DATABASES=1.
#
# DB_CONF_FILE and STAGING_DIR are owned by lib/core.sh; don't redefine.

DB_KNOWN_ENGINES=(mysql postgres sqlite)

source_database_label()       { printf '%s\n' "Databases on this VPS"; }
source_database_description() { printf '%s\n' "Dump MySQL / PostgreSQL / SQLite before upload (Python dumper)"; }

source_database_deps() {
    # Rclone is already installed by the destination. Here we only need
    # Python (always installed by phase 5) and the engine clients,
    # added as optional because not every VPS has every engine.
    printf '%s\n' "python3 ?mysql ?psql ?sqlite3"
}

source_database_prompt_config() {
    ask_yes_no INCLUDE_DATABASES "n" "Back up databases on this VPS (MySQL / PostgreSQL / SQLite)?"
    if [[ "$INCLUDE_DATABASES" != "y" ]]; then
        local eng
        for eng in "${DB_KNOWN_ENGINES[@]}"; do
            state_set "${eng^^}_ENABLED" 0
        done
        return 0
    fi

    # Source per-engine bash helpers.
    local eng
    for eng in "${DB_KNOWN_ENGINES[@]}"; do
        # shellcheck disable=SC1090
        source "${VCB_LIB_DIR}/db/${eng}.sh"
    done

    banner "Database discovery"
    # Iterating over DB_KNOWN_ENGINES means adding a new engine is a
    # drop-in: create lib/db/<name>.sh, define db_<name>_configure, then
    # add "<name>" to DB_KNOWN_ENGINES. No further edits here.
    for eng in "${DB_KNOWN_ENGINES[@]}"; do
        "db_${eng}_configure" \
            || warn_code VCB-BOOT-051 "${eng} config skipped"
    done
}

source_database_verify() {
    [[ "${INCLUDE_DATABASES:-n}" != "y" ]] && return 0
    [[ -r "$DB_CONF_FILE" ]] || return 1
}

source_database_contributes_paths() {
    [[ "${INCLUDE_DATABASES:-n}" != "y" ]] && return 0
    printf '%s\n' "$STAGING_DIR"
}
