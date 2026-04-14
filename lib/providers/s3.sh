# lib/providers/s3.sh — Amazon S3 and S3-compatible stores via rclone.
#
# Works with: AWS S3, Cloudflare R2, MinIO, Wasabi, Backblaze B2 (S3 API),
# DigitalOcean Spaces, Scaleway Object Storage, etc. Any endpoint that
# speaks the S3 API can reuse this provider by overriding S3_PROVIDER and
# S3_ENDPOINT at the prompt stage.

provider_s3_label()       { printf '%s\n' "Amazon S3 (or S3-compatible)"; }
provider_s3_description() { printf '%s\n' "AWS S3, Cloudflare R2, MinIO, Wasabi, DO Spaces, Scaleway..."; }
provider_s3_deps()        { printf '%s\n' "rclone tar curl"; }
provider_s3_rclone_backend() { printf '%s\n' "s3"; }
provider_s3_credentials_doc() { printf '%s\n' "docs/credentials/s3.md"; }

provider_s3_prompt_config() {
    ask_default REMOTE_NAME "s3" "rclone remote name"

    # S3 variant. Most users want AWS; the menu lets them switch.
    ask_choice S3_PROVIDER "S3-compatible provider" \
        "AWS|Amazon Web Services" \
        "Cloudflare|Cloudflare R2" \
        "Wasabi|Wasabi Hot Cloud Storage" \
        "DigitalOcean|DigitalOcean Spaces" \
        "Minio|MinIO / self-hosted" \
        "Other|Other S3-compatible endpoint"

    ask_default S3_REGION   "us-east-1" "S3 region"
    ask_default S3_ENDPOINT ""          "S3 endpoint URL (leave blank for AWS)"
    ask_default S3_BUCKET   ""          "S3 bucket name (must already exist)"

    # Secrets are NOT persisted — state_set ignores KEY_ID / SECRET / ACCESS_KEY.
    ask_secret  S3_ACCESS_KEY_ID     "S3 access key ID"
    ask_secret  S3_SECRET_ACCESS_KEY "S3 secret access key"
}

provider_s3_configure() {
    if [[ -z "${S3_BUCKET:-}" ]]; then
        err "S3_BUCKET is empty — re-run and provide a bucket name."
        return 1
    fi
    if [[ -z "${S3_ACCESS_KEY_ID:-}" || -z "${S3_SECRET_ACCESS_KEY:-}" ]]; then
        err "S3 credentials missing. This provider cannot use --yes without them."
        return 1
    fi

    if rclone listremotes 2>/dev/null | grep -q "^${REMOTE_NAME}:$"; then
        if [[ $FORCE_RECONFIGURE -eq 0 ]]; then
            log "rclone remote '${REMOTE_NAME}' already exists — rewriting."
        fi
    fi

    # Write directly to rclone.conf so the access key and secret key never
    # appear on argv (where `ps` would expose them). `rclone config create`
    # takes key=value on argv, which is unsafe for secrets.
    local rclone_conf="${HOME:-/root}/.config/rclone/rclone.conf"
    local rclone_dir
    rclone_dir=$(dirname "$rclone_conf")

    # 0077 umask closes every window where mktemp / touch / awk could
    # create a file at 0644 before the explicit chmod fires.
    local old_umask
    old_umask=$(umask)
    umask 0077

    mkdir -p "$rclone_dir"
    chmod 700 "$rclone_dir"
    # Also tighten the parent (~/.config) so directory listing is root-only.
    chmod 700 "$(dirname "$rclone_dir")" 2>/dev/null || true

    # Create the file if missing and immediately lock it down. The existing
    # file (if any) is chmodded before awk reads it so its contents are
    # never briefly world-readable mid-operation.
    if [[ ! -e "$rclone_conf" ]]; then
        : > "$rclone_conf"
    fi
    chmod 600 "$rclone_conf"

    local tmp
    tmp=$(mktemp "${rclone_conf}.XXXXXX") || {
        umask "$old_umask"
        err "mktemp failed next to $rclone_conf"
        return 1
    }
    # Strip any pre-existing section for this remote, then append the new one.
    awk -v name="$REMOTE_NAME" '
        BEGIN { skip = 0 }
        /^\[/ {
            skip = ($0 == "[" name "]") ? 1 : 0
        }
        { if (!skip) print }
    ' "$rclone_conf" > "$tmp"

    {
        printf '\n[%s]\n' "$REMOTE_NAME"
        printf 'type = s3\n'
        printf 'provider = %s\n' "$S3_PROVIDER"
        printf 'region = %s\n' "$S3_REGION"
        [[ -n "${S3_ENDPOINT:-}" ]] && printf 'endpoint = %s\n' "$S3_ENDPOINT"
        printf 'access_key_id = %s\n' "$S3_ACCESS_KEY_ID"
        printf 'secret_access_key = %s\n' "$S3_SECRET_ACCESS_KEY"
    } >> "$tmp"

    chmod 600 "$tmp"
    mv "$tmp" "$rclone_conf"
    umask "$old_umask"
    log "wrote rclone remote '${REMOTE_NAME}' (secrets stayed out of argv)"
}

provider_s3_verify() {
    rclone lsd "${REMOTE_NAME}:${S3_BUCKET}" >/dev/null 2>&1
}

provider_s3_remote_uri() {
    printf '%s:%s/%s\n' "$REMOTE_NAME" "$S3_BUCKET" "$DEST"
}

provider_s3_uninstall_hint() {
    cat <<EOF
To remove the S3 remote from rclone (does NOT delete the bucket or its contents):
  rclone config delete ${REMOTE_NAME}
Objects already uploaded remain in s3://${S3_BUCKET}/${DEST}/ — delete them
through the AWS console or  rclone purge ${REMOTE_NAME}:${S3_BUCKET}/${DEST}/
EOF
}
