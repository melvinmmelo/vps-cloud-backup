# lib/prompt.sh — user-input helpers.
# Every phase that asks the user something must go through these.
# They all respect YES_MODE (non-interactive) by falling back to the default.

_prompt() {
    # Prints prompt to stderr so stdout stays clean for callers that want it.
    printf '%s[?]%s %s' "$_C_BLUE" "$_C_RESET" "$*" >&2
}

# ask_default VAR_NAME DEFAULT PROMPT
# Reads a line from stdin, falls back to DEFAULT on empty, assigns to VAR_NAME,
# and persists through state_set so re-runs remember the answer.
# If the variable is already non-empty (typically from state_load), that value
# wins over the hardcoded DEFAULT so re-runs pre-fill previous answers.
ask_default() {
    local var=$1 default=$2 prompt=$3
    local answer current=""
    eval "current=\${$var:-}"
    [[ -n "$current" ]] && default=$current
    if [[ $YES_MODE -eq 1 ]]; then
        answer=$default
    else
        _prompt "${prompt} [${default}]: "
        IFS= read -r answer || answer=""
        answer=${answer:-$default}
    fi
    printf -v "$var" '%s' "$answer"
    state_set "$var" "$answer"
}

# ask_yes_no VAR_NAME DEFAULT PROMPT    (DEFAULT must be "y" or "n")
# If the variable already holds "y" or "n" (from a loaded state file), that
# value becomes the effective default so re-runs remember previous answers.
ask_yes_no() {
    local var=$1 default=$2 prompt=$3
    local answer suffix current=""
    eval "current=\${$var:-}"
    if [[ "$current" == "y" || "$current" == "n" ]]; then
        default=$current
    fi
    [[ "$default" == "y" ]] && suffix="[Y/n]" || suffix="[y/N]"
    if [[ $YES_MODE -eq 1 ]]; then
        answer=$default
    else
        _prompt "${prompt} ${suffix}: "
        IFS= read -r answer || answer=""
        answer=${answer,,}
        [[ -z "$answer" ]] && answer=$default
        case "$answer" in
            y|yes) answer=y ;;
            n|no)  answer=n ;;
            *)     answer=$default ;;
        esac
    fi
    printf -v "$var" '%s' "$answer"
    state_set "$var" "$answer"
}

# ask_secret VAR_NAME PROMPT
# Read without echo. Not persisted to state (secrets live in rclone.conf only).
ask_secret() {
    local var=$1 prompt=$2
    local answer
    if [[ $YES_MODE -eq 1 ]]; then
        err "ask_secret '$var' cannot run in --yes mode — secrets are not in state."
        return 1
    fi
    _prompt "${prompt}: "
    IFS= read -rs answer || answer=""
    printf '\n' >&2
    printf -v "$var" '%s' "$answer"
}

# ask_choice VAR_NAME PROMPT "key|label" "key|label" ...
# Shows a numbered menu, reads a number, assigns the matching key.
# Default selection = current value of VAR_NAME (from state) if it matches a key,
# otherwise the first option.
ask_choice() {
    local var=$1 prompt=$2
    shift 2
    local -a keys=() labels=()
    local entry key label
    for entry in "$@"; do
        key=${entry%%|*}; label=${entry#*|}
        keys+=("$key"); labels+=("$label")
    done

    local current=""
    eval "current=\${$var:-}"
    local default_idx=0 i
    for i in "${!keys[@]}"; do
        [[ "${keys[i]}" == "$current" ]] && default_idx=$i
    done

    if [[ $YES_MODE -eq 1 ]]; then
        printf -v "$var" '%s' "${keys[default_idx]}"
        state_set "$var" "${keys[default_idx]}"
        return 0
    fi

    printf '\n' >&2
    for i in "${!keys[@]}"; do
        printf '  %d) %s\n' $((i+1)) "${labels[i]}" >&2
    done
    printf '\n' >&2

    local choice answer_idx
    _prompt "${prompt} [$((default_idx+1))]: "
    IFS= read -r choice || choice=""
    if [[ -z "$choice" ]]; then
        answer_idx=$default_idx
    elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#keys[@]} )); then
        answer_idx=$((choice-1))
    else
        warn "Invalid choice '$choice' — using default."
        answer_idx=$default_idx
    fi

    printf -v "$var" '%s' "${keys[answer_idx]}"
    state_set "$var" "${keys[answer_idx]}"
}
