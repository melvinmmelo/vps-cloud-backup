# SQLite

SQLite has no credentials — databases are files. The bootstrap just needs
to know **which** files to back up.

## Discovery

When you enable SQLite during the bootstrap, it scans:

```
/var/lib       /srv        /opt        /var/www        /home
```

up to depth 4 for files ending in `.sqlite`, `.sqlite3`, or `.db`. The
first 20 matches are shown as a default list; you edit the list to add
or remove paths.

If your database lives elsewhere (e.g. inside a Docker volume at
`/var/lib/docker/volumes/myapp/_data/db.sqlite3`), just type the full
path at the prompt.

## What gets dumped

For each path you approve, the dumper runs:

```
sqlite3 /path/to/db.sqlite3 ".backup /tmp/<snapshot>"
```

`.backup` is SQLite's online backup command — it produces a consistent
copy while the database is being written, unlike a raw `cp`. The
snapshot is then gzipped into
`/var/backups/vcb-staging/sqlite/<basename>-<stamp>.sql.gz`.

## Restoring

```
gunzip -c db.sqlite3-2026-04-14_020000.sql.gz > db.sqlite3.restored
sqlite3 db.sqlite3.restored ".schema"   # sanity check
mv db.sqlite3.restored /path/to/db.sqlite3   # when you're sure
```

## Caveats

- **Symlinks** to SQLite files are followed. Back up the real path, not
  a symlink farm.
- **WAL files** (`-wal` and `-shm` siblings) are consumed by `.backup`
  during the snapshot — you do NOT need to back them up separately.
- If you have dozens of SQLite files, consider grouping them into one
  directory and pointing the filesystem source at that directory instead
  of listing each file in SQLITE_PATHS.
