# lib/providers/gdrive.sh — Google Drive via rclone.
#
# Google Drive uses an OAuth flow that requires a browser. On headless VPS,
# we answer "no" to rclone's auto-config question and use `rclone authorize`
# from a machine that has a browser. See docs/credentials/gdrive.md.

provider_gdrive_label()       { printf '%s\n' "Google Drive"; }
provider_gdrive_description() { printf '%s\n' "Personal/Workspace Google Drive via OAuth2 (rclone)"; }
provider_gdrive_deps()        { printf '%s\n' "rclone tar curl"; }
provider_gdrive_rclone_backend() { printf '%s\n' "drive"; }
provider_gdrive_credentials_doc() { printf '%s\n' "docs/credentials/gdrive.md"; }

provider_gdrive_prompt_config() {
    ask_default REMOTE_NAME "gdrive" "rclone remote name"
    # OAuth credentials are collected by rclone config itself in a moment.
    # We only remember the remote name here.
}

provider_gdrive_configure() {
    if rclone listremotes 2>/dev/null | grep -q "^${REMOTE_NAME}:$"; then
        if [[ $FORCE_RECONFIGURE -eq 0 ]]; then
            log "rclone remote '${REMOTE_NAME}' already exists — keeping."
            return 0
        fi
        warn "Force-reconfigure requested. Deleting existing '${REMOTE_NAME}' remote."
        rclone config delete "$REMOTE_NAME"
    fi

    cat >&2 <<EOF

rclone config will now launch. Answer these prompts:

  n                        (new remote)
  name>           ${REMOTE_NAME}
  Storage>        drive    (Google Drive)
  client_id>      <paste your Google Cloud OAuth Client ID>
  client_secret>  <paste your Google Cloud OAuth Client Secret>
  scope>          1        (full access)
  service_account_file>    (leave blank)
  Edit advanced config?  n

  Use auto config?
    NO  if this machine has no desktop browser (any VPS).
        rclone will print a 'rclone authorize' command — run that on
        your own Ubuntu/Mac/Windows desktop, authenticate in the browser
        it opens, then paste the JSON token blob back here.
    YES only if this machine has a GUI with a browser installed.

  Configure as Shared Drive?  n
  y                        (to save the remote)
  q                        (to quit rclone config)

See docs/credentials/gdrive.md for how to obtain client_id/secret.

EOF
    rclone config
}

provider_gdrive_verify() {
    rclone lsd "${REMOTE_NAME}:" >/dev/null 2>&1
}

provider_gdrive_remote_uri() {
    printf '%s:%s\n' "$REMOTE_NAME" "$DEST"
}

provider_gdrive_uninstall_hint() {
    cat <<EOF
To remove the Google Drive remote from rclone:
  rclone config delete ${REMOTE_NAME}
To revoke access in Google:
  https://myaccount.google.com/permissions
EOF
}
