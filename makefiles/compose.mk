# ================================================================
# Docker Compose Operations
# ================================================================

.PHONY: up down restart rebuild logs status
.PHONY: dev-up dev-down dev-restart dev-logs

# Docker Compose 파일 설정 (project.mk에서 오버라이드 가능)
COMPOSE_FILE ?= docker-compose.yml
DEV_COMPOSE_FILE ?= docker-compose.dev.yml
PROD_COMPOSE_FILE ?= docker-compose.prod.yml

# 환경별 Compose 파일 선택
ifeq ($(ENV),development)
    ACTIVE_COMPOSE_FILE := $(DEV_COMPOSE_FILE)
else ifeq ($(ENV),production)
    ACTIVE_COMPOSE_FILE := $(PROD_COMPOSE_FILE)
else
    ACTIVE_COMPOSE_FILE := $(COMPOSE_FILE)
endif

# ================================================================
# 환경별 타겟들
# ================================================================

up: env ## 🚀 Start services with Docker Compose
	@$(call colorecho, "🚀 Starting services ($(ENV) environment)...")
	@if [ ! -f $(ACTIVE_COMPOSE_FILE) ]; then \
		$(call warn, "Compose file $(ACTIVE_COMPOSE_FILE) not found, using default"); \
		ACTIVE_COMPOSE_FILE=$(COMPOSE_FILE); \
	fi; \
	$(call timed_command, "Docker Compose up", \
		docker-compose -f $$ACTIVE_COMPOSE_FILE up -d)
	@$(call success, "Services started successfully")
	@$(MAKE) status

down: ## 🚀 Stop services with Docker Compose
	@$(call colorecho, "🛑 Stopping services ($(ENV) environment)...")
	@if [ ! -f $(ACTIVE_COMPOSE_FILE) ]; then \
		ACTIVE_COMPOSE_FILE=$(COMPOSE_FILE); \
	fi; \
	$(call timed_command, "Docker Compose down", \
		docker-compose -f $$ACTIVE_COMPOSE_FILE down)
	@$(call success, "Services stopped successfully")

restart: ## 🚀 Restart services
	@$(call colorecho, "🔄 Restarting services...")
	@$(MAKE) down
	@$(MAKE) up

rebuild: ## 🚀 Rebuild and restart services
	@$(call colorecho, "🔨 Rebuilding and restarting services...")
	@if [ ! -f $(ACTIVE_COMPOSE_FILE) ]; then \
		ACTIVE_COMPOSE_FILE=$(COMPOSE_FILE); \
	fi; \
	docker-compose -f $$ACTIVE_COMPOSE_FILE down; \
	docker-compose -f $$ACTIVE_COMPOSE_FILE build --no-cache; \
	docker-compose -f $$ACTIVE_COMPOSE_FILE up -d
	@$(call success, "Services rebuilt and restarted")

# ================================================================
# 개발 환경 전용 타겟들
# ================================================================

dev-up: ## 🔧 Start development environment
	@$(call colorecho, "🚀 Starting development environment...")
	@if [ ! -f $(DEV_COMPOSE_FILE) ]; then \
		$(call warn, "Development compose file $(DEV_COMPOSE_FILE) not found"); \
		$(call colorecho, "Using default compose file: $(COMPOSE_FILE)"); \
		COMPOSE_FILE_TO_USE=$(COMPOSE_FILE); \
	else \
		COMPOSE_FILE_TO_USE=$(DEV_COMPOSE_FILE); \
	fi; \
	$(call timed_command, "Development environment startup", \
		docker-compose -f $$COMPOSE_FILE_TO_USE up -d)
	@$(call success, "Development environment started")
	@$(MAKE) dev-status

dev-down: ## 🔧 Stop development environment
	@$(call colorecho, "🛑 Stopping development environment...")
	@docker-compose -f $(DEV_COMPOSE_FILE) down 2>/dev/null || \
		docker-compose -f $(COMPOSE_FILE) down
	@$(call success, "Development environment stopped")

dev-restart: ## 🔧 Restart development environment
	@$(MAKE) dev-down
	@$(MAKE) dev-up

dev-logs: ## 🔧 Show development environment logs
	@$(call colorecho, "📋 Showing development logs...")
	@docker-compose -f $(DEV_COMPOSE_FILE) logs -f 2>/dev/null || \
		docker-compose -f $(COMPOSE_FILE) logs -f

# ================================================================
# 모니터링 및 상태 확인
# ================================================================

logs: ## 🔧 Show service logs
	@$(call colorecho, "📋 Showing service logs...")
	@if [ ! -f $(ACTIVE_COMPOSE_FILE) ]; then \
		ACTIVE_COMPOSE_FILE=$(COMPOSE_FILE); \
	fi; \
	docker-compose -f $$ACTIVE_COMPOSE_FILE logs -f

