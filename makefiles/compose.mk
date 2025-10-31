# ================================================================
# Docker Compose Operations
# ================================================================

.PHONY: up down restart rebuild logs status
.PHONY: dev-up dev-down dev-restart dev-logs

# Docker Compose 파일 설정 (project.mk에서 오버라이드 가능)
COMPOSE_CLI = docker compose

# COMPOSE_FILE_DEFAULT ?= docker-compose.yml
# COMPOSE_FILE_DEV ?= docker-compose.dev.yml
# COMPOSE_FILE_PROD ?= docker-compose.prod.yml

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

COMPOSE_FILE_TO_USE := $(if $(wildcard $(ACTIVE_COMPOSE_FILE)),$(ACTIVE_COMPOSE_FILE),$(COMPOSE_FILE_DEFAULT))

ifeq ($(wildcard $(ACTIVE_COMPOSE_FILE)),)
	COMPOSE_FILE_TO_USE = $(COMPOSE_FILE)
else
	COMPOSE_FILE_TO_USE = $(ACTIVE_COMPOSE_FILE)
endif

COMPOSE_COMMAND = $(COMPOSE_CLI) -f $(COMPOSE_FILE_TO_USE)

define compose_cmd
  $(COMPOSE_CLI) -f $(if $(wildcard $(ACTIVE_COMPOSE_FILE)),$(ACTIVE_COMPOSE_FILE),$(COMPOSE_FILE)) $(1)
endef

# ================================================================
# 환경별 타겟들
# ================================================================

deploy: ## 무중단 배포 (단일 컨테이너)
	@echo "🚀 배포 시작..."
	
	# 1. 새 이미지 pull
	@docker-compose pull app
	
	# 2. 무중단 재시작
	@docker-compose up -d --no-deps --build app
	# --no-deps: 의존성 재시작 안함
	# docker-compose가 자동으로:
	#   - 새 컨테이너 시작
	#   - 헬스체크 통과 대기
	#   - 구 컨테이너 종료
	
	@echo "✅ 배포 완료"


up: prepare-env ## 🚀 Start services (자동으로 .env 갱신 체크)	
	@$(call colorecho, 🚀 Starting services for [$(ENVIRONMENT)] environment using [$(COMPOSE_FILE_TO_USE)]...)
	@$(call timed_command, Starting $(COMPOSE_FILE_TO_USE), \
		$(COMPOSE_COMMAND) up -d)
	@$(call colorecho, \n)
	@$(MAKE) status

up-force: ## 🔧 Start services (.env 강제 갱신)
	@$(MAKE) prepare-env ENVIRONMENT=$(ENVIRONMENT)
	@$(MAKE) up ENVIRONMENT=$(ENVIRONMENT)

up-quick:  ## 🔧 Start services (.env 갱신 없이 빠른 시작)
	@$(call colorecho, 🚀 Starting services for [$(ENVIRONMENT)] environment...)
	@$(call timed_command, Starting $(COMPOSE_FILE_TO_USE), \
		$(COMPOSE_COMMAND) up -d)
	@$(MAKE) status


down: ## 🛑 Stop services for the current ENV
	@$(call colorecho, 🛑 Stopping services for [$(ENV)] environment using [$(COMPOSE_FILE_TO_USE)]...)
	@$(call timed_command, Stopping $(COMPOSE_FILE_TO_USE), \
		$(COMPOSE_COMMAND) down --remove-orphans)
	@$(call colorecho, \n)
	@$(MAKE) status

restart: ## 🔧 Restart services for the current ENV
	@$(call colorecho, 🔄 Restarting services...)
	@$(MAKE) down
	@$(MAKE) up


rebuild: ## 🔧 Rebuild services for the current ENV
	@$(call colorecho, 🔨 Rebuilding services for [$(ENV)] environment with no-cache...)
	@$(call timed_command, 🔨 Rebuild $(COMPOSE_COMMAND), \
		$(COMPOSE_COMMAND) build --no-cache)
	@$(call colorecho, 🚀 Services started successfully with $(COMPOSE_COMMAND))
	@echo ""
	@$(MAKE) status

# ================================================================
# 개발 환경 전용 타겟들
# ================================================================

dev-up: ## 🔧 Start development environment
	@$(call colorecho, 🚀 Starting development environment...)
	@if [ ! -f $(DEV_COMPOSE_FILE) ]; then \
		$(call warn, Development compose file $(DEV_COMPOSE_FILE) not found); \
		$(call colorecho, Using default compose file: $(COMPOSE_FILE)); \
		COMPOSE_FILE_TO_USE=$(COMPOSE_FILE); \
	else \
		COMPOSE_FILE_TO_USE=$(DEV_COMPOSE_FILE); \
	fi; \
	$(call timed_command, "Development environment startup", \
		docker-compose -f $$COMPOSE_FILE_TO_USE up -d)
	@$(call success, Development environment started)
	@$(MAKE) dev-status

