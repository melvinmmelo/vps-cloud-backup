# lib/notifiers/gmail.sh — Gmail SMTP notifier via stdlib smtplib.
#
# Collects Gmail App Password credentials and writes them to
# /etc/vps-cloud-backup/notifications.conf (mode 0600). The actual send is
# handled by `python3 -m vcb_notify send ...` at runtime.

notifier_gmail_label()       { printf '%s\n' "Gmail"; }
notifier_gmail_description() { printf '%s\n' "Send alerts through a Gmail account using an App Password"; }
notifier_gmail_deps()        { printf '%s\n' "python3"; }

notifier_gmail_prompt_config() {
    log "Gmail requires an App Password (not your regular Gmail password)."
    log "See docs/notifiers/gmail.md for how to generate one."
    ask_default GMAIL_USER ""           "Gmail address (the SMTP login)"
    ask_secret  GMAIL_APP_PASSWORD      "Gmail App Password (16 characters, spaces allowed)"
    ask_default GMAIL_TO   "$GMAIL_USER" "Recipient address (default: same as GMAIL_USER)"
    ask_default GMAIL_FROM_NAME "vps-cloud-backup" "Display name on outgoing mail"

    ask_yes_no GMAIL_ALERT_SUCCESS "n" "Send notification on successful backups?"
    # failure notifications are always on — that's the whole point
    GMAIL_EVENTS="setup.completed backup.failure backup.partial"
    [[ "$GMAIL_ALERT_SUCCESS" == "y" ]] && GMAIL_EVENTS="$GMAIL_EVENTS backup.success"
    state_set GMAIL_EVENTS "$GMAIL_EVENTS"
}

notifier_gmail_verify() {
    log "Sending test notification via Gmail..."
    if PYTHONPATH=/usr/local/lib python3 -m vcb_notify \
            --config "$NOTIFICATIONS_CONF_FILE" test --provider gmail; then
        log "Gmail test notification sent OK"
        return 0
    fi
    warn "Gmail test notification failed — check docs/notifiers/gmail.md"
    return 1
}
