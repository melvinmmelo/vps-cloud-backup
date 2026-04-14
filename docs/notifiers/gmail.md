# Gmail notifications

The Gmail notifier sends plain-text emails through `smtp.gmail.com:587`
(STARTTLS) using the Python stdlib. It uses an **App Password**, not
your regular Gmail password.

## 1. Enable 2-step verification

You can't generate an App Password until 2-step is on:

<https://myaccount.google.com/security> → **2-Step Verification** → **Turn on**.

## 2. Create an App Password

<https://myaccount.google.com/apppasswords>

If the link says "The setting you're looking for isn't available for your
account," double-check that 2-step is actually enabled. Workspace admins
may also need to allow App Passwords at the domain level.

1. App: **Other (Custom name)** → type `vps-cloud-backup`.
2. Click **Generate**.
3. Google shows you a **16-character** password. Copy it — once you close
   the dialog, you can't see it again (but you can always revoke and make
   a new one).

## 3. Run the bootstrap

When you reach the notifier prompts:

```
Gmail address              you@gmail.com
Gmail App Password         abcd efgh ijkl mnop     (paste the 16 chars)
Recipient address          alerts@example.com      (or leave blank for self)
Display name on outgoing   vps-cloud-backup
Notify on SUCCESS too?     n                        (default — failures only)
```

The bootstrap immediately sends a test notification at the end of
`phase_9_enable_and_test`. If you don't receive it, see the
troubleshooting section below.

## 4. Which events you get

By default, you're subscribed to:

- `setup.completed` — once, when the bootstrap finishes
- `backup.failure`  — a backup run exited non-zero
- `backup.partial`  — the Python dumper reported at least one failed dump

If you answered "yes" to "Notify on SUCCESS too?", you also get:

- `backup.success`  — every clean backup run

## Revoking access

<https://myaccount.google.com/apppasswords> → click the X next to the
App Password. Gmail instantly stops accepting logins with it.

After revocation, re-run `sudo ./bootstrap.sh --force-reconfigure` on
the VPS to enter a new App Password.

## Troubleshooting

### VCB-NOTIFY-010 — cannot reach smtp.gmail.com:587

Some VPS providers block outbound SMTP ports by default:

- **AWS EC2** — no block on port 587, but your default VPC SG must allow egress.
- **Google Cloud Compute** — outbound 25 is blocked, 587 is fine.
- **Hostinger** — 25/465/587 are usually open by default.

Test from the VPS:

```
nc -vz smtp.gmail.com 587
```

If that fails, open the port in your firewall / security group.

### VCB-NOTIFY-011 — authentication rejected

Three common causes:

1. You pasted your regular Gmail password, not an App Password. Gmail
   rejects regular passwords for SMTP when 2-step is on.
2. The App Password was revoked (by you or by Google's abuse system).
3. You pasted the password with extra spaces or the "spaces every 4 chars"
   display format. The stored password should be exactly 16 characters
   with no spaces — the bootstrap strips spaces on input, but double-check.

### I got the test mail but not the real ones

Check Gmail's "Sent" folder on the FROM account — if the sends are
happening but the receiver doesn't see them, Gmail itself filtered
them. Add the sender to the receiver's contacts.

Also check `/var/log/vcb-backup.log` for `VCB-NOTIFY-020` lines.
