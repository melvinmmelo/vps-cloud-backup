#!/usr/bin/env bash
# test/shellcheck.sh — run shellcheck + bash -n across every shell file.
#
# Usage: bash test/shellcheck.sh
# Requires: bash; shellcheck is optional (falls back to bash -n only).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

shopt -s nullglob
FILES=(
    bootstrap.sh
    uninstall.sh
    lib/*.sh
    lib/providers/*.sh
    lib/sources/*.sh
    lib/notifiers/*.sh
    lib/db/*.sh
    test/shellcheck.sh
)

fail=0
for f in "${FILES[@]}"; do
    if ! bash -n "$f" 2>&1; then
        echo "SYNTAX: $f"
        fail=1
    fi
done

if command -v shellcheck >/dev/null 2>&1; then
    # -x enables following of sourced files; we ignore "cannot find source"
    shellcheck -x -e SC1090,SC1091,SC2034,SC2016 "${FILES[@]}" || fail=1
else
    echo "[!] shellcheck not installed — ran bash -n only. Install with:"
    echo "    sudo apt-get install shellcheck"
fi

echo
if [[ $fail -eq 0 ]]; then
    echo "all shell files pass"
else
    echo "FAILED"
    exit 1
fi
