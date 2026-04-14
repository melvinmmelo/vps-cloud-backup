# lib/db/sqlite.sh — SQLite path discovery.
#
# SQLite has no auth. "Discovery" is finding candidate *.sqlite, *.sqlite3,
# *.db files on common paths and letting the user confirm.

db_sqlite_configure() {
    if ! command -v sqlite3 >/dev/null 2>&1; then
        log "sqlite3 CLI not installed — skipping SQLite"
        state_set SQLITE_ENABLED 0
        return 0
    fi

    log "scanning for SQLite databases (this may take a moment)..."
    local candidates
    candidates=$(find /var/lib /srv /opt /var/www /home -maxdepth 4 \
        \( -name '*.sqlite' -o -name '*.sqlite3' -o -name '*.db' \) \
        -type f 2>/dev/null | head -20 | tr '\n' ' ')

    if [[ -n "$candidates" ]]; then
        log "candidate SQLite files:"
        for f in $candidates; do
            printf '  %s\n' "$f" >&2
        done
    else
        log "no SQLite files auto-detected — you can still paste paths manually"
    fi

    ask_default SQLITE_PATHS "$candidates" \
        "SQLite file paths to back up (space-separated, blank = skip SQLite)"

    if [[ -z "$SQLITE_PATHS" ]]; then
        state_set SQLITE_ENABLED 0
        return 0
    fi
    state_set SQLITE_ENABLED 1
}
