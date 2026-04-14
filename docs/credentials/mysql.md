# MySQL / MariaDB credentials

The dumper needs to connect to your local MySQL server as a user that
can run `SHOW DATABASES`, read every table's schema, and execute
`mysqldump --single-transaction`. The default setup uses `root`; you
can switch to a dedicated backup user by editing `db.conf` after the
bootstrap.

## The three auth methods (tried in order)

1. **Unix socket auth** — works on Ubuntu/Debian default installs where
   `root` can log in via the local socket without a password. No
   credentials to store.
   ```
   mysql --protocol=socket -u root -e "SELECT 1"
   ```
2. **`/root/.my.cnf`** — a config file `mysql` reads at startup.
   Example content (mode 0600 root:root):
   ```ini
   [client]
   user=root
   password=YOUR_PASSWORD
   ```
3. **Password prompt** — the bootstrap asks for the root password and
   stores it in `/etc/vps-cloud-backup/db.conf` (0600 root:root).
   Transmitted via the `MYSQL_PWD` env var, never on the command line.

## Using a dedicated backup user (recommended for production)

Create a user with the minimum required privileges:

```sql
CREATE USER 'vcbbackup'@'localhost' IDENTIFIED BY 'pick-a-strong-password';
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER, RELOAD, PROCESS,
      REPLICATION CLIENT
  ON *.*
  TO 'vcbbackup'@'localhost';
FLUSH PRIVILEGES;
```

Then edit `/etc/vps-cloud-backup/db.conf`:

```
MYSQL_USER=vcbbackup
MYSQL_AUTH=password
MYSQL_PASSWORD=pick-a-strong-password
```

Make sure the file is still `0600 root:root` after editing:

```
sudo chown root:root /etc/vps-cloud-backup/db.conf
sudo chmod 600 /etc/vps-cloud-backup/db.conf
```

## What gets dumped

Per database:
```
mysqldump --single-transaction --routines --triggers --events --set-gtid-purged=OFF <db>
```

- `--single-transaction` — consistent snapshot without locking InnoDB tables
- `--routines` — stored procs/functions
- `--triggers` — triggers
- `--events` — events
- `--set-gtid-purged=OFF` — prevents the GTID-related header line that
  breaks plain restores on non-replication servers

System schemas (`mysql`, `information_schema`, `performance_schema`, `sys`)
are always excluded. Your per-user `MYSQL_EXCLUDE` list is applied on top.

## MariaDB

Same tools, same flow. `mysqldump` on MariaDB is compatible; the
bootstrap does not distinguish between them.

## Troubleshooting

See `docs/errors.md` entries VCB-DUMP-010, VCB-DUMP-011, VCB-DUMP-020,
VCB-DUMP-030.
