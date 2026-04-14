# lib/notifications_writer.sh — render /etc/vps-cloud-backup/notifications.conf.
#
# Read by the Python notifier (vcb_notify). Must be 0600 root:root.

write_notifications_conf() {
    [[ -n "${SELECTED_NOTIFIERS:-}" ]] || return 0

    log "writing ${NOTIFICATIONS_CONF_FILE}"
    {
        printf '# %s %s — managed, edits may be overwritten on re-run.\n' "$VCB_NAME" "$VCB_VERSION"
        printf '# Contains credentials — must stay 0600 root:root.\n\n'

        printf 'HOST=%q\n'      "$HOSTNAME_LC"
        printf 'PUBLIC_IP=%q\n' "$PUBLIC_IP"
        printf '\n'

        local n
        for n in $SELECTED_NOTIFIERS; do
            case "$n" in
                gmail)
                    printf '# --- Gmail ---\n'
                    printf 'GMAIL_ENABLED=%q\n'        "1"
                    printf 'GMAIL_EVENTS=%q\n'         "${GMAIL_EVENTS:-}"
                    printf 'GMAIL_USER=%q\n'           "${GMAIL_USER:-}"
                    printf 'GMAIL_APP_PASSWORD=%q\n'   "${GMAIL_APP_PASSWORD:-}"
                    printf 'GMAIL_TO=%q\n'             "${GMAIL_TO:-${GMAIL_USER:-}}"
                    printf 'GMAIL_FROM_NAME=%q\n'      "${GMAIL_FROM_NAME:-vps-cloud-backup}"
                    printf 'GMAIL_HOST=%q\n'           "$HOSTNAME_LC"
                    printf 'GMAIL_PUBLIC_IP=%q\n'      "$PUBLIC_IP"
                    printf '\n'
                    ;;
                *)
                    warn "unknown notifier: $n (skipped in notifications.conf)"
                    ;;
            esac
        done
    } | write_secure_conf "$NOTIFICATIONS_CONF_FILE"
}
