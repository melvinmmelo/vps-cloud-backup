# lib/schedule.sh — schedule menu + systemd OnCalendar rendering.
#
# Offers four presets: every 3 days (default, monotonic), daily, weekly,
# or custom. Custom is validated with `systemd-analyze calendar`.

schedule_prompt() {
    ask_choice SCHEDULE_PRESET "Backup schedule" \
        "every3days|Every 3 days (recommended, monotonic timer)" \
        "daily|Daily at a specific time" \
        "weekly|Weekly on Sunday" \
        "custom|Custom (I'll type a systemd OnCalendar expression)"

    case "$SCHEDULE_PRESET" in
        every3days)
            # Monotonic timer — no time-of-day prompt. Keep RUNTIME empty
            # so schedule_timer_body's heredoc doesn't leak an unquoted
            # `:00` into an OnCalendar line.
            RUNTIME=""
            state_set RUNTIME ""
            ;;
        daily)
            ask_default RUNTIME "02:30" "Time of day (HH:MM, 24h)"
            ;;
        weekly)
            ask_default RUNTIME "03:00" "Time of day on Sunday (HH:MM, 24h)"
            ;;
        custom)
            while :; do
                ask_default SCHEDULE_CUSTOM "*-*-1/3 02:30:00" \
                    "systemd OnCalendar expression"
                if systemd-analyze calendar "$SCHEDULE_CUSTOM" >/dev/null 2>&1; then
                    break
                fi
                warn_code VCB-BOOT-070 "invalid OnCalendar: $SCHEDULE_CUSTOM"
                [[ $YES_MODE -eq 1 ]] && err_code VCB-BOOT-070 "cannot prompt in --yes mode"
                # Reset so the next ask_default shows the canonical sample
                # rather than the previous invalid value as the default.
                SCHEDULE_CUSTOM=""
            done
            ;;
    esac
}

# Emits the lines that belong in the [Timer] section for the chosen preset.
schedule_timer_body() {
    case "$SCHEDULE_PRESET" in
        every3days)
            cat <<EOF
OnBootSec=15min
OnUnitActiveSec=3d
Persistent=true
RandomizedDelaySec=600
Unit=vcb-backup.service
EOF
            ;;
        daily)
            cat <<EOF
OnCalendar=*-*-* ${RUNTIME}:00
Persistent=true
RandomizedDelaySec=300
Unit=vcb-backup.service
EOF
            ;;
        weekly)
            cat <<EOF
OnCalendar=Sun ${RUNTIME}:00
Persistent=true
RandomizedDelaySec=300
Unit=vcb-backup.service
EOF
            ;;
        custom)
            cat <<EOF
OnCalendar=${SCHEDULE_CUSTOM}
Persistent=true
RandomizedDelaySec=300
Unit=vcb-backup.service
EOF
            ;;
    esac
}

schedule_human_label() {
    case "$SCHEDULE_PRESET" in
        every3days) printf '%s\n' "every 3 days (first run ~15min after bootstrap)" ;;
        daily)      printf 'daily at %s\n' "$RUNTIME" ;;
        weekly)     printf 'Sunday at %s\n' "$RUNTIME" ;;
        custom)     printf 'custom: %s\n' "$SCHEDULE_CUSTOM" ;;
    esac
}
