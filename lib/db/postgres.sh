# lib/db/postgres.sh — PostgreSQL auth probing and discovery.

db_postgres_configure() {
    if ! command -v psql >/dev/null 2>&1; then
        log "psql client not installed — skipping PostgreSQL"
        state_set POSTGRES_ENABLED 0
        return 0
    fi

    log "probing PostgreSQL auth methods..."
    POSTGRES_AUTH=""
    if sudo -n -u postgres psql -c "SELECT 1" >/dev/null 2>&1; then
        POSTGRES_AUTH=peer
        log "PostgreSQL: peer auth works via sudo -u postgres"
    elif [[ -r /root/.pgpass ]] && psql -h localhost -U postgres -c "SELECT 1" >/dev/null 2>&1; then
        POSTGRES_AUTH=pgpass
        log "PostgreSQL: ~/.pgpass works"
    else
        local tries=0
        while (( tries < 3 )); do
            ask_secret POSTGRES_PASSWORD "PostgreSQL postgres password (leave blank to skip)"
            if [[ -z "$POSTGRES_PASSWORD" ]]; then
                warn "PostgreSQL skipped by user"
                state_set POSTGRES_ENABLED 0
                return 0
            fi
            if PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U postgres -c "SELECT 1" >/dev/null 2>&1; then
                POSTGRES_AUTH=password
                break
            fi
            warn "PostgreSQL password rejected — try again"
            # `((tries++))` returns the pre-increment value (0) which
            # under `set -e` would kill the script on the first retry.
            tries=$((tries + 1))
        done
        if [[ -z "$POSTGRES_AUTH" ]]; then
            warn_code VCB-BOOT-051 "PostgreSQL credentials failed 3 times — skipping"
            state_set POSTGRES_ENABLED 0
            return 0
        fi
    fi

    state_set POSTGRES_ENABLED 1
    state_set POSTGRES_AUTH    "$POSTGRES_AUTH"
    state_set POSTGRES_USER    "postgres"
    state_set POSTGRES_HOST    "localhost"
    state_set POSTGRES_PORT    "5432"

    local dbs
    dbs=$(_postgres_list_databases)
    log "PostgreSQL databases found:"
    printf '  %s\n' $dbs >&2

    ask_default POSTGRES_EXCLUDE "" "PostgreSQL databases to EXCLUDE (blank = none)"
    ask_default POSTGRES_INCLUDE "" "PostgreSQL databases to INCLUDE (blank = all)"
}

_postgres_list_databases() {
    local sql="SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres'"
    case "$POSTGRES_AUTH" in
        peer)     sudo -u postgres psql -Atc "$sql" 2>/dev/null ;;
        pgpass)   psql -h localhost -U postgres -Atc "$sql" 2>/dev/null ;;
        password) PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U postgres -Atc "$sql" 2>/dev/null ;;
    esac | tr '\n' ' '
}
