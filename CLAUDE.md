# MySQL Docker — Operations Guide

> **Scope:** This repository manages a single MySQL 8.4 LTS container that hosts
> multiple independent project databases. There are no application containers
> here; each project connects to this shared instance with its own dedicated
> user and database.

---

## Table of Contents

1. [Repository structure](#1-repository-structure)
2. [First-time setup](#2-first-time-setup)
3. [Starting and stopping the stack](#3-starting-and-stopping-the-stack)
4. [Creating a database and user for a new project](#4-creating-a-database-and-user-for-a-new-project)
5. [Connecting from a project](#5-connecting-from-a-project)
6. [Backups](#6-backups)
7. [Restores](#7-restores)
8. [Health checks](#8-health-checks)
9. [Upgrading MySQL](#9-upgrading-mysql)
10. [Rollback and reversibility](#10-rollback-and-reversibility)
11. [Security posture](#11-security-posture)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Repository structure

```
mysql-docker/
├── docker-compose.yml          # Main compose file (MySQL 8.4 only)
├── Makefile                    # Shorthand for all common commands
├── .env.example                # Credential template — copy to .env
├── .env                        # ← NOT committed; your local secrets
├── .gitignore
│
├── conf/
│   └── mysql/
│       └── my.cnf              # MySQL server configuration (drop-in)
│
├── init/                       # SQL/shell scripts run on first init only
│   └── .gitkeep
│
├── backups/                    # Dump files land here (excluded from git)
│   └── .gitkeep
│
├── scripts/
│   ├── create-db.sh            # Provision a new database + user
│   ├── backup.sh               # Logical dump (mysqldump + gzip)
│   ├── restore.sh              # Restore a dump
│   └── healthcheck.sh          # Ping, version, db list, user list
│
└── .github/
    └── workflows/
        └── ci.yml              # Compose validation + smoke test
```

---

## 2. First-time setup

### Prerequisites

- Docker Desktop (macOS/Windows) or Docker Engine + Docker Compose v2 (Linux)
- `docker compose version` should report **v2.x** or later

### Steps

```bash
# 1. Clone the repository
git clone <repo-url> mysql-docker
cd mysql-docker

# 2. Create your local .env from the template
cp .env.example .env

# 3. Set a strong root password — edit .env and replace the placeholder.
#    Tip: generate one with:
openssl rand -base64 32

# 4. Start MySQL
docker compose up -d

# 5. Verify it is healthy (takes ~30 s on first boot)
docker compose ps
```

MySQL data is stored in the Docker named volume `mysql_data`. That volume
persists across `docker compose down` and container rebuilds.

---

## 3. Starting and stopping the stack

Prefer `make` targets for day-to-day use — they map directly to the
`docker compose` commands below.

```bash
make up          # docker compose up -d
make down        # docker compose down          (data volume kept)
make restart     # docker compose restart mysql  (after editing my.cnf)
make logs        # docker compose logs -f mysql
make ps          # docker compose ps
make shell       # docker compose exec mysql mysql -u root -p
```

Direct `docker compose` equivalents (for reference or scripting):

```bash
# Stop AND remove the data volume  ⚠ DESTRUCTIVE — data is gone
docker compose down -v
```

---

## 4. Creating a database and user for a new project

Each project should have its own database and a dedicated user with access
only to that database. **Never use the root account from application code.**

```bash
make new-db
```

You will be prompted for a database name, username, and password. The script
is idempotent — running it twice with the same name is safe.

### What the script does

```sql
CREATE DATABASE IF NOT EXISTS `<db_name>`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '<user>'@'%' IDENTIFIED BY '<password>';

GRANT ALL PRIVILEGES ON `<db_name>`.* TO '<user>'@'%';

FLUSH PRIVILEGES;
```

The `%` host wildcard is intentional — it means "any host that can reach this
MySQL socket", which in practice is limited to whatever can reach port 3306
(by default, only localhost on the Docker host).

### Manually (if you prefer raw SQL)

```bash
docker compose exec mysql mysql -u root -p
```

```sql
CREATE DATABASE `myproject` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'myproject_user'@'%' IDENTIFIED BY 'a-strong-password';
GRANT ALL PRIVILEGES ON `myproject`.* TO 'myproject_user'@'%';
FLUSH PRIVILEGES;
```

---

## 5. Connecting from a project

| Setting  | Value                  |
|----------|------------------------|
| Host     | `127.0.0.1`            |
| Port     | `3306` (or `MYSQL_PORT` from `.env`) |
| Database | your project DB name   |
| User     | your project user      |
| Password | set during create-db   |

**Example Laravel `.env`:**

```dotenv
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=myproject
DB_USERNAME=myproject_user
DB_PASSWORD=your-password
```

**Example DSN (PHP PDO / other):**

```
mysql://myproject_user:your-password@127.0.0.1:3306/myproject
```

---

## 6. Backups

Backups are logical dumps produced with `mysqldump` and compressed with gzip.
They are written to `backups/` with a timestamp in the filename.

```bash
# Back up a single database
make backup DB=myproject

# Back up ALL databases
make backup
```

Example output file: `backups/myproject_20240315_143022.sql.gz`

### Automating backups (cron)

```cron
# Daily at 02:00, back up all databases, keep 30 days of dumps
0 2 * * * cd /path/to/mysql-docker && ./scripts/backup.sh >> /var/log/mysql-backup.log 2>&1
find /path/to/mysql-docker/backups -name "*.sql.gz" -mtime +30 -delete
```

### mysqldump flags used

| Flag | Reason |
|------|--------|
| `--single-transaction` | Consistent InnoDB snapshot without table locks |
| `--routines` | Includes stored procedures and functions |
| `--triggers` | Includes triggers |
| `--set-gtid-purged=OFF` | Avoids errors when binary log is disabled |
| `--column-statistics=0` | Prevents histogram errors with MySQL 8 dumps |

---

## 7. Restores

> ⚠ **Destructive operation.** A restore overwrites data in the target
> database(s). The script asks for confirmation before proceeding.

```bash
# Restore into a specific database
make restore DUMP=backups/myproject_20240315_143022.sql.gz DB=myproject

# Restore an all-databases dump (no DB argument)
make restore DUMP=backups/all-databases_20240315_143022.sql.gz
```

If the target database does not yet exist, create it first:

```bash
make new-db   # provision the empty database
make restore DUMP=backups/myproject_....sql.gz DB=myproject
```

---

## 8. Health checks

```bash
make health
```

Outputs:

- `mysqladmin ping` result
- MySQL version and current server time
- Server uptime and thread statistics
- List of user-created databases (system schemas excluded)
- List of all MySQL users

---

## 9. Upgrading MySQL

MySQL 8.4 is the current LTS release. The `mysql:8.4` image tag always pulls
the latest 8.4.x patch on `make pull` / `docker compose pull`.

> **Note:** `mysql_upgrade` was removed in MySQL 8.4. The server now performs
> any necessary data-dictionary upgrades automatically on start-up.

### Patch upgrade (8.4.x → 8.4.y) — low risk

```bash
# 1. Take a full backup first
make backup

# 2. Pull the new image
make pull

# 3. Recreate the container (data volume is untouched)
docker compose up -d --force-recreate mysql

# 4. Verify
make health
```

### Major upgrade (8.4 → 9.x) — requires care

1. **Back up everything** with `make backup`.
2. Change the image tag in `docker-compose.yml` (e.g. `mysql:9.0`).
3. Start the container — MySQL will perform an in-place upgrade on the
   existing data volume. Watch the logs closely:
   ```bash
   make logs
   ```
4. If the upgrade fails or the container exits immediately, roll back:
   - Revert the image tag in `docker-compose.yml`
   - Restore from the dump taken in step 1 using `make restore`

### Pinning to a specific patch version

Change the image tag in `docker-compose.yml`:

```yaml
image: mysql:8.4.5
```

This prevents unintended upgrades during `make pull`.

---

## 10. Rollback and reversibility

| Action | Reversible? | Notes |
|--------|------------|-------|
| `docker compose down` | ✅ Yes | Data volume untouched; `up` restores state |
| `docker compose restart mysql` | ✅ Yes | Container restarts, data unchanged |
| Edit `my.cnf` + restart | ✅ Yes | Revert the file and restart |
| `docker compose pull` + recreate | ✅ Yes | Old image cached locally; revert tag and recreate |
| `docker compose down -v` | ❌ No | Destroys the `mysql_data` volume — data is gone |
| Dropped database/table | ❌ No | Must restore from a backup dump |
| MySQL major version upgrade | ⚠ Risky | Data directory format may change; restore from dump is the safest rollback |

**Rule of thumb:** always run `make backup` before any upgrade or destructive
schema change.

---

## 11. Security posture

- **Root password** is set via `.env` and never committed to git.
- **MySQL port** is bound to `127.0.0.1` only — not reachable from the
  network unless you deliberately change the binding in `docker-compose.yml`.
- **Per-project users** are granted access only to their own database. Root
  is for administration only.
- **`local_infile`** is disabled in `my.cnf` to prevent LOAD DATA LOCAL
  INFILE attacks.
- **`init/` directory** — any `.sql` or `.sh` files here run only on the very
  first container initialisation (when the data directory is empty). Do not
  place secrets in these files if you commit them.

### Rotating the root password

```bash
# 1. Take a backup
make backup

# 2. Connect as root and change the password
docker compose exec mysql mysql -u root -p -e \
  "ALTER USER 'root'@'localhost' IDENTIFIED BY 'new-strong-password';"

# 3. Update MYSQL_ROOT_PASSWORD in .env

# 4. Restart the container so the env var is re-read by scripts
docker compose restart mysql
```

---

## 12. Troubleshooting

### Container exits immediately after `docker compose up -d`

```bash
docker compose logs mysql
```

Common causes:

| Symptom in logs | Fix |
|-----------------|-----|
| `Access denied for user 'root'` | `MYSQL_ROOT_PASSWORD` in `.env` does not match the password stored in the data volume. Either fix `.env` or remove the volume with `docker compose down -v` and start fresh (data loss). |
| `Table './mysql/...' is marked as crashed` | Run `docker compose exec mysql mysqlcheck -u root -p --all-databases --auto-repair`. |
| `[ERROR] InnoDB: Cannot open datafile` | Permissions issue on the Docker volume. Check `docker volume inspect mysql-docker_mysql_data`. |
| Port already in use (`bind: address already in use`) | Change `MYSQL_PORT` in `.env` to a free port, or stop whatever is using 3306. |

### Cannot connect from a project (`Connection refused`)

1. Confirm the container is running and healthy:
   ```bash
   docker compose ps
   ```
2. Confirm the correct port:
   ```bash
   grep MYSQL_PORT .env
   ```
3. Test with `mysqladmin`:
   ```bash
   mysqladmin ping -h 127.0.0.1 -P 3306 --silent
   ```
4. Confirm the project is connecting to `127.0.0.1`, **not** `localhost`
   (on some systems `localhost` routes to a Unix socket which Docker does not
   expose).

### `mysql: command not found` inside the container

The official `mysql:8.4` image includes the `mysql` CLI. If you see this error
you are likely running the command outside the container. Prefix with
`docker compose exec mysql`:

```bash
docker compose exec mysql mysql -u root -p
```

### Slow queries

The slow-query log is enabled by default in `conf/mysql/my.cnf`. To inspect
it:

```bash
docker compose exec mysql tail -f /var/log/mysql/slow.log
```

### Character set or collation issues

Verify server defaults:

```bash
docker compose exec mysql mysql -u root -p -e \
  "SHOW VARIABLES LIKE 'character_set%'; SHOW VARIABLES LIKE 'collation%';"
```

If a legacy database was created with a different collation, convert
individual tables:

```sql
ALTER TABLE my_table CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

### Running arbitrary SQL without an interactive terminal

```bash
echo "SHOW DATABASES;" | docker compose exec -T mysql mysql -u root -p"${MYSQL_ROOT_PASSWORD}"
```
