#!/usr/bin/env bash
#
# vps-cloud-backup / uninstall.sh
#
# Reverses what bootstrap.sh installed. Safe to run twice — everything is
# guarded by existence checks. Does NOT remove:
#   - rclone itself (may be used by other tools)
#   - python3, curl, tar (pre-installed or used elsewhere)
#   - data on the cloud destination (the whole point — you still have your backups)
#
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "run as root: sudo $0" >&2
    exit 1
fi

VCB_PREFIX="vcb"
STATE_DIR="/etc/vps-cloud-backup"
BACKUP_SCRIPT="/usr/local/bin/${VCB_PREFIX}-backup.sh"
BACKUP_SERVICE="/etc/systemd/system/${VCB_PREFIX}-backup.service"
BACKUP_TIMER="/etc/systemd/system/${VCB_PREFIX}-backup.timer"
BACKUP_LOG="/var/log/${VCB_PREFIX}-backup.log"
STAGING_DIR="/var/backups/vcb-staging"
PYTHON_BASE="/usr/local/lib"

echo "[+] disabling timer and service..."
systemctl disable --now "${VCB_PREFIX}-backup.timer" 2>/dev/null || true
systemctl stop      "${VCB_PREFIX}-backup.service"   2>/dev/null || true

echo "[+] removing systemd units..."
rm -f "$BACKUP_TIMER" "$BACKUP_SERVICE"
systemctl daemon-reload 2>/dev/null || true

echo "[+] removing backup script..."
rm -f "$BACKUP_SCRIPT"

echo "[+] removing Python packages from ${PYTHON_BASE}..."
rm -rf "${PYTHON_BASE}/vcb_dumper" "${PYTHON_BASE}/vcb_notify"

echo "[+] removing staging directory..."
rm -rf "$STAGING_DIR"

read -r -p "[?] Remove config files at ${STATE_DIR} (bootstrap.env, db.conf, notifications.conf)? [y/N] " answer
case "$answer" in
    y|Y|yes)
        rm -rf "$STATE_DIR"
        echo "[+] config files removed"
        ;;
    *)
        echo "[!] keeping config files at ${STATE_DIR}"
        ;;
esac

read -r -p "[?] Remove backup log ${BACKUP_LOG}? [y/N] " answer
case "$answer" in
    y|Y|yes) rm -f "$BACKUP_LOG"; echo "[+] log removed" ;;
    *)       echo "[!] keeping log" ;;
esac

read -r -p "[?] Delete rclone remotes configured by this tool? [y/N] " answer
case "$answer" in
    y|Y|yes)
        if command -v rclone >/dev/null 2>&1; then
            for r in $(rclone listremotes 2>/dev/null); do
                echo "    rclone remote: $r"
            done
            read -r -p "    Enter the remote name to delete (or blank to skip): " r
            [[ -n "$r" ]] && rclone config delete "${r%:}" || true
        fi
        ;;
esac

cat <<EOF

[+] Uninstall complete.

NOT removed (delete manually if you want):
  - rclone itself
  - /root/.config/rclone/rclone.conf (still holds your remote secrets if you kept them)
  - Uploaded archives on the remote destination (your backups are still safe)
EOF
