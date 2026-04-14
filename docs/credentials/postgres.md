# PostgreSQL credentials

The dumper needs a user that can enumerate databases from `pg_database`
and run `pg_dump` on each one.

## The three auth methods (tried in order)

1. **Peer auth** — on Debian/Ubuntu default installs, the `postgres` OS
   user can log in as the `postgres` database role without a password
   via the Unix socket:
   ```
   sudo -u postgres psql -c "SELECT 1"
   ```
   The dumper invokes `pg_dump` through `sudo -u postgres` when this
   method is selected.
2. **`~/.pgpass`** — a config file `psql` and `pg_dump` consult.
   Mode 0600 root:root. Format:
   ```
   hostname:port:database:username:password
   ```
   Example:
   ```
   localhost:5432:*:postgres:YOUR_PASSWORD
   ```
3. **Password prompt** — stored in `/etc/vps-cloud-backup/db.conf` and
   passed via the `PGPASSWORD` env var.

## Using a dedicated backup role (recommended)

Create a role with `pg_read_all_data` (Postgres 14+) or manually granted
connect+usage+select on every schema:

```sql
CREATE ROLE vcbbackup LOGIN PASSWORD 'pick-a-strong-password';
GRANT pg_read_all_data TO vcbbackup;   -- Postgres 14+
```

Then edit `/etc/vps-cloud-backup/db.conf`:

```
POSTGRES_USER=vcbbackup
POSTGRES_AUTH=password
POSTGRES_PASSWORD=pick-a-strong-password
```

Remember to keep the file at `0600 root:root`.

## What gets dumped

Per database:

```
pg_dump --format=plain --no-owner --no-privileges <db>
```

- `--format=plain` — text SQL that `psql` restores with
  `gunzip -c <file>.sql.gz | psql`.
- `--no-owner --no-privileges` — makes restores portable across hosts;
  you apply your own ownership/permissions after restore.

The `template0`, `template1`, and `postgres` maintenance databases are
excluded by default. Add your own exclusions via `POSTGRES_EXCLUDE`.

## Troubleshooting

See `docs/errors.md` entries VCB-DUMP-010, VCB-DUMP-011, VCB-DUMP-020,
VCB-DUMP-030.
