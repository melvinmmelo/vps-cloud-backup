# lib/notifier_api.sh — notification channel abstraction.
#
# Mirrors lib/provider_api.sh but for notification channels (Gmail, Telegram,
# Slack, ...). Unlike destinations, notifiers are multi-select: the user
# can enable zero, one, or many simultaneously.
#
# Each file under lib/notifiers/*.sh defines:
#
#   notifier_<name>_label
#   notifier_<name>_description
#   notifier_<name>_deps
#   notifier_<name>_prompt_config     populates state + NOTIFY_CFG_* runtime vars
#   notifier_<name>_configure          writes to notifications.conf
#   notifier_<name>_verify             sends a test notification

notifier_list() {
    local file name
    shopt -s nullglob
    for file in "${VCB_LIB_DIR}/notifiers"/*.sh; do
        name=$(basename "$file" .sh)
        if declare -F "notifier_${name}_label" >/dev/null 2>&1; then
            printf '%s\n' "$name"
        fi
    done
    shopt -u nullglob
}

notifier_has() {
    local name=$1 verb=$2
    declare -F "notifier_${name}_${verb}" >/dev/null 2>&1
}

notifier_call() {
    local name=$1 verb=$2
    shift 2
    if ! notifier_has "$name" "$verb"; then
        err "notifier '$name' does not implement '$verb'"
        return 1
    fi
    "notifier_${name}_${verb}" "$@"
}
