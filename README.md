# MySQL Docker

A single MySQL 8.4 LTS instance running in Docker, designed to host multiple
independent project databases on one machine. No application containers — just
the database layer.

## What's inside

| What | Detail |
|------|--------|
| MySQL | 8.4 LTS (latest patch), `utf8mb4_unicode_ci` |
| Port | `127.0.0.1:3306` — localhost only, not publicly exposed |
| Data | Persisted in a named Docker volume (`mysql_data`) |
| Config | `conf/mysql/my.cnf` — InnoDB tuning, slow-query log, security defaults |
| Backups | `mysqldump` → gzip, stored in `backups/` |

---

## Quick start

**Requirements:** Docker Desktop (or Docker Engine + Compose v2)

```bash
# 1. Copy the environment template and set a strong root password
cp .env.example .env
# open .env and replace the placeholder value for MYSQL_ROOT_PASSWORD

# 2. Start MySQL
make up

# 3. Check it's healthy (~30 s on first boot)
make ps
```

That's it. MySQL is now running on `127.0.0.1:3306`.

---

## Add a database for a new project

Each project gets its own database and user. Never use root in application code.

```bash
make new-db
```

You'll be prompted for a database name, username, and password. The script is
idempotent — safe to run more than once with the same inputs.

Once done, connect from your project with:

```
host: 127.0.0.1
port: 3306
database: <name you chose>
user: <user you chose>
password: <password you chose>
```

---

## Common operations

All day-to-day tasks are available via `make`. Run `make` (no arguments) to
print the full command list.

```bash
make up                  # start MySQL
make down                # stop MySQL (data kept)
make restart             # restart after config changes
make ps                  # container status + health
make logs                # tail live logs
make shell               # interactive root MySQL shell
make health              # ping, version, db list, user list

make new-db              # provision a database + user (interactive)

make backup              # dump all databases
make backup DB=myproject # dump one database
make restore DUMP=backups/myproject_20240315_143022.sql.gz DB=myproject

make pull                # pull latest mysql:8.4 image (before upgrading)
```

> To wipe all data completely: `docker compose down -v`  ⚠ irreversible

---

## Repository layout

```
mysql-docker/
├── docker-compose.yml        # MySQL 8.4 service definition
├── Makefile                  # Shorthand for all common commands
├── .env.example              # Credential template — copy to .env
├── conf/mysql/my.cnf         # MySQL server configuration
├── init/                     # SQL/shell files run on first boot only
├── backups/                  # Dump files land here (not committed)
└── scripts/
    ├── create-db.sh          # Provision a database + user
    ├── backup.sh             # Create a compressed dump
    ├── restore.sh            # Restore from a dump
    └── healthcheck.sh        # Operational health summary
```

---

## Security defaults

- Root password is set via `.env` — never hardcoded, never committed.
- MySQL port is bound to `127.0.0.1` only (not reachable from the network).
- Each project uses its own user with access limited to its own database.
- `local_infile` is disabled in `my.cnf`.

---

## Full documentation

See [CLAUDE.md](CLAUDE.md) for detailed coverage of upgrades, rollback
strategy, rotating credentials, and troubleshooting.
