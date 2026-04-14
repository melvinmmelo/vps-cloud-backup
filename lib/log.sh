# lib/log.sh — colored, stderr-only logging helpers.
# All logging goes to stderr so functions can safely use stdout for return values.

if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
    _C_RED=$'\e[31m'; _C_GREEN=$'\e[32m'; _C_YELLOW=$'\e[33m'
    _C_BLUE=$'\e[34m'; _C_BOLD=$'\e[1m'; _C_RESET=$'\e[0m'
else
    _C_RED=""; _C_GREEN=""; _C_YELLOW=""; _C_BLUE=""; _C_BOLD=""; _C_RESET=""
fi

log()    { printf '%s[+]%s %s\n' "$_C_GREEN"  "$_C_RESET" "$*" >&2; }
warn()   { printf '%s[!]%s %s\n' "$_C_YELLOW" "$_C_RESET" "$*" >&2; }
err()    { printf '%s[x]%s %s\n' "$_C_RED"    "$_C_RESET" "$*" >&2; }
banner() { printf '\n%s== %s ==%s\n'  "$_C_BOLD" "$*" "$_C_RESET" >&2; }
