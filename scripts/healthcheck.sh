#!/usr/bin/env bash
# scripts/healthcheck.sh
#
# Quick operational health check — prints MySQL version, uptime, and
# the list of user-created databases.
#
# Usage:
#   ./scripts/healthcheck.sh
#
# Run from the repository root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

# ── Ping ─────────────────────────────────────────────────────────────────────
echo "── Ping ─────────────────────────────────────────────────────────────"
docker compose -f "${REPO_ROOT}/docker-compose.yml" exec -T mysql \
  mysqladmin ping -h 127.0.0.1 --silent && echo "mysqladmin ping: OK"

# ── Version & uptime ─────────────────────────────────────────────────────────
echo ""
echo "── Server info ──────────────────────────────────────────────────────"
docker compose -f "${REPO_ROOT}/docker-compose.yml" exec -T mysql \
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" --silent \
  -e "SELECT VERSION() AS version, NOW() AS server_time;"

docker compose -f "${REPO_ROOT}/docker-compose.yml" exec -T mysql \
  mysqladmin -u root -p"${MYSQL_ROOT_PASSWORD}" status

# ── Databases ────────────────────────────────────────────────────────────────
echo ""
echo "── User databases (excluding system schemas) ────────────────────────"
docker compose -f "${REPO_ROOT}/docker-compose.yml" exec -T mysql \
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" --silent \
  -e "SELECT schema_name AS database_name
      FROM information_schema.schemata
      WHERE schema_name NOT IN ('information_schema','performance_schema','mysql','sys')
      ORDER BY schema_name;"

# ── Users ────────────────────────────────────────────────────────────────────
echo ""
echo "── MySQL users ──────────────────────────────────────────────────────"
docker compose -f "${REPO_ROOT}/docker-compose.yml" exec -T mysql \
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" --silent \
  -e "SELECT user, host FROM mysql.user ORDER BY user, host;"
