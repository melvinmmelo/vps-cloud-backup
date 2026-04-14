# vps-cloud-backup

**What this does, in one sentence:** you run one command on a fresh
Linux server, answer a few questions, and from that moment on the
server automatically backs up your files and databases to Google Drive
(or Amazon S3) on a schedule and emails you if anything goes wrong.

**Who it's for:** anyone who owns a VPS (AWS, Google Cloud, Hostinger,
DigitalOcean, Linode, Contabo, Vultr, ...) and wants automated backups
without spending a weekend wiring up `cron` + `mysqldump` + `rclone` +
scripts + alerts. If you know how to SSH into your server, you know
enough to use this.

---

## What you need before you start

You need three things ready **on any computer, not the VPS** — the VPS
is what you'll install the backup onto.

1. **A Google Drive or Amazon S3 destination** for your backups.
   - For Google Drive: follow [`docs/credentials/gdrive.md`](docs/credentials/gdrive.md)
     once to get a Client ID and Client Secret. Takes ~5 minutes. **You
     can reuse the same credentials on every VPS you set up.**
   - For Amazon S3 (or Cloudflare R2, Wasabi, DO Spaces, etc.): follow
     [`docs/credentials/s3.md`](docs/credentials/s3.md) once to create a
     bucket and get an Access Key ID + Secret Access Key.
2. **(Optional) A Gmail account** if you want email alerts when a
   backup fails. You'll need an "App Password" — [`docs/notifiers/gmail.md`](docs/notifiers/gmail.md)
   walks you through it. You can skip this step if you don't want alerts.
3. **A VPS you can SSH into**, running one of:
   - Ubuntu 20.04 / 22.04 / 24.04
   - Debian 11 / 12 / 13
   - Amazon Linux 2 / 2023
   - RHEL / Rocky / AlmaLinux 8 / 9
   - Fedora 38+

   You need to be able to run commands as `root` (or use `sudo`).

---

## The five minutes from fresh VPS to automated backups

