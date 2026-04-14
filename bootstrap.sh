#!/usr/bin/env bash
#
# vps-cloud-backup / bootstrap.sh
#
# One-shot installer for automated cloud backups on a fresh Linux VPS.
# Clone the repo, run `sudo ./bootstrap.sh`, answer a few prompts.
#
#   sudo ./bootstrap.sh [-y] [--force-reconfigure] [--provider NAME]
#
# See README.md for the full walkthrough.
set -euo pipefail

# Locate ourselves so sourced libs can find siblings regardless of cwd.
VCB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VCB_LIB_DIR="${VCB_ROOT}/lib"
export VCB_ROOT VCB_LIB_DIR

# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/core.sh"
# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/log.sh"
# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/errors.sh"
# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/state.sh"
# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/prompt.sh"
# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/secure_conf.sh"
# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/detect.sh"
# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/pkg.sh"
# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/provider_api.sh"
# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/sources.sh"
# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/notifier_api.sh"
# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/schedule.sh"
# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/python_install.sh"
# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/db_conf_writer.sh"
# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/notifications_writer.sh"
# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/systemd.sh"
# shellcheck disable=SC1091
source "${VCB_LIB_DIR}/backup_script.sh"

# Destination providers, sources, notifiers — directory-scan discovery.
shopt -s nullglob
for _f in "${VCB_LIB_DIR}/providers"/*.sh; do
    # shellcheck disable=SC1090
    source "$_f"
done
for _f in "${VCB_LIB_DIR}/sources"/*.sh; do
    # shellcheck disable=SC1090
    source "$_f"
done
for _f in "${VCB_LIB_DIR}/notifiers"/*.sh; do
    # shellcheck disable=SC1090
    source "$_f"
done
shopt -u nullglob

core_install_trap
parse_args "$@"
require_root "$@"
state_load

# ============================================================================
# Phase 1 — detect environment
# ============================================================================
phase_1_detect() {
    banner "Detecting environment"
    detect_distro   || err_code VCB-BOOT-002 "cannot identify distribution"
    detect_pkgmgr   || err_code VCB-BOOT-003 "no supported package manager"
    detect_arch
    detect_hostname
    ensure_cmd curl curl
    detect_cloud
    detect_public_ip
    [[ "$PUBLIC_IP" == "unknown" ]] && warn_code VCB-BOOT-004 "public IP unknown"
}

phase_2_confirm_env() {
    cat >&2 <<EOF

  Hostname        : ${HOSTNAME_LC}
  Public IP       : ${PUBLIC_IP}
  Distro          : ${DISTRO_NAME}
  Architecture    : ${ARCH}
  Package manager : ${PKG_MGR}
  Cloud           : ${CLOUD}

EOF
    ask_yes_no _GO "y" "Proceed with these values?"
    [[ "$_GO" == "n" ]] && { warn "aborted by user"; exit 0; }
}

# ============================================================================
# Phase 3 — pick destination provider
# ============================================================================
phase_3_select_provider() {
    banner "Pick a backup destination"
    if [[ -n "$PROVIDER_OVERRIDE" ]]; then
        state_set PROVIDER_NAME "$PROVIDER_OVERRIDE"
        log "using --provider $PROVIDER_NAME"
    else
        provider_select_interactive
    fi
    log "destination: $PROVIDER_NAME"
}

phase_4_provider_prompt() {
    banner "Destination configuration ($PROVIDER_NAME)"
    provider_call "$PROVIDER_NAME" prompt_config
}

# ============================================================================
# Phase 5 — install base dependencies (before provider configure, before sources)
# ============================================================================
phase_5_install_deps() {
    banner "Installing base dependencies"
    ensure_cmd tar     tar     || err_code VCB-BOOT-005 "tar install failed"
    ensure_cmd python3 python3 || err_code VCB-BOOT-005 "python3 install failed"
    local provider_deps
    provider_deps=$(provider_call "$PROVIDER_NAME" deps || true)
    local d
    for d in $provider_deps; do
        case "$d" in
            rclone) ensure_rclone || err_code VCB-BOOT-005 "rclone install failed" ;;
            *)      ensure_cmd "$d" "$d" || err_code VCB-BOOT-005 "$d install failed" ;;
        esac
    done
}

# ============================================================================
# Phase 5b — select which sources to include (fs + db are both optional-ish)
# ============================================================================
phase_5b_source_select() {
    banner "Sources"
    # Run prompt_config for every known source. Each source's prompt_config
    # is responsible for setting its own INCLUDE_<NAME> gate.
    local name
    for name in $(sources_list); do
        sources_call "$name" prompt_config
    done
}

# Install engine client tools only if the database source was enabled.
phase_5c_source_deps() {
    [[ "${INCLUDE_DATABASES:-n}" == "y" ]] || return 0
    banner "Installing database client tools"
    # Per-engine best-effort installs; missing clients cause that engine
    # to be skipped in phase_7b_db_discover.
    case "$PKG_MGR" in
        apt)
            pkg_install mysql-client   || warn "mysql-client install failed (ok if you don't use MySQL)"
            pkg_install postgresql-client || warn "postgresql-client install failed (ok if you don't use Postgres)"
            pkg_install sqlite3        || warn "sqlite3 install failed (ok if you don't use SQLite)"
            ;;
        dnf|yum)
            $PKG_MGR install -y -q mysql || warn "mysql install failed"
            $PKG_MGR install -y -q postgresql || warn "postgresql install failed"
            $PKG_MGR install -y -q sqlite || warn "sqlite install failed"
            ;;
    esac
}

# ============================================================================
# Phase 6 — configure the destination remote and verify
# ============================================================================
phase_6_configure_remote() {
    banner "Configuring remote ($PROVIDER_NAME)"
    provider_call "$PROVIDER_NAME" configure \
        || err_code VCB-BOOT-010 "$PROVIDER_NAME configure failed"
    provider_call "$PROVIDER_NAME" verify \
        || err_code VCB-BOOT-011 "$PROVIDER_NAME verify failed"
    log "destination is reachable."
}

# ============================================================================
# Phase 7 — collect top-level backup config (DEST, retention, mode)
# ============================================================================
# Split into two functions so --reconfigure policy and --reconfigure schedule
# can target them independently. The full-bootstrap flow runs both in sequence.
phase_7_collect_backup_config() {
    banner "Backup policy"

    local slug
    slug=$(printf '%s_%s' "$HOSTNAME_LC" "$PUBLIC_IP" | tr -c 'A-Za-z0-9._-' '_')

    ask_default DEST "backups/${slug}" "Destination folder on the remote"
    ask_default RETENTION_DAYS "30"    "Retention in days (older archives auto-deleted)"
    ask_choice  BACKUP_MODE "Backup mode" \
        "mirror|Mirror files as-is (recommended for SQL dumps)" \
        "snapshot|Timestamped tar.gz archive (recommended for system configs)"
}

phase_7a_schedule() {
    banner "Schedule"
    schedule_prompt
}

# ============================================================================
# Phase 7c — write db.conf  (if databases enabled)
# Phase 7d — pick and configure notification channels
# ============================================================================
phase_7c_write_db_conf() {
    write_db_conf
}

phase_7d_notifiers() {
    banner "Notifications"
    ask_yes_no _NOTIFY_ON "y" "Enable failure notifications?"
    if [[ "$_NOTIFY_ON" != "y" ]]; then
        SELECTED_NOTIFIERS=""
        state_set SELECTED_NOTIFIERS ""
        return 0
    fi

    local name opts=()
    for name in $(notifier_list); do
        local label
        label=$(notifier_call "$name" label)
        opts+=("$name|$label")
    done

    if [[ ${#opts[@]} -eq 0 ]]; then
        warn "no notifier plugins found under lib/notifiers/"
        SELECTED_NOTIFIERS=""
        state_set SELECTED_NOTIFIERS ""
        return 0
    fi

    # For v1 we only have Gmail. When more are added the user gets a menu;
    # for now we auto-select the one channel and prompt its config.
    if [[ ${#opts[@]} -eq 1 ]]; then
        SELECTED_NOTIFIERS=${opts[0]%%|*}
        log "auto-selecting sole notifier: $SELECTED_NOTIFIERS"
    else
        ask_choice SELECTED_NOTIFIERS "Notification channel" "${opts[@]}"
    fi

    notifier_call "$SELECTED_NOTIFIERS" prompt_config
    state_set SELECTED_NOTIFIERS "$SELECTED_NOTIFIERS"

    write_notifications_conf
}

# ============================================================================
# Phase 8 — install Python packages + backup script + systemd units
# ============================================================================
phase_8_install_artifacts() {
    banner "Installing artifacts"
    # Python packages must be in place before we render the backup script
    # and certainly before phase_9 tries to run it.
    install_python_packages
    install_backup_script
    install_systemd_units
}

# ============================================================================
# Phase 9 — optional first run, optional test notification
# ============================================================================
phase_9_enable_and_test() {
    banner "First run"

    if [[ -n "${SELECTED_NOTIFIERS:-}" ]]; then
        notifier_call "$SELECTED_NOTIFIERS" verify \
            || warn "notifier test failed — check your App Password and docs/notifiers/${SELECTED_NOTIFIERS}.md"
    fi

    ask_yes_no _TEST "y" "Run a test backup right now?"
    if [[ "$_TEST" == "y" ]]; then
        log "triggering ${VCB_PREFIX}-backup.service..."
        systemctl start "${VCB_PREFIX}-backup.service" || true
        sleep 2
        log "last 40 log lines:"
        tail -n 40 "$BACKUP_LOG" 2>/dev/null || true
    fi
}

# ============================================================================
# Phase 10 — print summary
# ============================================================================
phase_10_summary() {
    cat >&2 <<EOF

${_C_GREEN}${_C_BOLD}Bootstrap complete.${_C_RESET}

  backup script    : ${BACKUP_SCRIPT}
  systemd unit     : ${BACKUP_SERVICE}
  systemd timer    : ${BACKUP_TIMER}
  schedule         : $(schedule_human_label)
  log file         : ${BACKUP_LOG}
  destination      : ${PROVIDER_NAME} -> ${DEST}
  db dumper        : $([[ "${INCLUDE_DATABASES:-n}" == "y" ]] && echo "enabled, $DB_CONF_FILE" || echo "disabled")
  notifications    : $([[ -n "${SELECTED_NOTIFIERS:-}" ]] && echo "$SELECTED_NOTIFIERS, $NOTIFICATIONS_CONF_FILE" || echo "disabled")
  state            : ${STATE_FILE}

Useful commands:
  systemctl list-timers ${VCB_PREFIX}-backup.timer
  systemctl start  ${VCB_PREFIX}-backup.service    # run one now
  systemctl status ${VCB_PREFIX}-backup.service
  journalctl -u ${VCB_PREFIX}-backup.service -n 50
  tail -f ${BACKUP_LOG}

To uninstall everything:
  sudo ./uninstall.sh

Docs:
  README.md             — user guide
  docs/errors.md        — every VCB-* error code, cause, and fix
  docs/credentials/     — per-provider and per-engine credential walkthroughs
  CLAUDE.md             — coding standards for contributors / AI agents
EOF
}

# ============================================================================
# --reconfigure dispatcher: re-run just the phases for one section, then
# re-render the backup script + systemd units. Requires prior state.
# Adding a section: update VCB_RECONFIGURE_SECTIONS in lib/core.sh AND add
# a case arm below AND document it in print_reconfigure_help.
# ============================================================================
run_reconfigure() {
    local section=$1 s valid=0
    for s in "${VCB_RECONFIGURE_SECTIONS[@]}"; do
        [[ "$s" == "$section" ]] && { valid=1; break; }
    done
    if (( ! valid )); then
        err "unknown --reconfigure section: '${section}'"
        err "valid sections: ${VCB_RECONFIGURE_SECTIONS[*]}"
        err_code VCB-BOOT-080 "unknown reconfigure section '${section}'"
    fi
    if [[ ! -r "$STATE_FILE" ]]; then
        err_code VCB-BOOT-080 \
            "no prior state at $STATE_FILE — run a full bootstrap first"
    fi

    # Environment detection is always needed so template rendering in
    # phase_8 has HOSTNAME_LC / PUBLIC_IP / PKG_MGR available.
    phase_1_detect

    case "$section" in
        provider)
            phase_3_select_provider
            phase_4_provider_prompt
            phase_5_install_deps
            phase_6_configure_remote
            ;;
        sources)
            phase_5b_source_select
            phase_5c_source_deps
            phase_7c_write_db_conf
            ;;
        policy)
            phase_7_collect_backup_config
            ;;
        schedule)
            phase_7a_schedule
            ;;
        notifier)
            phase_7d_notifiers
            ;;
    esac

    phase_8_install_artifacts
    phase_10_summary
    state_save
    log "reconfigure(${section}) complete"
}

# ----------------------------------------------------------------------------
# Run all phases.
# ----------------------------------------------------------------------------
if [[ -n "$RECONFIGURE_SECTION" ]]; then
    run_reconfigure "$RECONFIGURE_SECTION"
    exit 0
fi

phase_1_detect
phase_2_confirm_env
phase_3_select_provider
phase_4_provider_prompt
phase_5_install_deps
phase_5b_source_select
phase_5c_source_deps
phase_6_configure_remote
phase_7_collect_backup_config
phase_7a_schedule
phase_7c_write_db_conf
phase_7d_notifiers
phase_8_install_artifacts
phase_9_enable_and_test
phase_10_summary
state_save

# One-time setup notification.
if [[ -n "${SELECTED_NOTIFIERS:-}" ]]; then
    PYTHONPATH=/usr/local/lib python3 -m vcb_notify \
        --config "$NOTIFICATIONS_CONF_FILE" \
        send --event setup.completed --severity info \
        --subject "vps-cloud-backup installed on $HOSTNAME_LC" \
        --body "Bootstrap finished at $(date -Is). Next backup: $(schedule_human_label)." \
        --context "host=$HOSTNAME_LC" --context "ip=$PUBLIC_IP" >/dev/null 2>&1 || true
fi
