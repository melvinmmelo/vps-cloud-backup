# Google Drive credentials

One-time setup in the Google Cloud Console. You reuse the same
`client_id` + `client_secret` on every VPS you bootstrap.

## Why your own OAuth client?

rclone ships with a default client, but it's shared across every rclone
user in the world and heavily rate-limited. Yours takes ~5 minutes and
gives you the full API quota.

## 1. Create a Google Cloud project

1. Go to <https://console.cloud.google.com/>.
2. Top bar → project dropdown → **New Project**.
3. Name it anything (e.g. `vps-cloud-backup`). Organization: **No organization** is fine.
4. Click **Create** and make sure the new project is selected in the top bar.

## 2. Enable the Google Drive API

1. Left menu → **APIs & Services** → **Library**.
2. Search **Google Drive API**.
3. Click it → **Enable**.

## 3. Configure the OAuth consent screen

1. Left menu → **APIs & Services** → **OAuth consent screen**.
2. User Type: **External** → **Create**.
3. Fill in:
   - App name: `vps-cloud-backup` (or anything)
   - User support email: your Gmail
   - Developer contact: your Gmail
4. Save and continue.
5. **Scopes** page: just **Save and continue** — rclone asks for scopes at runtime.
6. **Test users** page: **Add users** → add the Gmail address whose Drive will receive backups. Save and continue.
7. Back to dashboard.

> Leave **Publishing status = Testing**. You don't need verification.
> Test-user refresh tokens do NOT expire, so as long as you're in the
> test users list, you're fine indefinitely.

## 4. Create the OAuth Client ID

1. Left menu → **APIs & Services** → **Credentials**.
2. **+ Create Credentials** → **OAuth client ID**.
3. Application type: **Desktop app**.
4. Name: `rclone` (or anything).
5. Click **Create**. A dialog pops up with:
   ```
   Client ID       : ....apps.googleusercontent.com
   Client secret   : GOCSPX-....
   ```
6. Copy both. Keep the secret safe — it's not a password-equivalent, but it's close.

## 5. Use them with rclone (the bootstrap prompts you)

When `bootstrap.sh` runs `rclone config`, answer:

```
n                        (new remote)
name>           gdrive
Storage>        drive    (Google Drive)
client_id>      <paste Client ID>
client_secret>  <paste Client Secret>
scope>          1        (full access)
service_account_file>    (leave blank)
Edit advanced config?  n

Use auto config?
  NO  on any VPS (no desktop browser on the server)
  YES on a workstation that has a web browser

Configure as Shared Drive?  n
y  (to save)
q  (to quit config)
```

## Headless VPS workflow

On a VPS you answer **`n`** to "Use auto config?". rclone prints a
command like:

```
rclone authorize "drive" "<CLIENT_ID>" "<CLIENT_SECRET>"
```

Run that command on **your own desktop** (which has a browser), sign in
with the same Google account you added as a Test User, and it prints a
JSON token blob to your terminal. Copy the whole blob and paste it back
into the VPS `rclone config` prompt. Done.

## Verify

```
rclone lsd gdrive:
```

should list your Drive's top-level folders without errors.
