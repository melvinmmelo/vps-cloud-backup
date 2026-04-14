# lib/db_conf_writer.sh — render /etc/vps-cloud-backup/db.conf from runtime state.
#
# The Python dumper reads this file. The schema is documented in docs/errors.md
# (VCB-DUMP-001) and in CLAUDE.md.

write_db_conf() {
    [[ "${INCLUDE_DATABASES:-n}" == "y" ]] || return 0

    log "writing ${DB_CONF_FILE}"
    {
        printf '# %s %s — managed, edits may be overwritten on re-run.\n' "$VCB_NAME" "$VCB_VERSION"
        printf '# Contains credentials — must stay 0600 root:root.\n\n'

        printf 'STAGING_DIR=%q\n' "$STAGING_DIR"
        printf 'LOG_LEVEL=%q\n'   "INFO"
        printf 'STAMP_FORMAT=%q\n' "%Y-%m-%d_%H%M%S"
        printf '\n'

        printf '# --- MySQL ---\n'
        printf 'MYSQL_ENABLED=%q\n' "${MYSQL_ENABLED:-0}"
        if [[ "${MYSQL_ENABLED:-0}" == "1" ]]; then
            printf 'MYSQL_AUTH=%q\n'    "$MYSQL_AUTH"
            printf 'MYSQL_USER=%q\n'    "${MYSQL_USER:-root}"
            printf 'MYSQL_HOST=%q\n'    "${MYSQL_HOST:-localhost}"
            printf 'MYSQL_PORT=%q\n'    "${MYSQL_PORT:-3306}"
            printf 'MYSQL_INCLUDE=%q\n' "${MYSQL_INCLUDE:-}"
            printf 'MYSQL_EXCLUDE=%q\n' "${MYSQL_EXCLUDE:-}"
            [[ "$MYSQL_AUTH" == "password" && -n "${MYSQL_PASSWORD:-}" ]] && \
                printf 'MYSQL_PASSWORD=%q\n' "$MYSQL_PASSWORD"
        fi
        printf '\n'

        printf '# --- PostgreSQL ---\n'
        printf 'POSTGRES_ENABLED=%q\n' "${POSTGRES_ENABLED:-0}"
        if [[ "${POSTGRES_ENABLED:-0}" == "1" ]]; then
            printf 'POSTGRES_AUTH=%q\n'    "$POSTGRES_AUTH"
            printf 'POSTGRES_USER=%q\n'    "${POSTGRES_USER:-postgres}"
            printf 'POSTGRES_HOST=%q\n'    "${POSTGRES_HOST:-localhost}"
            printf 'POSTGRES_PORT=%q\n'    "${POSTGRES_PORT:-5432}"
            printf 'POSTGRES_INCLUDE=%q\n' "${POSTGRES_INCLUDE:-}"
            printf 'POSTGRES_EXCLUDE=%q\n' "${POSTGRES_EXCLUDE:-}"
            [[ "$POSTGRES_AUTH" == "password" && -n "${POSTGRES_PASSWORD:-}" ]] && \
                printf 'POSTGRES_PASSWORD=%q\n' "$POSTGRES_PASSWORD"
        fi
        printf '\n'

        printf '# --- SQLite ---\n'
        printf 'SQLITE_ENABLED=%q\n' "${SQLITE_ENABLED:-0}"
        if [[ "${SQLITE_ENABLED:-0}" == "1" ]]; then
            printf 'SQLITE_PATHS=%q\n' "${SQLITE_PATHS:-}"
        fi
    } | write_secure_conf "$DB_CONF_FILE"
}
