SHELL := /bin/bash
export BRAXY_GIT_SHA := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
COMPOSE := docker compose

# This machine's address on the local network: the source address of the
# default route (Linux), or the Wi-Fi/Ethernet address (macOS). Empty offline.
LAN_IP_CMD := ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($$i == "src") { print $$(i + 1); exit }}'
LAN_IP_CMD_MAC := ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null

.PHONY: up urls down logs seed reset test test-backend test-frontend e2e shell

up: ## start pg, redis, s3, backend (hot reload) and frontend; waits until the backend is healthy
	@echo "Starting Braxy (the first run compiles the backend, ~3 min)..."
	$(COMPOSE) up -d --build --wait
	@$(MAKE) --no-print-directory urls

urls: ## print the URLs to open the app here and on other devices on the network
	@echo "Braxy is up (pedro / password123):"
	@echo "  Local:   http://localhost:5173"
	@lan="$$($(LAN_IP_CMD))"; [ -n "$$lan" ] || lan="$$($(LAN_IP_CMD_MAC))"; if [ -n "$$lan" ]; then echo "  Network: http://$$lan:5173  (phone or another computer on the same network)"; fi

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f backend frontend

seed:
	$(COMPOSE) exec backend saci db:seed

reset: ## wipe all volumes (database, redis, s3) and start fresh
	$(COMPOSE) down -v
	$(MAKE) up

test: test-backend test-frontend

test-backend:
	$(COMPOSE) run --rm --no-deps -e APP_ENV=test backend crystal spec

test-frontend:
	cd frontend && npm run typecheck && npm test

e2e: ## needs `make up`
	cd frontend && npx playwright test

shell:
	$(COMPOSE) exec backend bash
