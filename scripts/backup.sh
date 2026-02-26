#!/usr/bin/env bash
# scripts/backup.sh
#
# Logical (mysqldump) backup of one or all databases.
# Dumps are written to the backups/ directory with a timestamp in the filename.
# Dump files are compressed with gzip.
#
# Usage:
#   ./scripts/backup.sh              # backs up ALL databases
#   ./scripts/backup.sh myproject    # backs up a single database
#
# Run from the repository root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${REPO_ROOT}/backups"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

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

# ── Determine backup target ──────────────────────────────────────────────────
TARGET_DB="${1:-}"

MYSQLDUMP_FLAGS=(
  --single-transaction   # consistent snapshot without locking (InnoDB)
  --routines             # include stored procedures & functions
  --triggers             # include triggers
  --set-gtid-purged=OFF  # avoids issues when binary log is disabled
  --column-statistics=0  # prevents errors on MySQL 8 → older clients
)

if [[ -n "${TARGET_DB}" ]]; then
  DUMP_LABEL="${TARGET_DB}"
  DUMP_FLAGS=("${MYSQLDUMP_FLAGS[@]}" "${TARGET_DB}")
else
  DUMP_LABEL="all-databases"
  DUMP_FLAGS=("${MYSQLDUMP_FLAGS[@]}" "--all-databases")
fi

OUTPUT_FILE="${BACKUP_DIR}/${DUMP_LABEL}_${TIMESTAMP}.sql.gz"

# ── Run dump ─────────────────────────────────────────────────────────────────
mkdir -p "${BACKUP_DIR}"

echo "Starting backup: ${DUMP_LABEL} → ${OUTPUT_FILE}"

docker compose -f "${REPO_ROOT}/docker-compose.yml" exec -T mysql \
  mysqldump -u root -p"${MYSQL_ROOT_PASSWORD}" "${DUMP_FLAGS[@]}" \
  | gzip > "${OUTPUT_FILE}"

BYTES=$(stat -f%z "${OUTPUT_FILE}" 2>/dev/null || stat -c%s "${OUTPUT_FILE}")
echo "Backup complete: ${OUTPUT_FILE} ($(( BYTES / 1024 )) KB)"
echo ""
echo "To restore this dump:"
echo "  ./scripts/restore.sh ${OUTPUT_FILE} [database_name]"
