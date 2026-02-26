#!/usr/bin/env bash
# scripts/restore.sh
#
# Restore a logical dump produced by scripts/backup.sh.
#
# Usage:
#   ./scripts/restore.sh <dump_file>              # restore an all-databases dump
#   ./scripts/restore.sh <dump_file> <db_name>    # restore into a specific database
#
# The target database must already exist when restoring a single-database dump.
# Use scripts/create-db.sh first if needed.
#
# ⚠  DESTRUCTIVE: restoring overwrites existing data in the target database(s).
# Run from the repository root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Arguments ────────────────────────────────────────────────────────────────
DUMP_FILE="${1:-}"
TARGET_DB="${2:-}"

if [[ -z "${DUMP_FILE}" ]]; then
  echo "Usage: $0 <dump_file> [database_name]"
  exit 1
fi

if [[ ! -f "${DUMP_FILE}" ]]; then
  echo "ERROR: Dump file not found: ${DUMP_FILE}"
  exit 1
fi

# ── Load .env ────────────────────────────────────────────────────────────────
ENV_FILE="${REPO_ROOT}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: .env file not found at ${ENV_FILE}"
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

# ── Confirmation prompt ───────────────────────────────────────────────────────
echo ""
echo "  ⚠  WARNING: This will overwrite data in the target database(s)."
echo ""
echo "  Dump file : ${DUMP_FILE}"
echo "  Target    : ${TARGET_DB:-ALL DATABASES (from dump)}"
echo ""
read -rp "  Type 'yes' to continue: " CONFIRM

if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

# ── Decompress and pipe to MySQL ──────────────────────────────────────────────
echo ""
echo "Restoring …"

if [[ "${DUMP_FILE}" == *.gz ]]; then
  DECOMPRESS="gunzip -c"
elif [[ "${DUMP_FILE}" == *.bz2 ]]; then
  DECOMPRESS="bunzip2 -c"
else
  DECOMPRESS="cat"
fi

if [[ -n "${TARGET_DB}" ]]; then
  ${DECOMPRESS} "${DUMP_FILE}" | \
    docker compose -f "${REPO_ROOT}/docker-compose.yml" exec -T mysql \
      mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "${TARGET_DB}"
else
  ${DECOMPRESS} "${DUMP_FILE}" | \
    docker compose -f "${REPO_ROOT}/docker-compose.yml" exec -T mysql \
      mysql -u root -p"${MYSQL_ROOT_PASSWORD}"
fi

echo "Restore complete."