logs-tail: ## 🔧 Show last 100 lines of logs
	@$(call colorecho, "📋 Showing last 100 lines of logs...")
	@if [ ! -f $(ACTIVE_COMPOSE_FILE) ]; then \
		ACTIVE_COMPOSE_FILE=$(COMPOSE_FILE); \
	fi; \
	docker-compose -f $$ACTIVE_COMPOSE_FILE logs --tail=100

status: ## 🔧 Show services status
	@echo "$(BLUE)Services Status:$(RESET)"
	@if [ ! -f $(ACTIVE_COMPOSE_FILE) ]; then \
		ACTIVE_COMPOSE_FILE=$(COMPOSE_FILE); \
	fi; \
	docker-compose -f $$ACTIVE_COMPOSE_FILE ps

dev-status: ## 🔧 Show development services status
	@echo "$(BLUE)Development Services Status:$(RESET)"
	@docker-compose -f $(DEV_COMPOSE_FILE) ps 2>/dev/null || \
		docker-compose -f $(COMPOSE_FILE) ps

# ================================================================
# 서비스별 작업
# ================================================================

exec-service: ## 🔧 Execute command in specific service (usage: make exec-service SERVICE=web COMMAND="ls -la")
	@if [ -z "$(SERVICE)" ]; then \
		$(call error, "SERVICE is required. Usage: make exec-service SERVICE=web COMMAND='bash'"); \
		exit 1; \
	fi; \
	COMMAND_TO_RUN="$${COMMAND:-bash}"; \
	$(call colorecho, "🔧 Executing '$$COMMAND_TO_RUN' in service $(SERVICE)..."); \
	if [ ! -f $(ACTIVE_COMPOSE_FILE) ]; then \
		ACTIVE_COMPOSE_FILE=$(COMPOSE_FILE); \
	fi; \
	docker-compose -f $$ACTIVE_COMPOSE_FILE exec $(SERVICE) $$COMMAND_TO_RUN

restart-service: ## 🔧 Restart specific service (usage: make restart-service SERVICE=web)
	@if [ -z "$(SERVICE)" ]; then \
		$(call error, "SERVICE is required. Usage: make restart-service SERVICE=web"); \
		exit 1; \
	fi; \
	$(call colorecho, "🔄 Restarting service $(SERVICE)..."); \
	if [ ! -f $(ACTIVE_COMPOSE_FILE) ]; then \
		ACTIVE_COMPOSE_FILE=$(COMPOSE_FILE); \
	fi; \
	docker-compose -f $$ACTIVE_COMPOSE_FILE restart $(SERVICE); \
	$(call success, "Service $(SERVICE) restarted")

logs-service: ## 🔧 Show logs for specific service (usage: make logs-service SERVICE=web)
	@if [ -z "$(SERVICE)" ]; then \
		$(call error, "SERVICE is required. Usage: make logs-service SERVICE=web"); \
		exit 1; \
	fi; \
	$(call colorecho, "📋 Showing logs for service $(SERVICE)..."); \
	if [ ! -f $(ACTIVE_COMPOSE_FILE) ]; then \
		ACTIVE_COMPOSE_FILE=$(COMPOSE_FILE); \
	fi; \
	docker-compose -f $$ACTIVE_COMPOSE_FILE logs -f $(SERVICE)

# ================================================================
# 환경 관리
# ================================================================

env: ## 🔧 Create .env file from current configuration
	@$(call colorecho, "📝 Creating .env file...")
	@echo "# Generated .env file - $(shell date)" > .env
	@echo "REPO_HUB=$(REPO_HUB)" >> .env
	@echo "NAME=$(NAME)" >> .env
	@echo "VERSION=$(VERSION)" >> .env
	@echo "TAGNAME=$(TAGNAME)" >> .env
	@echo "ENV=$(ENV)" >> .env
	@echo "COMPOSE_FILE=$(ACTIVE_COMPOSE_FILE)" >> .env
	@$(call success, ".env file created successfully")

env-show: ## 🔧 Show current environment variables
	@echo "$(BLUE)Current Environment Configuration:$(RESET)"
	@echo "  Environment: $(ENV)"
	@echo "  Compose File: $(ACTIVE_COMPOSE_FILE)"
	@echo "  Project Name: $(NAME)"
	@echo "  Version: $(VERSION)"
	@echo "  Image Tag: $(TAGNAME)"
	@echo ""
	@if [ -f .env ]; then \
		echo "$(BLUE).env file contents:$(RESET)"; \
		cat .env | sed 's/^/  /'; \
	else \
		echo "$(YELLOW).env file not found$(RESET)"; \
	fi

# ================================================================
# 정리 작업
# ================================================================