dev-down: ## 🔧 Stop development environment
	@$(call colorecho, 🛑 Stopping development environment...)
	@docker-compose -f $(DEV_COMPOSE_FILE) down 2>/dev/null || \
		docker-compose -f $(COMPOSE_FILE) down
	@$(call success, Development environment stopped)

dev-restart: ## 🔧 Restart development environment
	@$(MAKE) dev-down
	@$(MAKE) dev-up

dev-logs: ## 🔧 Show development environment logs
	@$(call colorecho, 📋 Showing development logs...)
	@docker-compose -f $(DEV_COMPOSE_FILE) logs -f 2>/dev/null || \
		docker-compose -f $(COMPOSE_FILE) logs -f

# ================================================================
# 모니터링 및 상태 확인
# ================================================================

logs: ## 🔧 Show service logs
	@$(call colorecho, 📋 Showing service logs...)
	@$(COMPOSE_COMMAND) logs -f

logs-tail: ## 🔧 Show last 100 lines of logs
	@$(call colorecho, 📋 Showing last 100 lines of logs...)
	@$(COMPOSE_COMMAND) logs -f --tail=100

status: ## 📊 Show status of services
	@$(call colorecho, 📊 Status for [$(ENV)] environment using [$(COMPOSE_FILE_TO_USE)]:)
	@$(COMPOSE_COMMAND) ps

dev-status: ## 🔧 Show development services status
	@echo "$(BLUE)Development Services Status:$(RESET)"
	@docker-compose -f $(DEV_COMPOSE_FILE) ps 2>/dev/null || \
		docker-compose -f $(COMPOSE_FILE) ps

# ================================================================
# 서비스별 작업
# ================================================================

exec-service: ## 🔧 특정 서비스에서 명령어 실행 (사용법: make exec-service SERVICE=web COMMAND="ls -la")
	@if [ -z "$(SERVICE)" ]; then \
		echo "$(RED)에러: SERVICE 변수가 필요합니다. 사용법: make exec-service SERVICE=web$(RESET)"; \
		exit 1; \
	fi
	@COMMAND_TO_RUN="$${COMMAND:-bash}"; \
	echo "🔧 [$(SERVICE)] 서비스에서 '$$COMMAND_TO_RUN' 명령어를 실행합니다..."; \
	$(COMPOSE_COMMAND) exec $(SERVICE) $$COMMAND_TO_RUN

restart-service: ## 🔧 특정 서비스 재시작 (사용법: make restart-service SERVICE=web)
	@if [ -z "$(SERVICE)" ]; then \
		echo "$(RED)에러: SERVICE 변수가 필요합니다. 사용법: make restart-service SERVICE=web$(RESET)"; \
		exit 1; \
	fi
	@echo "🔄 [$(SERVICE)] 서비스를 재시작합니다..."
	@$(COMPOSE_COMMAND) restart $(SERVICE)
	@echo "$(GREEN)✅ [$(SERVICE)] 서비스가 성공적으로 재시작되었습니다.$(RESET)"

logs-service: ## 🔧 특정 서비스 로그 보기 (사용법: make logs-service SERVICE=web)
	@if [ -z "$(SERVICE)" ]; then \
		echo "$(RED)에러: SERVICE 변수가 필요합니다. 사용법: make logs-service SERVICE=web$(RESET)"; \
		exit 1; \
	fi
	@echo "📋 [$(SERVICE)] 서비스의 로그를 표시합니다..."
	@$(COMPOSE_COMMAND) logs -f $(SERVICE)


# ================================================================
# 환경 관리
# ================================================================
# env: ## 🔧 Create .env file from current configuration
# 	@$(call colorecho, 📝 Creating .env file...)
# 	@echo "# Generated .env file - $(shell date)" > .env
# 	@echo "REPO_HUB=$(REPO_HUB)" >> .env
# 	@echo "NAME=$(NAME)" >> .env
# 	@echo "VERSION=$(VERSION)" >> .env
# 	@echo "TAGNAME=$(TAGNAME)" >> .env
# 	@echo "ENV=$(ENV)" >> .env
# 	@echo "COMPOSE_FILE=$(ACTIVE_COMPOSE_FILE)" >> .env
# 	@echo "CURRENT_COMMIT_LONG=$(CURRENT_COMMIT_LONG)" >> .env
# 	@echo "CURRENT_COMMIT_SHORT=$(CURRENT_COMMIT_SHORT)" >> .env
# 	@echo "CURRENT_BRANCH=$(CURRENT_BRANCH)" >> .env
# 	@echo "BUILD_REVISION=$(BUILD_REVISION)" >> .env
# 	@$(call success, .env file created successfully)

