# lib/backup_script.sh — render /usr/local/bin/vcb-backup.sh from the template.

install_backup_script() {
    local tmpl="${VCB_ROOT}/templates/backup.sh.tmpl"
    local remote_uri
    remote_uri=$(provider_call "$PROVIDER_NAME" remote_uri)

    # Union of filesystem + database (staging) + (future sources) paths.
    local combined_sources=""
    if [[ "${INCLUDE_FILESYSTEM:-y}" == "y" && -n "$SOURCES_STR" ]]; then
        combined_sources="$SOURCES_STR"
    fi
    if [[ "${INCLUDE_DATABASES:-n}" == "y" ]]; then
        combined_sources="${combined_sources:+$combined_sources }$STAGING_DIR"
    fi

    # A backup with zero sources would generate a vcb-backup.sh that calls
    # rclone on an empty path list — silently "succeeding" while uploading
    # nothing. Refuse to proceed so the user re-runs and picks a source.
    if [[ -z "$combined_sources" ]]; then
        err_code VCB-BOOT-005 \
            "no backup sources selected — enable at least filesystem or databases"
    fi

    local notify_enabled=0
    [[ -n "${SELECTED_NOTIFIERS:-}" ]] && notify_enabled=1

    log "Writing ${BACKUP_SCRIPT}"
    render_template "$tmpl" "$BACKUP_SCRIPT" \
        REMOTE_URI          "$remote_uri" \
        SOURCES_STR         "$combined_sources" \
        RETENTION_DAYS      "$RETENTION_DAYS" \
        BACKUP_MODE         "$BACKUP_MODE" \
        HOST                "$HOSTNAME_LC" \
        PUBLIC_IP           "$PUBLIC_IP" \
        LOG_PATH            "$BACKUP_LOG" \
        PROVIDER_NAME       "$PROVIDER_NAME" \
        INCLUDE_DATABASES   "${INCLUDE_DATABASES:-n}" \
        STAGING_DIR         "$STAGING_DIR" \
        DB_CONF             "$DB_CONF_FILE" \
        NOTIFY_ENABLED      "$notify_enabled" \
        NOTIFICATIONS_CONF  "$NOTIFICATIONS_CONF_FILE"

    chmod 755 "$BACKUP_SCRIPT"

    touch "$BACKUP_LOG"
    chmod 640 "$BACKUP_LOG"
}
