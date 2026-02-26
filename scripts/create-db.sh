#!/usr/bin/env bash
# scripts/create-db.sh
#
# Create a new database and a dedicated user for a project.
# Idempotent: safe to run more than once for the same database/user.
#
# Usage:
#   ./scripts/create-db.sh
#
# You will be prompted for:
#   DB_NAME     — name of the new database
#   DB_USER     — MySQL user for the project (do NOT use root for daily use)
#   DB_PASSWORD — password for that user
#
# The script reads MYSQL_ROOT_PASSWORD from the .env file in the repo root.
# Run from the repository root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Load .env ────────────────────────────────────────────────────────────────
ENV_FILE="${REPO_ROOT}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: .env file not found at ${ENV_FILE}"
  echo "       Copy .env.example to .env and fill in your credentials."
  exit 1
fi

# shellcheck disable=SC1090
set -o allexport
source "${ENV_FILE}"
set +o allexport

if [[ -z "${MYSQL_ROOT_PASSWORD:-}" ]]; then
  echo "ERROR: MYSQL_ROOT_PASSWORD is not set in .env"
  exit 1
fi

# ── Prompt for project details ───────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo "  Create project database & user"
echo "══════════════════════════════════════════"
echo ""

read -rp "  Database name  : " DB_NAME
read -rp "  MySQL username : " DB_USER
read -rsp "  MySQL password : " DB_PASSWORD
echo ""

if [[ -z "${DB_NAME}" || -z "${DB_USER}" || -z "${DB_PASSWORD}" ]]; then
  echo "ERROR: All three fields are required."
  exit 1
fi

# Refuse to create a user called 'root' via this script.
if [[ "${DB_USER}" == "root" ]]; then
  echo "ERROR: Do not use 'root' as a project user. Choose a project-specific name."
  exit 1
fi

MYSQL_PORT="${MYSQL_PORT:-3306}"

# ── Run SQL ──────────────────────────────────────────────────────────────────
echo ""
echo "Creating database '${DB_NAME}' and user '${DB_USER}' …"

docker compose -f "${REPO_ROOT}/docker-compose.yml" exec -T mysql \
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<SQL
-- Database
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- User (localhost inside the container covers all Docker network connections)
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';

-- Permissions: full access to this database only, nothing else.
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';

FLUSH PRIVILEGES;
SQL

echo ""
echo "Done."
echo ""
echo "  Database : ${DB_NAME}"
echo "  User     : ${DB_USER}"
echo "  Host     : 127.0.0.1:${MYSQL_PORT}"
echo ""
echo "Connection string (DSN):"
echo "  mysql://${DB_USER}:<password>@127.0.0.1:${MYSQL_PORT}/${DB_NAME}"
echo ""
echo "REMINDER: Store the password in your project's own .env — not here."
