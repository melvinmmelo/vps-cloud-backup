# lib/secure_conf.sh — helpers for writing config files with strict permissions.
#
# Every root-only config file goes through write_secure_conf to guarantee
# 0600 root:root regardless of umask. The stat check after write is the
# invariant the Python side asserts on read (see config._assert_safe_perms).

# write_secure_conf DEST < content
# Reads body from stdin, writes it to a tempfile, chmods 600, chowns root,
# atomic-renames to DEST, then stats to verify.
# The permission-check failure maps to VCB-BOOT-050 for db.conf and
# VCB-BOOT-060 for notifications.conf so docs/errors.md can point users at
# the right fix.
write_secure_conf() {
    local dest=$1
    local dir
    dir=$(dirname "$dest")
    mkdir -p "$dir"
    chmod 700 "$dir"

    local tmp
    tmp=$(mktemp "${dest}.XXXXXX")
    cat > "$tmp"
    chown root:root "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$dest"

    local perms owner code
    perms=$(stat -c '%a' "$dest")
    owner=$(stat -c '%u:%g' "$dest")
    if [[ "$perms" != "600" || "$owner" != "0:0" ]]; then
        case "$dest" in
            *notifications.conf) code=VCB-BOOT-060 ;;
            *)                   code=VCB-BOOT-050 ;;
        esac
        err_code "$code" "config file $dest has wrong permissions: $owner $perms"
    fi
}
