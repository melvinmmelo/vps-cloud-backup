# lib/systemd.sh — render and install the systemd service + timer.

install_systemd_units() {
    local service_tmpl="${VCB_ROOT}/templates/backup.service.tmpl"

    log "Writing ${BACKUP_SERVICE}"
    render_template "$service_tmpl" "$BACKUP_SERVICE" \
        BACKUP_SCRIPT "$BACKUP_SCRIPT"

    log "Writing ${BACKUP_TIMER}"
    _write_timer_unit

    systemctl daemon-reload || err_code VCB-BOOT-030 "systemctl daemon-reload failed"
    systemctl enable --now "${VCB_PREFIX}-backup.timer" \
        || err_code VCB-BOOT-031 "failed to enable ${VCB_PREFIX}-backup.timer"
    log "Timer enabled. Next run:"
    systemctl list-timers "${VCB_PREFIX}-backup.timer" --no-pager 2>/dev/null \
        | sed -n '1,3p' >&2 || true
}

# Writes the .timer unit based on SCHEDULE_PRESET (see lib/schedule.sh).
_write_timer_unit() {
    {
        printf '[Unit]\n'
        printf 'Description=vps-cloud-backup scheduled run — %s\n\n' "$(schedule_human_label)"
        printf '[Timer]\n'
        schedule_timer_body
        printf '\n[Install]\n'
        printf 'WantedBy=timers.target\n'
    } > "$BACKUP_TIMER"
}
