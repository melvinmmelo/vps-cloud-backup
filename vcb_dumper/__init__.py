"""vcb_dumper — database dump subsystem for vps-cloud-backup.

Imported by: vcb_dumper.__main__ and the unit tests under test/python/.
Calls out to: mysqldump, pg_dump, sqlite3 via subprocess. Pure stdlib.
"""
from __future__ import annotations

__version__ = "0.1.0"
