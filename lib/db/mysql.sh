# lib/db/mysql.sh — MySQL / MariaDB auth probing and discovery.
#
# Called by lib/sources/database.sh. Populates MYSQL_* state keys
# (everything non-secret) and sets $MYSQL_PASSWORD in the running shell
# when a password had to be prompted (it never enters state).

db_mysql_configure() {
    if ! command -v mysql >/dev/null 2>&1; then
        log "mysql client not installed — skipping MySQL"
        state_set MYSQL_ENABLED 0
        return 0
    fi

    log "probing MySQL auth methods..."
    MYSQL_AUTH=""
    if mysql --protocol=socket -u root -e "SELECT 1" >/dev/null 2>&1; then
        MYSQL_AUTH=socket
        log "MySQL: socket auth works (no password needed)"
    elif [[ -r /root/.my.cnf ]] && mysql --defaults-file=/root/.my.cnf -e "SELECT 1" >/dev/null 2>&1; then
        MYSQL_AUTH=my_cnf
        log "MySQL: /root/.my.cnf works"
    else
        local tries=0
        while (( tries < 3 )); do
            ask_secret MYSQL_PASSWORD "MySQL root password (leave blank to skip MySQL)"
            if [[ -z "$MYSQL_PASSWORD" ]]; then
                warn "MySQL skipped by user"
                state_set MYSQL_ENABLED 0
                return 0
            fi
            if MYSQL_PWD="$MYSQL_PASSWORD" mysql -u root -h localhost -e "SELECT 1" >/dev/null 2>&1; then
                MYSQL_AUTH=password
                break
            fi
            warn "MySQL password rejected — try again"
            # `((tries++))` returns the pre-increment value (0) which
            # under `set -e` kills the script before the loop finishes.
            tries=$((tries + 1))
        done
        if [[ -z "$MYSQL_AUTH" ]]; then
            warn_code VCB-BOOT-051 "MySQL credentials failed 3 times — skipping MySQL"
            state_set MYSQL_ENABLED 0
            return 0
        fi
    fi

    state_set MYSQL_ENABLED 1
    state_set MYSQL_AUTH    "$MYSQL_AUTH"
    state_set MYSQL_USER    "root"
    state_set MYSQL_HOST    "localhost"
    state_set MYSQL_PORT    "3306"

    # Discover and let the user pick.
    local dbs
    dbs=$(_mysql_list_databases)
    log "MySQL databases found:"
    printf '  %s\n' $dbs >&2

    ask_default MYSQL_EXCLUDE "" "MySQL databases to EXCLUDE (space-separated, blank = none)"
    ask_default MYSQL_INCLUDE "" "MySQL databases to INCLUDE (blank = all, wins over exclude)"
}

_mysql_list_databases() {
    # Passwords are passed exclusively via MYSQL_PWD so they never appear on
    # argv and eval never interpolates them (no single-quote injection).
    case "$MYSQL_AUTH" in
        socket)
            mysql --protocol=socket -u root -N -B -e 'SHOW DATABASES' 2>/dev/null
            ;;
        my_cnf)
            mysql --defaults-file=/root/.my.cnf -N -B -e 'SHOW DATABASES' 2>/dev/null
            ;;
        password)
            MYSQL_PWD="$MYSQL_PASSWORD" \
                mysql -u root -h localhost -N -B -e 'SHOW DATABASES' 2>/dev/null
            ;;
    esac | grep -Ev '^(mysql|information_schema|performance_schema|sys)$' || true
}
