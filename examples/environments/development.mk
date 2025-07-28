# ================================================================
# Development Environment Configuration
# ================================================================

# 개발환경 전용 설정
DEBUG = true
DOCKER_BUILD_OPTION += --progress=plain

# 개발용 Docker Compose 파일
COMPOSE_FILE = docker-compose.dev.yml

# 개발환경에서는 캐시 사용하지 않음
DOCKER_BUILD_OPTION += --no-cache

# 개발환경 전용 포트 설정
DEV_PORT = 3000
DEV_DB_PORT = 5433

# 개발환경 전용 환경 변수
NODE_ENV = development
PYTHON_ENV = development
LOG_LEVEL = debug

# ================================================================
# 개발환경 전용 타겟들
# ================================================================

dev-up: ## 🚀 Start development environment with hot reload
	@$(call colorecho, "🚀 Starting development environment...")
	@docker-compose -f $(COMPOSE_FILE) up -d
	@$(call success, "Development environment started")
	@$(MAKE) dev-status

dev-down: ## 🛑 Stop development environment
	@$(call colorecho, "🛑 Stopping development environment...")
	@docker-compose -f $(COMPOSE_FILE) down
	@$(call success, "Development environment stopped")

dev-restart: ## 🔄 Restart development environment
	@$(MAKE) dev-down
	@$(MAKE) dev-up

dev-logs: ## 📋 Show development logs
	@$(call colorecho, "📋 Showing development logs...")
	@docker-compose -f $(COMPOSE_FILE) logs -f

dev-status: ## 📊 Show development services status
	@echo "$(BLUE)Development Services Status:$(RESET)"
	@docker-compose -f $(COMPOSE_FILE) ps

dev-shell: ## 🐚 Get shell access to main service
	@$(call colorecho, "🐚 Starting shell in development container...")
	@docker-compose -f $(COMPOSE_FILE) exec app sh

dev-watch: ## 👀 Watch for changes and rebuild
	@$(call colorecho, "👀 Watching for changes...")
	@while inotifywait -r -e modify,create,delete . 2>/dev/null; do \
		$(call colorecho, "🔄 Changes detected, rebuilding..."); \
		$(MAKE) build; \
	done

dev-seed: ## 🌱 Seed development database
	@$(call colorecho, "🌱 Seeding development database...")
	@# 개발 데이터 시딩 로직 추가
	@if [ -f "scripts/seed-dev-data.sh" ]; then \
		bash scripts/seed-dev-data.sh; \
	else \
		echo "Create scripts/seed-dev-data.sh for development data seeding"; \
	fi
	@$(call success, "Development database seeded")

dev-reset: ## 🔄 Reset development environment completely
	@$(call warn, "This will remove all development data")
	@echo "Continue? [y/N] " && read ans && [ $${ans:-N} = y ]
	@$(call colorecho, "🔄 Resetting development environment...")
	@docker-compose -f $(COMPOSE_FILE) down -v
	@docker-compose -f $(COMPOSE_FILE) up -d
	@$(MAKE) dev-seed
	@$(call success, "Development environment reset")

# ================================================================
# 개발용 테스트 및 디버깅
# ================================================================

test-dev: ## 🧪 Run tests in development mode
	@$(call colorecho, "🧪 Running development tests...")
	@docker-compose -f $(COMPOSE_FILE) exec app npm test -- --watch

debug: ## 🐛 Start application in debug mode
	@$(call colorecho, "🐛 Starting debug mode...")
	@docker-compose -f $(COMPOSE_FILE) exec app npm run debug

profile: ## 📊 Run performance profiling
	@$(call colorecho, "📊 Running performance profiling...")
	@docker-compose -f $(COMPOSE_FILE) exec app npm run profile