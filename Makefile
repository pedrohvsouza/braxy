SHELL := /bin/bash
export BRAXY_GIT_SHA := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
COMPOSE := docker compose

.PHONY: up down logs seed reset test test-backend test-frontend e2e shell

up: ## start pg, redis, s3, backend (hot reload) and frontend
	$(COMPOSE) up -d --build
	@echo "Braxy: http://localhost:5173  (pedro / password123)"

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
