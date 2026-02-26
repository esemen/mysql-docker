.DEFAULT_GOAL := help

# ── Colours ───────────────────────────────────────────────────────────────────
CYAN  := \033[36m
RESET := \033[0m

.PHONY: help up down restart logs shell ps health new-db backup restore pull

help: ## Show this help message
	@echo ""
	@echo "  MySQL Docker — available commands"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-10s$(RESET) %s\n", $$1, $$2}'
	@echo ""

# ── Lifecycle ─────────────────────────────────────────────────────────────────

up: ## Start MySQL in the background
	docker compose up -d

down: ## Stop MySQL (data volume is kept)
	docker compose down

restart: ## Restart MySQL — use after editing conf/mysql/my.cnf
	docker compose restart mysql

pull: ## Pull the latest mysql:8.4 image (run before a patch upgrade)
	docker compose pull mysql

# ── Observability ─────────────────────────────────────────────────────────────

ps: ## Show container status and health
	docker compose ps

logs: ## Tail live MySQL logs  (Ctrl-C to exit)
	docker compose logs -f mysql

health: ## Ping, version, database list, user list
	./scripts/healthcheck.sh

# ── Shell access ──────────────────────────────────────────────────────────────

shell: ## Open an interactive root MySQL shell
	docker compose exec mysql mysql -u root -p

# ── Project databases ─────────────────────────────────────────────────────────

new-db: ## Create a database + dedicated user for a project (interactive)
	./scripts/create-db.sh

# ── Backups & restores ────────────────────────────────────────────────────────

backup: ## Dump to backups/ — single DB: make backup DB=myproject  /  all: make backup
	./scripts/backup.sh $(DB)

restore: ## Restore a dump — make restore DUMP=backups/file.sql.gz [DB=myproject]
	@test -n "$(DUMP)" || \
	  (echo ""; echo "  ERROR: DUMP is required."; \
	   echo "  Usage: make restore DUMP=backups/file.sql.gz [DB=myproject]"; \
	   echo ""; exit 1)
	./scripts/restore.sh $(DUMP) $(DB)