Open your VPS terminal (Hostinger's web console, AWS's "EC2 Instance
Connect," or just `ssh user@your-vps-ip`) and run:

```bash
# 1. Install git if it's not already there
sudo apt-get update && sudo apt-get install -y git       # Ubuntu / Debian
# OR
sudo dnf install -y git                                   # Amazon Linux / RHEL

# 2. Clone this repo
git clone https://github.com/melvinmmelo/vps-cloud-backup.git

# 3. Run the bootstrap
cd vps-cloud-backup
sudo ./bootstrap.sh
```

That's it. Now you answer the prompts.

> **Safety net:** before installing anything, the bootstrap creates an
> on-demand `timeshift` snapshot of the whole system. If anything goes
> sideways you can roll back with `sudo timeshift --restore` and pick the
> snapshot tagged `vps-cloud-backup pre-install snapshot`. The snapshot
> step is skipped on `--reconfigure` re-runs (which only edit existing
> config and don't warrant a fresh rollback point).

---

## What the prompts look like

Here's the whole thing, start to finish. Nothing is hidden — you can
read exactly what you'll be asked.

### Step 1 — confirm what the bootstrap detected about your VPS

```
== Detecting environment ==
[+] curl already present — skipping

  Hostname        : ip-172-31-42-10
  Public IP       : 54.175.89.22
  Distro          : Ubuntu 24.04 LTS (noble)
  Architecture    : x86_64
  Package manager : apt
  Cloud           : AWS EC2

[?] Proceed with these values? [Y/n]: y
```

Just press **Enter**. The detected values are almost always right.

### Step 2 — pick where backups go

```
== Pick a backup destination ==

  1) Google Drive
  2) Amazon S3 (or S3-compatible)

[?] Pick a backup destination [1]: 1
```

Pick **1** for Google Drive or **2** for S3 and press Enter.

### Step 3 — enter the credentials you prepared earlier

For **Google Drive**, the bootstrap launches `rclone config` and tells
you exactly what to type at each prompt:

```
[+] Installing rclone from https://rclone.org/install.sh (latest stable)...
[+] launching rclone config — follow the instructions below

  n                        (new remote)
  name>           gdrive
  Storage>        drive
  client_id>      <paste your Google Cloud OAuth Client ID>
  client_secret>  <paste your Google Cloud OAuth Client Secret>
  scope>          1         (full access)
  Use auto config? n        (because this is a VPS with no browser)
  ...
```

When it asks **"Use auto config?"**, answer **`n`**, then follow the
headless workflow in [`docs/credentials/gdrive.md`](docs/credentials/gdrive.md#headless-vps-workflow).

For **Amazon S3**:

```
[?] rclone remote name [s3]: s3
[?] S3-compatible provider
  1) Amazon Web Services
  ...
[?] Pick: 1
[?] S3 region [us-east-1]: us-east-1
[?] S3 endpoint URL (leave blank for AWS):
[?] S3 bucket name: yourname-vps-backups
[?] S3 access key ID: AKIA...................
[?] S3 secret access key:                           (hidden while typing)
```

### Step 4 — pick what gets backed up

```
== Sources ==
[?] Back up filesystem paths? [Y/n]: y
[?] Paths to back up (space-separated, no spaces inside paths) [/etc /home /root /var/www]:

[?] Back up databases on this VPS (MySQL / PostgreSQL / SQLite)? [y/N]: y
```

- **Filesystem paths** — the directories on the server you want uploaded.
  The defaults are fine for most people. If all you care about is SQL
  dumps, delete the defaults and type just that directory.
- **Databases** — if you say yes, the bootstrap auto-detects MySQL,
  PostgreSQL, and SQLite on the server and asks for credentials only
  for the ones it finds.

### Step 5 — pick the schedule

```
== Backup policy ==
[?] Destination folder on the remote [backups/ip-172-31-42-10_54.175.89.22]:
[?] Retention in days (older archives auto-deleted) [30]: 30
[?] Backup mode
  1) Mirror files as-is (recommended for SQL dumps)
  2) Timestamped tar.gz archive (recommended for system configs)
[?] Pick [1]: 1

  1) Every 3 days (recommended, monotonic timer)
  2) Daily at a specific time
  3) Weekly on Sunday
  4) Custom
[?] Backup schedule [1]: 1
```

**Every 3 days** is the recommended default. If you pick **Daily** or
**Weekly** you're asked for a time of day (24-hour, e.g. `02:30`).

### Step 6 — optional: turn on email alerts

```
== Notifications ==
[?] Enable failure notifications? [Y/n]: y
[+] auto-selecting sole notifier: gmail
[?] Gmail address (the SMTP login): you@gmail.com
[?] Gmail App Password (16 characters, spaces allowed):    (hidden)
[?] Recipient address (default: same as GMAIL_USER) [you@gmail.com]: alerts@example.com
[?] Display name on outgoing mail [vps-cloud-backup]:
[?] Send notification on successful backups? [y/N]: n
```

You'll get an email the instant a backup fails, plus a one-time "setup
complete" email right now.

### Step 7 — first run

```
== First run ==
[+] Sending test notification via Gmail...
[+] Gmail test notification sent OK
[?] Run a test backup right now? [Y/n]: y
```

Say **yes**. The bootstrap runs one backup immediately so you can see
that everything works before walking away.

---

## After bootstrap — what to remember

The bootstrap prints a summary at the end with the important paths.
Pin them somewhere. The three commands you'll actually use:

```bash
# When is the next automatic backup?
systemctl list-timers vcb-backup.timer

# Force a backup right now
sudo systemctl start vcb-backup.service

# What happened during the last run?
tail -100 /var/log/vcb-backup.log
```

---

## Common problems

### "The test backup said it worked but I don't see any files on Google Drive"

Check rclone is actually talking to the right account:

```bash
rclone lsd gdrive:
rclone ls gdrive:backups/
```

If those are empty, the backup went somewhere else — most likely you
chose the wrong Google account during the OAuth flow. Fix it:

```bash
sudo ./bootstrap.sh --reconfigure provider
```

(`--reconfigure provider` re-runs only the destination phases and
re-auths rclone. The older `--force-reconfigure` flag does the same
thing as part of a full bootstrap re-run — either works.)

### "The bootstrap failed somewhere in the middle"

Every failure has an error code like `VCB-BOOT-011`. Look it up in
[`docs/errors.md`](docs/errors.md) — there's a dedicated entry with
symptoms and fix for every code.

Re-running the bootstrap is safe: it remembers your previous answers
and skips the installed parts. Your typed answers become the new
defaults (press Enter to accept).

### "Backups are running but I'm not getting emails"

Usually one of:

1. The App Password was typed with spaces — it should be exactly 16
   characters, no spaces.
2. Your VPS provider blocks outbound port 587 — test with
   `nc -vz smtp.gmail.com 587`.
3. Gmail filtered your own mail to spam.

Full troubleshooting in [`docs/notifiers/gmail.md`](docs/notifiers/gmail.md#troubleshooting).

### "I need to change the schedule / retention / source paths"

Re-run only the section you want to change instead of the whole bootstrap:

```bash
sudo ./bootstrap.sh --reconfigure schedule    # new OnCalendar / frequency
sudo ./bootstrap.sh --reconfigure policy      # retention, dest folder, mirror vs tar.gz
sudo ./bootstrap.sh --reconfigure sources     # filesystem paths + which DBs
sudo ./bootstrap.sh --reconfigure notifier    # email recipient, App Password, ...
sudo ./bootstrap.sh --reconfigure provider    # switch destination or re-auth
```

Run `sudo ./bootstrap.sh --reconfigure help` to see the full list. Plain
`sudo ./bootstrap.sh` (no flags) still works — it remembers your old
answers and you only need to change the one you want different — but
`--reconfigure` is faster and skips the snapshot step.

### "I want to completely remove vps-cloud-backup"

```bash
sudo ./uninstall.sh
```

Does not touch your uploaded backups on Google Drive / S3 — those stay
safe. Does not remove `rclone` itself (might be used by other tools).

---

## Restoring a backup

This tool only handles the **upload** side. Restoring is always manual,
because every situation is different. The short version:

```bash
# 1. Pick a file to restore
rclone ls gdrive:backups/ | grep myapp
rclone copy "gdrive:backups/myhost_1.2.3.4/vcb-staging/mysql/myapp-2026-04-13_020000.sql.gz" ./

# 2. Decompress and restore
gunzip myapp-2026-04-13_020000.sql.gz
mysql myapp < myapp-2026-04-13_020000.sql
```

For SQLite: `gunzip -c file.sql.gz > db.sqlite3`.
For Postgres: `gunzip -c file.sql.gz | psql mydb`.
For tarball (snapshot mode): `tar -xzf vcb-myhost-2026-04-13_020000.tar.gz`.

---

## What's in this repo

| File / dir | What it does |
|---|---|
| `bootstrap.sh`    | The one-shot installer you run on your VPS |
| `uninstall.sh`    | Reverses what the bootstrap installed |
| `lib/`            | Bash helpers: detection, logging, prompts, package install, systemd rendering |
| `lib/providers/`  | Destination plugins (Google Drive, S3). Drop a new `.sh` file here to add one. |
| `lib/sources/`    | Source plugins (filesystem, databases). |
| `lib/notifiers/`  | Notification plugins (Gmail today; Telegram/Slack in the future). |
| `lib/db/`         | Per-engine credential probing (MySQL, Postgres, SQLite). |
| `vcb_dumper/`     | Python package that dumps databases. OOP, stdlib only, no pip. |
| `vcb_notify/`     | Python package that sends notifications. OOP, stdlib only. |
| `templates/`      | The generated backup script and systemd units. |
| `docs/`           | Guides: credentials per provider, error reference, architecture |
| `CLAUDE.md`       | Coding standards for future contributors and AI agents |
| `LICENSE`         | MIT |

---

## Extending it

- **Add a new destination (Azure Blob, Backblaze B2, ...)**: drop
  `lib/providers/<name>.sh` and add a docs page. Zero edits to existing
  files. See [`docs/architecture.md`](docs/architecture.md).
- **Add a new database engine (MongoDB, Redis, ...)**: one Python class
  under `vcb_dumper/engines/` plus a one-line entry in
  `vcb_dumper/engines/__init__.py` plus a bash probing helper under
  `lib/db/`. See [`CLAUDE.md`](CLAUDE.md).
- **Add a new notification channel (Telegram, Slack, Discord, ...)**:
  one class under `vcb_notify/providers/` plus a bash front-end in
  `lib/notifiers/`.

## License

MIT — see [`LICENSE`](LICENSE). Use it for anything, no warranty.