# env-show: env ## 🧐 Show current environment variables
# 	@echo "$(BLUE)Current Environment Configuration:$(RESET)"
# 	@echo "  Environment (ENV)   : $(ENV)"
# 	@echo "  Compose CLI         : $(COMPOSE_CLI)"
# 	@echo "  Active Compose File : $(COMPOSE_FILE_TO_USE)"
# 	@echo "  Project Name (NAME) : $(NAME)"
# 	@echo "  Version (VERSION)   : $(VERSION)"
# 	@echo "  Image Tag (TAGNAME) : $(TAGNAME)"
# 	@echo "  Build Revision (BUILD_REVISION) : $(BUILD_REVISION)"
# 	@echo "  Current Commit Long (CURRENT_COMMIT_LONG) : $(CURRENT_COMMIT_LONG)"
# 	@echo "  Current Commit Short (CURRENT_COMMIT_SHORT) : $(CURRENT_COMMIT_SHORT)"
# 	@echo "  Current Branch (CURRENT_BRANCH) : $(CURRENT_BRANCH)"
# 	@echo ""
# 	@if [ -f .env ]; then \
# 		echo "$(BLUE).env file contents:$(RESET)"; \
# 		cat .env | sed 's/^/  /'; \
# 	else \
# 		echo "$(YELLOW)NOTE: .env file not found. Create one with 'make env'.$(RESET)"; \
# 	fi



# ================================================================
# 정리 작업
# ================================================================

compose-clean: ## 🧹 Clean Docker Compose resources
	@echo "🧹 Docker Compose 리소스를 정리합니다..."
	@$(MAKE) down 2>/dev/null || true
	@$(COMPOSE_COMMAND) rm -fv
	@$(COMPOSE_COMMAND) down --volumes --remove-orphans 2>/dev/null || true
	@echo "$(GREEN)✅ Docker Compose 정리가 완료되었습니다.$(RESET)"

# ================================================================
# 스케일링
# ================================================================

scale: ## 🔧 Scale services (usage: make scale SERVICE=web REPLICAS=3)
	@if [ -z "$(SERVICE)" ] || [ -z "$(REPLICAS)" ]; then \
		echo "$(RED)에러: SERVICE와 REPLICAS 변수가 필요합니다. 사용법: make scale SERVICE=web REPLICAS=3$(RESET)"; \
		exit 1; \
	fi
	@echo "⚖️  [$(SERVICE)] 서비스를 [$(REPLICAS)]개로 스케일링합니다..."
	@$(COMPOSE_COMMAND) up -d --scale $(SERVICE)=$(REPLICAS)
	@echo "$(GREEN)✅ [$(SERVICE)] 서비스가 성공적으로 스케일링되었습니다.$(RESET)"

# ================================================================
# 헬스체크 및 테스트
# ================================================================

health-check: ## 🔧 Check health of all services
	@echo "🩺 서비스 상태를 확인합니다..."
	@SERVICES=$$($(COMPOSE_COMMAND) config --services); \
	for service in $$SERVICES; do \
		echo "Checking $$service..."; \
		CONTAINER_ID=$$(docker ps -q --filter "name=$$service"); \
		if [ -n "$$CONTAINER_ID" ]; then \
			STATUS=$$(docker inspect --format='{{.State.Health.Status}}' $$CONTAINER_ID 2>/dev/null || echo "no-health-check"); \
			echo "  $$service: $$STATUS"; \
		else \
			echo "  $$service: not running"; \
		fi; \
	done

compose-test: ## 🔧 Run compose-based tests
	@echo "🧪 compose 기반 테스트를 실행합니다..."
	@if [ -f docker-compose.test.yml ]; then \
		$(COMPOSE_CLI) -f docker-compose.test.yml up --build --abort-on-container-exit; \
		$(COMPOSE_CLI) -f docker-compose.test.yml down; \
	else \
		echo "$(YELLOW)⚠️  docker-compose.test.yml 파일을 찾을 수 없습니다.$(RESET)"; \
	fi

# ================================================================
# 백업 및 복원
# ================================================================

backup-volumes: ## 🔧 Backup Docker volumes
	@echo "💾 Docker 볼륨을 백업합니다..."
	@BACKUP_DIR="./backups/$$(date +%Y%m%d_%H%M%S)"; \
	mkdir -p $$BACKUP_DIR; \
	VOLUMES=$$($(COMPOSE_COMMAND) config --volumes); \
	for volume in $$VOLUMES; do \
		echo "Backing up volume: $$volume"; \
		docker run --rm -v $$volume:/data -v $$BACKUP_DIR:/backup alpine tar czf /backup/$$volume.tar.gz -C /data .; \
	done; \
	echo "$(GREEN)✅ 볼륨이 $$BACKUP_DIR 에 성공적으로 백업되었습니다.$(RESET)"

# ================================================================
# 디버깅
# ================================================================

compose-config: ## 🔧 Show resolved Docker Compose configuration
	@echo "📋 해석된 compose 설정을 표시합니다..."
	@$(COMPOSE_COMMAND) config

compose-images: ## 🔧 Show images used by compose services
	@echo "🖼️  compose 서비스가 사용하는 이미지를 표시합니다..."
	@$(COMPOSE_COMMAND) images