compose-clean: ## 🧹 Clean Docker Compose resources
	@$(call colorecho, "🧹 Cleaning Docker Compose resources...")
	@$(MAKE) down 2>/dev/null || true
	@if [ ! -f $(ACTIVE_COMPOSE_FILE) ]; then \
		ACTIVE_COMPOSE_FILE=$(COMPOSE_FILE); \
	fi; \
	docker-compose -f $$ACTIVE_COMPOSE_FILE rm -f; \
	docker-compose -f $$ACTIVE_COMPOSE_FILE down --volumes --remove-orphans 2>/dev/null || true
	@$(call success, "Docker Compose cleanup completed")

# ================================================================
# 스케일링
# ================================================================

scale: ## 🔧 Scale services (usage: make scale SERVICE=web REPLICAS=3)
	@if [ -z "$(SERVICE)" ] || [ -z "$(REPLICAS)" ]; then \
		$(call error, "SERVICE and REPLICAS are required. Usage: make scale SERVICE=web REPLICAS=3"); \
		exit 1; \
	fi; \
	$(call colorecho, "⚖️  Scaling service $(SERVICE) to $(REPLICAS) replicas..."); \
	if [ ! -f $(ACTIVE_COMPOSE_FILE) ]; then \
		ACTIVE_COMPOSE_FILE=$(COMPOSE_FILE); \
	fi; \
	docker-compose -f $$ACTIVE_COMPOSE_FILE up -d --scale $(SERVICE)=$(REPLICAS); \
	$(call success, "Service $(SERVICE) scaled to $(REPLICAS) replicas")

# ================================================================
# 헬스체크 및 테스트
# ================================================================

health-check: ## 🔧 Check health of all services
	@$(call colorecho, "🩺 Checking service health...")
	@if [ ! -f $(ACTIVE_COMPOSE_FILE) ]; then \
		ACTIVE_COMPOSE_FILE=$(COMPOSE_FILE); \
	fi; \
	SERVICES=$$(docker-compose -f $$ACTIVE_COMPOSE_FILE config --services); \
	for service in $$SERVICES; do \
		echo "Checking $$service..."; \
		CONTAINER_ID=$$(docker-compose -f $$ACTIVE_COMPOSE_FILE ps -q $$service); \
		if [ -n "$$CONTAINER_ID" ]; then \
			STATUS=$$(docker inspect --format='{{.State.Health.Status}}' $$CONTAINER_ID 2>/dev/null || echo "no-health-check"); \
			echo "  $$service: $$STATUS"; \
		else \
			echo "  $$service: not running"; \
		fi; \
	done

compose-test: ## 🔧 Run compose-based tests
	@$(call colorecho, "🧪 Running compose tests...")
	@if [ -f docker-compose.test.yml ]; then \
		docker-compose -f docker-compose.test.yml up --build --abort-on-container-exit; \
		docker-compose -f docker-compose.test.yml down; \
	else \
		$(call warn, "No docker-compose.test.yml found"); \
	fi

# ================================================================
# 백업 및 복원
# ================================================================

backup-volumes: ## 🔧 Backup Docker volumes
	@$(call colorecho, "💾 Backing up Docker volumes...")
	@BACKUP_DIR="./backups/$$(date +%Y%m%d_%H%M%S)"; \
	mkdir -p $$BACKUP_DIR; \
	if [ ! -f $(ACTIVE_COMPOSE_FILE) ]; then \
		ACTIVE_COMPOSE_FILE=$(COMPOSE_FILE); \
	fi; \
	VOLUMES=$$(docker-compose -f $$ACTIVE_COMPOSE_FILE config --volumes); \
	for volume in $$VOLUMES; do \
		echo "Backing up volume: $$volume"; \
		docker run --rm -v $$volume:/data -v $$BACKUP_DIR:/backup alpine tar czf /backup/$$volume.tar.gz -C /data .; \
	done; \
	$(call success, "Volumes backed up to $$BACKUP_DIR")

# ================================================================
# 디버깅
# ================================================================

compose-config: ## 🔧 Show resolved Docker Compose configuration
	@$(call colorecho, "📋 Showing resolved compose configuration...")
	@if [ ! -f $(ACTIVE_COMPOSE_FILE) ]; then \
		ACTIVE_COMPOSE_FILE=$(COMPOSE_FILE); \
	fi; \
	docker-compose -f $$ACTIVE_COMPOSE_FILE config

compose-images: ## 🔧 Show images used by compose services
	@$(call colorecho, "🖼️  Showing compose images...")
	@if [ ! -f $(ACTIVE_COMPOSE_FILE) ]; then \
		ACTIVE_COMPOSE_FILE=$(COMPOSE_FILE); \
	fi; \
	docker-compose -f $$ACTIVE_COMPOSE_FILE images